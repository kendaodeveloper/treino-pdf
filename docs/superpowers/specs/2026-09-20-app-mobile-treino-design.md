# App Mobile Four Fit - Design Spec

**Data:** 2026-09-20
**Status:** Aprovado pelo usuario

---

## Visao Geral

App mobile (iOS + Android) para alunos da consultoria Four Fit visualizarem seus treinos e registrarem cargas, repeticoes e observacoes. Treinadores tambem acessam o app para acompanhar/editar treinos dos alunos como se fossem eles.

## Escopo

### Dentro do escopo (este projeto)
- App mobile com React Native + Expo
- Login com email/senha (Supabase Auth)
- Dashboard de treino (portar renderizacao do index.html atual)
- Tracking de cargas (peso por rep range), repeticoes e observacoes
- Seletor de semana com dimming (after-weeks + body-type)
- Cronometro flutuante
- Videos do YouTube embeddados no app; demais links abrem externamente
- Perfil treinador: lista de alunos, acessa treino como se fosse o aluno
- Persistencia em Supabase (Postgres + RLS)

### Fora do escopo (projeto futuro: site do treinador)
- Cadastro de alunos
- Import de PDF e parsing
- Gestao de treinos (criar, editar JSON, atribuir a alunos)
- Painel administrativo

## Arquitetura

```
+-------------------+     +-------------------+
|   App Mobile      |     |  Site Treinador   |
|  (React Native    |     |  (futuro)         |
|   + Expo)         |     |                   |
+---------+---------+     +---------+---------+
          |                         |
          +------------+------------+
                       |
                +------v------+
                |  Supabase   |
                |  - Auth     |
                |  - Postgres |
                |  - RLS      |
                +-------------+
```

Dois produtos separados, um backend compartilhado.

## Stack Tecnica

| Camada | Tecnologia |
|--------|-----------|
| App Mobile | React Native + Expo (SDK mais recente) |
| Linguagem | TypeScript |
| Backend/DB | Supabase (Postgres) |
| Auth | Supabase Auth (email/senha) |
| Seguranca | Row Level Security (RLS) |
| Videos YouTube | react-native-youtube-iframe ou WebView |
| Videos outros | Linking.openURL (abre externamente) |
| Deploy | Expo EAS Build -> App Store + Google Play |

## Modelo de Dados (Supabase)

```sql
-- Treinadores
create table trainers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null unique,
  name text not null,
  email text not null unique,
  created_at timestamptz default now()
);

-- Alunos
create table students (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null unique,
  trainer_id uuid references trainers(id) not null,
  name text not null,
  email text not null unique,
  created_at timestamptz default now()
);

-- Treinos (JSON completo vindo do parser)
create table workouts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references students(id) not null,
  json_data jsonb not null,
  version integer default 1,
  is_active boolean default true,
  imported_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Anotacoes (substitui localStorage)
create table annotations (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid references workouts(id) not null,
  student_id uuid references students(id) not null,
  semana_atual integer default 1,
  obs jsonb default '{}',       -- { "treino-1-ex-1": "texto", ... }
  pesos jsonb default '{}',     -- { "treino-1-ex-1": { "15": 80, "12": 85 }, ... }
  updated_at timestamptz default now(),
  unique (workout_id, student_id)
);
```

### RLS Policies

```sql
-- Habilitar RLS em todas as tabelas
alter table trainers enable row level security;
alter table students enable row level security;
alter table workouts enable row level security;
alter table annotations enable row level security;

-- TRAINERS: treinador ve apenas seu proprio perfil
create policy "trainer_reads_own" on trainers
  for select using (user_id = auth.uid());

-- STUDENTS: aluno ve apenas seu proprio perfil
create policy "student_reads_own" on students
  for select using (user_id = auth.uid());

-- STUDENTS: treinador ve seus alunos
create policy "trainer_reads_students" on students
  for select using (
    trainer_id in (select id from trainers where user_id = auth.uid())
  );

-- WORKOUTS: aluno ve apenas seus treinos
create policy "student_reads_own_workouts" on workouts
  for select using (
    student_id in (select id from students where user_id = auth.uid())
  );

-- WORKOUTS: treinador ve treinos dos seus alunos
create policy "trainer_reads_student_workouts" on workouts
  for select using (
    student_id in (
      select s.id from students s
      join trainers t on s.trainer_id = t.id
      where t.user_id = auth.uid()
    )
  );

-- ANNOTATIONS: aluno le/cria/atualiza suas anotacoes
create policy "student_reads_own_annotations" on annotations
  for select using (
    student_id in (select id from students where user_id = auth.uid())
  );

create policy "student_inserts_own_annotations" on annotations
  for insert with check (
    student_id in (select id from students where user_id = auth.uid())
  );

create policy "student_updates_own_annotations" on annotations
  for update using (
    student_id in (select id from students where user_id = auth.uid())
  );

-- ANNOTATIONS: treinador le/cria/atualiza anotacoes dos seus alunos
create policy "trainer_reads_student_annotations" on annotations
  for select using (
    student_id in (
      select s.id from students s
      join trainers t on s.trainer_id = t.id
      where t.user_id = auth.uid()
    )
  );

create policy "trainer_inserts_student_annotations" on annotations
  for insert with check (
    student_id in (
      select s.id from students s
      join trainers t on s.trainer_id = t.id
      where t.user_id = auth.uid()
    )
  );

create policy "trainer_updates_student_annotations" on annotations
  for update using (
    student_id in (
      select s.id from students s
      join trainers t on s.trainer_id = t.id
      where t.user_id = auth.uid()
    )
  );

-- INSERT/UPDATE/DELETE de workouts e students: apenas via service key (site do treinador)
-- Service key bypassa RLS, portanto nao precisa de policies para essas operacoes
-- Nao ha policies de INSERT para workouts/students com anon key (app mobile)

-- Trigger para atualizar updated_at automaticamente
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger workouts_updated_at before update on workouts
  for each row execute function update_updated_at();

create trigger annotations_updated_at before update on annotations
  for each row execute function update_updated_at();

-- Indexes para performance
create index idx_workouts_student_active on workouts (student_id, is_active);
create index idx_students_trainer on students (trainer_id);
-- annotations (workout_id, student_id) ja tem index via UNIQUE constraint
```

**Resumo de permissoes:**

| Tabela | Aluno | Treinador | Service key (site) |
|--------|-------|-----------|-------------------|
| trainers | - | SELECT (proprio) | INSERT/UPDATE |
| students | SELECT (proprio) | SELECT (seus alunos) | INSERT/UPDATE |
| workouts | SELECT (seus) | SELECT (de seus alunos) | INSERT/UPDATE/DELETE |
| annotations | SELECT/INSERT/UPDATE (seus) | SELECT/INSERT/UPDATE (de seus alunos) | - |

## Modulos do App

### 1. Auth (6-10h)
- Tela de login (email + senha)
- Sessao persistente (Supabase session refresh)
- Logout
- Deteccao automatica de role (treinador vs aluno) via tabela trainers/students

### 2. Selecao de Aluno - apenas treinador (4-6h)
- Lista de alunos vinculados ao treinador
- Tap em aluno -> entra no dashboard do aluno
- Indicador visual de "visualizando como [nome do aluno]"

### 3. Dashboard do Treino (30-45h) -- MODULO PRINCIPAL
Portar a renderizacao do index.html para React Native components:

- **Info do aluno**: card com treinador, aluno, idade, objetivo, frequencia, duracao, descanso
- **Semana atual**: seletor (radio/picker) semanas 1-12
- **Periodizacao**: tabela/cards com semana, periodo, series, descanso, cadencia, falha, metodo
- **Metodos**: cards por semana (condicional, so se existir no JSON)
- **Alongamentos e Mobilidades**: tabela com seq, tempo, nome, video
- **Manobras Respiratorias**: tabela com seq, series, nome, video
- **Treinos** (accordion, 1 aberto por vez):
  - Auto-abre treino do dia
  - Header com dias/foco
  - Aquecimento: exercicios com reps e video
  - Exercicios: agrupados por seq, sub-exercicios, rowspan visual
  - Aerobio: exercicio com duracao e video
  - Relaxamento: exercicio com reps e video

### 4. Tracking de Cargas (8-12h)
- 5 selects por exercicio (rep ranges: 15/12/10/8/6)
- Range de peso: 1-500kg
- Pesos de sub-exercicios: chave `treino-X-ex-Y-sub-Z`
- Pesos de aquecimento: chave `treino-X-warm-Y`
- Sync com Supabase (debounce para nao spammar requests)

### 5. Observacoes (4-6h)
- Textarea por grupo de exercicio
- Textarea para aquecimento
- Sync com Supabase (debounce)

### 6. Semana Atual + Dimming (10-15h)
- Seletor de semana persiste no Supabase (campo `semana_atual` em annotations)
- **applyExerciseDimming**: logica de after-weeks e has-replacement
  - `afterWeek` eh extraido do campo `nome` do exercicio em runtime usando regex: `/ap[oó]s\s+(?:a\s+)?(\d+)\s*[ªº]?\s+semanas?/i` e `/ESSE\s+EXERC[IÍ]CIO\s+AP[OÓ]S\s+A\s+(\d+)[ªº]?\s+SEMANA/i`
  - Mesma logica do `getAfterWeek()` do index.html — nao existe campo `afterWeek` no JSON, eh derivado do nome
  - Se semanaAtual <= N: dim sub-exercicio (ainda nao ativo)
  - Se semanaAtual > N e tem replacement: dim exercicio principal (substituido)
- **applyBodyTypeDimming**: MMII/MMSS baseado no treino aberto
  - MMII: `/mmii|perna|inferior|panturrilha|gl[úu]teo|coxa/i`
  - MMSS: `/mmss|superior|dorsa[il]s?|peito(?:ral)?|costas|b[ií]ceps|tr[ií]ceps|ombro|deltoid|bra[cç]o/i`
  - Treino com ambos: sem dimming (tudo visivel)
- Dimming de weight rows adjacentes

### 7. Cronometro (3-5h)
- Stopwatch (contagem progressiva), acionado manualmente pelo usuario
- Floating na parte inferior da tela
- Play/pause/reset
- Formato MM:SS:000
- Max 30 minutos (para ao atingir)
- Nao persiste entre navegacoes de tela (reseta ao sair do treino)
- Nao roda em background (apenas enquanto app esta em foreground)

### 8. Videos (4-6h)
- Detecta URL do YouTube -> embeda com react-native-youtube-iframe (player inline)
- Demais URLs (Google Drive, Vimeo, Streamable, Loom) -> Linking.openURL
- Botao de video ao lado do nome do exercicio

### 9. Backend Supabase (6-10h)
- Schema SQL + migrations
- RLS policies (aluno, treinador)
- Indexes para performance
- Seed data para testes

### 10. Testes e QA (10-15h)
- Testar com todos os 10 JSONs da pasta teste/
- Testar em iOS e Android (Expo Go + build)
- Edge cases: treino sem dias da semana, Biset, Superserie, Pos-exaustao, metodos opcionais
- v1 eh online-only (requer conexao com internet para funcionar)

### 11. Deploy (6-10h)
- Expo EAS Build configuracao
- Apple Developer Account setup
- Google Play Console setup
- Primeiro build para as lojas

## Estimativa Total

| Cenario | Horas | Custo |
|---------|:-----:|:-----:|
| Voce mesmo com Claude Code | ~120h do seu tempo | R$ 1.500-3.000 (infra + contas dev) |
| Dev freelancer junior/pleno | 120-150h | R$ 10.000-22.000 |
| Dev freelancer senior/agencia | 100-130h | R$ 15.000-39.000 |

### Custos recorrentes

| Item | Custo |
|------|:-----:|
| Supabase Free Tier (ate 500MB, 50k users) | R$ 0/mes |
| Supabase Pro (se crescer) | ~R$ 130/mes ($25) |
| Apple Developer Account | ~R$ 520/ano ($99) |
| Google Play Console | ~R$ 130 one-time ($25) |

## Estrutura de JSON (referencia)

O app consome o mesmo JSON que o parser do index.html ja gera. Estrutura completa documentada no CLAUDE.md do projeto. Campos principais:

- `treinador`, `aluno`, `idade`, `objetivo`, `frequencia`, `duracao_total`, `descanso`
- `periodizacao[]`: semana, periodo, series, descanso, cadencia, falha, metodo
- `metodos[]`: semana, periodo, metodo, descricao
- `alongamentos[]`: seq, tempo, exercicio, isSubExercise, video
- `manobras[]`: seq, series, exercicio, isSubExercise, video
- `treinos[]`: identificador, dias_e_foco, aquecimento[], exercicios[], aerobio[], relaxamento[]

## Navegacao

```
Auth Stack (nao autenticado):
  - LoginScreen

Aluno (Tab Navigator):
  - DashboardScreen (treino completo, accordion, tracking)
  - PerfilScreen (logout, info basica)

Treinador (Stack Navigator):
  - StudentListScreen (lista de alunos)
  - StudentDashboardScreen (mesmo componente que DashboardScreen, contexto do aluno selecionado)
  - PerfilScreen (logout)
```

Deteccao de role no login: consulta `trainers` e `students` pelo `auth.uid()`. Se encontra em `trainers`, vai para o fluxo treinador. Se encontra em `students`, vai direto pro dashboard.

## State Management

- **Zustand** para estado global (usuario autenticado, role, aluno selecionado pelo treinador, semana atual)
- **React Query (TanStack Query)** para cache e sync de dados do Supabase (workouts, annotations)
- **Estado local** (useState) para UI transiente (accordion aberto, cronometro, inputs em edicao)

## Data Fetching

- **Workouts**: fetch unico ao montar DashboardScreen, cached pelo React Query. Re-fetch ao fazer pull-to-refresh.
- **Annotations**: fetch ao montar + upsert com debounce de 500ms ao editar peso/obs. Usa `ON CONFLICT (workout_id, student_id) DO UPDATE`.
- **Sem real-time/subscriptions na v1**: simplicidade. Treinador ve dados atualizados ao abrir o treino do aluno (fetch on mount).
- **Sem offline na v1**: app requer conexao. Erro de rede mostra toast/snackbar com retry.

## Workout Versioning (re-import)

Quando o treinador re-importa um PDF pelo site:
- O site cria um novo row em `workouts` com `version` incrementado e `is_active = true`
- O workout antigo fica com `is_active = false` (soft delete)
- Annotations antigas continuam vinculadas ao workout antigo (nao sao deletadas)
- O app mobile mostra apenas o workout ativo (`is_active = true`)
- **Limitacao conhecida**: chaves de peso/obs sao posicionais (treino-1-ex-3). Se a ordem dos exercicios mudar no novo PDF, as annotations do workout antigo nao migram automaticamente. Isso eh aceitavel na v1 — o aluno recomeça o tracking no novo treino.

## Decisoes de Design

1. **JSON como fonte de verdade**: o app nao parseia PDF — recebe o JSON pronto do site do treinador
2. **Annotations separadas do workout**: permite re-import de PDF sem perder cargas/obs (vinculadas a versao especifica)
3. **RLS ao inves de middleware**: seguranca no nivel do banco, nao na API
4. **Debounce no sync**: evita requests excessivos ao editar pesos/obs rapidamente
5. **YouTube inline, resto externo**: melhor UX para o caso mais comum (YouTube) sem complexidade de embedar todos os players
6. **Expo EAS**: simplifica build e deploy sem precisar de Xcode/Android Studio localmente
7. **Online-only na v1**: evita complexidade de sync/conflitos offline. Offline fica para v2 se necessario.
8. **afterWeek derivado em runtime**: nao existe campo afterWeek no JSON — eh extraido do nome do exercicio com regex, igual ao index.html. Evita mudar o formato do JSON que o parser ja gera.

## Escopo Futuro (alem do site do treinador)

- Offline com cache local + sync
- Push notifications (lembrete de treino)
- Historico de pesos por exercicio (grafico de evolucao)
- Suporte a peso decimal (2.5kg increments)
- Migracao de annotations entre versoes de workout
