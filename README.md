This is a fork of [mini.map](https://github.com/nvim-mini/mini.map) with changes I personally want.

Fork changes are marked `<fork>` in `lua/mini/map.lua`, and covered by the suites in `test/`
(run `./test/run_all.sh`).

# changes

### Marks integration
- Lines with marks are highlighted if you add `MiniMap.gen_integration.marks()` to your integrations.
- Extmarks are added showing the mark letter.
  - These use their own namespaces (`MiniMapMarksHl` / `MiniMapMarksVirt`) so they no longer
    fight with the integration highlights, but they still overwrite the default extmarks that
    show integration counts, and there is no way to disable that.
- Marks are refreshed directly from `MiniMap.refresh()` rather than only via the integration.

### Map updates on every buffer type
- `H.is_proper_buftype()` always returns `true`, so the map (and especially the position bar)
  updates for terminal, help and other special buffers, not just normal ones.

### Performance
- `H.mask_rescaled_from_strings()` replaces upstream's `H.mask_from_strings()` + `H.mask_rescale()`
  pair, which allocated one table cell per character in the whole buffer and called
  `vim.str_utfindex()` once per whitespace character. Encoding a 5000-line file went from ~320 ms
  to ~4 ms.
- `H.update_map_lines()` skips re-encoding when nothing that affects the map has changed. Upstream
  re-encoded on every `BufEnter`, `TextChanged`, `VimResized` and `ModeChanged *:n`, so every
  window switch and every return to Normal mode paid a full encode for identical output.

---

Upstream README follows.

---

<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-map_readme.png?raw=true" alt="mini.map" style="max-width:100%;border:solid 2px"/> </p>

### Window with buffer text overview, scrollbar, and highlights

See more details in [Features](#features) and [Documentation](doc/mini-map.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-map) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-map.mp4 -->
https://user-images.githubusercontent.com/24854248/195806215-10e05020-50b7-4bee-9447-ee5af3e971ec.mp4

## Features

- Show and manage special floating window displaying automatically updated overview of current buffer text. Window takes up whole height of Neovim instance and is fixed to a left/right side. Map content is computed by taking all current lines, converting it to binary whitespace/non-whitespace mask, rescaling to appropriate dimensions, and converting back to strings consisting from special encoding symbols. All this is done very fast and asynchronously.

    See `:h MiniMap.open()`, `:h MiniMap.refresh()`, `:h MiniMap.close()`, `:h MiniMap.toggle()`, `:h MiniMap.toggle_side()`.

    For a general overview and tips, see `:h mini.map-usage`.

- Show scrollbar next to map content. It represents current line and view (top and bottom visible lines). Can be the only thing shown, making map window a "pure scrollbar".

- Highlight map lines representing certain data in current buffer. This is done via extensible set of callables, called integrations. There are pre-built generators for common integrations:
    - Builtin search.
    - Builtin diagnostic.
    - General diff hunks provided by ['mini.diff'](https://nvim-mini.org/mini.nvim/readmes/mini-diff).
    - Hunks provided by ['lewis6991/gitsigns.nvim'](https://github.com/lewis6991/gitsigns.nvim).
    For more details see `:h MiniMap.gen_integration`.

- Focus on map window to quickly browse current (source) buffer. Moving inside map window updates cursor position in source window enabling fast and targeted buffer exploration. To focus back, hit `<CR>` to accept current explored position or `<Esc>` to go back to original position. See `:h MiniMap.toggle_focus()`.

- Customizable:
    - Encoding symbols used to display binary information of different resolution (default is 3x2). There are pre-built generators for different basic character families and resolutions. See `:h MiniMap.gen_encode_symbols`.
    - Scrollbar symbols, separate for line and view. Can have any width (even zero, which virtually disables scrollbar).
    - Integrations producing map line highlights.
    - Window options: side (left/right), width, 'winblend', and more.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

There are two branches to install from:

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
- `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch.

Here are code snippets for some common installation methods (use only one):

<details>
<summary><b>(Recommended)</b> With <a href="https://neovim.io/doc/user/helptag.html?tag=vim.pack">vim.pack</a> (on Neovim 0.12 and newer)</summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
vim.pack.add({ 'https://github.com/nvim-mini/mini.map' })
```

Stable branch:

```lua
vim.pack.add({
  { src = 'https://github.com/nvim-mini/mini.map', version = 'stable' },
})
```

</details>

<details>
<summary>With <a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a> (before Neovim 0.12)</summary>

**Full library**

Follow [recommended 'mini.deps' installation](https://nvim-mini.org/mini.nvim/readmes/mini-deps#installation).

**Standalone plugin**:

Main branch:

```lua
add('nvim-mini/mini.map')
```

Stable branch:

```lua
add({ source = 'nvim-mini/mini.map', checkout = 'stable' })
```

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
{ 'nvim-mini/mini.map', version = false },
```

Stable branch:

```lua
{ 'nvim-mini/mini.map', version = '*' },
```

</details>

**Important**: don't forget to call `require('mini.map').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Highlight integrations (none by default)
  integrations = nil,

  -- Symbols used to display data
  symbols = {
    -- Encode symbols. See `:h MiniMap.config` for specification and
    -- `:h MiniMap.gen_encode_symbols` for pre-built ones.
    -- Default: solid blocks with 3x2 resolution.
    encode = nil,

    -- Scrollbar parts for view and line. Use empty string to disable any.
    scroll_line = '█',
    scroll_view = '┃',
  },

  -- Window options
  window = {
    -- Whether window is focusable in normal way (with `wincmd` or mouse)
    focusable = false,

    -- Side to stick ('left' or 'right')
    side = 'right',

    -- Whether to show count of multiple integration highlights
    show_integration_count = true,

    -- Total width
    width = 10,

    -- Value of 'winblend' option
    winblend = 25,

    -- Z-index
    zindex = 10,
  },
}
```

## Similar plugins

- [wfxr/minimap.vim](https://github.com/wfxr/minimap.vim)
- [dstein64/nvim-scrollview](https://github.com/dstein64/nvim-scrollview)
- [petertriho/nvim-scrollbar](https://github.com/petertriho/nvim-scrollbar)
- [lewis6991/satellite.nvim](https://github.com/lewis6991/satellite.nvim)
