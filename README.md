this is just a crappy fork of [mini.nvim](https://github.com/echasnovski/mini.map) with stuff I personally want

# changes
- map has a marks integration.
	- Lines with marks will be highlighted if you add MiniMap.gen_integration.marks() to your integrations
	- extmarks are added showing the mark letter
		- these overwrite the default extmarks that show line counts and unfortunately I have not included any way to disable this.
