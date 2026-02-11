vim9script
# Startup integration test — verifies the plugin loads without errors by
# mimicking a real installation using Vim's native package manager.
# Opens temp files with R-related extensions to trigger the full
# ftdetect → ftplugin → syntax chain and checks for source-time errors
# (E700, E477, E117, etc.) that unit tests miss.

g:SetSuite('startup')

var plugin_root = expand('<sfile>:p:h:h')

# ========================================================================
# Set up runtimepath like Vim's native package manager
# ========================================================================
# Set rtp to ONLY plugin root + $VIMRUNTIME (exclude personal vimfiles)
execute 'set runtimepath=' .. fnameescape(plugin_root) .. ',' .. $VIMRUNTIME
filetype plugin indent on
syntax on

# Register custom filetypes (quarto, rout)
execute 'source ' .. fnameescape(plugin_root .. '/ftdetect/r.vim')

# ========================================================================
# Helper: open a temp file, trigger the filetype chain, check for errors
# ========================================================================
def TestStartup(ext: string, ft: string, label: string)
  var tmpfile = tempname() .. ext
  writefile(['# test content'], tmpfile)

  v:errmsg = ''
  var caught = ''
  try
    execute 'edit ' .. fnameescape(tmpfile)
    # Fall back to manual filetype if auto-detection missed it
    if &filetype != ft
      execute 'set filetype=' .. ft
    endif
  catch
    caught = v:exception
  endtry

  var err = caught != '' ? caught : v:errmsg
  g:Assert(err == '', label .. ': ' .. err)

  try
    bwipeout!
  catch
  endtry
  delete(tmpfile)
enddef

# ========================================================================
# Helper: set filetype on a scratch buffer (for types without extensions)
# ========================================================================
def TestStartupByFt(ft: string, label: string)
  enew
  setlocal buftype=nofile bufhidden=wipe

  v:errmsg = ''
  var caught = ''
  try
    execute 'set filetype=' .. ft
  catch
    caught = v:exception
  endtry

  var err = caught != '' ? caught : v:errmsg
  g:Assert(err == '', label .. ': ' .. err)

  try
    bwipeout!
  catch
  endtry
enddef

# ========================================================================
# Extension-based filetypes (.R first to initialise common_global.vim)
# ========================================================================
TestStartup('.R',    'r',      'r')
TestStartup('.Rmd',  'rmd',    'rmd')
TestStartup('.Rnw',  'rnoweb', 'rnoweb')
TestStartup('.Rd',   'rhelp',  'rhelp')
TestStartup('.Rrst', 'rrst',   'rrst')
TestStartup('.qmd',  'quarto', 'quarto')
TestStartup('.Rout', 'rout',   'rout')

# ========================================================================
# Programmatic filetypes (no file extension mapping)
# ========================================================================
TestStartupByFt('rdoc', 'rdoc')

# rbrowser's BufUnload calls SendToVimcom — skip by setting guard
if has_key(g:rplugin, 'update_glbenv')
  g:rplugin.update_glbenv = 1
endif
TestStartupByFt('rbrowser', 'rbrowser')
if has_key(g:rplugin, 'update_glbenv')
  g:rplugin.update_glbenv = 0
endif

# ========================================================================
# syntax/rdocpreview.vim (sourced explicitly by the plugin, not by ft)
# ========================================================================
if !has_key(g:rplugin, 'compl_cls')
  g:rplugin.compl_cls = 'f'
endif

enew
setlocal buftype=nofile bufhidden=wipe
v:errmsg = ''
var rdp_caught = ''
try
  execute 'source ' .. fnameescape(plugin_root .. '/syntax/rdocpreview.vim')
catch
  rdp_caught = v:exception
endtry

var rdp_err = rdp_caught != '' ? rdp_caught : v:errmsg
g:Assert(rdp_err == '', 'syntax/rdocpreview.vim: ' .. rdp_err)

try
  bwipeout!
catch
endtry
