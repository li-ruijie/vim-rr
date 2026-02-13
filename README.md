# vim-rr

Maintenance fork of [jalvesaq/Vim-R](https://github.com/jalvesaq/Vim-R) — a Vim
plugin for editing and running R code. Windows and Linux only; Neovim users should
use [R.nvim](https://github.com/R-nvim/R.nvim).

This fork focuses on correctness: getting concurrency right between Vim, R, and
the TCP middleware; replacing brittle timer-based sequencing with event-driven
callbacks; hardening the C extensions against buffer overflows and race conditions;
and eliminating external dependencies (Python, macOS, Neovim). The entire codebase
has been ported to Vim9script. New features are unlikely — the goal is reliability
over scope.

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
git clone https://github.com/li-ruijie/vim-rr %USERPROFILE%\vimfiles\pack\plugins\start\vim-rr
```

See the full [documentation](doc/vim-rr.txt) for configuration and usage.

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

Code can be sent to R via a Vim terminal buffer, a tmux pane, or (on Windows)
directly through the TCP link to RGui. The core logic lives in `R/start_r.vim`
(process lifecycle), `R/vimrcom.vim` (job/channel I/O), and
`R/common_global.vim` (global state). The `vimrserver` middleware
(`R/vimcom/src/apps/vimrserver.c`) and `vimcom` R package
(`R/vimcom/src/vimcom.c`) handle the TCP bridge.

## Focus areas

### Concurrency and thread safety

Bridging Vim and R involves complex concurrency, particularly on Windows where
RStudio runs the R console on the main thread while `vimcom` (the plugin's C
extension) listens for commands on a background TCP thread. This creates three
problems: rapid-fire commands can overwrite the buffer before R executes the
previous one; the TCP thread cannot safely call the R API while R's main thread
is blocked on user input; and interrupting R (Ctrl+C, breakpoints) can leave the
"busy" flag stuck, blocking all future updates.

`vim-rr` solves these with a mutex-protected linked-list eval queue and a
heuristic recovery mechanism (5-second staleness timeout resets the busy flag):

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
                                            │   └──────┬──────┘                 │
                                            │          │                        │
                                            │   [MUTEX_UNLOCK] 🔓               │
                                            │          │                        │
                                            │          ▼                        │
                                            │   ┌─────────────┐                 │
                                            │   │  Exec Cmds  │                 │
                                            │   └──────┬──────┘                 │
                                            │          │                        │
                                            │          ▼                        │
                                            │   [MUTEX_LOCK] 🔒                 │
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

### Event-driven lifecycle

Startup, shutdown, and restart are sequenced through event callbacks rather than
hardcoded timer delays. `SetVimcomInfo` triggers `SetSendCmdToR` synchronously
when vimcom connects; `WaitVimcomStart` uses a cancellable timeout instead of a
polling loop. `RQuit` uses an async `exit_cb` for RStudio (with a 2-second
safety timeout) instead of a sleep-poll loop. `RRestart` sets a flag;
`ClearRInfo` checks it and defers `StartR` via a 1ms event-loop yield — no
guessed timer delays.

### TCP protocol correctness

Every message from vimrserver to vimcom uses an 8-byte hex length-prefix
(`%08X` + payload), eliminating TCP fragmentation and concatenation issues.
Large Vim commands use a separate `\x11` size-prefix protocol. When vimcom's TCP
connection drops (R crash, RStudio close, remote disconnect), vimrserver's
`receive_msg` thread notifies Vim via `OnVimcomDisconnect`; subsequent quit or
restart commands force-kill the R process instead of sending through the dead
TCP path.

### Security hardening

All shell-out paths use `shellescape()` or list-form `job_start()`. R code
injection is escaped at the send boundary. vimrserver binds to localhost only,
authenticated with a 128-bit secret generated via OS crypto APIs
(`/dev/urandom`, `BCryptGenRandom`). The tmpdir is validated for symlinks,
permissions, and type, with a randomised fallback on failure.

## Changes from upstream

**Ported to Vim9script** — all 40 source `.vim` files use `def`/`enddef`, typed
parameters, and `var` declarations. Re-source guards on all files with `def g:`.

**Concurrency fixes** — mutex-protected linked-list eval queue replacing static
flag-based command deferral; `r_is_busy` recovery after RStudio interrupt
(tryCatch + 5s timeout); C stack overflow fix for R API calls on Windows TCP
thread (`R_CStackStart` save/restore); heap overflow fix in `hi_glbenv_fun`.

**Event-driven lifecycle** — startup, quit, and restart sequenced via event
callbacks instead of hardcoded timers; RStudio quit uses async `exit_cb` with
safety timeout.

**TCP correctness** — 8-byte hex length-prefix protocol (vimrserver→vimcom);
`\x11` size-prefix for large Vim commands; disconnect detection with force-kill
fallback.

**Security** — `shellescape()` and list-form `job_start()` on all shell-out
paths; vimrserver bound to localhost with 128-bit crypto secret; tmpdir
validation with randomised fallback.

**C source audit** — buffer overflow fixes, null-terminator guards, graceful
thread shutdown, PROTECT/UNPROTECT balancing, mutex for shared state,
`snprintf` replacing `sprintf`.

**Dependencies removed** — Neovim, macOS, Python (BibTeX completion and Evince
SyncTeX rewritten in pure Vim9script).

**New features** — `RRestart()` with `<Plug>RRestart` mapping; RStudio launched
as Vim job with automatic window visibility; TCP disconnect detection;
`R_force_quit_on_close` option.

**Testing** — 14 test files, 411 assertions, pre-commit test gate; Vim9script
lint (E114, E117, E477, E700, E1012, E1073); startup integration test;
callflow static analysis; BibTeX deep-comparison against 23 pybtex reference
files.
