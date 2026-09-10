vim.opt.runtimepath:prepend(".")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
-- tests/run_tests.lua
-- Suíte de testes unitários para o neovim-anki-sync
-- Executar com: nvim --headless -l tests/run_tests.lua

local sync = require("neovim-anki-sync")
local parser = require("neovim-anki-sync.parser")

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
