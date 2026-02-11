vim9script

# This file contains code used only if has("gui_running")

if exists("g:did_vimr_gui_running")
    finish
endif
g:did_vimr_gui_running = 1

var tll = exists('g:maplocalleader') ? '<Tab>' .. g:maplocalleader : '<Tab>\\'

var ikblist = execute("imap")
var nkblist = execute("nmap")
var vkblist = execute("vmap")
var iskblist = split(ikblist, "\n")
var nskblist = split(nkblist, "\n")
var vskblist = split(vkblist, "\n")
var imaplist: list<list<string>> = []
var vmaplist: list<list<string>> = []
var nmaplist: list<list<string>> = []
for i in iskblist
    var si = split(i)
    if len(si) == 3 && si[2] =~ "<Plug>R"
        add(imaplist, [si[1], si[2]])
    endif
endfor
for i in nskblist
    var si = split(i)
    if len(si) == 3 && si[2] =~ "<Plug>R"
        add(nmaplist, [si[1], si[2]])
    endif
endfor
for i in vskblist
    var si = split(i)
    if len(si) == 3 && si[2] =~ "<Plug>R"
        add(vmaplist, [si[1], si[2]])
    endif
endfor

def g:RNMapCmd(plug: string): string
    for [el1, el2] in nmaplist
        if el2 == plug
            return el1
        endif
    endfor
    return ''
enddef

def g:RIMapCmd(plug: string): string
    for [el1, el2] in imaplist
        if el2 == plug
            return el1
        endif
    endfor
    return ''
enddef

def g:RVMapCmd(plug: string): string
    for [el1, el2] in vmaplist
        if el2 == plug
            return el1
        endif
    endfor
    return ''
enddef

def g:RCreateMenuItem(type: string, label: string, plug: string, combo: string, target: string)
    if index(g:R_disable_cmds, plug) > -1
        return
    endif
    var tg: string
    var il: string
    if type =~ '0'
        tg = target .. '<CR>0'
        il = 'i'
    else
        tg = target .. '<CR>'
        il = 'a'
    endif
    if type =~ "n"
        if hasmapto('<Plug>' .. plug, "n")
            var boundkey = g:RNMapCmd('<Plug>' .. plug)
            execute 'nmenu <silent> &R.' .. label .. '<Tab>' .. boundkey .. ' ' .. tg
        else
            execute 'nmenu <silent> &R.' .. label .. tll .. combo .. ' ' .. tg
        endif
    endif
    if type =~ "v"
        if hasmapto('<Plug>' .. plug, "v")
            var boundkey = g:RVMapCmd('<Plug>' .. plug)
            execute 'vmenu <silent> &R.' .. label .. '<Tab>' .. boundkey .. ' ' .. '<Esc>' .. tg
        else
            execute 'vmenu <silent> &R.' .. label .. tll .. combo .. ' ' .. '<Esc>' .. tg
        endif
    endif
    if type =~ "i"
        if hasmapto('<Plug>' .. plug, "i")
            var boundkey = g:RIMapCmd('<Plug>' .. plug)
            execute 'imenu <silent> &R.' .. label .. '<Tab>' .. boundkey .. ' ' .. '<Esc>' .. tg .. il
        else
            execute 'imenu <silent> &R.' .. label .. tll .. combo .. ' ' .. '<Esc>' .. tg .. il
        endif
    endif
enddef

def g:RBrowserMenu()
    g:RCreateMenuItem('nvi', 'Object\ browser.Open/Close', 'RUpdateObjBrowser', 'ro', ':call g:RObjBrowser()')
    g:RCreateMenuItem('nvi', 'Object\ browser.Expand\ (all\ lists)', 'ROpenLists', 'r=', ':call g:RBrOpenCloseLs(1)')
    g:RCreateMenuItem('nvi', 'Object\ browser.Collapse\ (all\ lists)', 'RCloseLists', 'r-', ':call g:RBrOpenCloseLs(0)')
    if &filetype == "rbrowser"
        imenu <silent> R.Object\ browser.Toggle\ (cur)<Tab>Enter <Esc>:call g:RBrowserDoubleClick()<CR>
        nmenu <silent> R.Object\ browser.Toggle\ (cur)<Tab>Enter :call g:RBrowserDoubleClick()<CR>
    endif
    g:rplugin.hasmenu = 1
enddef

def g:RControlMenu()
    g:RCreateMenuItem('nvi', 'Command.List\ space', 'RListSpace', 'rl', ':call g:SendCmdToR("ls()")')
    g:RCreateMenuItem('nvi', 'Command.Clear\ console\ screen', 'RClearConsole', 'rr', ':call g:RClearConsole()')
    g:RCreateMenuItem('nvi', 'Command.Clear\ all', 'RClearAll', 'rm', ':call g:RClearAll()')
    "-------------------------------
    menu R.Command.-Sep01- <nul>
    g:RCreateMenuItem('nvi', 'Command.Print\ (cur)', 'RObjectPr', 'rp', ':call g:RAction("print")')
    g:RCreateMenuItem('nvi', 'Command.Names\ (cur)', 'RObjectNames', 'rn', ':call g:RAction("vim.names")')
    g:RCreateMenuItem('nvi', 'Command.Structure\ (cur)', 'RObjectStr', 'rt', ':call g:RAction("str")')
    g:RCreateMenuItem('nvi', 'Command.View\ data\.frame\ (cur)', 'RViewDF', 'rv', ':call g:RAction("viewobj")')
    g:RCreateMenuItem('nvi', 'Command.View\ data\.frame\ (cur)\ in\ horizontal\ split', 'RViewDF', 'vs', ':call g:RAction("viewobj", ", howto=''split''")')
    g:RCreateMenuItem('nvi', 'Command.View\ data\.frame\ (cur)\ in\ vertical\ split', 'RViewDF', 'vv', ':call g:RAction("viewobj", ", howto=''vsplit''")')
    g:RCreateMenuItem('nvi', 'Command.View\ head(data\.frame)\ (cur)\ in\ horizontal\ split', 'RViewDF', 'vh', ':call g:RAction("viewobj", ", howto=''above 7split'', nrows=6")')
    g:RCreateMenuItem('nvi', 'Command.Run\ dput(cur)\ and\ show\ output\ in\ new\ tab', 'RDputObj', 'td', ':call g:RAction("dputtab")')
    "-------------------------------
    menu R.Command.-Sep02- <nul>
    g:RCreateMenuItem('nvi', 'Command.Arguments\ (cur)', 'RShowArgs', 'ra', ':call g:RAction("args")')
    g:RCreateMenuItem('nvi', 'Command.Example\ (cur)', 'RShowEx', 're', ':call g:RAction("example")')
    g:RCreateMenuItem('nvi', 'Command.Help\ (cur)', 'RHelp', 'rh', ':call g:RAction("help")')
    "-------------------------------
    menu R.Command.-Sep03- <nul>
    g:RCreateMenuItem('nvi', 'Command.Summary\ (cur)', 'RSummary', 'rs', ':call g:RAction("summary")')
    g:RCreateMenuItem('nvi', 'Command.Plot\ (cur)', 'RPlot', 'rg', ':call g:RAction("plot")')
    g:RCreateMenuItem('nvi', 'Command.Plot\ and\ summary\ (cur)', 'RSPlot', 'rb', ':call g:RAction("plotsumm")')
    g:rplugin.hasmenu = 1
enddef

def g:MakeRMenu()
    if g:rplugin.hasmenu == 1
        return
    endif

    # Do not translate "File":
    menutranslate clear

    #---------------------------------------------------------------------------
    # Start/Close
    #---------------------------------------------------------------------------
    g:RCreateMenuItem('nvi', 'Start/Close.Start\ R\ (default)', 'RStart', 'rf', ':call g:StartR("R")')
    g:RCreateMenuItem('nvi', 'Start/Close.Start\ R\ (custom)', 'RCustomStart', 'rc', ':call g:StartR("custom")')
    "-------------------------------
    menu R.Start/Close.-Sep1- <nul>
    g:RCreateMenuItem('nvi', 'Start/Close.Close\ R\ (no\ save)', 'RClose', 'rq', ":call g:RQuit('no')")
    menu R.Start/Close.-Sep2- <nul>

    nmenu <silent> R.Start/Close.Stop\ R<Tab>:RStop :RStop<CR>

    #---------------------------------------------------------------------------
    # Send
    #---------------------------------------------------------------------------
    if &filetype == "r" || g:R_never_unmake_menu
        g:RCreateMenuItem('ni', 'Send.File', 'RSendFile', 'aa', ':call g:SendFileToR("silent")')
        g:RCreateMenuItem('ni', 'Send.File\ (echo)', 'RESendFile', 'ae', ':call g:SendFileToR("echo")')
        g:RCreateMenuItem('ni', 'Send.File\ (open\ \.Rout)', 'RShowRout', 'ao', ':call g:ShowRout()')
    endif
    "-------------------------------
    menu R.Send.-Sep3- <nul>
    g:RCreateMenuItem('ni', 'Send.Block\ (cur)', 'RSendMBlock', 'bb', ':call g:SendMBlockToR("silent", "stay")')
    g:RCreateMenuItem('ni', 'Send.Block\ (cur,\ echo)', 'RESendMBlock', 'be', ':call g:SendMBlockToR("echo", "stay")')
    g:RCreateMenuItem('ni', 'Send.Block\ (cur,\ down)', 'RDSendMBlock', 'bd', ':call g:SendMBlockToR("silent", "down")')
    g:RCreateMenuItem('ni', 'Send.Block\ (cur,\ echo\ and\ down)', 'REDSendMBlock', 'ba', ':call g:SendMBlockToR("echo", "down")')
    "-------------------------------
    if &filetype == "rnoweb" || &filetype == "rmd" || &filetype == "quarto" || &filetype == "rrst" || g:R_never_unmake_menu
        menu R.Send.-Sep4- <nul>
        g:RCreateMenuItem('ni', 'Send.Chunk\ (cur)', 'RSendChunk', 'cc', ':call b:SendChunkToR("silent", "stay")')
        g:RCreateMenuItem('ni', 'Send.Chunk\ (cur,\ echo)', 'RESendChunk', 'ce', ':call b:SendChunkToR("echo", "stay")')
        g:RCreateMenuItem('ni', 'Send.Chunk\ (cur,\ down)', 'RDSendChunk', 'cd', ':call b:SendChunkToR("silent", "down")')
        g:RCreateMenuItem('ni', 'Send.Chunk\ (cur,\ echo\ and\ down)', 'REDSendChunk', 'ca', ':call b:SendChunkToR("echo", "down")')
        g:RCreateMenuItem('ni', 'Send.Chunk\ (from\ first\ to\ here)', 'RSendChunkFH', 'ch', ':call g:SendFHChunkToR()')
    endif
    "-------------------------------
    if &filetype == "quarto"
        menu R.Send.-Sep5- <nul>
        g:RCreateMenuItem('ni', 'Send.Quarto\ render\ (cur\ file)', 'RQuartoRender', 'qr', ':call g:RQuarto("render")')
        g:RCreateMenuItem('ni', 'Send.Quarto\ preview\ (cur\ file)', 'RQuartoPreview', 'qp', ':call g:RQuarto("preview")')
        g:RCreateMenuItem('ni', 'Send.Quarto\ stop\ preview\ (all\ files)', 'RQuartoStop', 'qs', ':call g:RQuarto("stop")')
    endif
    "-------------------------------
    menu R.Send.-Sep6- <nul>
    g:RCreateMenuItem('ni', 'Send.Function\ (cur)', 'RSendFunction', 'ff', ':call g:SendFunctionToR("silent", "stay")')
    g:RCreateMenuItem('ni', 'Send.Function\ (cur,\ echo)', 'RESendFunction', 'fe', ':call g:SendFunctionToR("echo", "stay")')
    g:RCreateMenuItem('ni', 'Send.Function\ (cur\ and\ down)', 'RDSendFunction', 'fd', ':call g:SendFunctionToR("silent", "down")')
    g:RCreateMenuItem('ni', 'Send.Function\ (cur,\ echo\ and\ down)', 'REDSendFunction', 'fa', ':call g:SendFunctionToR("echo", "down")')
    "-------------------------------
    menu R.Send.-Sep7- <nul>
    g:RCreateMenuItem('v', 'Send.Selection', 'RSendSelection', 'ss', ':call g:SendSelectionToR("silent", "stay")')
    g:RCreateMenuItem('v', 'Send.Selection\ (echo)', 'RESendSelection', 'se', ':call g:SendSelectionToR("echo", "stay")')
    g:RCreateMenuItem('v', 'Send.Selection\ (and\ down)', 'RDSendSelection', 'sd', ':call g:SendSelectionToR("silent", "down")')
    g:RCreateMenuItem('v', 'Send.Selection\ (echo\ and\ down)', 'REDSendSelection', 'sa', ':call g:SendSelectionToR("echo", "down")')
    g:RCreateMenuItem('v', 'Send.Selection\ (and\ insert\ output)', 'RSendSelAndInsertOutput', 'so', ':call g:SendSelectionToR("echo", "stay", "NewtabInsert")')
    "-------------------------------
    menu R.Send.-Sep8- <nul>
    g:RCreateMenuItem('ni', 'Send.Paragraph', 'RSendParagraph', 'pp', ':call g:SendParagraphToR("silent", "stay")')
    g:RCreateMenuItem('ni', 'Send.Paragraph\ (echo)', 'RESendParagraph', 'pe', ':call g:SendParagraphToR("echo", "stay")')
    g:RCreateMenuItem('ni', 'Send.Paragraph\ (and\ down)', 'RDSendParagraph', 'pd', ':call g:SendParagraphToR("silent", "down")')
    g:RCreateMenuItem('ni', 'Send.Paragraph\ (echo\ and\ down)', 'REDSendParagraph', 'pa', ':call g:SendParagraphToR("echo", "down")')
    "-------------------------------
    menu R.Send.-Sep9- <nul>
    g:RCreateMenuItem('ni0', 'Send.Line', 'RSendLine', 'l', ':call g:SendLineToR("stay")')
    g:RCreateMenuItem('ni0', 'Send.Line\ (and\ down)', 'RDSendLine', 'd', ':call g:SendLineToR("down")')
    g:RCreateMenuItem('ni0', 'Send.Line\ (and\ insert\ output)', 'RDSendLineAndInsertOutput', 'o', ':call g:SendLineToRAndInsertOutput()')
    g:RCreateMenuItem('i', 'Send.Line\ (and\ new\ one)', 'RSendLAndOpenNewOne', 'q', ':call g:SendLineToR("newline")')
    g:RCreateMenuItem('n', 'Send.Left\ part\ of\ line\ (cur)', 'RNLeftPart', 'r<Left>', ':call g:RSendPartOfLine("left", 0)')
    g:RCreateMenuItem('n', 'Send.Right\ part\ of\ line\ (cur)', 'RNRightPart', 'r<Right>', ':call g:RSendPartOfLine("right", 0)')
    g:RCreateMenuItem('i', 'Send.Left\ part\ of\ line\ (cur)', 'RILeftPart', 'r<Left>', 'l:call g:RSendPartOfLine("left", 1)')
    g:RCreateMenuItem('i', 'Send.Right\ part\ of\ line\ (cur)', 'RIRightPart', 'r<Right>', 'l:call g:RSendPartOfLine("right", 1)')
    if &filetype == "r"
        g:RCreateMenuItem('ni', 'Send.Line \(above\ ones)', 'RSendAboveLines', 'su', ':call g:SendAboveLinesToR()')
    endif

    #---------------------------------------------------------------------------
    # Control
    #---------------------------------------------------------------------------
    g:RControlMenu()
    "-------------------------------
    menu R.Command.-Sep31- <nul>
    if &filetype != "rdoc"
        g:RCreateMenuItem('nvi', 'Command.Set\ working\ directory\ (cur\ file\ path)', 'RSetwd', 'rd', ':call g:RSetWD()')
    endif
    "-------------------------------
    if &filetype == "rnoweb" || g:R_never_unmake_menu
        menu R.Command.-Sep32- <nul>
        g:RCreateMenuItem('nvi', 'Command.Sweave\ (cur\ file)', 'RSweave', 'sw', ':call g:RWeave("nobib", 0, 0)')
        g:RCreateMenuItem('nvi', 'Command.Sweave\ and\ PDF\ (cur\ file)', 'RMakePDF', 'sp', ':call g:RWeave("nobib", 0, 1)')
        g:RCreateMenuItem('nvi', 'Command.Sweave,\ BibTeX\ and\ PDF\ (cur\ file)', 'RBibTeX', 'sb', ':call g:RWeave("bibtex", 0, 1)')
    endif
    menu R.Command.-Sep33- <nul>
    if &filetype == "rnoweb"
        g:RCreateMenuItem('nvi', 'Command.Knit\ (cur\ file)', 'RKnit', 'kn', ':call g:RWeave("nobib", 1, 0)')
        g:RCreateMenuItem('nvi', 'Command.Knit\ and\ PDF\ (cur\ file)', 'RMakePDFK', 'kp', ':call g:RWeave("nobib", 1, 1)')
        g:RCreateMenuItem('nvi', 'Command.Knit,\ BibTeX\ and\ PDF\ (cur\ file)', 'RBibTeXK', 'kb', ':call g:RWeave("bibtex", 1, 1)')
    else
        g:RCreateMenuItem('nvi', 'Command.Knit\ (cur\ file)', 'RKnit', 'kn', ':call g:RKnit()')
        g:RCreateMenuItem('nvi', 'Command.Markdown\ render\ (cur\ file)', 'RMakeRmd', 'kr', ':call g:RMakeRmd("default")')
        if &filetype == "quarto"
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ PDF\ (cur\ file)', 'RMakePDFK', 'kp', ':call g:RMakeRmd("pdf")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ Beamer\ PDF\ (cur\ file)', 'RMakePDFKb', 'kl', ':call g:RMakeRmd("beamer")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ HTML\ (cur\ file)', 'RMakeHTML', 'kh', ':call g:RMakeRmd("html")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ ODT\ (cur\ file)', 'RMakeODT', 'ko', ':call g:RMakeRmd("odt")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ Word\ Document\ (cur\ file)', 'RMakeWord', 'kw', ':call g:RMakeRmd("docx")')
        else
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ PDF\ (cur\ file)', 'RMakePDFK', 'kp', ':call g:RMakeRmd("pdf_document")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ Beamer\ PDF\ (cur\ file)', 'RMakePDFKb', 'kl', ':call g:RMakeRmd("beamer_presentation")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ HTML\ (cur\ file)', 'RMakeHTML', 'kh', ':call g:RMakeRmd("html_document")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ ODT\ (cur\ file)', 'RMakeODT', 'ko', ':call g:RMakeRmd("odt_document")')
            g:RCreateMenuItem('nvi', 'Command.Knit\ and\ Word\ Document\ (cur\ file)', 'RMakeWord', 'kw', ':call g:RMakeRmd("word_document")')
        endif
        g:RCreateMenuItem('nvi', 'Command.Markdown\ render\ [all\ in\ YAML]\ (cur\ file)', 'RMakeRmd', 'ka', ':call g:RMakeRmd("all")')
    endif
    if &filetype == "r" || g:R_never_unmake_menu
        g:RCreateMenuItem('nvi', 'Command.Spin\ (cur\ file)', 'RSpin', 'ks', ':call g:RSpin()')
    endif
    if ($DISPLAY != "" && g:R_synctex && &filetype == "rnoweb") || g:R_never_unmake_menu
        menu R.Command.-Sep34- <nul>
        g:RCreateMenuItem('nvi', 'Command.Open\ PDF\ (cur\ file)', 'ROpenPDF', 'op', ':call g:ROpenPDF("Get Master")')
        g:RCreateMenuItem('nvi', 'Command.Search\ forward\ (SyncTeX)', 'RSyncFor', 'gp', ':call g:SyncTeX_forward()')
        g:RCreateMenuItem('nvi', 'Command.Go\ to\ LaTeX\ (SyncTeX)', 'RSyncTex', 'gt', ':call g:SyncTeX_forward(1)')
    endif
    "-------------------------------
    menu R.Command.-Sep35- <nul>
    g:RCreateMenuItem('n', 'Command.Debug\ (function)', 'RDebug', 'bg', ':call g:RAction("debug")')
    g:RCreateMenuItem('n', 'Command.Undebug\ (function)', 'RUndebug', 'ud', ':call g:RAction("undebug")')
    "-------------------------------
    if &filetype == "r" || &filetype == "rnoweb" || g:R_never_unmake_menu
        menu R.Command.-Sep36- <nul>
        nmenu <silent> R.Command.Build\ tags\ file\ (cur\ dir)<Tab>:RBuildTags :call g:RBuildTags()<CR>
        imenu <silent> R.Command.Build\ tags\ file\ (cur\ dir)<Tab>:RBuildTags <Esc>:call g:RBuildTags()<CR>a
    endif

    menu R.-Sep37- <nul>

    #---------------------------------------------------------------------------
    # Edit
    #---------------------------------------------------------------------------
    if &filetype == "r" || &filetype == "rnoweb" || &filetype == "rrst" || &filetype == "rhelp" || g:R_never_unmake_menu
        if g:R_assign == 1 || g:R_assign == 2
            silent execute 'imenu <silent> R.Edit.Insert\ \"\ <-\ \"<Tab>' .. g:R_assign_map .. ' <Esc>:call g:ReplaceUnderS()<CR>a'
        endif
        imenu <silent> R.Edit.Complete\ object\ name<Tab>^X^O <C-X><C-O>
        menu R.Edit.-Sep41- <nul>
        nmenu <silent> R.Edit.Indent\ (line)<Tab>== ==
        vmenu <silent> R.Edit.Indent\ (selected\ lines)<Tab>= =
        nmenu <silent> R.Edit.Indent\ (whole\ buffer)<Tab>gg=G gg=G
        menu R.Edit.-Sep42- <nul>
        if g:R_enable_comment
            g:RCreateMenuItem('ni', 'Edit.Toggle\ comment\ (line/sel)', 'RToggleComment', 'xx', ':call g:RComment("normal")')
            g:RCreateMenuItem('v',  'Edit.Toggle\ comment\ (line/sel)', 'RToggleComment', 'xx', ':call g:RComment("selection")')
            g:RCreateMenuItem('ni', 'Edit.Comment\ (line/sel)', 'RSimpleComment', 'xc', ':call g:RSimpleCommentLine("normal", "c")')
            g:RCreateMenuItem('v',  'Edit.Comment\ (line/sel)', 'RSimpleComment', 'xc', ':call g:RSimpleCommentLine("selection", "c")')
            g:RCreateMenuItem('ni', 'Edit.Uncomment\ (line/sel)', 'RSimpleUnComment', 'xu', ':call g:RSimpleCommentLine("normal", "u")')
            g:RCreateMenuItem('v',  'Edit.Uncomment\ (line/sel)', 'RSimpleUnComment', 'xu', ':call g:RSimpleCommentLine("selection", "u")')
            g:RCreateMenuItem('ni', 'Edit.Add/Align\ right\ comment\ (line,\ sel)', 'RRightComment', ';', ':call g:MovePosRCodeComment("normal")')
            g:RCreateMenuItem('v',  'Edit.Add/Align\ right\ comment\ (line,\ sel)', 'RRightComment', ';', ':call g:MovePosRCodeComment("selection")')
        endif
        if &filetype == "rnoweb" || &filetype == "rrst" || &filetype == "rmd" || &filetype == "quarto" || g:R_never_unmake_menu
            menu R.Edit.-Sep43- <nul>
            g:RCreateMenuItem('n', 'Edit.Go\ (next\ R\ chunk)', 'RNextRChunk', 'gn', ':call b:NextRChunk()')
            g:RCreateMenuItem('n', 'Edit.Go\ (previous\ R\ chunk)', '', 'gN', ':call b:PreviousRChunk()')
        endif
    endif

    #---------------------------------------------------------------------------
    # Object Browser
    #---------------------------------------------------------------------------
    g:RBrowserMenu()

    #---------------------------------------------------------------------------
    # Help
    #---------------------------------------------------------------------------
    menu R.-Sep51- <nul>
    amenu R.Help\ (plugin).Overview :help vim-r-overview<CR>
    amenu R.Help\ (plugin).Main\ features :help vim-r-features<CR>
    amenu R.Help\ (plugin).Installation :help vim-r-installation<CR>
    amenu R.Help\ (plugin).Use :help vim-r-use<CR>
    amenu R.Help\ (plugin).Known\ bugs\ and\ workarounds :help vim-r-known-bugs<CR>

    amenu R.Help\ (plugin).Options.Assignment\ operator\ and\ Rnoweb\ code :help R_assign<CR>
    amenu R.Help\ (plugin).Options.Object\ Browser :help R_objbr_place<CR>
    amenu R.Help\ (plugin).Options.Vim\ as\ pager\ for\ R\ help :help R_vimpager<CR>
    amenu R.Help\ (plugin).Options.R\ path :help R_path<CR>
    amenu R.Help\ (plugin).Options.Arguments\ to\ R :help R_args<CR>
    amenu R.Help\ (plugin).Options.Omni\ completion\ when\ R\ not\ running :help R_start_libs<CR>
    amenu R.Help\ (plugin).Options.Syntax\ highlighting\ of\ \.Rout\ files :help Rout_more_colors<CR>
    amenu R.Help\ (plugin).Options.Special\ R\ functions :help R_listmethods<CR>
    amenu R.Help\ (plugin).Options.Never\ unmake\ the\ R\ menu :help R_never_unmake_menu<CR>

    amenu R.Help\ (plugin).Custom\ key\ bindings :help vim-r-key-bindings<CR>
    amenu R.Help\ (plugin).News :help vim-r-news<CR>

    amenu R.Help\ (R)<Tab>:Rhelp :call g:SendCmdToR("help.start()")<CR>
    g:rplugin.hasmenu = 1
enddef

def g:UnMakeRMenu()
    if g:rplugin.hasmenu == 0 || g:R_never_unmake_menu == 1 || &previewwindow || (&buftype == "nofile" && &filetype != "rbrowser")
        return
    endif
    aunmenu R
    g:rplugin.hasmenu = 0
enddef

def g:MakeRBrowserMenu()
    g:rplugin.curbuf = bufname("%")
    if g:rplugin.hasmenu == 1
        return
    endif
    menutranslate clear
    g:RControlMenu()
    g:RBrowserMenu()
enddef
