-- Four Fit - schema (rodar no SQL Editor do Supabase, projeto limpo)
-- Treinador: login email/senha (Supabase Auth), vinculado pelo email (auth.jwt()->>'email').
-- Aluno: sem login, acessa pelo link secreto (students.access_token) via funcoes *_by_token.

create table companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz default now()
);

create table trainers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) not null,
  name text not null,
  email text not null unique,          -- sempre minusculo
  created_at timestamptz default now()
);

create table students (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid references trainers(id) not null,
  name text not null,
  access_token uuid not null unique default gen_random_uuid(),  -- link do aluno: ?t=<token>
  workout jsonb,                       -- JSON gerado pelo parser do PDF
  workout_updated_at timestamptz,
  payments jsonb not null default '{}', -- meses pagos: { "2026-10": true, ... }
  created_at timestamptz default now()
);

create table annotations (
  student_id uuid primary key references students(id) on delete cascade,
  semana_atual integer default 1,
  obs jsonb default '{}',              -- { "treino-1-ex-1": "texto", ... }
  pesos jsonb default '{}',            -- { "treino-1-ex-1": { "15": "80", ... }, ... }
  updated_at timestamptz default now()
);

-- Agenda do treinador: um horario marcado com um aluno (sem recorrencia)
create table appointments (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid references trainers(id) not null,
  student_id uuid references students(id) on delete cascade not null,
  starts_at timestamptz not null,
  created_at timestamptz default now()
);

-- lista do treinador: filtra por treinador e ordena por cadastro (mais recentes primeiro)
create index idx_students_trainer_created on students (trainer_id, created_at desc);
-- agenda: horarios do treinador por dia
create index idx_appointments_trainer_starts on appointments (trainer_id, starts_at);

-- id do treinador logado (security definer evita recursao de RLS)
create or replace function public.my_trainer_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from trainers where email = lower(auth.jwt()->>'email')
$$;

alter table companies enable row level security;
alter table trainers enable row level security;
alter table students enable row level security;
alter table annotations enable row level security;
alter table appointments enable row level security;

-- Treinador ve o proprio cadastro e a propria empresa
create policy trainers_select_own on trainers
  for select using (email = (select lower(auth.jwt()->>'email')));

create policy companies_select_own on companies
  for select using (id in (select company_id from trainers));

-- Treinador ve/gerencia apenas seus alunos
-- (select ...) = avaliado uma vez por consulta, nao por linha
create policy students_select on students
  for select using (trainer_id = (select public.my_trainer_id()));

create policy students_insert on students
  for insert with check (trainer_id = (select public.my_trainer_id()));

create policy students_update on students
  for update using (trainer_id = (select public.my_trainer_id()))
  with check (trainer_id = (select public.my_trainer_id()));

create policy students_delete on students
  for delete using (trainer_id = (select public.my_trainer_id()));

-- Treinador le/grava anotacoes dos seus alunos
create policy annotations_all on annotations
  for all using (student_id in (select id from students))
  with check (student_id in (select id from students));

-- Treinador gerencia a propria agenda (so com alunos dele)
create policy appointments_all on appointments
  for all using (trainer_id = (select public.my_trainer_id()))
  with check (trainer_id = (select public.my_trainer_id()) and student_id in (select id from students));

-- === Acesso do aluno pelo link (sem login) ===
-- Unico caminho do anon: nao ha grant de tabela para anon.

-- Treino + anotacoes do aluno dono do token (null se token invalido)
create or replace function public.student_by_token(p_token uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'name', s.name,
    'trainer_name', t.name,
    'workout', s.workout,
    'semana_atual', coalesce(a.semana_atual, 1),
    'obs', coalesce(a.obs, '{}'::jsonb),
    'pesos', coalesce(a.pesos, '{}'::jsonb)
  )
  from students s
  join trainers t on t.id = s.trainer_id
  left join annotations a on a.student_id = s.id
  where s.access_token = p_token
$$;

-- Salva anotacoes do aluno dono do token
create or replace function public.save_annotations_by_token(
  p_token uuid, p_semana integer, p_obs jsonb, p_pesos jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_student_id uuid;
begin
  select id into v_student_id from students where access_token = p_token;
  if v_student_id is null then
    raise exception 'Link invalido';
  end if;
  -- limite de tamanho (anon pode chamar direto pela API; evita encher o banco)
  if octet_length(coalesce(p_obs, '{}')::text) + octet_length(coalesce(p_pesos, '{}')::text) > 200000 then
    raise exception 'Anotacoes muito grandes';
  end if;
  insert into annotations (student_id, semana_atual, obs, pesos, updated_at)
  values (v_student_id, coalesce(p_semana, 1), coalesce(p_obs, '{}'), coalesce(p_pesos, '{}'), now())
  on conflict (student_id) do update
    set semana_atual = excluded.semana_atual,
        obs = excluded.obs,
        pesos = excluded.pesos,
        updated_at = now();
end;
$$;

-- Grants
grant select on companies, trainers to authenticated;
grant select, insert, update, delete on students to authenticated;
grant select, insert, update on annotations to authenticated;
grant select, insert, delete on appointments to authenticated;
revoke execute on function public.my_trainer_id() from public, anon;
grant execute on function public.my_trainer_id() to authenticated;

revoke execute on function public.student_by_token(uuid) from public;
revoke execute on function public.save_annotations_by_token(uuid, integer, jsonb, jsonb) from public;
grant execute on function public.student_by_token(uuid) to anon, authenticated;
grant execute on function public.save_annotations_by_token(uuid, integer, jsonb, jsonb) to anon, authenticated;
