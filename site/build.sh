#!/bin/sh
# Build do Cloudflare Pages: gera config.js a partir das variaveis de ambiente do projeto.
set -e
: "${SUPABASE_URL:?defina SUPABASE_URL nas variaveis de ambiente do Cloudflare Pages}"
: "${SUPABASE_ANON_KEY:?defina SUPABASE_ANON_KEY nas variaveis de ambiente do Cloudflare Pages}"
cat > config.js <<EOF
window.SUPABASE_URL = "$SUPABASE_URL";
window.SUPABASE_ANON_KEY = "$SUPABASE_ANON_KEY";
EOF
echo "config.js gerado"
