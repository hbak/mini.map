-- Differential + performance test for the <fork> map encoder rewrite.
--
-- `H.mask_rescaled_from_strings()` replaced upstream's `H.mask_from_strings()`
-- + `H.mask_rescale()` pair for performance. This test pins the replacement to
-- the exact output of the code it replaced: the original algorithm is inlined
-- below verbatim as the reference, and every case must match byte for byte.
--
-- Run:  nvim --headless -l test/encode_test.lua

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:append(plugin_root)
local MiniMap = require('mini.map')

--============================ REFERENCE (upstream, verbatim) ============================
local Ref = {}

Ref.str_width = function(x) return (vim.str_utfindex(x)) end

Ref.tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do table.insert(res, x) end
  return res
end

Ref.mask_from_strings = function(strings, _)
  local tab_space = string.rep(' ', vim.o.tabstop)
  local res = {}
  for i, s in ipairs(strings) do
    local s_ext = s:gsub('\t', tab_space)
    local n_cols = Ref.str_width(s_ext)
    local mask_row = Ref.tbl_repeat(true, n_cols)
    s_ext:gsub('()%s', function(j) mask_row[vim.str_utfindex(s_ext, j)] = false end)
    res[i] = mask_row
  end
  return res
end

Ref.mask_rescale = function(mask, opts)
  local source_rows, source_cols = #mask, 0
  for _, m_row in ipairs(mask) do source_cols = math.max(source_cols, #m_row) end
  local resolution = opts.symbols.resolution
  local n_rows = math.min(source_rows, opts.n_rows * resolution.row)
  local n_cols = math.min(source_cols, opts.n_cols * resolution.col)
  local res = {}
  for i = 1, n_rows do res[i] = Ref.tbl_repeat(false, n_cols) end
  local rows_coeff, cols_coeff = n_rows / source_rows, n_cols / source_cols
  for i, m_row in ipairs(mask) do
    for j, m in ipairs(m_row) do
      local res_i = math.floor((i - 1) * rows_coeff) + 1
      local res_j = math.floor((j - 1) * cols_coeff) + 1
      res[res_i][res_j] = m or res[res_i][res_j]
    end
  end
  return res
end

Ref.mask_to_symbols = function(mask, opts)
  local symbols = opts.symbols
  local row_resol, col_resol = symbols.resolution.row, symbols.resolution.col
  local powers_of_two = {}
  for i = 0, (row_resol * col_resol - 1) do powers_of_two[i] = 2 ^ i end
  local symbols_n_rows, symbols_n_cols = math.ceil(#mask / row_resol), math.ceil(#mask[1] / col_resol)
  local symbol_ind = {}
  for i = 1, symbols_n_rows do symbol_ind[i] = Ref.tbl_repeat(0, symbols_n_cols) end
  for i = 0, #mask - 1 do
    local row = mask[i + 1]
    local row_div, row_mod = math.floor(i / row_resol), i % row_resol
    for j = 0, #row - 1 do
      local col_div, col_mod = math.floor(j / col_resol), j % col_resol
      local two_power = row_mod * col_resol + col_mod
      local to_add = row[j + 1] and powers_of_two[two_power] or 0
      symbol_ind[row_div + 1][col_div + 1] = symbol_ind[row_div + 1][col_div + 1] + to_add
    end
  end
  local res = {}
  for i, row in ipairs(symbol_ind) do
    res[i] = table.concat(vim.tbl_map(function(id) return symbols[id + 1] end, row))
  end
  return res
end

Ref.encode = function(strings, opts)
  local mask = Ref.mask_from_strings(strings, opts)
  return Ref.mask_to_symbols(Ref.mask_rescale(mask, opts), opts)
end

--================================== HARNESS ==================================
local pass, fail, failures = 0, 0, {}

local function check(label, lines, opts)
  local ok_ref, ref = pcall(Ref.encode, lines, opts)
  local ok_new, new = pcall(MiniMap.encode_strings, lines, opts)
  if ok_ref ~= ok_new then
    fail = fail + 1
    failures[#failures + 1] = ('%s: error mismatch (ref_ok=%s new_ok=%s) %s / %s')
      :format(label, ok_ref, ok_new, tostring(ref), tostring(new))
  elseif not ok_ref then
    pass = pass + 1 -- both rejected the input
  elseif not vim.deep_equal(ref, new) then
    fail = fail + 1
    local detail = {}
    for i = 1, math.max(#ref, #new) do
      if ref[i] ~= new[i] then
        detail[#detail + 1] = ('    row %d: ref=%q new=%q'):format(i, tostring(ref[i]), tostring(new[i]))
        if #detail >= 3 then break end
      end
    end
    failures[#failures + 1] = ('%s: output mismatch\n%s'):format(label, table.concat(detail, '\n'))
  else
    pass = pass + 1
  end
end

--================================ TEST CASES =================================
local cases = {
  { 'simple ascii', { 'hello world', '  indented line', 'x' } },
  { 'empty lines mixed', { 'abc', '', '   ', 'def', '' } },
  { 'all whitespace', { '   ', '\t\t', ' ' } },
  { 'single line', { 'one single line here' } },
  { 'single char', { 'x' } },
  { 'tabs', { '\tif x then', '\t\treturn 1', '\tend' } },
  { 'tabs mixed with spaces', { ' \t mixed \t stuff ', '\ta\tb\tc' } },
  { 'unicode accents', { 'héllo wörld', 'café  naïve', 'ünïcödé' } },
  { 'cjk', { '日本語 テスト', '中文 字符 测试', 'abc 日本 def' } },
  { 'emoji', { 'hi 👋 there', '🎉🎉 party 🎉', 'a👍b' } },
  { 'unicode + tabs', { '\théllo\tworld', 'café\t\tnaïve' } },
  { 'trailing whitespace', { 'abc   ', 'def\t', 'ghi' } },
  { 'leading whitespace only', { '        abc', '    def' } },
  { 'very long line', { string.rep('abc def ', 200), 'short' } },
  { 'ragged widths', { 'a', 'ab cd', string.rep('x', 300), '  ', 'zzz' } },
  { 'nbsp is not %s', { 'a\194\160b', 'c d' } },
  { 'punctuation heavy', { '!@#$%^&*()', '[]{}<>,.;:', '   ---   ' } },
  { 'invalid utf8 bytes', { '\255\255', 'a\200\200b', '\128 x', 'é\255日' } },
  { 'lone continuation bytes', { '\128', '\191\191 a', '\194' } },
}
do
  local code = {}
  for i = 1, 500 do
    code[i] = string.rep('  ', i % 5) .. 'local v' .. i .. ' = f(' .. i .. ')  -- c' .. i
  end
  cases[#cases + 1] = { 'generated 500 code lines', code }

  local uni = {}
  for i = 1, 200 do uni[i] = string.rep(' ', i % 4) .. 'héllo 日本 ' .. i .. ' 👋 tail' end
  cases[#cases + 1] = { 'generated 200 unicode lines', uni }
end

local variants = {
  { 'dot 4x2 @ 20x48', MiniMap.gen_encode_symbols.dot('4x2'), 48, 20 },
  { 'dot 3x2 @ 20x48', MiniMap.gen_encode_symbols.dot('3x2'), 48, 20 },
  { 'block 3x2 @ 20x48', MiniMap.gen_encode_symbols.block('3x2'), 48, 20 },
  { 'block 2x1 @ 12x30', MiniMap.gen_encode_symbols.block('2x1'), 30, 12 },
  { 'block 1x2 @ 10x20', MiniMap.gen_encode_symbols.block('1x2'), 20, 10 },
  { 'shade 2x1 @ 5x10', MiniMap.gen_encode_symbols.shade('2x1'), 10, 5 },
  { 'shade 1x2 @ 1x1', MiniMap.gen_encode_symbols.shade('1x2'), 1, 1 },
  { 'dot 4x2 @ 500x1000 (upscale)', MiniMap.gen_encode_symbols.dot('4x2'), 1000, 500 },
}

for _, ts in ipairs({ 8, 4, 2, 1 }) do
  vim.o.tabstop = ts
  for _, case in ipairs(cases) do
    for _, v in ipairs(variants) do
      check(('ts=%d | %s | %s'):format(ts, case[1], v[1]), case[2], { n_rows = v[3], n_cols = v[4], symbols = v[2] })
    end
  end
end

-- Randomized fuzz, including invalid UTF-8 and odd geometries
do
  local alphabet =
    { 'a', 'B', 'z', '9', ' ', ' ', '  ', '\t', 'é', '日', '👍', '.', '_', '-', '\194\160', '\255', '\200\200' }
  local syms = {}
  for _, v in ipairs(variants) do syms[#syms + 1] = v[2] end
  math.randomseed(20260910)
  for iter = 1, 500 do
    local lines = {}
    for i = 1, math.random(1, 40) do
      local t = {}
      for _ = 1, math.random(0, 50) do t[#t + 1] = alphabet[math.random(#alphabet)] end
      lines[i] = table.concat(t)
    end
    vim.o.tabstop = ({ 1, 2, 4, 8 })[math.random(4)]
    check(
      'fuzz #' .. iter,
      lines,
      { n_rows = math.random(1, 60), n_cols = math.random(1, 40), symbols = syms[math.random(#syms)] }
    )
  end
end

--============================== PERFORMANCE ==============================
-- The rewrite exists for speed; assert it actually is faster so a future
-- refactor can't silently reintroduce the freeze.
local perf_lines = {}
for i = 1, 5000 do
  perf_lines[i] = string.rep('  ', i % 6) .. 'local var_' .. i .. ' = compute(' .. i .. ', "a string", opts)  -- c' .. i
end
vim.o.tabstop = 8
local perf_opts = { n_rows = 48, n_cols = 20, symbols = MiniMap.gen_encode_symbols.dot('4x2') }

local function time_ms(fn, n)
  fn()
  local t0 = vim.uv.hrtime()
  for _ = 1, n do fn() end
  return (vim.uv.hrtime() - t0) / 1e6 / n
end

local old_ms = time_ms(function() Ref.encode(perf_lines, perf_opts) end, 3)
local new_ms = time_ms(function() MiniMap.encode_strings(perf_lines, perf_opts) end, 10)
local speedup = old_ms / new_ms
print(('\nperf (5000 lines): old %.1f ms -> new %.1f ms (%.0fx)'):format(old_ms, new_ms, speedup))

local BUDGET_MS = 40 -- generous; measured ~5 ms on a 2026 laptop
if new_ms > BUDGET_MS then
  fail = fail + 1
  failures[#failures + 1] = ('perf: encoding 5000 lines took %.1f ms, budget is %d ms'):format(new_ms, BUDGET_MS)
else
  pass = pass + 1
end

--================================= REPORT =================================
print(('\n=== %d passed, %d failed ==='):format(pass, fail))
for _, f in ipairs(failures) do print('FAIL: ' .. f) end
if fail > 0 then vim.cmd('cquit 1') end
