# Passo a passo - Colocar o site Four Fit no ar

Ordem: **Supabase -> GitHub -> Cloudflare -> Teste**. Marque os `[ ]` conforme for fazendo.

- **Treinador**: entra com email/senha.
- **Aluno**: nao tem login. Acessa por um link secreto (`.../?t=<codigo>`) que o treinador copia no site e envia (ex: WhatsApp).

O que vai pro ar eh a pasta `site/`. O `index.html` da raiz (GitHub Pages) continua igual.

---

## Parte 1 - Supabase (banco + login dos treinadores)

### 1.1 Projeto
- [ ] Ja tem o projeto criado. Se for recomecar do zero: **SQL Editor** > colar `supabase/reset.sql` > **Run** (apaga tabelas, funcoes e TODOS os logins)
- [ ] Data API: **Enable Data API** ligado, **Automatically expose new tables** desligado, **Enable automatic RLS** ligado

### 1.2 Criar as tabelas
- [ ] **SQL Editor** > **New query** > colar todo o `supabase/schema.sql` > **Run**
- [ ] Deve aparecer "Success. No rows returned"
- O `schema.sql` eh para projeto limpo (os `create table` falham se as tabelas ja existem). Se o banco ja esta no ar e o `schema.sql` mudou, rode so o trecho alterado (ex: os `create or replace function` e o `drop policy` + `create policy` correspondentes) em vez do `reset.sql`, que apaga alunos e logins

### 1.3 Cadastrar empresa e treinadores
- [ ] Conferir nomes/emails em `supabase/seed.sql` (emails em minusculo)
- [ ] **SQL Editor** > **New query** > colar o seed > **Run**
- [ ] Conferir em **Table Editor > trainers**

### 1.4 Configurar o login
- [ ] **Authentication** > **Sign In / Providers** (ou **Providers**) > **Email**
- [ ] **Allow new users to sign up**: DESLIGADO (so voce cria login, pelo painel)
- [ ] **Confirm email**: tanto faz (os treinadores sao criados ja confirmados)
- [ ] Salvar

### 1.5 Criar o login de cada treinador
Para **cada** treinador do seed:
- [ ] **Authentication** > **Users** > **Add user** > **Create new user**
- [ ] Email: **exatamente o mesmo** do seed
- [ ] Senha inicial (o treinador troca depois em "Trocar senha" no site)
- [ ] Marcar **Auto Confirm User** > **Create user**

### 1.6 Chaves para o Cloudflare
- [ ] **Project Settings** > **API Keys**
- [ ] Copiar **Project URL** e a **publishable key** (`sb_publishable_...`)
- **NAO** usar a secret key / service_role em lugar nenhum

---

## Parte 2 - GitHub

- [ ] Commit + push na `main` com `site/`, `supabase/` e `docs/`
- [ ] O `site/config.js` **nao** vai pro GitHub (esta no `.gitignore`); ele eh gerado no build

---

## Parte 3 - Cloudflare

### 3.1 Criar o projeto
- [ ] https://dash.cloudflare.com > **Workers & Pages** > **Create** > **Import a repository** > este repositorio

### 3.2 Build
Tela com **Deploy command** (Workers):

| Campo | Valor |
|-------|-------|
| Project name | `fourfit` (igual ao `name` em `site/wrangler.jsonc`) |
| Production branch | `main` |
| Build command | `sh build.sh` |
| Deploy command | `npx wrangler deploy` |
| Path / Root directory | `site` |

Tela **sem** Deploy command (Pages):

| Campo | Valor |
|-------|-------|
| Production branch | `main` |
| Framework preset | None |
| Build command | `sh build.sh` |
| Build output directory | `.` |
| Root directory | `site` |

### 3.3 Variaveis
| Nome | Valor |
|------|-------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | publishable key |

- Workers: **Settings > Build > Variables and secrets** (variavel **de build**)
- Pages: **Settings > Variables and Secrets**
- [ ] Se o primeiro build falhou por falta delas: **Deployments** > **Retry deployment** (ou qualquer push na `main`)

### 3.4 URL
- Workers: `https://fourfit.<sua-conta>.workers.dev`
- Pages: `https://<projeto>.pages.dev`

---

## Parte 4 - Testar

### 4.1 Treinador
- [ ] Abrir a URL > entrar com email/senha de um treinador
- [ ] Cadastrar um aluno (so o nome)
- [ ] **Importar treino** > **Importar PDF** > escolher o PDF > **Converter**
- [ ] Mudar um peso e uma observacao
- [ ] **<- Alunos** > **Exibir treino**: peso/observacao salvos

### 4.2 Aluno
- [ ] Na lista, **Copiar link** do aluno (o botao so aparece depois que o aluno tem treino importado)
- [ ] Abrir o link no celular (ou aba anonima): deve abrir direto o treino, sem login e sem a parte de importar PDF, com o nome do treinador no topo
- [ ] Os pesos/obs do 4.1 aparecem; mudar um peso, recarregar a pagina: continua salvo
- [ ] Salvar o link nos favoritos / tela inicial do celular

### 4.3 Link revogado
- [ ] No treinador: **Gerar novo link** no aluno
- [ ] O link antigo deve mostrar "Link invalido ou expirado"

---

## Dia a dia

- **Novo treinador**: inserir em `trainers` (Table Editor ou SQL, email minusculo) + criar o login dele (passo 1.5)
- **Novo aluno**: treinador cadastra pelo site e envia o link (**Copiar link**)
- **Treino novo**: treinador abre o aluno e importa o PDF de novo (desmarque "Manter anotacoes" para zerar pesos/obs)
- **Link vazou / aluno saiu**: **Gerar novo link** (o antigo para de funcionar) ou **Remover aluno** (apaga treino e anotacoes)
- **Pagamentos**: na lista de alunos, marcar os meses pagos (setas trocam o ano)
- **Treinador esqueceu a senha**: Supabase > Authentication > Users > clicar no usuario > definir nova senha
- **Atualizar o site**: qualquer push na `main` publica sozinho

## Rodar no computador (opcional)

```sh
cp site/config.example.js site/config.js   # preencher URL e publishable key
cd site && python3 -m http.server 8000     # abrir http://localhost:8000
```

## Problemas comuns

| Sintoma | Causa provavel |
|---------|----------------|
| Popup "Configuracao ausente" | Variaveis do build nao foram lidas. Conferir nome exato e se sao de **build**, refazer o deploy |
| Build falha com "defina SUPABASE_URL" | Faltam as variaveis de build |
| "Email ou senha invalidos" | Login do treinador nao criado (1.5) ou sem "Auto Confirm User" |
| "Este email nao eh de um treinador cadastrado" | Email do login diferente do email no seed |
| Link do aluno: "Link invalido ou expirado" | Link antigo (foi gerado um novo), aluno removido, ou link copiado pela metade |
| Erro "permission denied" | `schema.sql` nao rodou inteiro; rodar `reset.sql` e depois `schema.sql` + `seed.sql` |
