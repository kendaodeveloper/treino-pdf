# Site Four Fit - Design Spec

**Data:** 2026-10-17
**Status:** Rascunho (reformulacao de `2026-09-20-app-mobile-treino-design.md` para web-only)

---

## Visao Geral

Site responsivo (mobile-first) para alunos da consultoria Four Fit visualizarem seus treinos e registrarem cargas, repeticoes e observacoes. Treinadores tambem acessam o site para acompanhar/editar treinos dos alunos como se fossem eles.

**Nao ha apps nativos (iOS/Android).** O acesso eh pelo navegador do celular ou desktop. O site pode ser "instalado" na tela inicial como PWA (atalho com icone e tela cheia), sem passar por App Store ou Google Play.

### O que mudou em relacao a spec mobile (2026-09-20)

| Item | Spec mobile | Esta spec (web) |
|------|-------------|-----------------|
| Plataforma | React Native + Expo (iOS + Android) | React + Vite (navegador) |
| Distribuicao | App Store + Google Play (EAS Build) | URL publica + PWA instalavel |
| Videos YouTube | react-native-youtube-iframe | `<iframe>` do YouTube (youtube-nocookie) |
| Videos outros | Linking.openURL | `<a target="_blank" rel="noopener">` |
| Navegacao | React Navigation (Tab/Stack) | React Router (rotas por URL) |
| Contas de dev | Apple ($99/ano) + Google ($25) | Nenhuma |
| Reaproveitamento do index.html | Reescrever UI em componentes RN | Portar HTML/CSS quase direto para JSX (tabelas, rowspan, selects) |
| Estimativa | ~120h | ~65-100h |

Backend (Supabase), modelo de dados, RLS, regras de dimming e formato do JSON **nao mudam**.

## Escopo

### Dentro do escopo (este projeto)
- Site com React + Vite + TypeScript, mobile-first
- Login com email/senha (Supabase Auth)
- Dashboard de treino (portar renderizacao do index.html atual)
- Tracking de cargas (peso por rep range), repeticoes e observacoes
- Seletor de semana com dimming (after-weeks + body-type)
- Cronometro flutuante
- Videos do YouTube embeddados inline; demais links abrem em nova aba
- Perfil treinador: lista de alunos, acessa treino como se fosse o aluno
- Persistencia em Supabase (Postgres + RLS)
- PWA basico: manifest + icones para "Adicionar a tela inicial" (sem offline)

### Fora do escopo (projeto futuro: area do treinador)
- Cadastro de alunos
- Import de PDF e parsing
- Gestao de treinos (criar, editar JSON, atribuir a alunos)
- Painel administrativo

Como agora tudo eh web, a area do treinador pode ser construida **no mesmo projeto** (rotas `/admin/*`) em vez de um site separado — ver Decisoes de Design.

## Arquitetura

```
+---------------------------------------------+
|              Site (React + Vite)            |
|                                             |
|  /login  /treino  /alunos  /perfil          |
|  /admin/* (futuro: import PDF, cadastros)   |
+----------------------+----------------------+
                       |
                       | supabase-js (anon key + sessao do usuario)
                       |
                +------v------+
                |  Supabase   |
                |  - Auth     |
                |  - Postgres |
                |  - RLS      |
                +-------------+
```

Um unico frontend web, um backend compartilhado. Hospedagem estatica (SPA) — nao ha servidor proprio na v1.

## Stack Tecnica

| Camada | Tecnologia |
|--------|-----------|
| Frontend | React 19 + Vite |
| Linguagem | TypeScript |
| Roteamento | React Router |
| Estilo | CSS Modules ou CSS puro (portado do `<style>` do index.html) |
| Backend/DB | Supabase (Postgres) |
| Auth | Supabase Auth (email/senha) |
| Seguranca | Row Level Security (RLS) |
| Videos YouTube | `<iframe>` (`youtube-nocookie.com/embed/...`) |
| Videos outros | Link em nova aba |
| PWA | vite-plugin-pwa (manifest + icones; service worker sem cache offline) |
| Deploy | Vercel, Netlify ou Cloudflare Pages (free tier) |

### Seguranca de chaves
- O frontend usa apenas a **anon key** do Supabase (publica por design; a protecao vem do RLS).
- A **service key nunca vai para o frontend** nem para o repositorio. Operacoes que precisam dela (cadastro de alunos, import de treinos) ficam para a area do treinador, executadas via Supabase Edge Function ou backend com a chave em variavel de ambiente/secret manager.
- URL e anon key via variaveis de ambiente do Vite (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`), configuradas no painel do provedor de deploy.

## Modelo de Dados (Supabase)

Identico a spec mobile.

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

-- INSERT/UPDATE/DELETE de workouts e students: apenas via service key (area do treinador, server-side)
-- Service key bypassa RLS, portanto nao precisa de policies para essas operacoes
-- Nao ha policies de INSERT para workouts/students com anon key (frontend)

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

| Tabela | Aluno | Treinador | Service key (server-side) |
|--------|-------|-----------|-------------------|
| trainers | - | SELECT (proprio) | INSERT/UPDATE |
| students | SELECT (proprio) | SELECT (seus alunos) | INSERT/UPDATE |
| workouts | SELECT (seus) | SELECT (de seus alunos) | INSERT/UPDATE/DELETE |
| annotations | SELECT/INSERT/UPDATE (seus) | SELECT/INSERT/UPDATE (de seus alunos) | - |

## Modulos do Site

### 1. Auth (4-6h)
- Pagina de login (email + senha)
- Sessao persistente (supabase-js guarda a sessao no localStorage e faz refresh automatico)
- Logout
- Deteccao automatica de role (treinador vs aluno) via tabela trainers/students
- Rotas protegidas: sem sessao -> redireciona para `/login`
- Configurar Site URL / Redirect URLs no Supabase Auth com o dominio do site

### 2. Selecao de Aluno - apenas treinador (3-5h)
- Lista de alunos vinculados ao treinador (`/alunos`)
- Clique em aluno -> `/alunos/:studentId` (dashboard do aluno)
- Banner fixo "Visualizando como [nome do aluno]" com link para voltar a lista

### 3. Dashboard do Treino (20-30h) -- MODULO PRINCIPAL
Portar a renderizacao do index.html (`renderWorkoutVisual`) para componentes React. Como continua sendo HTML, a estrutura de tabelas (`<tbody class="exercise-group">`, `rowspan`, `colspan`) e o CSS atual podem ser reaproveitados quase integralmente.

- **Info do aluno**: card com treinador, aluno, idade, objetivo, frequencia, duracao, descanso
- **Semana atual**: seletor semanas 1-12
- **Periodizacao**: tabela com semana, periodo, series, descanso, cadencia, falha, metodo
- **Metodos**: cards por semana (condicional, so se existir no JSON)
- **Alongamentos e Mobilidades**: tabela com seq, tempo, nome, video
- **Manobras Respiratorias**: tabela com seq, series, nome, video
- **Treinos** (accordion, 1 aberto por vez):
  - Auto-abre treino do dia (`treinoMatchesToday`)
  - Header com dias/foco (mesma regra do index.html: sem dias da semana -> prefixa com identificador)
  - Aquecimento: exercicios com reps e video
  - Exercicios: agrupados por seq, sub-exercicios, rowspan
  - Aerobio: exercicio com duracao e video
  - Relaxamento: exercicio com reps e video

Layout responsivo: mobile-first (uso principal na academia, pelo celular), com largura maxima centralizada no desktop.

### 4. Tracking de Cargas (6-8h)
- 5 `<select>` nativos por exercicio (rep ranges: 15/12/10/8/6) — no celular abrem o picker nativo do sistema
- Range de peso: 1-500kg
- Pesos de sub-exercicios: chave `treino-X-ex-Y-sub-Z`
- Pesos de aquecimento: chave `treino-X-warm-Y`
- Sync com Supabase (debounce)

### 5. Observacoes (3-4h)
- Textarea por grupo de exercicio
- Textarea para aquecimento
- Sync com Supabase (debounce)

### 6. Semana Atual + Dimming (8-12h)
- Seletor de semana persiste no Supabase (campo `semana_atual` em annotations)
- **Dimming por semana** (equivalente a `applyExerciseDimming`): calculado no render (prop/classe `dimmed`), nao mais via manipulacao de DOM
  - `afterWeek` eh extraido do campo `nome` do exercicio em runtime usando regex: `/ap[oó]s\s+(?:a\s+)?(\d+)\s*[ªº]?\s+semanas?/i` e `/ESSE\s+EXERC[IÍ]CIO\s+AP[OÓ]S\s+A\s+(\d+)[ªº]?\s+SEMANA/i`
  - Mesma logica do `getAfterWeek()` do index.html — nao existe campo `afterWeek` no JSON, eh derivado do nome
  - Se semanaAtual <= N: dim sub-exercicio (ainda nao ativo), e a propria linha no caso standalone (selfAfterWeek)
  - Se semanaAtual > N e tem replacement: dim exercicio principal (substituido)
  - Weight rows seguem o dimming da linha a que pertencem
- **Dimming por tipo de corpo** (equivalente a `applyBodyTypeDimming`): MMII/MMSS baseado no treino aberto
  - MMII: `/mmii|perna|inferior|panturrilha|gl[úu]teo|coxa/i`
  - MMSS: `/mmss|superior|dorsa[il]s?|peito(?:ral)?|costas|b[ií]ceps|tr[ií]ceps|ombro|deltoid|bra[cç]o/i`
  - Treino com ambos ou sem match: sem dimming (tudo visivel)
  - Aplica em alongamentos/manobras marcados com "(DIAS DE/DOS MMII/MMSS)"
- As duas logicas sao combinadas (OR): um item fica dimmed se qualquer uma das regras mandar

### 7. Cronometro (2-4h)
- Stopwatch (contagem progressiva), acionado manualmente pelo usuario
- Floating fixo na parte inferior da tela (`position: fixed`)
- Play/pause/reset
- Formato MM:SS:000
- Max 30 minutos (para ao atingir)
- Calculado por timestamp (`Date.now()` no start), nao por contagem de ticks — navegadores reduzem timers em aba de segundo plano, mas o tempo exibido continua correto ao voltar
- Nao persiste entre rotas (reseta ao sair do treino)

### 8. Videos (2-4h)
- Detecta URL do YouTube -> abre player inline (`<iframe>` em modal ou expandido abaixo do exercicio), carregado so ao clicar (lazy)
- Demais URLs (Google Drive, Vimeo, Streamable, Loom) -> nova aba
- Botao de video ao lado do nome do exercicio

### 9. Backend Supabase (6-10h)
- Schema SQL + migrations (Supabase CLI)
- RLS policies (aluno, treinador)
- Indexes para performance
- Seed data para testes (usando os JSONs de `teste/`)

### 10. Testes e QA (8-12h)
- Testar com todos os JSONs da pasta `teste/`
- Navegadores alvo: Safari iOS, Chrome Android, Chrome/Safari/Firefox desktop
- Testar PWA instalado (iOS "Adicionar a Tela de Inicio" e Android "Instalar app")
- Edge cases: treino sem dias da semana, Biset, Superserie, Pos-exaustao, metodos opcionais
- Testes unitarios (Vitest) para as funcoes puras portadas: `getAfterWeek`, deteccao MMII/MMSS, `treinoMatchesToday`, montagem de headers
- v1 eh online-only (requer conexao com internet)

### 11. Deploy (2-4h)
- Projeto no Vercel/Netlify/Cloudflare Pages conectado ao repositorio (deploy automatico no push para `main`, preview por PR)
- Variaveis de ambiente (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`)
- Rewrite de SPA (todas as rotas -> `index.html`)
- Dominio proprio + HTTPS (automatico no provedor)
- Manifest PWA + icones

## Estimativa Total

| Cenario | Horas | Custo |
|---------|:-----:|:-----:|
| Voce mesmo com Claude Code | ~65-100h do seu tempo | R$ 0-100 (dominio) |
| Dev freelancer junior/pleno | 65-100h | R$ 5.500-14.500 |
| Dev freelancer senior/agencia | 55-85h | R$ 8.000-25.000 |

### Custos recorrentes

| Item | Custo |
|------|:-----:|
| Hospedagem (Vercel/Netlify/Cloudflare Pages free tier) | R$ 0/mes |
| Supabase Free Tier (ate 500MB, 50k users) | R$ 0/mes |
| Supabase Pro (se crescer) | ~R$ 130/mes ($25) |
| Dominio `.com.br` | ~R$ 40/ano |

Sem custos de Apple Developer Account nem Google Play Console.

## Estrutura de JSON (referencia)

O site consome o mesmo JSON que o parser do index.html ja gera. Estrutura completa documentada no CLAUDE.md do projeto. Campos principais:

- `treinador`, `aluno`, `idade`, `objetivo`, `frequencia`, `duracao_total`, `descanso`
- `periodizacao[]`: semana, periodo, series, descanso, cadencia, falha, metodo
- `metodos[]`: semana, periodo, metodo, descricao
- `alongamentos[]`: seq, tempo, exercicio, isSubExercise, video
- `manobras[]`: seq, series, exercicio, isSubExercise, video
- `treinos[]`: identificador, dias_e_foco, aquecimento[], exercicios[], aerobio[], relaxamento[]

## Rotas

```
Publico:
  /login                    -> LoginPage

Aluno (autenticado):
  /treino                   -> DashboardPage (treino completo, accordion, tracking)
  /perfil                   -> PerfilPage (logout, info basica)

Treinador (autenticado):
  /alunos                   -> StudentListPage (lista de alunos)
  /alunos/:studentId        -> DashboardPage (mesmo componente, contexto do aluno selecionado)
  /perfil                   -> PerfilPage (logout)

Futuro:
  /admin/*                  -> area do treinador (import PDF, cadastros)
```

Deteccao de role no login: consulta `trainers` e `students` pelo `auth.uid()`. Se encontra em `trainers`, redireciona para `/alunos`. Se encontra em `students`, redireciona para `/treino`. Rotas de treinador acessadas por aluno redirecionam para `/treino` (o RLS ja impede o acesso aos dados; o guard eh so de UX).

A URL `/alunos/:studentId` permite ao treinador favoritar/compartilhar o link direto do treino de um aluno.

## State Management

- **Zustand** para estado global (usuario autenticado, role, semana atual)
- **Aluno selecionado pelo treinador**: vem da URL (`:studentId`), nao do store
- **React Query (TanStack Query)** para cache e sync de dados do Supabase (workouts, annotations)
- **Estado local** (useState) para UI transiente (accordion aberto, cronometro, inputs em edicao)

## Data Fetching

- **Workouts**: fetch unico ao montar DashboardPage, cached pelo React Query. Re-fetch ao focar a aba (`refetchOnWindowFocus`) ou recarregar a pagina.
- **Annotations**: fetch ao montar + upsert com debounce de 500ms ao editar peso/obs. Usa `ON CONFLICT (workout_id, student_id) DO UPDATE`.
- **Flush ao sair**: ao trocar de rota ou esconder a aba (`visibilitychange`), dispara o upsert pendente imediatamente para nao perder a ultima edicao.
- **Sem real-time/subscriptions na v1**: simplicidade. Treinador ve dados atualizados ao abrir o treino do aluno.
- **Sem offline na v1**: site requer conexao. Erro de rede mostra toast com retry.

## Workout Versioning (re-import)

Quando o treinador re-importa um PDF (area do treinador, futuro):
- Cria um novo row em `workouts` com `version` incrementado e `is_active = true`
- O workout antigo fica com `is_active = false` (soft delete)
- Annotations antigas continuam vinculadas ao workout antigo (nao sao deletadas)
- O site mostra apenas o workout ativo (`is_active = true`)
- **Limitacao conhecida**: chaves de peso/obs sao posicionais (treino-1-ex-3). Se a ordem dos exercicios mudar no novo PDF, as annotations do workout antigo nao migram automaticamente. Isso eh aceitavel na v1 — o aluno recomeca o tracking no novo treino.

## Decisoes de Design

1. **Web-only, sem apps nativos**: elimina contas de desenvolvedor, revisao de lojas e builds por plataforma. Um deploy atualiza todos os usuarios na hora.
2. **PWA basico em vez de app nativo**: o aluno pode instalar o atalho na tela inicial e abrir em tela cheia, com experiencia proxima de app, sem custo de loja.
3. **React + Vite (SPA) em vez de Next.js**: nao ha necessidade de SEO nem SSR (tudo atras de login); SPA estatica eh mais simples de hospedar e se aproxima do index.html atual.
4. **Reaproveitar HTML/CSS do index.html**: o dashboard atual ja eh mobile-first e funciona; portar para JSX reduz bastante o esforco frente a reescrever em React Native.
5. **Dimming declarativo**: as regras de `applyExerciseDimming`/`applyBodyTypeDimming` viram funcoes puras que retornam se um item esta dimmed, aplicadas no render — mais testavel que a versao atual baseada em DOM.
6. **JSON como fonte de verdade**: o site do aluno nao parseia PDF — recebe o JSON pronto.
7. **Annotations separadas do workout**: permite re-import de PDF sem perder cargas/obs (vinculadas a versao especifica).
8. **RLS ao inves de middleware**: seguranca no nivel do banco; o frontend so tem a anon key.
9. **Debounce no sync + flush ao sair**: evita requests excessivos e nao perde a ultima edicao.
10. **YouTube inline, resto em nova aba**: melhor UX para o caso mais comum sem embedar todos os players.
11. **Online-only na v1**: evita complexidade de sync/conflitos offline.
12. **afterWeek derivado em runtime**: nao existe campo afterWeek no JSON — eh extraido do nome do exercicio com regex, igual ao index.html.
13. **Area do treinador no mesmo projeto (futuro)**: como tudo eh web, o import de PDF (parser atual do index.html) e os cadastros podem viver em `/admin/*` no mesmo codebase, compartilhando componentes e tipos. Operacoes com service key ficam server-side (Edge Function).

## Escopo Futuro

- Area do treinador (`/admin/*`): import de PDF, cadastro de alunos, gestao de treinos
- Offline com cache via service worker + sync
- Notificacoes (Web Push — no iOS so funciona com o PWA instalado)
- Screen Wake Lock durante o treino (evitar que a tela apague)
- Historico de pesos por exercicio (grafico de evolucao)
- Suporte a peso decimal (2.5kg increments)
- Migracao de annotations entre versoes de workout
- Importar anotacoes existentes do localStorage do index.html atual
