-- Differential test for the <fork> `gen_integration.builtin_search()` rewrite.
--
-- Ground truth is what a real `/` search finds: the upstream `search()` walk,
-- but driven by a `searchcount()` call that passes `timeout = 0`. Omitting
-- `timeout` (which upstream does) silently applies a ~40 ms budget and returns
-- a partial `total`, which is the truncation bug this suite pins.
--
-- The integration reports one entry per matching LINE, so every comparison is
-- on the set of matching lines.
--
-- Run:  nvim --headless -l test/search_test.lua

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:append(plugin_root)

vim.o.lines, vim.o.columns = 50, 200
vim.o.swapfile = false
vim.o.hlsearch = true

local MiniMap = require('mini.map')
MiniMap.setup({
  integrations = { MiniMap.gen_integration.builtin_search() },
  symbols = { encode = MiniMap.gen_encode_symbols.dot('4x2') },
})
local integration = MiniMap.gen_integration.builtin_search()

local pass, fail, failures = 0, 0, {}
local function ok(label, cond, extra)
  if cond then pass = pass + 1 else
    fail = fail + 1
    failures[#failures + 1] = label .. (extra and ('  (' .. extra .. ')') or '')
  end
end

-- Ground truth: distinct lines a real search visits, counted without a timeout.
local function truth_lines(pattern)
  local view = vim.fn.winsaveview()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local sc = vim.fn.searchcount({ recompute = true, maxcount = 0, timeout = 0 })
  local set = {}
  for _ = 1, (sc.total or 0) do
    vim.fn.search(pattern)
    set[vim.fn.line('.')] = true
  end
  vim.fn.winrestview(view)
  return set
end

local function integration_lines()
  local set = {}
  for _, h in ipairs(integration()) do set[h.line] = true end
  return set
end

local function describe(set)
  local n, mx = 0, 0
  for l in pairs(set) do n = n + 1; if l > mx then mx = l end end
  return n, mx
end

local function check(label, buf_lines, pattern)
  vim.api.nvim_buf_set_lines(0, 0, -1, true, buf_lines)
  vim.fn.setreg('/', pattern)
  vim.cmd('let v:hlsearch = 1')
  MiniMap.refresh()
  vim.wait(20)

  local want, got = truth_lines(pattern), integration_lines()
  local nw, mw = describe(want)
  local ng, mg = describe(got)

  local missing, extra = {}, {}
  for l in pairs(want) do if not got[l] then missing[#missing + 1] = l end end
  for l in pairs(got) do if not want[l] then extra[#extra + 1] = l end end
  table.sort(missing); table.sort(extra)

  if #missing == 0 and #extra == 0 then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = ('%s: want %d lines (last %d), got %d (last %d); %d missing, %d extra%s')
      :format(label, nw, mw, ng, mg, #missing, #extra,
        #missing > 0 and (' e.g. missing ' .. table.concat({ missing[1], missing[2], missing[3] }, ',')) or '')
  end
end

-- Open the map so `H.is_source_buffer()` is satisfied
MiniMap.open()
vim.wait(200)

-- ============================ truncation cases ============================
-- These are the regression: a large buffer or an expensive pattern makes
-- `searchcount()` time out and report a partial total.
local function gen(n, f) local t = {} for i = 1, n do t[i] = f(i) end return t end

local wide = gen(20000, function(i) return 'local value_' .. i .. ' = compute(foo, bar)  -- note ' .. i end)
check('20k buffer, common token "o"', wide, 'o')
check('20k buffer, common token "e"', wide, 'e')
check('20k buffer, expensive regex', wide, [[\v(a|b|c|d|e|f|.)*note]])
check('20k buffer, one hit per line', wide, 'value')
check('20k buffer, sparse hits', gen(20000, function(i)
  return (i % 100 == 0) and ('local target_' .. i) or ('local v' .. i)
end), 'target')
check('50k buffer, common token', gen(50000, function(i) return 'alpha beta gamma ' .. i end), 'a')

-- ============================ ordinary cases ============================
local small = { 'foo bar', 'nothing', 'BAR foo', '   ', 'foo foo foo', 'last' }
check('small buffer, plain', small, 'foo')
check('small buffer, no matches', small, 'zzzznope')
check('small buffer, every line', small, [[^]])
check('multiple hits per line', small, 'foo')
check('regex quantifier', small, [[fo*]])
check('word boundary', small, [[\<foo\>]])
check('very magic', small, [[\v(foo|bar)]])
check('very nomagic', small, [[\Vfoo]])
check('unicode', { 'héllo wörld', 'HÉLLO', 'plain' }, 'héllo')
check('tabs and blanks', { '\tfoo', '', '\t\tfoo', '   ' }, 'foo')

-- ====================== case sensitivity matrix ======================
local case_buf = { 'lowercase foo here', 'UPPERCASE FOO HERE', 'MixedCase Foo Here', 'no match at all' }
for _, cfg in ipairs({ { false, false }, { true, false }, { true, true }, { false, true } }) do
  vim.o.ignorecase, vim.o.smartcase = cfg[1], cfg[2]
  for _, pat in ipairs({ 'foo', 'FOO', 'Foo', [[\cfoo]], [[\CFOO]], [[\cFOO]], [[\<Foo\>]] }) do
    check(('case ic=%s scs=%s pat=%s'):format(cfg[1], cfg[2], pat), case_buf, pat)
  end
end
vim.o.ignorecase, vim.o.smartcase = true, false

-- ============ patterns match_line cannot do (must fall back) ============
-- `foo` has to end the line and `bar` start the next one for the pattern to
-- match at all; otherwise this asserts nothing.
local multiline_buf = {}
for i = 1, 2000 do multiline_buf[i] = (i % 2 == 1) and ('alpha ' .. i .. ' foo') or ('bar beta ' .. i) end
check('multi-line pattern', multiline_buf, [[foo\nbar]])
check('position atom \\%2l', { 'aaa', 'aaa', 'aaa' }, [[\%2l.]])
check('escaped backslash-n', { [[a\nb]], 'plain' }, [[\\n]])

-- The fallback counts matches itself, so it needs `timeout = 0` just as much:
-- this pattern routes to it (contains `\%`) and matches often enough that a
-- timed-out count would truncate the result.
check('fallback, count would time out', wide, [[\%>0lo]])

-- ======================= guards / degenerate input =======================
vim.api.nvim_buf_set_lines(0, 0, -1, true, { 'foo', 'bar' })
vim.fn.setreg('/', 'foo')
vim.cmd('let v:hlsearch = 0')
ok('returns nothing when v:hlsearch is 0', vim.tbl_count(integration_lines()) == 0)
vim.cmd('let v:hlsearch = 1')
vim.o.hlsearch = false
ok("returns nothing when 'hlsearch' is off", vim.tbl_count(integration_lines()) == 0)
vim.o.hlsearch = true
vim.fn.setreg('/', '')
vim.cmd('let v:hlsearch = 1')
local okempty = pcall(integration_lines)
ok('empty pattern does not error', okempty)
vim.fn.setreg('/', [[\v(]])
local okbad = pcall(integration_lines)
ok('invalid pattern does not error', okbad)

-- the integration must not disturb the cursor or the view
vim.fn.setreg('/', 'foo')
vim.api.nvim_buf_set_lines(0, 0, -1, true, gen(500, function(i) return 'foo line ' .. i end))
vim.api.nvim_win_set_cursor(0, { 250, 3 })
vim.cmd('normal! zz')
local before_view, before_cur = vim.fn.winsaveview(), vim.api.nvim_win_get_cursor(0)
integration()
local after_view, after_cur = vim.fn.winsaveview(), vim.api.nvim_win_get_cursor(0)
ok('cursor is preserved', vim.deep_equal(before_cur, after_cur),
  ('%s -> %s'):format(vim.inspect(before_cur), vim.inspect(after_cur)))
ok('view is preserved', before_view.topline == after_view.topline and before_view.leftcol == after_view.leftcol)

-- ============================== performance ==============================
vim.api.nvim_buf_set_lines(0, 0, -1, true, wide)
vim.fn.setreg('/', 'o')
vim.cmd('let v:hlsearch = 1')
integration()
local t0 = vim.uv.hrtime()
for _ = 1, 5 do integration() end
local ms = (vim.uv.hrtime() - t0) / 1e6 / 5
print(('\nperf (20k lines, 100k matches): %.1f ms'):format(ms))
local BUDGET_MS = 40 -- measured ~3 ms; upstream's walk took ~150 ms when correct
ok(('perf within %d ms budget'):format(BUDGET_MS), ms <= BUDGET_MS, ('%.1f ms'):format(ms))

print(('\n=== %d passed, %d failed ==='):format(pass, fail))
for _, f in ipairs(failures) do print('FAIL: ' .. f) end
if fail > 0 then vim.cmd('cquit 1') end
