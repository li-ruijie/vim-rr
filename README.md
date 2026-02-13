# vim-rr

Maintenance fork of [jalvesaq/Vim-R](https://github.com/jalvesaq/Vim-R) — a Vim plugin for editing and running R code. Windows and Linux only; support for macOS and Neovim has been dropped. Neovim users should use [R.nvim](https://github.com/R-nvim/R.nvim) instead.

This fork started to fix a bug where RStudio's window would not appear on Windows. It has since grown into a larger effort: the entire codebase has been ported to Vim9script, and many bugs have been fixed. Features may be removed in the future to keep the maintenance burden low, and new features are unlikely to be added.

## Features

- Send code to R — lines, selections, paragraphs, functions, blocks, or entire files
- Omni-completion for R objects, function arguments, and chunk options
- Object browser for `.GlobalEnv` and loaded packages

## Requirements

- Vim >= 8.2.84 (with `+channel`, `+job`, `+conceal`)
- R >= 4.0.0
- A C compiler (the bundled `vimcom` R package is compiled automatically)
- [Rtools](https://cran.r-project.org/bin/windows/Rtools/) on Windows

## Installation

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'li-ruijie/vim-rr'
```

### Vim packages (manual)

```sh
# Unix
mkdir -p ~/.vim/pack/plugins/start
git clone https://github.com/li-ruijie/vim-rr ~/.vim/pack/plugins/start/vim-rr

# Windows
git clone https://github.com/li-ruijie/vim-rr %USERPROFILE%\vimfiles\pack\plugins\start\vim-r
```

See the full [documentation](doc/vim-r.txt) for configuration and usage.

## Software Architecture

Vim communicates with R through `vimrserver` (a TCP server run as a Vim job) and `vimcom` (an R package with a C extension that connects to `vimrserver` over TCP).

```text
  ┌───────────────────────────────────────────────────────────────────────────────────┐
  │                                   Vim Editor                                      │
  │ ┌──────────────────────┐                                                          │
  │ │   Filetype Detection │                                                          │
  │ │   [ftdetect/r.vim]   │                                                          │
  │ └──────────┬───────────┘                                                          │
  │            ▼                                                                      │
  │ ┌───────────────────────────────────────────────────────────────────────────────┐ │
  │ │                           Filetype Plugins (Entry Points)                     │ │
  │ │ [ftplugin/r_vimr.vim]      [ftplugin/rmd_vimr.vim]  [ftplugin/rbrowser.vim]   │ │
  │ │ (Main R logic)             (RMarkdown support)      (Object Browser UI)       │ │
  │ └──────────┬─────────────────────────────┬──────────────────────┬───────────────┘ │
  │            │ Sources                     │ Sources              │ Sources         │
  │            ▼                             ▼                      ▼                 │
  │ ┌───────────────────────────────────────────────────────────────────────────────┐ │
  │ │                            Core Logic (Vim Script)                            │ │
  │ │                                                                               │ │
  │ │ ┌───────────────────────┐   ┌───────────────────────┐   ┌───────────────────┐ │ │
  │ │ │  R/common_global.vim  │◄──│    R/start_r.vim      │──►│  R/vimrcom.vim    │ │ │
  │ │ │  (Global Config/State)│   │  (Process Management) │   │ (Job/IPC Handler) │ │ │
  │ │ └───────────────────────┘   └──────────┬────────────┘   └─────────▲─────────┘ │ │
  │ │                                        │ Starts                   │           │ │
  │ │ ┌───────────────────────┐              │ Job                      │ IO        │ │
  │ │ │   R/functions.vim     │              │                          │ Channels  │ │
  │ │ │   (Syntax/Helpers)    │              │                          │           │ │
  │ │ └───────────────────────┘              │                          │           │ │
  │ └────────────────────────────────────────┼──────────────────────────┼───────────┘ │
  └──────────────────────────────────────────┼──────────────────────────┼─────────────┘
                                             │                          │
                                             │ Forks                    │ Stdio
                                             ▼                          ▼
                                  ┌───────────────────────┐    ┌─────────────────────┐
                                  │      R Process        │    │     vimrserver      │
                                  │ (Terminal/External)   │    │    (Middleware)     │
                                  │                       │    │ [R/vimcom/src/apps] │
                                  │  Loads: vimcom pkg    │    └──────────▲──────────┘
                                  └──────────┬────────────┘               │
                                             │                            │
                                             │                            │
                                             ▼                            │ TCP Socket
  ┌───────────────────────────────────────────────────────────────────────┼──────────┐
  │                                  R Environment                        │          │
  │ ┌─────────────────────────────────────────────────────────────────────┼────────┐ │
  │ │                             vimcom R Package                        │        │ │
  │ │                                                                     │        │ │
  │ │ ┌───────────────────────┐      ┌────────────────────────┐           │        │ │
  │ │ │   R/vimcom/R/*.R      │◄────►│  R/vimcom/src/vimcom.c │◄──────────┘        │ │
  │ │ │ (R-side Hooks/Tools)  │      │  (TCP Client/C Glue)   │                    │ │
  │ │ └───────────────────────┘      └────────────────────────┘                    │ │
  │ └──────────────────────────────────────────────────────────────────────────────┘ │
  └──────────────────────────────────────────────────────────────────────────────────┘
```

## Challenges

### Concurrency and Thread Safety (Windows/RStudio)

Bridging Vim and R involves complex concurrency, particularly on Windows where RStudio runs the R console on the main thread while `vimcom` (the plugin's C extension) listens for commands on a background TCP thread. This architecture creates several critical race conditions:

1.  **Command Overwrite**: Rapid-fire commands from Vim (like sending a visual block line-by-line) could overwrite the command buffer before R's main thread had a chance to execute the previous one.
2.  **Deadlocks**: When R waits for user input, the main thread is blocked. The TCP thread cannot safely call the R API to execute code without risking a crash, but waiting for R to become idle causes a deadlock.
3.  **State Desynchronization**: Interrupting R (e.g., `Ctrl+C` or a breakpoint) could leave the plugin thinking R is "busy" forever, blocking future updates like the Object Browser.

`vim-rr` solves these issues using a mutex-protected event queue and a heuristic recovery mechanism:

```text
      Vim Editor                                      R Process (vimcom)
      ┌────────┐                            ┌───────────────────────────────────┐
      │ :RSend ├──┐                         │                                   │
      └────────┘  │ TCP (localhost)         │       [TCP Listener Thread]       │
                  │                         │                 │                 │
      ┌────────┐  │   ┌──────────────┐      │     (1) Receive Command 'E'       │
      │ :RSend ├──┼──►│  vimrserver  │─────►│                 ▼                 │
      └────────┘  │   │(Dynamic Buff)│      │          [MUTEX_LOCK] 🔒          │
                  │   └──────────────┘      │                 │                 │
      ┌────────┐  │                         │      ┌──────────┴──────────┐      │
      │ :RSend ├──┘                         │      │ Check: r_is_busy?   │      │
      └────────┘                            │      └─┬─────────────────┬─┘      │
                                            │        │ YES             │ NO     │
                                            │        ▼                 │        │
                                            │  ┌───────────┐           │        │
                                            │  │Check Timer│           │        │
                                            │  │> 5.0 sec? │           │        │
                                            │  └─┬───────┬─┘           │        │
                                            │    │ YES   │ NO          │        │
  ┌──────────────────────────────────────┐  │    ▼       ▼             │        │
  │ RECOVERY MECHANISM                   │  │ ┌─────┐  ┌─────┐         │        │
  │ If R is stopped at a breakpoint      │  │ │RESET│  │Push │         │        │
  │ or interrupted (Ctrl+C), 'busy'      │  │ │Busy │  │ to  │(Linked  │        │
  │ stays 1. The TCP thread detects      │  │ │ = 0 │  │Queue│ List)   │        │
  │ staleness (>5s) and forces reset.    │  │ └──┬──┘  └─┬───┘         │        │
  └──────────────────────────────────────┘  │    │       │             │        │
                                            │    │       ▼             │        │
                                            │    │  ┌──────────────┐   │        │
                                            │    │  │[MUTEX_UNLOCK]│   │        │
                                            │    │  │      🔓      │   │        │
                                            │    │  └──────────────┘   │        │
                                            │    │       │ (Done)      │        │
                                            │    └───────┼─────────────┘        │
                                            │            ▼                      │
                                            │      ┌───────────┐                │
                                            │      │Set Busy=1 │                │
                                            │      │BusySince=T│                │
                                            │      └─────┬─────┘                │
                                            │            ▼                      │
                                            │     ┌──────────────┐              │
                                            │     │[MUTEX_UNLOCK]│              │
                                            │     │      🔓      │              │
                                            │     └──────┬───────┘              │
                                            │            ▼                      │
                                            │      ┌──────────┐                 │
                                            │      │ Exec Now │                 │
                                            │      │ (HACK)   │                 │
                                            │      └─────┬────┘                 │
                                            │            │                      │
                                            │            ▼                      │
                                            │     [R API Call]                  │
                                            │            │                      │
                                            │            │                      │
                                            │   [Main R Thread]                 │
                                            │            │                      │
                                            │            │ (R finishes task)    │
                                            │            │                      │
                                            │            ▼                      │
                                            │   ┌─────────────────┐             │
                                            │   │   vimcom_task   │             │
                                            │   │ (Task Callback) │             │
                                            │   └──────┬──────────┘             │
                                            │          │                        │
                                            │          ▼                        │
                                            │   [MUTEX_LOCK] 🔒                 │
                                            │          │                        │
                                            │   ┌──────┴──────┐                 │
                                            │   │ Drain Queue │                 │
                                            │   │ & Exec Cmds │                 │
                                            │   └──────┬──────┘                 │
                                            │          │                        │
                                            │   ┌──────┴──────┐                 │
                                            │   │ Set Busy=0  │                 │
                                            │   └──────┬──────┘                 │
                                            │          │                        │
                                            │   [MUTEX_UNLOCK] 🔓               │
                                            │          │                        │
                                            │          ▼                        │
                                            │      (R Idle)                     │
                                            └───────────────────────────────────┘
```

### Component Breakdown

1.  **Vim Frontend (`ftplugin/`, `ftdetect/`)**:
    *   Detects R-related files (`.R`, `.Rmd`, `.Rnw`, etc.).
    *   Initializes buffer-local mappings, commands, and settings.
    *   Sources the core logic scripts from the `R/` directory.

2.  **Core Logic (`R/`)**:
    *   **`common_global.vim`**: Maintains global state (`g:rplugin`), checks versions, and handles initialization.
    *   **`start_r.vim`**: Responsible for spawning the R process (either in a Vim terminal buffer or external terminal like tmux) and the `vimrserver` process.
    *   **`vimrcom.vim`**: Manages the low-level asynchronous communication (Jobs/Channels) between Vim and the `vimrserver` binary.
    *   **`functions.vim`**: Contains helper functions and syntax highlighting logic.

3.  **Middleware (`vimrserver`)**:
    *   Located in `R/vimcom/src/apps/vimrserver.c`.
    *   A lightweight C program compiled on the user's machine.
    *   Acts as a TCP server/router. It decouples Vim from R, allowing R to send messages (like "completion data ready" or "object browser updated") to Vim asynchronously without blocking either process.

4.  **R Integration (`vimcom` Package)**:
    *   An R package located in `R/vimcom/`.
    *   **`src/vimcom.c`**: The C extension that connects to `vimrserver` via TCP. It intercepts R output and state changes.
    *   **`R/*.R`**: R functions that generate completion lists, format data for the object browser, and handle help requests. These are called by Vim (via `vimrserver`) or triggered by R hooks.

Code can be sent to R via a Vim terminal buffer, a tmux pane, or (on Windows) directly through the TCP link to RGui.

## Changelog

### Features

- Add `RRestart()` function and `<Plug>RRestart` mapping
- Launch RStudio as a Vim job with automatic window visibility on Windows (Electron starts hidden via `job_start`; a PowerShell script polls for the Chrome_WidgetWin_1 window and calls `ShowWindow(SW_RESTORE)`)
- Detect vimcom TCP disconnect: vimrserver notifies Vim when the connection drops, Vim warns the user, and `RQuit`/`RRestart` force-kill the R process instead of silently failing
- Add `R_force_quit_on_close` option: when set alongside `R_quit_on_close`, force-kills R/RStudio on Vim exit if the TCP connection is already broken

### Security and performance

- Validate tmpdir (symlink, permissions, type) with fallback to randomised path
- Bind vimrserver to localhost; generate 128-bit secret via OS crypto APIs
- Cache `TmuxOption()` result to avoid `system()` call on every `SendCmdToR_Term`

### Platform changes

- Remove Neovim support
- Remove macOS support
- Remove Python dependency: BibTeX parsing and Evince SyncTeX are now pure Vim9script (not yet rigorously tested)

### Bug fixes

- Fix C stack overflow from R API calls on Windows TCP thread
- Fix heap overflow in `hi_glbenv_fun` when R has many functions
- Fix `\x11` size-prefix protocol for large Vim commands
- Fix 14 injection vulnerabilities: `shellescape()`, list-form `job_start()`, quote escaping
- Fix 32 type mismatches, regex precedence, and missing guards from deep call-flow review

### Vim9script port

- Port all 40 source `.vim` files to Vim9script (`def`/`enddef`, typed parameters, `var` declarations)
- Add `delfunc` re-source guard pattern for `start_r.vim` (62 global functions)
- Add variable-based re-source guards to all 18 vim9 files with `def g:`
- Replace `legacy execute` with vim9 `execute` in job callbacks
- Port syntax files (rdocpreview, rdoc, rbrowser, rout)

### Testing and linting

- Add test suite (13 files, 304 assertions) and pre-commit test gate
- Add vim9script lint rules (E114, E117, E477, E700, E1012, E1073)
- Add startup integration test for all syntax and ftplugin files
- Add callflow static analysis tests
- Add pre-commit hook to sync vimcom version in help docs

