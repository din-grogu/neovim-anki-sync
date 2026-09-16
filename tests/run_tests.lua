vim.opt.runtimepath:prepend(".")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
-- tests/run_tests.lua
-- Suíte de testes unitários para o neovim-anki-sync
-- Executar com: nvim --headless -l tests/run_tests.lua

local sync = require("neovim-anki-sync")
local parser = require("neovim-anki-sync.parser")
local table_parser = require("neovim-anki-sync.table")

local total_tests = 0
local passed_tests = 0
local failed_tests = 0

local function assert_eq(actual, expected, test_name)
    total_tests = total_tests + 1
    if actual == expected then
        passed_tests = passed_tests + 1
        print(string.format("  ✓ %s", test_name))
    else
        failed_tests = failed_tests + 1
        print(string.format("  ✗ %s", test_name))
        print(string.format("    Esperado: %s", vim.inspect(expected)))
        print(string.format("    Recebido: %s", vim.inspect(actual)))
    end
end

print("\n========================================================")
print("  Iniciando suíte de testes do neovim-anki-sync (Lua)  ")
print("========================================================\n")

-- -----------------------------------------------------------
-- 1. Testes de conversão Markdown inline para HTML
-- -----------------------------------------------------------
print("1. Testes de Markdown inline para HTML:")

local md_bold = parser.markdown_inline_to_html("Este texto é **muito importante** e __relevante__")
assert_eq(md_bold, "Este texto é <b>muito importante</b> e <b>relevante</b>", "Conversão de negrito (** e __)")

local md_italic = parser.markdown_inline_to_html("Este é um evento *futuro e incerto* no negócio")
assert_eq(md_italic, "Este é um evento <i>futuro e incerto</i> no negócio", "Conversão de itálico (*)")

local md_mark = parser.markdown_inline_to_html("Atenção para o ==prazo decadencial==")
assert_eq(md_mark, "Atenção para o <mark>prazo decadencial</mark>", "Conversão de destaque (==)")

local md_code = parser.markdown_inline_to_html("Use a função `vim.system` no Neovim")
assert_eq(md_code, "Use a função <code>vim.system</code> no Neovim", "Conversão de inline code (`)")

local md_link = parser.markdown_inline_to_html("Veja no [Código Civil](https://planalto.gov.br)")
assert_eq(md_link, 'Veja no <a href="https://planalto.gov.br">Código Civil</a>', "Conversão de link markdown")

local md_cloze_preserved = parser.markdown_inline_to_html("O prazo é de {{c1::180 dias}} para a anulação.")
assert_eq(md_cloze_preserved, "O prazo é de {{c1::180 dias}} para a anulação.", "Preservação de cloze {{c1::...}}")

local md_combined = parser.markdown_inline_to_html("O termo é **{{c1::certo}}** e a condição é *{{c1::incerta}}*.")
assert_eq(md_combined, "O termo é <b>{{c1::certo}}</b> e a condição é <i>{{c1::incerta}}</i>.", "Combinação de bold/italic com clozes")


-- -----------------------------------------------------------
-- 2. Testes de ignorar blocos de código com cercas (fenced blocks)
-- -----------------------------------------------------------
print("\n2. Testes de blocos de código cercados (fenced code blocks):")

local lines_with_code = {
    "- Card normal #card",
    "  Explicação do card normal",
    "",
    "```markdown",
    "- Exemplo dentro de código não é card #card",
    "  deck:: IgnoreMe",
    "```",
    "",
    "- Segundo card normal #card",
    "  Segunda resposta"
}

local parsed_code_cards = parser.parse_lines(lines_with_code)
assert_eq(#parsed_code_cards, 2, "Ignora linha com #card dentro de bloco de código")


-- -----------------------------------------------------------
-- 3. Testes de resolução de diretórios e baralhos (Deck Resolution)
-- -----------------------------------------------------------
print("\n3. Testes de resolução de nomes de baralhos:")

-- Caso A: Hierarquia padrão com notes_dir definido
sync.setup({
    deck = "Default",
    deck_prefix = "",
    include_filename_in_deck = true,
    notes_dir = "/home/dieb/nextcloud/Documentos/Concursos"
})

local nd, rd, rf = sync._get_notes_dir_and_relative("/home/dieb/nextcloud/Documentos/Concursos/sefaz-df/direito-civil/notes/aula-04-fato-negocio-prescricao-decadencia.md")
assert_eq(rd, "sefaz-df/direito-civil/notes", "Caminho relativo correto com notes_dir")

local deck1 = sync._resolve_deck_name(rd, "aula-04-fato-negocio-prescricao-decadencia.md")
assert_eq(deck1, "sefaz-df::direito-civil::notes::aula-04-fato-negocio-prescricao-decadencia", "Mapeamento hierárquico com nome do arquivo")

-- Caso B: Com deck_prefix configurado
sync.setup({
    deck = "Default",
    deck_prefix = "Concursos",
    include_filename_in_deck = true,
    notes_dir = "/home/dieb/nextcloud/Documentos/Concursos"
})
local deck2 = sync._resolve_deck_name(rd, "aula-04-fato-negocio-prescricao-decadencia.md")
assert_eq(deck2, "Concursos::sefaz-df::direito-civil::notes::aula-04-fato-negocio-prescricao-decadencia", "Mapeamento com deck_prefix")

-- Caso C: Sem o nome do arquivo no final (include_filename_in_deck = false)
sync.setup({
    deck = "Default",
    deck_prefix = "",
    include_filename_in_deck = false,
    notes_dir = "/home/dieb/nextcloud/Documentos/Concursos"
})
local deck3 = sync._resolve_deck_name(rd, "aula-04-fato-negocio-prescricao-decadencia.md")
assert_eq(deck3, "sefaz-df::direito-civil::notes", "Mapeamento sem nome do arquivo (apenas pastas)")

-- Caso D: Arquivo na raiz de notes_dir (relative_dir = "") com include_filename_in_deck = true
sync.setup({
    deck = "Default",
    deck_prefix = "",
    include_filename_in_deck = true
})
local deck_root = sync._resolve_deck_name("", "topico.md")
assert_eq(deck_root, "Default::topico", "Fallback para deck padrão com nome do arquivo quando na raiz")

-- Caso D2: Arquivo na raiz de notes_dir com include_filename_in_deck = false
sync.setup({
    deck = "Default",
    deck_prefix = "",
    include_filename_in_deck = false
})
local deck_root2 = sync._resolve_deck_name("", "topico.md")
assert_eq(deck_root2, "Default", "Fallback para deck padrão sem nome do arquivo quando na raiz")

-- Caso E: Expansão de til (~) em notes_dir
sync.setup({
    notes_dir = "~/nextcloud/Documentos/Concursos"
})
local nd_tilde = sync._get_notes_dir_and_relative("/home/dieb/nextcloud/Documentos/Concursos/sefaz-df/direito-civil/notes/aula-04.md")
assert_eq(nd_tilde:sub(1, 1), "/", "Expansão de ~ resolve para caminho absoluto")


-- -----------------------------------------------------------
-- 4. Testes de injeção de UUID via Buffer API
-- -----------------------------------------------------------
print("\n4. Testes de injeção de UUID via Buffer API do Neovim:")

local bufnr = vim.api.nvim_create_buf(false, true)
local test_buf_lines = {
    "# Tópico de Teste",
    "",
    "- O que é Neovim? #card",
    "  Um editor de texto modal e moderno.",
    "",
    "- O que é Anki? #card",
    "  Um software de repetição espaçada."
}
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, test_buf_lines)

local cards_buf, err_buf, modified = parser.parse_buffer(bufnr)
assert_eq(#cards_buf, 2, "Detecta 2 cards no buffer")
assert_eq(modified, true, "Sinaliza que o buffer foi modificado com UUIDs")

-- Verifica se as linhas no buffer receberam o comentário <!-- id: ... -->
local updated_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local has_uuid1 = updated_lines[3]:match("<!%-%-%s*id:%s*([%x%-]+)%s*%-%->") ~= nil
local has_uuid2 = updated_lines[6]:match("<!%-%-%s*id:%s*([%x%-]+)%s*%-%->") ~= nil
assert_eq(has_uuid1, true, "Primeiro card recebeu comentário com UUID no buffer")
assert_eq(has_uuid2, true, "Segundo card recebeu comentário com UUID no buffer")

-- Idempotência: rodar novamente não deve reinjetar nem alterar os UUIDs
local cards_buf2, _, modified2 = parser.parse_buffer(bufnr)
assert_eq(modified2, false, "Idempotência: buffer não é modificado se os cards já têm UUID")
assert_eq(cards_buf2[1].uuid, cards_buf[1].uuid, "UUID do card permanece o mesmo na segunda passagem")

vim.api.nvim_buf_delete(bufnr, { force = true })

-- -----------------------------------------------------------
-- 5. Testes de formatação Outliner (Cabeçalhos em bullets e pais)
-- -----------------------------------------------------------
print("\n5. Testes de formatação Outliner (Cabeçalhos e hierarquia de pais):")

-- Teste de formatação de títulos de cards com cabeçalhos
local t_h1, lvl1 = parser.format_card_title("- # Título Principal #card")
assert_eq(t_h1, '<b style="font-size: 1.25em;">Título Principal</b>', "Título de card com nível # recebe estilo h1")
assert_eq(lvl1, 1, "Nível numérico 1 detectado")

local t_h2, lvl2 = parser.format_card_title("  - ## Ato jurídico #card <!-- id: abc -->")
assert_eq(t_h2, '<b style="font-size: 1.15em;">Ato jurídico</b>', "Título de card com nível ## recebe estilo h2")
assert_eq(lvl2, 2, "Nível numérico 2 detectado")

local t_h3, lvl3 = parser.format_card_title("    - ### Termo essencial #card")
assert_eq(t_h3, '<b style="font-size: 1.05em;">Termo essencial</b>', "Título de card com nível ### recebe estilo h3")

local t_plain, lvl0 = parser.format_card_title("  - Pergunta comum sem cabeçalho #card")
assert_eq(t_plain, "Pergunta comum sem cabeçalho", "Título de card sem cabeçalho mantém texto padrão")
assert_eq(lvl0, 0, "Nível numérico 0 para card sem cabeçalho")

-- Teste de formatação e limpeza de bullets pais
local p_h1 = parser.format_parent_bullet("# Fatos Jurídicos")
assert_eq(p_h1, "<b>Fatos Jurídicos</b>", "Bullet pai com # é limpo e formatado em negrito")

local p_h2 = parser.format_parent_bullet("## Defeitos do negócio jurídico")
assert_eq(p_h2, "<b>Defeitos do negócio jurídico</b>", "Bullet pai com ## é limpo e formatado em negrito")

local p_plain = parser.format_parent_bullet("Normas importantes")
assert_eq(p_plain, "Normas importantes", "Bullet pai comum mantém formatação textual")

local p_container1 = parser.format_parent_bullet("## Cards")
assert_eq(p_container1, nil, "Container '## Cards' é filtrado e ignorado dos pais")

local p_container2 = parser.format_parent_bullet("### Flashcards")
assert_eq(p_container2, nil, "Container '### Flashcards' é filtrado e ignorado dos pais")

-- Teste integrado com estrutura real do usuário
local outliner_lines = {
    "- # Fatos Jurídicos",
    "  - ## Ato jurídico #card",
    "    - Aqueles que independem da vontade humana, mas apresentam efeitos jurídicos.",
    "    - Morte, nascimento, maioridade, etc.",
    "  - ## Defeitos do negócio jurídico",
    "    - ## Cards",
    "      - Tanto a condição suspensiva quanto o termo inicial... #card",
}

local parsed_outliner = parser.parse_lines(outliner_lines)
assert_eq(#parsed_outliner, 2, "Detecta os 2 cartões da estrutura outliner")

-- Card 1 (Iniciado no cabeçalho ## Ato jurídico)
local card1 = parsed_outliner[1]
assert_eq(#card1.parent_bullets, 1, "Card 1 possui 1 bullet pai (Fatos Jurídicos)")
assert_eq(card1.parent_bullets[1], "# Fatos Jurídicos", "Pai do Card 1 é o cabeçalho # Fatos Jurídicos")
assert_eq(card1.front:match('^<b style="font%-size: 1%.15em;">Ato jurídico</b>') ~= nil, true, "Card 1 inicia com título formatado em destaque")
assert_eq(card1.front:match("{{c1::") ~= nil, true, "Card 1 possui cloze com os bullets filhos")

-- Card 2 (Sob container ## Cards)
local card2 = parsed_outliner[2]
assert_eq(#card2.parent_bullets, 3, "Card 2 captura os 3 pais na árvore de indentação")
local formatted_p1 = parser.format_parent_bullet(card2.parent_bullets[1])
local formatted_p2 = parser.format_parent_bullet(card2.parent_bullets[2])
local formatted_p3 = parser.format_parent_bullet(card2.parent_bullets[3])
assert_eq(formatted_p1, "<b>Fatos Jurídicos</b>", "Primeiro pai é limpo")
assert_eq(formatted_p2, "<b>Defeitos do negócio jurídico</b>", "Segundo pai é limpo")
assert_eq(formatted_p3, nil, "Terceiro pai (## Cards) é filtrado com sucesso")

-- -----------------------------------------------------------
-- 6. Testes do módulo de tabelas Markdown (table.lua e integração com parser.lua)
-- -----------------------------------------------------------
print("\n6. Testes de tabelas Markdown para HTML e Anki:")

-- 6.1 split_cells
local cells1 = table_parser.split_cells("| Col 1 | Col 2 | Col 3 |")
assert_eq(#cells1, 3, "split_cells: detecta 3 células")
assert_eq(cells1[1], "Col 1", "split_cells: célula 1 limpa")
assert_eq(cells1[2], "Col 2", "split_cells: célula 2 limpa")
assert_eq(cells1[3], "Col 3", "split_cells: célula 3 limpa")

local cells_escaped = table_parser.split_cells("| Valor com \\| pipe | Coluna 2 |")
assert_eq(#cells_escaped, 2, "split_cells: pipe escapado (\\|) não quebra coluna")
assert_eq(cells_escaped[1], "Valor com | pipe", "split_cells: restaura pipe escapado")

local cells_code = table_parser.split_cells("| `a | b` | `c` |")
assert_eq(#cells_code, 2, "split_cells: pipe dentro de código inline não quebra coluna")
assert_eq(cells_code[1], "`a | b`", "split_cells: preserva código com pipe intacto")

local cells_empty = table_parser.split_cells("| A | | C |")
assert_eq(#cells_empty, 3, "split_cells: não descarta célula vazia no meio")
assert_eq(cells_empty[2], "", "split_cells: célula vazia é string vazia")

-- 6.2 is_table_row e is_delimiter_row
assert_eq(table_parser.is_table_row("| A | B |"), true, "is_table_row: linha normal de tabela")
assert_eq(table_parser.is_table_row("- Bullet normal"), false, "is_table_row: bullet não é tabela")
assert_eq(table_parser.is_table_row("# Cabeçalho"), false, "is_table_row: cabeçalho não é tabela")
assert_eq(table_parser.is_delimiter_row("| :--- | :---: | ---: |"), true, "is_delimiter_row: linha separadora válida")
assert_eq(table_parser.is_delimiter_row("| Texto | Normal |"), false, "is_delimiter_row: linha de texto não é separadora")
assert_eq(table_parser.is_delimiter_row("---"), false, "is_delimiter_row: linha horizontal simples não é tabela")

-- 6.3 parse_alignments
local aligns = table_parser.parse_alignments("| :--- | :---: | ---: | --- |")
assert_eq(aligns[1], "left", "parse_alignments: alinhamento à esquerda (:---)")
assert_eq(aligns[2], "center", "parse_alignments: alinhamento centralizado (:---:)")
assert_eq(aligns[3], "right", "parse_alignments: alinhamento à direita (---:)")
assert_eq(aligns[4], nil, "parse_alignments: alinhamento padrão (---)")

-- 6.4 markdown_table_to_html puro
local raw_tbl_lines = {
    "| Conceito | Descrição |",
    "| :--- | ---: |",
    "| **Negrito** | Valor 1 |",
    "| `Código` | ==Destaque== |"
}
local tbl_html = table_parser.markdown_table_to_html(raw_tbl_lines, parser.markdown_inline_to_html)
assert_eq(tbl_html:find('<table class="anki%-table">') ~= nil, true, "markdown_table_to_html: gera tag table com classe anki-table")
assert_eq(tbl_html:find('<th style="text%-align: left;">Conceito</th>') ~= nil, true, "markdown_table_to_html: th com alinhamento esquerdo")
assert_eq(tbl_html:find('<th style="text%-align: right;">Descrição</th>') ~= nil, true, "markdown_table_to_html: th com alinhamento direito")
assert_eq(tbl_html:find('<b>Negrito</b>') ~= nil, true, "markdown_table_to_html: processa inline markdown negrito")
assert_eq(tbl_html:find('<code>Código</code>') ~= nil, true, "markdown_table_to_html: processa inline code")
assert_eq(tbl_html:find('<mark>Destaque</mark>') ~= nil, true, "markdown_table_to_html: processa highlight")

-- 6.5 Integração: Cartão com tabela e clozes nas células
local card_with_table_cloze = {
    "- Comparativo entre Prescrição e Decadência #card",
    "  | Critério | Prescrição | Decadência |",
    "  | :--- | :--- | :--- |",
    "  | Objeto | {{c1::Direito a prestação}} | {{c1::Direito potestativo}} |",
    "  | Renúncia | {{c2::Permitida após consumada}} | {{c2::Não permitida (legal)}} |"
}
local parsed_table_cards = parser.parse_lines(card_with_table_cloze)
assert_eq(#parsed_table_cards, 1, "parse_lines: detecta 1 cartão com tabela")
local t_card = parsed_table_cards[1]
assert_eq(t_card.front:find('<table class="anki%-table">') ~= nil, true, "parse_lines: frente do cartão contém tag anki-table")
assert_eq(t_card.front:find('{{c1::Direito a prestação}}') ~= nil, true, "parse_lines: cloze c1 na célula é preservado")
assert_eq(t_card.front:find('{{c2::Permitida após consumada}}') ~= nil, true, "parse_lines: cloze c2 na célula é preservado")
assert_eq(t_card.front:find('{{c1::\n<table') == nil, true, "parse_lines: não embrulha tabela já clozada")

-- 6.6 Integração: Cartão com tabela sem clozes manuais (auto-cloze envolve tabela inteira)
local card_with_table_autocloze = {
    "- Tabela de conceitos jurídicos #card",
    "  | Conceito | Definição |",
    "  | --- | --- |",
    "  | Fato | Qualquer acontecimento |"
}
local parsed_autocloze = parser.parse_lines(card_with_table_autocloze)
assert_eq(#parsed_autocloze, 1, "parse_lines: detecta cartão de tabela auto-cloze")
assert_eq(parsed_autocloze[1].front:find('{{c1::\n<table class="anki%-table">') ~= nil, true, "parse_lines: auto-cloze envolve a tabela inteira")

-- 6.7 Integração: build_card_front monta hierarquia de parent bullets e card aninhados
local card_build = {
    front = "<b>Título</b>\n{{c1::conteúdo}}",
    parent_bullets = { "# Pai 1", "## Pai 2", "## Cards" },
}
local built_front = parser.build_card_front(card_build)
assert_eq(built_front:find('<ul><li><b>Pai 1</b><ul><li><b>Pai 2</b><ul><li><b>Título</b>') ~= nil, true, "build_card_front: pais e card em hierarquia aninhada")
assert_eq(built_front:find('## Cards') == nil, true, "build_card_front: container ## Cards filtrado")
assert_eq(built_front:find('{{c1::conteúdo}}</li></ul></li></ul></li></ul>') ~= nil, true, "build_card_front: fechamento balanceado de listas")

-- 6.8 Integração: build_card_front para cartão sem pais mantém bullet raiz
local card_no_parents = {
    front = "Pergunta sem pais\n{{c1::Resposta}}",
    parent_bullets = {},
}
local built_no_parents = parser.build_card_front(card_no_parents)
assert_eq(built_no_parents, "<ul><li>Pergunta sem pais\n{{c1::Resposta}}</li></ul>", "build_card_front: card sem pais envolvido em bullet raiz")

-- 6.9 Integração: Cartão misto (bullets e tabela)
local card_mixed = {
    "- Card Misto #card",
    "  - Item antes da tabela",
    "  | Col 1 | Col 2 |",
    "  | --- | --- |",
    "  | A | B |",
    "  - Item após a tabela"
}
local parsed_mixed = parser.parse_lines(card_mixed)
assert_eq(#parsed_mixed, 1, "parse_lines: detecta cartão misto")
local mixed_html = parsed_mixed[1].front
assert_eq(mixed_html:find('Item antes da tabela') ~= nil, true, "parse_lines: bullet anterior preservado")
assert_eq(mixed_html:find('<table class="anki%-table">') ~= nil, true, "parse_lines: tabela intermediária renderizada")
-- 6.10 Integração: Tabela iniciada em bullet de outliner (- | Col 1 | Col 2 |)
local card_outliner_table = {
    "    - ### Sinônimos para os componentes patrimoniais #card <!-- id: a84ada8a-1a87-4b83-b4de-76b8163da379 -->",
    "      - | Ativo | Passivo | Patrimônio Líquido |",
    "        | :---: | :---: | :---: |",
    "        | Patrimônio Bruto | {{c1::Passivo Exigível}} | Situação Líquida |"
}
local parsed_outliner_table = parser.parse_lines(card_outliner_table)
assert_eq(#parsed_outliner_table, 1, "parse_lines: detecta tabela iniciada com bullet (- | ... |)")
assert_eq(parsed_outliner_table[1].front:find('<table class="anki%-table">') ~= nil, true, "parse_lines: outliner bullet convertido para table")
assert_eq(parsed_outliner_table[1].front:find('<th style="text%-align: center;">Ativo</th>') ~= nil, true, "parse_lines: cabeçalho th limpo sem bullet")

-- -----------------------------------------------------------
-- Relatório Final
-- -----------------------------------------------------------
print("\n========================================================")
print(string.format("  Resultados: %d total | %d passaram | %d falharam", total_tests, passed_tests, failed_tests))
print("========================================================\n")

if failed_tests > 0 then
    os.exit(1)
else
    os.exit(0)
end
