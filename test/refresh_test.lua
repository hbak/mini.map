-- Integration test for the <fork> refresh cache in `H.update_map_lines()`.
--
-- Upstream re-encoded the entire source buffer on every `BufEnter`,
-- `TextChanged`, `BufWritePost`, `VimResized` and `ModeChanged *:n`. The cache
-- skips the encode when none of its inputs changed. These tests pin both
-- halves: that redundant refreshes are skipped, and that every input which
-- *should* invalidate the map still does.
--
-- Run:  nvim --headless -l test/refresh_test.lua

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:append(plugin_root)

vim.o.lines, vim.o.columns = 50, 200
vim.o.swapfile = false

local MiniMap = require('mini.map')

-- Count encodes by wrapping the function `H.update_map_lines()` calls.
local encodes = 0
local real_encode = MiniMap.encode_strings
MiniMap.encode_strings = function(...)
  encodes = encodes + 1
  return real_encode(...)
end

MiniMap.setup({
  integrations = { MiniMap.gen_integration.builtin_search(), MiniMap.gen_integration.marks() },
  symbols = { encode = MiniMap.gen_encode_symbols.dot('4x2') },
  window = { show_integration_count = false },
})

local pass, fail, failures = 0, 0, {}
local function ok(label, cond, extra)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = label .. (extra and ('  (' .. extra .. ')') or '')
  end
end

-- Fill a scratch buffer with source lines
local src_buf = vim.api.nvim_get_current_buf()
local lines = {}
for i = 1, 3000 do
  lines[i] = string.rep('  ', i % 6) .. 'local var_' .. i .. ' = compute(' .. i .. ')  -- comment ' .. i
end
vim.api.nvim_buf_set_lines(src_buf, 0, -1, true, lines)

-- Settle: open the map and drain scheduled work
MiniMap.open()
vim.wait(300)

local function refresh_and_drain(...)
  MiniMap.refresh(...)
  vim.wait(60)
end

local function map_lines()
  return vim.api.nvim_buf_get_lines(MiniMap.current.buf_data.map, 0, -1, true)
end

-- ---------- map actually rendered ----------
local rendered = map_lines()
ok('map window is open', MiniMap.current.win_data[vim.api.nvim_get_current_tabpage()] ~= nil)
ok('map has lines', #rendered > 0, '#lines=' .. #rendered)
local nonblank = 0
for _, l in ipairs(rendered) do
  if l:gsub('%s', '') ~= '' then nonblank = nonblank + 1 end
end
ok('map lines carry encoded content', nonblank > 0, 'nonblank=' .. nonblank)

-- ---------- redundant refresh is skipped ----------
encodes = 0
for _ = 1, 10 do refresh_and_drain() end
ok('10 identical refreshes cause 0 re-encodes', encodes == 0, 'encodes=' .. encodes)

-- ---------- content-change handler is skipped ----------
-- `CursorMoved`/`ModeChanged` autocmds do not fire under `nvim --headless -l`,
-- so invoke the handlers those autocmds are wired to.
encodes = 0
for _ = 1, 10 do
  MiniMap.on_content_change()
  vim.wait(20)
end
ok('10 content-change events cause 0 re-encodes', encodes == 0, 'encodes=' .. encodes)

-- ---------- cursor movement is skipped ----------
encodes = 0
for i = 1, 50 do
  vim.api.nvim_win_set_cursor(0, { i * 20, 0 })
  MiniMap.on_view_change()
  vim.wait(5)
end
ok('50 cursor moves cause 0 re-encodes', encodes == 0, 'encodes=' .. encodes)

-- ---------- real content change DOES re-encode ----------
local before = map_lines()
encodes = 0
vim.api.nvim_buf_set_lines(src_buf, 0, 200, true, {})
refresh_and_drain()
ok('content change triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
local after = map_lines()
ok('content change alters map lines', not vim.deep_equal(before, after))

-- ---------- window resize DOES re-encode ----------
encodes = 0
MiniMap.refresh({ window = { width = 30 } })
vim.wait(80)
ok('width change triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
MiniMap.refresh({ window = { width = 10 } })
vim.wait(80)

-- ---------- encode symbol change DOES re-encode ----------
-- Different resolution ...
encodes = 0
MiniMap.refresh({ symbols = { encode = MiniMap.gen_encode_symbols.block('3x2') } })
vim.wait(80)
ok('encode resolution change triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
local block_3x2_lines = map_lines()

-- ... and a different glyph set at the *same* resolution, which shares every
-- other cache-key component and so must be distinguished by the glyphs alone.
encodes = 0
MiniMap.refresh({ symbols = { encode = MiniMap.gen_encode_symbols.dot('3x2') } })
vim.wait(80)
ok('same-resolution glyph change triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
ok('same-resolution glyph change alters map lines', not vim.deep_equal(block_3x2_lines, map_lines()))

MiniMap.refresh({ symbols = { encode = MiniMap.gen_encode_symbols.dot('4x2') } })
vim.wait(80)

-- ---------- tabstop change DOES re-encode ----------
encodes = 0
vim.bo[src_buf].tabstop = 4
refresh_and_drain()
ok('tabstop change triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
vim.bo[src_buf].tabstop = 8
refresh_and_drain()

-- ---------- switching source buffer DOES re-encode ----------
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(other, 0, -1, true, { 'other buffer', '  second line', 'third' })
encodes = 0
vim.api.nvim_set_current_buf(other)
vim.wait(80)
ok('switching source buffer triggers re-encode', encodes >= 1, 'encodes=' .. encodes)
ok('source buffer tracked', MiniMap.current.buf_data.source == other)
-- and switching back re-encodes again (different changedtick/content)
encodes = 0
vim.api.nvim_set_current_buf(src_buf)
vim.wait(80)
ok('switching back triggers re-encode', encodes >= 1, 'encodes=' .. encodes)

-- ---------- marks still work ----------
for i, l in ipairs({ 100, 600, 1200, 1800, 2400 }) do
  vim.api.nvim_win_set_cursor(0, { l, 0 })
  vim.cmd('normal! m' .. string.char(96 + i))
end
refresh_and_drain()
local marks = MiniMap.get_marks()
ok('marks detected', #marks == 5, '#marks=' .. #marks)

local map_buf = MiniMap.current.buf_data.map
local function extmark_count(ns_name)
  local ns = vim.api.nvim_get_namespaces()[ns_name]
  if ns == nil then return -1 end
  return #vim.api.nvim_buf_get_extmarks(map_buf, ns, 0, -1, {})
end
ok('mark highlights present', extmark_count('MiniMapMarksHl') == 5, 'n=' .. extmark_count('MiniMapMarksHl'))
ok('mark letters present', extmark_count('MiniMapMarksVirt') == 5, 'n=' .. extmark_count('MiniMapMarksVirt'))

-- marks must not accumulate across refreshes
for _ = 1, 5 do refresh_and_drain() end
ok('mark highlights do not duplicate', extmark_count('MiniMapMarksHl') == 5, 'n=' .. extmark_count('MiniMapMarksHl'))
ok('mark letters do not duplicate', extmark_count('MiniMapMarksVirt') == 5, 'n=' .. extmark_count('MiniMapMarksVirt'))

-- deleting a mark removes its indicator
vim.cmd('delmarks a')
refresh_and_drain()
ok('deleted mark is cleared', extmark_count('MiniMapMarksVirt') == 4, 'n=' .. extmark_count('MiniMapMarksVirt'))

-- ---------- scrollbar still tracks the view ----------
local line_ns = vim.api.nvim_get_namespaces()['MiniMapScrollLine']
local function scroll_line_marks(source_line)
  vim.api.nvim_win_set_cursor(0, { source_line, 0 })
  vim.cmd('normal! zz')
  MiniMap.on_view_change()
  vim.wait(60)
  return vim.api.nvim_buf_get_extmarks(map_buf, line_ns, 0, -1, {})
end
local top_marks = scroll_line_marks(1)
local bot_marks = scroll_line_marks(2500)
ok('scroll line indicator exists', #top_marks == 1 and #bot_marks == 1)
ok('scroll line indicator moves with cursor', top_marks[1] and bot_marks[1] and top_marks[1][2] ~= bot_marks[1][2],
  'top=' .. tostring(top_marks[1] and top_marks[1][2]) .. ' bot=' .. tostring(bot_marks[1] and bot_marks[1][2]))

-- ---------- toggle off/on rebuilds correctly ----------
MiniMap.close()
vim.wait(50)
MiniMap.open()
vim.wait(150)
local reopened = map_lines()
ok('map still renders after close/open', #reopened > 0 and reopened[1] ~= nil)
local nb2 = 0
for _, l in ipairs(reopened) do if l:gsub('%s', '') ~= '' then nb2 = nb2 + 1 end end
ok('reopened map carries content', nb2 > 0, 'nonblank=' .. nb2)

print(('\n=== %d passed, %d failed ==='):format(pass, fail))
for _, f in ipairs(failures) do print('FAIL: ' .. f) end
if fail > 0 then vim.cmd('cquit 1') end
