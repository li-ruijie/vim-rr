vim9script

# Backward search from SumatraPDF. This file is sourced by the Vim that
# SumatraPDF starts for a double click in a PDF, with an inverse search
# command such as the following one (see |vim-rr-sumatra| in the help file):
#
#   vim -v --not-a-term -T dumb -S ".../R/sumatra_inverse.vim"
#       -c "RInverseSearch %l '%f'" -c "quitall!"
#
# That Vim is not the one that edits the document, so the search is passed to
# every running Vim through its server name. A Vim in which vim-rr has loaded
# its SumatraPDF support and which edits an Rnoweb file of the document
# jumps to the line. Every other Vim ignores the request.

# "args" is the line number, a space, and the file name between apostrophes.
# The name is taken as text, so an apostrophe inside it is passed on intact.
def Broadcast(args: string)
    var m = matchlist(args, '^\s*\(\d\+\)\s\+''\(.*\)''\s*$')
    if empty(m)
        return
    endif
    var expr = printf("exists('*g:SumatraInverseSearch') ? g:SumatraInverseSearch('%s', %d) : ''",
        substitute(m[2], "'", "''", 'g'), str2nr(m[1]))
    for server in split(serverlist(), "\n")
        # A Vim that cannot answer, such as this one, must not end the loop
        try
            remote_expr(server, expr)
        catch
        endtry
    endfor
enddef

command! -nargs=* RInverseSearch Broadcast(<q-args>)
