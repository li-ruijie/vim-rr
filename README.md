# vim-r

Maintenance fork of [jalvesaq/Vim-R](https://github.com/jalvesaq/Vim-R) — a Vim plugin for editing and running R code.

## Features

- Start, restart, and close R from Vim
- Send lines, selections, paragraphs, functions, blocks, or entire files to R
- Omni-completion for R objects, function arguments, knitr chunk options, and Quarto cell options
- Object Browser for `.GlobalEnv` and loaded packages
- View R documentation in a Vim buffer with syntax highlighting
- Additional syntax highlighting for functions of loaded packages
- SyncTeX support for Rnoweb documents
- Limited support for debugging R functions

## Requirements

- Vim >= 8.2.84 (with `+channel`, `+job`, `+conceal`)
- R >= 4.0.0
- A C compiler (the bundled `vimcom` R package is compiled automatically)
- [Rtools](https://cran.r-project.org/bin/windows/Rtools/) on Windows

## Installation

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'li-ruijie/vim-r'
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ 'li-ruijie/vim-r' }
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use 'li-ruijie/vim-r'
```

### Vim packages (manual)

```sh
# Unix
mkdir -p ~/.vim/pack/plugins/start
git clone https://github.com/li-ruijie/vim-r ~/.vim/pack/plugins/start/vim-r

# Windows
git clone https://github.com/li-ruijie/vim-r %USERPROFILE%\vimfiles\pack\plugins\start\vim-r
```

See the full [documentation](doc/vim-r.txt) for configuration and usage.

## How it works

Vim communicates with R through `vimrserver` (a TCP server run as a Vim job) and `vimcom` (an R package with a C extension that connects to `vimrserver` over TCP).

```
Vim ──stdio──▸ vimrserver ◂──TCP──▸ vimcom ──▸ R
```

Code can be sent to R via a Vim terminal buffer, a tmux pane, or (on Windows) directly through the TCP link to RGui.
