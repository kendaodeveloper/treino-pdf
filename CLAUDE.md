# Four Fit - Protocolo de Treino

Single-page app (index.html, ~1600 linhas) que importa PDFs de treino da consultoria Four Fit e renderiza um dashboard interativo mobile-first.

## Stack

- **HTML/CSS/JS** puro, tudo em `index.html` (sem build, sem framework)
- **PDF.js 3.4.120** via CDN para extrair texto e links dos PDFs
- **localStorage** para persistir dados do treino e anotacoes do usuario

## Estrutura do arquivo index.html

```
Linhas ~1-360     CSS (estilos inline no <style>)
Linhas ~360-410   HTML (estrutura basica, input file, botoes)
Linhas ~410-520   JS: funcoes auxiliares (localStorage, anotacoes, pesos, semanas)
Linhas ~520-600   JS: applyBodyTypeDimming(), applyExerciseDimming(), load do localStorage
Linhas ~600-680   JS: processarPDF() - extrai texto e links do PDF via PDF.js
Linhas ~680-750   JS: findTextY(), findVideoByPosition() - associacao de videos por posicao Y
Linhas ~750-1150  JS: parseWorkoutTextByBlocks() - parser generico do PDF
Linhas ~1150-1250 JS: toggleSection(), getDayOfWeek(), applySectionVisibility()
Linhas ~1250-1620 JS: renderWorkoutVisual() - renderiza todo o HTML do dashboard
```

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
  "periodizacao": [{ "semana": 1, "periodo": "", "series": "", "descanso": "", "cadencia": "", "falha": "" }],
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

### Alongamentos e Manobras (pagina que contem "ALONGAMENTOS")
Parseia sequencialmente: seq (numero ou "Mobilidade") -> tempo/series -> nome do exercicio.
Transicao de alongamentos para manobras ocorre apos "Mobilidade".

### Periodizacao (pagina com "PERIODIZACAO" + "TABELA DE RM")
Encontra marcadores de semana (1a, 2a, ..., 12a) e extrai periodo, series, descanso, cadencia, falha.
Para na tabela de RM (linhas com "X%" ou "X RM") para nao poluir a ultima semana.

### Treinos (paginas com "EXERCICIOS")
Cada pagina de treino contem: WARM UP, EXERCICIOS, AEROBIO, RELAXAMENTO.
- Identificador: "TREINO N" ou "TREINO N E M"
- dias_e_foco: detecta dias da semana, "Caso treinar mais de Xx", ou foco entre parenteses no relaxamento (ex: "(Dorsais, Deltoide e Biceps)", "(MMII Completo)")
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
- Alongamentos e Mobilidades
- Manobras Respiratorias e Abdominais
- Treinos (1 card por treino, auto-abre o do dia)

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

2. **applyBodyTypeDimming()** - baseado no tipo do treino do dia:
   - Detecta se hoje e MMII ou MMSS pelo `dias_e_foco` que casa com o dia da semana
   - `data-body-type="mmii"` ou `"mmss"` nas manobras: dim se nao casa com o tipo do dia
   - Sem dias da semana (ex: Daniel Alves): nenhum dimming aplicado (tudo visivel)
   - Respeita o dimming de semanas: nao remove exercise-dimmed se after-weeks ou has-replacement esta ativo

### Headers dos treinos
- Com dias da semana: "Segunda e Sexta-Feira\n(Dorsais, Deltoide e Biceps)"
- Sem dias da semana: "TREINO 1\n(Dorsais, Deltoide e Biceps)" (prefixado com identificador)

### Auto-abertura de treinos
- Ao carregar do localStorage: abre apenas o treino do dia (pela funcao treinoMatchesToday)
- Ao importar novo PDF: abre todos

## Filtros no parser

Fragmentos de logo/marca sao filtrados no warmup parser:
- Caractere isolado: `/^[A-Za-z0-9]$/` (ex: "4", "F")
- Letras espacadas: `/^([A-Za-z]\s){3,}[A-Za-z]?$/` (ex: "c o n s u l t o r i a")
- Nomes de marca: "our Fit", "Four Fit", "consultoria", "Roberto Oliveira"

## PDFs de teste (pasta `teste/`)

- `Treino - Kenneth.pdf` - 3 treinos (1E5, 2E4, 3), periodizacao com Forca Pura, tem dias da semana
- `Consultoria 2 - Daniel Alves.pdf` - 3 treinos sem dias da semana (so foco), Pos-exaustao com hifen
- `Consultoria - Lucas Paim.pdf` - 4 treinos (1, 2E5, 3, 4 alternativo), Biset
- Outros PDFs para testes adicionais
- `kenneth-ok.json` e `lucas-paim-ok.json` - JSONs de referencia para validacao

## Debug

Logs no console (comentados com "NAO REMOVER"):
- fullText completo e JSON parseado apos importar PDF
- Para reativar: descomentar as linhas ~649-652

Variaveis de teste:
- `diaSemana` (topo do script, linha ~409): `null` por default (usa dia real). Setar para `'segunda'`, `'terca'`, `'quarta'`, `'quinta'`, `'sexta'`, `'sabado'` ou `'domingo'` para simular outro dia. DEVE ficar no topo do script (antes do load do localStorage) por causa de hoisting.
