# Collects the commands that the R code of vimcom builds for Vim, with no R
# running under Vim. test_17_names_in_r.vim runs it and evaluates each command.
# Usage: Rscript vimcom_commands.R <R/vimcom/R> <output file> <work directory>
args <- commandArgs(trailingOnly = TRUE)
src <- args[[1]]
out <- args[[2]]
work <- args[[3]]

# The functions are read into an environment of their own, where the compiled
# routine that sends a command is replaced. The replacement hands the command
# back as a condition, which ends the function that built it.
env <- new.env()
assign(".C", function(name, cmd, ...) {
    stop(structure(class = c("vimcmd", "condition"), list(message = cmd, call = NULL)))
}, envir = env)
# The packages that render a document are not needed to build a command
rendering <- list(knit2pdf = function(...) NULL,
                  render = function(...) "it's a \"doc\".html")
assign("::", function(pkg, name) {
    pkg <- as.character(substitute(pkg))
    name <- as.character(substitute(name))
    if (pkg %in% c("knitr", "rmarkdown")) rendering[[name]] else getExportedValue(pkg, name)
}, envir = env)
assign("require", function(...) TRUE, envir = env)
invisible(Map(function(f) sys.source(file.path(src, f), envir = env),
              c("misc.R", "help.R", "interlace.R", "bol.R")))

command <- function(expr) {
    tryCatch({
        expr
        "no command"
    }, vimcmd = conditionMessage)
}

Sys.setenv(VIMR_TMPDIR = work, VIMR_ID = "1")
options(browser = "my 'browser'", vimcom.delim = "\t")
assign("it's", data.frame(a = 1), envir = .GlobalEnv)
assign("it's \"f\"\\", function(x, y = 1) NULL, envir = .GlobalEnv)
assign("plainf", function(a, b = 2) NULL, envir = .GlobalEnv)
assign("d'f", structure(data.frame(1, 2), names = c("it's", "b")), envir = .GlobalEnv)
writeLines("1 + 1", file.path(work, "code.R"))

cmds <- c(
    command(env[["vim.interlace.rrst"]]("it's.Rrst", rrstdir = work)),
    command(env[["vim.interlace.rmd"]]("a.Rmd", rmddir = work)),
    command(env[["vim.edit"]](1, "")),
    command(env[["vim_viewobj"]]("it's")),
    command(env[["vim_viewobj"]]("it's", R_df_viewer = "View(%s)")),
    command(env[["vim_viewobj"]]("no'such")),
    command(env[["vim_dput"]]("c('a')")),
    command(env[["vim_capture_source_output"]](file.path(work, "code.R"), "it's out")),
    command(env[["vim_insert"]](1 + 1, "it's")),
    command(env[["vim.example"]]("it's")),
    command(env[["vim.help"]]("it's", 80L)),
    # A line break, which the text of an R error holds as well
    command(env[["vim_viewobj"]]("no\nsuch")),
    command(env[["vim.GlobalEnv.fun.args"]]("it's \"f\"\\")),
    # A message for the server, which puts the items into a command for Vim
    command(env[["vim_complete_args"]]("7", "plainf", "", firstobj = "d'f", ldf = TRUE))
)
writeLines(cmds, out, useBytes = TRUE)
