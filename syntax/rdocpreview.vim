vim9script

syntax clear

syn match inLineCodeDelim /`/ conceal contained
syn match mdIBDelim /*/ conceal contained

syn region markdownCode start="`" end="`" keepend contains=inLineCodeDelim concealends
syn region mdItalic start="\*\ze\S" end="\S\zs\*\|^$" skip="\\\*" contains=mdIBDelim keepend concealends
syn region mdBold start="\*\*\ze\S" end="\S\zs\*\*\|^$" skip="\\\*" contains=mdIBDelim keepend concealends
syn region mdBoldItalic start="\*\*\*\ze\S" end="\S\zs\*\*\*\|^$" skip="\\\*" contains=mdIBDelim keepend concealends

if get(g:rplugin, 'compl_cls', '') == 'f'
    syn include @R syntax/r.vim
    syn region rCodeRegion matchgroup=Conceal start="^```{R} $" end="^```$" contains=@R concealends
else
    syn include @Rout syntax/rout.vim
    syn region rCodeRegion matchgroup=Conceal start="^```{Rout} $" end="^```$" contains=@Rout concealends
endif

hi link markdownCode Special
hi mdItalic term=italic cterm=italic gui=italic
hi mdBold term=bold cterm=bold gui=bold
hi mdBoldItalic term=bold cterm=bold gui=bold
