# Site Four Fit - Setup (Supabase + Cloudflare Pages)

Codigo do site em `site/` (mesmo `index.html` de sempre + login, painel do treinador e dados no Supabase).
SQL em `supabase/`. O `index.html` da raiz continua sendo o do GitHub Pages, sem mudanca.

## 1. Supabase

1. Criar projeto.
2. **SQL Editor**: rodar `supabase/schema.sql` e depois `supabase/seed.sql` (troque os emails dos treinadores antes).
3. **Authentication > Sign In / Providers > Email**: desligar **Confirm email** (o treinador cria o login do aluno direto pelo site). Manter "Allow new users to sign up" ligado.
4. **Authentication > Users > Add user**: criar um usuario para cada treinador do seed (mesmo email, marcar **Auto Confirm User**).
5. **Project Settings > API**: copiar **Project URL** e **anon public key**.

## 2. Cloudflare Pages

Workers & Pages > Create > Pages > Connect to Git > este repositorio:

| Campo | Valor |
|-------|-------|
| Production branch | `main` |
| Framework preset | None |
| Build command | `sh build.sh` |
| Build output directory | `.` |
| Root directory | `site` |
| Variaveis de ambiente | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |

O `build.sh` gera o `config.js` a partir das variaveis. A URL fica `https://<projeto>.pages.dev`.

### Alternativa: fluxo de Workers (tela pede "Deploy command")

| Campo | Valor |
|-------|-------|
| Project name | `fourfit` (igual ao `name` do `site/wrangler.jsonc`) |
| Build command | `sh build.sh` |
| Deploy command | `npx wrangler deploy` |
| Path / Root directory | `site` |
| Build variables (Settings > Build > Variables and secrets) | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |

URL: `https://fourfit.<sua-conta>.workers.dev`.

## 3. Uso

- **Treinador**: entra com o login criado no passo 1.4 > cadastra aluno (nome, email, senha inicial) > Abrir > importa o PDF.
- **Aluno**: entra com o email/senha que o treinador passou. Pode trocar a senha em "Trocar senha".

## Rodar localmente

```sh
cp site/config.example.js site/config.js   # preencher URL e anon key
cd site && python3 -m http.server 8000
```
