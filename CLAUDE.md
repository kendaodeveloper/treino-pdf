# Four Fit - Protocolo de Treino

Single-page app (index.html, ~1600 linhas) que importa PDFs de treino da consultoria Four Fit e renderiza um dashboard interativo mobile-first.

## Stack

- **HTML/CSS/JS** puro, tudo em `index.html` (sem build, sem framework)
- **PDF.js 3.4.120** via CDN para extrair texto e links dos PDFs
- **localStorage** para persistir dados do treino e anotacoes do usuario

## Estrutura do arquivo index.html

Tudo em um unico arquivo. Ordem no codigo:
1. CSS (estilos inline no `<style>`)
2. HTML (estrutura basica, input file, botoes)
3. JS: variaveis globais (todas no topo: `diaSemana`, `statusMsg`, `fileInput`, `convertBtn`, `visualOutput`, `showObsFields`), `showErrorPopup`, helpers de localStorage/anotacoes/pesos/semanas
4. JS: `applyBodyTypeDimming()`, `applyExerciseDimming()`, load do localStorage
5. JS: `processarPDF()` - extrai texto e links do PDF via PDF.js
6. JS: `findTextY()`, `findVideoByPosition()` - associacao de videos por posicao Y
7. JS: `parseWorkoutTextByBlocks()` - parser generico do PDF
8. JS: `toggleSection()`, `getDayOfWeek()`, `applySectionVisibility()`
9. JS: `renderWorkoutVisual()` - renderiza todo o HTML do dashboard

## Fluxo de dados

```
PDF -> PDF.js -> textContent.items (texto + coordenadas Y) + annotations (links)
    -> fullText (texto concatenado por pagina: "--- SECAO_PAGINA_N ---")
    -> pageData[N] = { textItems: [{str, y}], links: [{url, y}] }
    -> parseWorkoutTextByBlocks(fullText, pageData) -> JSON estruturado
    -> localStorage('treino-pdf-data') -> renderWorkoutVisual(jsonData)
```

## Estrutura do JSON parseado

```json
{
  "treinador": "string",
  "aluno": "string",
  "idade": "string",
  "objetivo": "string",
  "frequencia": "string",
  "duracao_total": "string",
  "descanso": "string",
  "periodizacao": [{ "semana": 1, "periodo": "", "series": "", "descanso": "", "cadencia": "", "falha": "", "metodo": "" }],
  "metodos": [{ "semana": 1, "periodo": "", "metodo": "", "descricao": "" }],
  "alongamentos": [{ "seq": "", "tempo": "", "exercicio": "", "isSubExercise": false, "video": "url" }],
  "manobras": [{ "seq": "", "series": "", "exercicio": "", "isSubExercise": false, "video": "url" }],
  "treinos": [{
    "identificador": "TREINO 1 E 5",
    "dias_e_foco": "Segunda e Sexta-Feira (Dorsais, Deltoide e Biceps)",
    "aquecimento": [{ "nome": "", "reps": "", "video": "url" }],
    "exercicios": [{ "seq": "1°", "nome": "", "isSubExercise": false, "video": "url" }],
    "aerobio": [{ "nome": "", "duracao": "", "video": "url" }],
    "relaxamento": [{ "nome": "", "reps": "", "video": "url" }]
  }]
}
```

## Parser PDF (parseWorkoutTextByBlocks)

### Metadados (pagina ~4)
Regex no fullText para extrair: TREINADOR, ALUNO, OBJETIVO, FREQUENCIA, DURACAO TOTAL, DESCANSO.
- OBJETIVO: lookahead usa `\nCARGA\s*\|` (nao `\nCARGA` sozinho) para evitar casar com palavras como "cargas" no texto
- Acentos flexiveis: PER[ÍI]ODO, FREQU[ÊE]NCIA, DURA[ÇC][ÃA]O

### Alongamentos e Manobras (pagina que contem "ALONGAMENTOS")
Parseia sequencialmente: seq (numero ou "Mobilidade") -> tempo/series -> nome do exercicio.
Transicao de alongamentos para manobras: ocorre no primeiro seq numerico APOS ter visto pelo menos um "Mobilidade" (flag seenMobilidade). Permite multiplas entradas Mobilidade nos alongamentos.
- Tempo: aspas unicode (smart quotes) sao normalizadas para aspas simples

### Periodizacao (pagina com "PERIODIZACAO" + "TABELA DE RM")
Encontra marcadores de semana (1a, 2a, ..., 12a) e extrai periodo, series, descanso, cadencia, falha, metodo.
Para na tabela de RM (linhas com "X%" ou "X RM") para nao poluir a ultima semana.
- Falha: corrige palavras quebradas pelo PDF.js (ex: "Concêntr ica" -> "Concêntrica")
- Falha vs Metodo: separados apos descanso — falha termina em "Concêntrica", o restante eh metodo (ex: "Strip Set Metab.", "Cluster Var. I")

### Metodos (pagina com "METODOS" + semanas, SEM "TABELA DE RM")
Parseia blocos por semana (1a, 2a, ...): periodo, nome do metodo e descricao (Realizar/Pratica).
Semanas sem metodo ficam com metodo = "--------".
- Filtra headers de tabela (SEMANAS, PERÍODO, MÉTODO, DESCRIÇÃO) e logo/marca
- Periodo multiline: "Princípio de" + "Força" sao juntados
- Presente apenas em alguns PDFs (ex: Camila Marquezini)

### Treinos (paginas com "EXERCICIOS")
Cada pagina de treino contem: WARM UP, EXERCICIOS, AEROBIO, RELAXAMENTO.
- Identificador: "TREINO N" ou "TREINO N E M"
- dias_e_foco: detecta dias da semana, "Caso treinar..."/"Treino extra caso...", ou foco entre parenteses no relaxamento (ex: "(Dorsais, Deltoide e Biceps)", "(MMII Completo)")
- Warmup: filtra "(apos...)" como notas, "Superserie" isolado eh prefixado na proxima linha
- Aerobio: texto entre parenteses juntado com exercicio anterior (ex: "Livre (intensidade moderada a alta)")
- Exercicios sao agrupados por seq (1°, 2°, ...) com sub-exercicios:
  - **Superserie**: prefixo "Superserie" no nome
  - **Pos exaustao**: prefixo "Pos exaustao" ou "Pos-exaustao" (com hifen) no nome
  - **Biset**: prefixo "Biset" (pode vir como linha separada ou mid-line)
  - **(apos X semanas ...)**: exercicio substituto apos N semanas

### Associacao de videos (findVideoByPosition)
1. Encontra a posicao Y do texto do exercicio nos textItems da pagina
2. Encontra o link (annotation) mais proximo por Y (tolerancia < 50 unidades)
3. Remove o link apos uso (splice) para nao reusar
4. **Ordem de prioridade**: exercicios primeiro, depois warmup/aerobio/relaxamento (evita que aerobio "roube" links de exercicios)
5. findTextY busca: substring completa -> primeiros 15 chars -> fallback por palavras (pontua por quantidade de matches)
6. warmup/aerobio/relaxamento: se nome com prefixo (Superserie/Pos exaustao/Biset) nao encontra, tenta sem prefixo

## Persistencia (localStorage)

- `treino-pdf-data`: JSON completo do treino parseado
- `treino-pdf-anotacoes`: `{ semanaAtual: N, obs: { "treino-X-ex-Y": "texto" }, pesos: { "treino-X-ex-Y": { "15": valor, "12": valor, ... } } }`
  - Pesos de sub-exercicios: chave `treino-X-ex-Y-sub-Z`
- Checkbox "Manter anotacoes" controla se obs/pesos sao preservados ao reimportar

## Rendering (renderWorkoutVisual)

### Secoes
- Info do aluno (sempre aberta)
- Semana Atual (seletor 1-12, collapsed por padrao)
- Periodizacao (tabela de semanas, collapsed)
- Metodos (collapsed, so aparece se PDF tiver pagina de metodos)
- Alongamentos e Mobilidades
- Manobras Respiratorias e Abdominais
- Treinos (1 card por treino, auto-abre o do dia, accordion: so 1 aberto por vez)

### Exercicios - estrutura de cada grupo
```html
<tbody class="exercise-group">
  <tr data-has-replacement?>  <!-- exercicio principal, td[rowspan] na coluna seq -->
    <td rowspan="N">seq</td><td>nome</td><td>video</td>
  </tr>
  <tr><td colspan="2">peso row (5 selects: 15/12/10/8/6 reps, 1-500kg)</td></tr>
  <tr data-after-weeks="6"?>  <!-- sub-exercicio -->
    <td>nome</td><td>video</td>
  </tr>
  <tr><td colspan="2">peso row do sub</td></tr>
  <tr><td colspan="2">textarea obs (se habilitado)</td></tr>
</tbody>
```

### Sistema de dimming (exercise-dimmed)

Duas logicas independentes aplicadas em sequencia:

1. **applyExerciseDimming()** - baseado em semana atual:
   - `data-after-weeks="N"`: se semanaAtual <= N, dim o sub (substituicao ainda nao ativa)
   - `data-has-replacement`: se semanaAtual > N, dim o exercicio principal (substituido)
   - Tambem dim/undim as weight rows adjacentes (nextElementSibling/previousElementSibling)

2. **applyBodyTypeDimming()** - baseado no treino aberto (nao no dia da semana):
   - Detecta MMII ou MMSS pelo `dias_e_foco` do treino aberto (nao collapsed)
   - MMII: `/mmii|perna|inferior/i`
   - MMSS: `/mmss|superior|dorsa[il]s?|peito(?:ral)?|costas|b[ií]ceps|tr[ií]ceps|ombro|deltoid|bra[cç]o/i`
   - Treino misto ou sem match: `todayType = null`, sem dimming (tudo visivel)
   - `data-body-type="mmii"` ou `"mmss"` em alongamentos e manobras com "(DIAS DE/DOS MMII/MMSS)": dim se nao casa com o tipo
   - Chamada automaticamente ao abrir/fechar treinos no toggleSection
   - Respeita o dimming de semanas: nao remove exercise-dimmed se after-weeks ou has-replacement esta ativo

### Headers dos treinos
- Com dias da semana: "Segunda e Sexta-Feira\n(Dorsais, Deltoide e Biceps)"
- Sem dias da semana: "TREINO 1\n(Dorsais, Deltoide e Biceps)" (prefixado com identificador)

### Auto-abertura de treinos
- Ao carregar do localStorage ou importar PDF: abre apenas o treino do dia (pela funcao treinoMatchesToday)
- Comportamento accordion: ao abrir um treino, os outros fecham automaticamente (toggleSection)

## Filtros no parser

Fragmentos de logo/marca sao filtrados no warmup parser:
- Caractere isolado: `/^[A-Za-z0-9]$/` (ex: "4", "F")
- Letras espacadas: `/^([A-Za-z]\s){3,}[A-Za-z]?$/` (ex: "c o n s u l t o r i a")
- Nomes de marca: "our Fit", "Four Fit", "consultoria", "Roberto Oliveira"

## JSONs de teste (pasta `teste/`)

- `kenneth.json` - 3 treinos (1E5, 2E4, 3), periodizacao com Forca Pura, tem dias da semana
- `lucas-paim.json` - 4 treinos (1, 2E5, 3, 4 alternativo), Biset
- `daniel-alves.json` - 3 treinos sem dias da semana (so foco), Pos-exaustao com hifen
- `laryssa-siena.json` - 3 treinos (1E3, 2E4, 5), mobilidade dupla (MMII + MMSS)
- `talita-alves.json` - 5 treinos, relaxamento com fragmento curto ("Ca"+"deia")
- `bianca-vitalino.json` - 3 treinos, "DIAS DOS MMII/MMSS" (com "DOS"), objetivo com "cargas"
- `carolina-vanzolini.json` - 4 treinos, aerobio com "(intensidade...)", warmup com Superserie isolado, "(MMII)"/"(MMSS)" sem "DIAS DE"
- `camila-marquezini.json` - 3 treinos, pagina de Metodos com descricoes, coluna MÉTODO na periodizacao

## Debug

Logs no console (comentados com "NAO REMOVER"):
- fullText completo e JSON parseado apos importar PDF
- Para reativar: descomentar as linhas ~649-652

Variaveis de teste:
- `diaSemana` (topo do script, linha ~409): `null` por default (usa dia real). Setar para `'segunda'`, `'terca'`, `'quarta'`, `'quinta'`, `'sexta'`, `'sabado'` ou `'domingo'` para simular outro dia. DEVE ficar no topo do script (antes do load do localStorage) por causa de hoisting.
