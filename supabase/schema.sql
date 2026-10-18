-- Four Fit - schema (rodar no SQL Editor do Supabase)
-- Vinculo usuario <-> treinador/aluno eh pelo email do login (auth.jwt()->>'email').

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
  email text not null unique,          -- sempre minusculo
  workout jsonb,                       -- JSON gerado pelo parser do PDF
  workout_updated_at timestamptz,
  created_at timestamptz default now()
);

create table annotations (
  student_id uuid primary key references students(id) on delete cascade,
  semana_atual integer default 1,
  obs jsonb default '{}',              -- { "treino-1-ex-1": "texto", ... }
  pesos jsonb default '{}',            -- { "treino-1-ex-1": { "15": "80", ... }, ... }
  updated_at timestamptz default now()
);

create index idx_students_trainer on students (trainer_id);

-- id do treinador logado (security definer evita recursao de RLS)
create or replace function public.my_trainer_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from trainers where email = lower(auth.jwt()->>'email')
$$;

alter table companies enable row level security;
alter table trainers enable row level security;
alter table students enable row level security;
alter table annotations enable row level security;

-- Treinador ve o proprio cadastro e a propria empresa
create policy trainers_select_own on trainers
  for select using (email = lower(auth.jwt()->>'email'));

create policy companies_select_own on companies
  for select using (id in (select company_id from trainers));

-- Aluno ve o proprio cadastro (com o treino); treinador ve/gerencia seus alunos
create policy students_select on students
  for select using (
    email = lower(auth.jwt()->>'email') or trainer_id = public.my_trainer_id()
  );

create policy students_insert on students
  for insert with check (trainer_id = public.my_trainer_id());

create policy students_update on students
  for update using (trainer_id = public.my_trainer_id())
  with check (trainer_id = public.my_trainer_id());

create policy students_delete on students
  for delete using (trainer_id = public.my_trainer_id());

-- Anotacoes: quem enxerga o aluno (ele mesmo ou o treinador dele) le e grava
create policy annotations_all on annotations
  for all using (student_id in (select id from students))
  with check (student_id in (select id from students));

grant select on companies, trainers to authenticated;
grant select, insert, update, delete on students to authenticated;
grant select, insert, update on annotations to authenticated;
grant execute on function public.my_trainer_id() to authenticated;
