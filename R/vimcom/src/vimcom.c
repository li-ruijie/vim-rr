#include <R.h> /* to include Rconfig.h */
#include <Rdefines.h>
#include <Rinternals.h>
#include <R_ext/Parse.h>
#ifndef WIN32
#define HAVE_SYS_SELECT_H
#include <R_ext/eventloop.h>
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>

#ifdef __FreeBSD__
#include <netinet/in.h>
#endif

#include <unistd.h>

#ifdef WIN32
#include <process.h>
#include <winsock2.h>
#ifdef _WIN64
#include <inttypes.h>
#endif
#else
#include <arpa/inet.h> // inet_addr()
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <sys/socket.h>
#endif

#ifndef WIN32
// Needed to know what is the prompt
#include <Rinterface.h>
#define R_INTERFACE_PTRS 1
extern int (*ptr_R_ReadConsole)(const char *, unsigned char *, int, int);
static int (*save_ptr_R_ReadConsole)(const char *, unsigned char *, int, int);
static int debugging;           // Is debugging a function now?
LibExtern SEXP R_SrcfileSymbol; // R internal variable defined in Defn.h.
static void SrcrefInfo(void);
#endif
static int debug_r; // Should detect when `browser()` is running and start
                    // debugging mode?

static int initialized = 0; // TCP client successfully connected to the server.

static int verbose = 0;  // 1: version number; 2: initial information; 3: TCP in
                         // and out; 4: more verbose; 5: really verbose.
static int allnames = 0; // Show hidden objects in omni completion and
                         // Object Browser?
static int nlibs = 0;    // Number of loaded libraries.
static int needs_lib_msg = 0;    // Did the number of libraries change?
static int needs_glbenv_msg = 0; // Did .GlobalEnv change?

static char nrs_port[16]; // vimrserver port.
static char vimsecr[128]; // Secret for authenticated TCP communication.

static char *glbnvbuf1;   // Temporary buffer used to store the list of
                          // .GlobalEnv objects.
static char *glbnvbuf2;   // Temporary buffer used to store the list of
                          // .GlobalEnv objects.
static char *send_ge_buf; // Temporary buffer used to store the list of
                          // .GlobalEnv objects.

static unsigned long lastglbnvbsz;         // Previous size of glbnvbuf2.
static unsigned long glbnvbufsize = 32768; // Current size of glbnvbuf2.

static unsigned long tcp_header_len; // Lenght of vimsecr + 9. Stored in a
                                     // variable to avoid repeatedly calling
                                     // strlen().

static double timelimit =
    100.0; // Maximum acceptable time to build list of .GlobalEnv objects
static int sizelimit = 1000000; // Maximum acceptable size of string
                                // representing .GlobalEnv (list of objects)
static int maxdepth = 12; // How many levels to parse in lists and S4 objects
// when building list of objects for auto-completion. The value decreases if
// the listing is too slow.
static int curdepth = 0; // Current level of the list or S4 object being parsed
                         // for omni-completion.
static int autoglbenv = 0; // Should the list of objects in .GlobalEnv be
// automatically updated after each top level command is executed? It will
// always be 1 if the Object Browser is open.

static char tmpdir[512]; // The environment variable VIMR_TMPDIR.
static int setwidth = 0; // Set the option width after each command is executed
static int oldcolwd = 0; // Last set width.

static int flag_glbenv = 0; // Do we have to list objects from .GlobalEnv?
#ifndef WIN32
static int flag_debug = 0; // Do we need to get file name and line information
                           // of debugging function?
#endif

#ifdef WIN32
static CRITICAL_SECTION flag_mutex;
#define FLAG_LOCK() EnterCriticalSection(&flag_mutex)
#define FLAG_UNLOCK() LeaveCriticalSection(&flag_mutex)
#else
static pthread_mutex_t flag_mutex = PTHREAD_MUTEX_INITIALIZER;
#define FLAG_LOCK() pthread_mutex_lock(&flag_mutex)
#define FLAG_UNLOCK() pthread_mutex_unlock(&flag_mutex)
#endif

// Linked-list queue for deferred eval commands. Commands are enqueued by the
// TCP thread (case 'E' / 'L') and drained by vimcom_task (Windows) or
// vimcom_exec (Unix) on the main R thread.
#define MAX_EVAL_CMD 65536

typedef struct eval_node {
    struct eval_node *next;
    char cmd[]; // flexible array member — allocated inline with node
} eval_node_t;

static eval_node_t *eval_head = NULL;
static eval_node_t *eval_tail = NULL;

/**
 * @brief Enqueue a command for deferred execution.
 * Must be called under FLAG_LOCK.
 */
static void eval_queue_push(const char *cmd) {
    size_t len = strlen(cmd);
    if (len > MAX_EVAL_CMD) {
        REprintf("vimcom: command too long (%zu bytes, max %d)\n", len,
                 MAX_EVAL_CMD);
        return;
    }
    eval_node_t *node = malloc(sizeof(eval_node_t) + len + 1);
    if (!node) {
        REprintf("vimcom: malloc failed for eval queue node\n");
        return;
    }
    memcpy(node->cmd, cmd, len + 1);
    node->next = NULL;
    if (eval_tail)
        eval_tail->next = node;
    else
        eval_head = node;
    eval_tail = node;
}

/**
 * @brief Detach the entire queue and return its head.
 * Must be called under FLAG_LOCK. Caller owns the returned list.
 */
static eval_node_t *eval_queue_drain(void) {
    eval_node_t *queue = eval_head;
    eval_head = eval_tail = NULL;
    return queue;
}

/**
 * @brief Free a detached queue without executing any commands.
 * Used for cleanup on disconnect/shutdown.
 */
static void eval_queue_free(eval_node_t *queue) {
    while (queue) {
        eval_node_t *tmp = queue;
        queue = queue->next;
        free(tmp);
    }
}

#ifdef WIN32
extern void (*R_PolledEvents)(void);
static void (*original_polled_events)(void) = NULL;
static int r_is_busy = 1; // Is R executing a top level command? R memory will
// become corrupted and R will crash afterwards if we execute a function that
// creates R objects while R is busy.
static time_t busy_since = 0; // When r_is_busy was last set to 1. Used by the
// TCP thread to auto-reset a stale r_is_busy flag (e.g. after RStudio
// interrupt kills the task callback).
#else
static int fired = 0; // Do we have commands waiting to be executed?
static int ifd;       // input file descriptor
static int ofd;       // output file descriptor
static InputHandler *ih;
#endif

/**
 * @typedef lib_info_
 * @brief Structure with name and version number of a library.
 *
 * The complete information of libraries is stored in its `omnils_`, `fun_` and
 * `args_` files in the Vim-R cache directory. The vimrserver only needs the
 * name and version number of the library to read the corresponding files.
 *
 */
typedef struct lib_info_ {
    char *name;
    char *version;
    unsigned long strlen;
    struct lib_info_ *next;
} LibInfo;

static LibInfo *libList; // Linked list of loaded libraries information (names
                         // and version numbers).

static void vimcom_checklibs(void);
static void send_to_vim(char *msg);
static void vimcom_eval_expr(const char *buf);

#ifdef WIN32
SOCKET sfd; // File descriptor of socket used in the TCP connection with the
            // vimrserver.
static HANDLE tid; // Identifier of thread running TCP connection loop.
extern void Rconsolecmd(char *cmd); // Defined in R: src/gnuwin32/rui.c.
#else
static int sfd = -1;  // File descriptor of socket used in the TCP connection
                      // with the vimrserver.
static pthread_t tid; // Identifier of thread running TCP connection loop.
#endif

static void escape_str(char *s) {
    while (*s) {
        if (*s == '\n')
            *s = ' ';
        s++;
    }
}

/**
 * @brief Concatenate two strings.
 *
 * @param dest Destination buffer.
 * @param src String to be appended to `dest`.
 * @return Pointer to the new NULL terminating byte of `dest`.
 */
static char *vimcom_strcat(char *dest, const char *src) {
    while (*dest)
        dest++;
    while ((*dest++ = *src++))
        ;
    return --dest;
}

/**
 * @brief Replace buffers used to store omni-completion information with
 * bigger ones.
 *
 * @return Pointer to the NULL terminating byte of glbnvbuf2.
 */
static char *vimcom_grow_buffers(void) {
    unsigned long new_size = glbnvbufsize + 32768;

    // Allocate all three buffers atomically — commit or roll back
    char *new1 = (char *)calloc(new_size, sizeof(char));
    char *new2 = (char *)calloc(new_size, sizeof(char));
    char *new3 = (char *)calloc(new_size + 64, sizeof(char));
    if (!new1 || !new2 || !new3) {
        free(new1);
        free(new2);
        free(new3);
        REprintf("vimcom: grow_buffers failed\n");
        return (glbnvbuf2 + strlen(glbnvbuf2));
    }

    strcpy(new1, glbnvbuf1);
    free(glbnvbuf1);
    glbnvbuf1 = new1;

    strcpy(new2, glbnvbuf2);
    free(glbnvbuf2);
    glbnvbuf2 = new2;

    free(send_ge_buf);
    send_ge_buf = new3;

    lastglbnvbsz = glbnvbufsize;
    glbnvbufsize = new_size;
    return (glbnvbuf2 + strlen(glbnvbuf2));
}

/**
 * @brief Send string to vimrserver.
 *
 * The function sends a string to vimrserver through the TCP connection
 * established at `vimcom_Start()`.
 *
 * @param msg The message to be sent.
 */
static void send_to_vim(char *msg) {
    if (sfd == -1)
        return;

    int sent;
    char b[192];
    size_t len;

    if (verbose > 2) {
        if (strlen(msg) < 128)
            REprintf("send_to_vim [%lld] {%s}: %s\n", (long long)sfd, vimsecr,
                     msg);
    }

    len = strlen(msg);

    /*
       TCP message format:
         VIMR_SECRET : Prefix VIMR_SECRET to msg to increase security
         000000000    : Size of message in 9 digits
         msg          : The message
         \x11         : Final byte

       Notes:

       - The string is terminated by a final \x11 byte which hopefully is never
         used in any R code. It would be slower to escape special characters.

       - The time to save the file at /dev/shm is bigger than the time to send
         the buffer through a TCP connection.

       - When the msg is very big, it's faster to send the final message in
         three pieces than to call snprintf() to assemble everything in a
         single string.
    */

    // Send the header
    snprintf(b, sizeof(b), "%s%09zu", vimsecr, len);
    sent = send(sfd, b, tcp_header_len, 0);
    if (sent < 0 || (size_t)sent != tcp_header_len) {
        if (sent == -1)
            REprintf("Error sending message header to Vim-R: -1\n");
        else
            REprintf("Error sending message header to Vim-R: %lu x %d\n",
                     tcp_header_len, sent);
#ifdef WIN32
        closesocket(sfd);
        WSACleanup();
#else
        close(sfd);
#endif
        sfd = -1;
        strcpy(nrs_port, "0");
        return;
    }

    // based on code found on php source
    // Send the message
    char *pCur = msg;
    char *pEnd = msg + len;
    int loop = 0;
    while (pCur < pEnd) {
        sent = send(sfd, pCur, pEnd - pCur, 0);
        if (sent >= 0) {
            pCur += sent;
        } else if (sent == -1) {
            REprintf("Error sending message to Vim-R: %zu x %zu\n", len,
                     pCur - msg);
            return;
        }
        loop++;
        if (loop == 100) {
            // The goal here is to avoid infinite loop.
            // TODO: Maybe delete this check because php code does not have
            // something similar
            REprintf("Too many attempts to send message to Vim-R: %zu x %d\n",
                     len, sent);
            return;
        }
    }

    // End the message with \x11
    sent = send(sfd, "\x11", 1, 0);
    if (sent != 1)
        REprintf("Error sending final byte to Vim-R: 1 x %d\n", sent);
}

/**
 * @brief Function called by R code to send message to vimrserver.
 *
 * @param cmd The message to be sent.
 */
void vimcom_msg_to_vim(char **cmd) { send_to_vim(*cmd); }

/**
 * @brief Duplicate single quotes.
 *
 * We use single quote to define field names and values of Vim dictionaries.
 * Single quotes within such strings must be duplicated to avoid Vim errors
 * when evaluating the string as a dictionary.
 *
 * @param buf Original string.
 * @param buf2 Destination buffer of the new string with duplicated quotes.
 * @param bsize Size limit of destination buffer.
 */
static void vimcom_squo(const char *buf, char *buf2, int bsize) {
    int i = 0, j = 0;
    while (j < bsize) {
        if (buf[i] == '\'') {
            buf2[j] = '\'';
            j++;
            buf2[j] = '\'';
        } else if (buf[i] == 0) {
            buf2[j] = 0;
            break;
        } else {
            buf2[j] = buf[i];
        }
        i++;
        j++;
    }
    buf2[bsize - 1] = 0;
}

/**
 * @brief Quote strings with backticks.
 *
 * The names of R objects that are invalid to be inserted directly in the
 * console must be quoted with backticks.
 *
 * @param b1 Name to be quoted.
 * @param b2 Destination buffer to the quoted name.
 */
static void vimcom_backtick(const char *b1, char *b2) {
    int i = 0, j = 0;
    while (i < 511 && j < 510 && b1[i] != '$' && b1[i] != '@' && b1[i] != 0) {
        if (b1[i] == '[' && b1[i + 1] == '[') {
            b2[j] = '[';
            i++;
            j++;
            if (j >= 510)
                break;
            b2[j] = '[';
            i++;
            j++;
        } else {
            b2[j] = '`';
            j++;
        }
        while (i < 511 && j < 510 && b1[i] != '$' && b1[i] != '@' &&
               b1[i] != '[' && b1[i] != 0) {
            b2[j] = b1[i];
            i++;
            j++;
        }
        if (j < 510 && b1[i - 1] != ']') {
            b2[j] = '`';
            j++;
        }
        if (b1[i] == 0)
            break;
        if (j < 510 && b1[i] != '[') {
            b2[j] = b1[i];
            i++;
            j++;
        }
    }
    b2[j] = 0;
}

/**
 * @brief Creates a new LibInfo structure to store the name and version
 * number of a library
 *
 * @param nm Name of the library.
 * @param vrsn Version number of the library.
 * @return Pointer to the new LibInfo structure.
 */
static LibInfo *vimcom_lib_info_new(const char *nm, const char *vrsn) {
    LibInfo *pi = calloc(1, sizeof(LibInfo));
    if (!pi)
        return NULL;
    pi->name = malloc((strlen(nm) + 1) * sizeof(char));
    if (!pi->name) {
        free(pi);
        return NULL;
    }
    strcpy(pi->name, nm);
    pi->version = malloc((strlen(vrsn) + 1) * sizeof(char));
    if (!pi->version) {
        free(pi->name);
        free(pi);
        return NULL;
    }
    strcpy(pi->version, vrsn);
    pi->strlen = strlen(pi->name) + strlen(pi->version) + 2;
    return pi;
}

/**
 * @brief Adds a new LibInfo structure to libList, the linked list of loaded
 * libraries.
 *
 * @param nm The name of the library
 * @param vrsn The version number of the library
 */
static void vimcom_lib_info_add(const char *nm, const char *vrsn) {
    LibInfo *pi = vimcom_lib_info_new(nm, vrsn);
    if (!pi) {
        REprintf("vimcom: malloc failed in vimcom_lib_info_add\n");
        return;
    }
    if (libList) {
        pi->next = libList;
        libList = pi;
    } else {
        libList = pi;
    }
}

/**
 * @brief Returns a pointer to information on an library.
 *
 * @param nm Name of the library.
 * @return Pointer to a LibInfo structure with information on the library
 * `nm`.
 */
static LibInfo *vimcom_get_lib(const char *nm) {
    if (!libList)
        return NULL;

    LibInfo *pi = libList;
    do {
        if (strcmp(pi->name, nm) == 0)
            return pi;
        pi = pi->next;
    } while (pi);

    return NULL;
}

/**
 * @brief This function adds a line with information for
 * omni-completion.
 *
 * @param x Object whose information is to be generated.
 *
 * @param xname The name of the object.
 *
 * @param curenv Current "environment" of object x. If x is an element of a list
 * or S4 object, `curenv` will be the representation of the parent structure.
 * Example: for `x` in `alist$aS4obj@x`, `curenv` will be `alist$aS4obj@`.
 *
 * @param p A pointer to the current NULL byte terminating the glbnvbuf2
 * buffer.
 *
 * @param depth Current number of levels in lists and S4 objects.
 *
 * @return The pointer p updated after the insertion of the new line.
 */
static char *vimcom_glbnv_line(SEXP *x, const char *xname, const char *curenv,
                               char *p, int depth) {
    if (depth > maxdepth)
        return p;

    if (depth > curdepth)
        curdepth = depth;

    int xgroup = 0; // 1 = function, 2 = data.frame, 3 = list, 4 = s4
    char ebuf[64];
    int len = 0;
    SEXP txt, lablab;
    SEXP sn = R_NilValue;
    char buf[576];
    char bbuf[512];

    // Grow if less than 2048 bytes remain in the buffer
    if ((size_t)(p - glbnvbuf2) + 2048 > glbnvbufsize)
        p = vimcom_grow_buffers();

    p = vimcom_strcat(p, curenv);
    snprintf(ebuf, 63, "%s", xname);
    escape_str(ebuf);
    p = vimcom_strcat(p, ebuf);

    if (Rf_isLogical(*x)) {
        p = vimcom_strcat(p, "\006%\006");
    } else if (Rf_isNumeric(*x)) {
        p = vimcom_strcat(p, "\006{\006");
    } else if (Rf_isFactor(*x)) {
        p = vimcom_strcat(p, "\006!\006");
    } else if (Rf_isValidString(*x)) {
        p = vimcom_strcat(p, "\006~\006");
    } else if (Rf_isFunction(*x)) {
        p = vimcom_strcat(p, "\006\003\006");
        xgroup = 1;
    } else if (Rf_isFrame(*x)) {
        p = vimcom_strcat(p, "\006$\006");
        xgroup = 2;
    } else if (Rf_isNewList(*x)) {
        p = vimcom_strcat(p, "\006[\006");
        xgroup = 3;
    } else if (Rf_isS4(*x)) {
        p = vimcom_strcat(p, "\006<\006");
        xgroup = 4;
    } else if (Rf_isEnvironment(*x)) {
        p = vimcom_strcat(p, "\006:\006");
    } else if (TYPEOF(*x) == PROMSXP) {
        p = vimcom_strcat(p, "\006&\006");
    } else {
        p = vimcom_strcat(p, "\006*\006");
    }

    // Specific class of object, if any
    PROTECT(txt = getAttrib(*x, R_ClassSymbol));
    if (!isNull(txt)) {
        p = vimcom_strcat(p, CHAR(STRING_ELT(txt, 0)));
    }
    UNPROTECT(1);

    p = vimcom_strcat(p, "\006.GlobalEnv\006");

    if (xgroup == 1) {
        /* It would be necessary to port args2buff() from src/main/deparse.c to
           here but it's too big. So, it's better to call vimcom:::vim.args()
           during omni completion. FORMALS() may return an object that will
           later crash R:
           https://github.com/jalvesaq/Vim-R/issues/543#issuecomment-748981771
         */
        p = vimcom_strcat(p, "[\x12not_checked\x12]");
    }

    // Add label
    PROTECT(lablab = allocVector(STRSXP, 1));
    SET_STRING_ELT(lablab, 0, mkChar("label"));
    PROTECT(txt = getAttrib(*x, lablab));
    if (length(txt) > 0) {
        if (Rf_isValidString(txt)) {
            snprintf(buf, 159, "\006\006%s", CHAR(STRING_ELT(txt, 0)));
            escape_str(buf);
            p = vimcom_strcat(p, buf);
        } else {
            p = vimcom_strcat(p, "\006\006Error: label is not a valid string.");
        }
    } else {
        p = vimcom_strcat(p, "\006\006");
    }
    UNPROTECT(2);

    // Add the object length
    if (xgroup == 2) {
        snprintf(buf, 127, " [%d, %d]", length(Rf_GetRowNames(*x)), length(*x));
        p = vimcom_strcat(p, buf);
    } else if (xgroup == 3) {
        snprintf(buf, 127, " [%d]", length(*x));
        p = vimcom_strcat(p, buf);
    } else if (xgroup == 4) {
        SEXP cmdSexp, cmdexpr;
        ParseStatus status;
        snprintf(buf, 575, "%s%s", curenv, xname);
        vimcom_backtick(buf, bbuf);
        snprintf(buf, 575, "slotNames(%s)", bbuf);
        PROTECT(cmdSexp = allocVector(STRSXP, 1));
        SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
        PROTECT(cmdexpr = R_ParseVector(cmdSexp, -1, &status, R_NilValue));
        if (status == PARSE_OK) {
            int er = 0;
            PROTECT(sn = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv, &er));
            if (er)
                REprintf("vimcom error executing command: slotNames(%s%s)\n",
                         curenv, xname);
            else
                len = length(sn);
            UNPROTECT(1);
        } else {
            REprintf("vimcom error: invalid value in slotNames(%s%s)\n", curenv,
                     xname);
        }
        UNPROTECT(2);
        snprintf(buf, 127, " [%d]", len);
        p = vimcom_strcat(p, buf);
    }

    // finish the line
    p = vimcom_strcat(p, "\006\n");

    if (xgroup > 1) {
        char newenv[576];
        SEXP elmt = R_NilValue;
        const char *ename;

        if (xgroup == 4) {
            snprintf(newenv, 575, "%s%s@", curenv, xname);
            if (len > 0) {
                for (int i = 0; i < len; i++) {
                    ename = CHAR(STRING_ELT(sn, i));
                    PROTECT(elmt = R_do_slot(*x, Rf_install(ename)));
                    p = vimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
            }
        } else {
            SEXP listNames;
            snprintf(newenv, 575, "%s%s$", curenv, xname);
            PROTECT(listNames = getAttrib(*x, R_NamesSymbol));
            len = length(listNames);
            if (len == 0) { /* Empty list? */
                int len1 = length(*x);
                if (len1 > 0) { /* List without names */
                    len1 -= 1;
                    if (newenv[strlen(newenv) - 1] == '$')
                        newenv[strlen(newenv) - 1] = 0; // Delete trailing '$'
                    for (int i = 0; i < len1; i++) {
                        snprintf(ebuf, sizeof(ebuf), "[[%d]]", i + 1);
                        elmt = VECTOR_ELT(*x, i);
                        p = vimcom_glbnv_line(&elmt, ebuf, newenv, p,
                                              depth + 1);
                    }
                    snprintf(ebuf, sizeof(ebuf), "[[%d]]", len1 + 1);
                    PROTECT(elmt = VECTOR_ELT(*x, len1));
                    p = vimcom_glbnv_line(&elmt, ebuf, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
            } else { /* Named list */
                SEXP eexp;
                len -= 1;
                for (int i = 0; i < len; i++) {
                    PROTECT(eexp = STRING_ELT(listNames, i));
                    ename = CHAR(eexp);
                    UNPROTECT(1);
                    if (ename[0] == 0) {
                        snprintf(ebuf, sizeof(ebuf), "[[%d]]", i + 1);
                        ename = ebuf;
                    }
                    PROTECT(elmt = VECTOR_ELT(*x, i));
                    p = vimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
                ename = CHAR(STRING_ELT(listNames, len));
                if (ename[0] == 0) {
                    snprintf(ebuf, sizeof(ebuf), "[[%d]]", len + 1);
                    ename = ebuf;
                }
                PROTECT(elmt = VECTOR_ELT(*x, len));
                p = vimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                UNPROTECT(1);
            }
            UNPROTECT(1); /* listNames */
        }
    }
    return p;
}

/**
 * @brief Generate a list of objects in .GlobalEnv and store it in the
 * glbnvbuf2 buffer. The string stored in glbnvbuf2 represents a file with the
 * same format of the `omnils_` files in Vim-R's cache directory.
 */
static void vimcom_globalenv_list(void) {
    if (verbose > 4)
        REprintf("vimcom_globalenv_list()\n");
    const char *varName;
    SEXP envVarsSEXP, varSEXP;

    if (tmpdir[0] == 0)
        return;

    clock_t tm = clock();

    memset(glbnvbuf2, 0, glbnvbufsize);
    char *p = glbnvbuf2;

    curdepth = 0;

    PROTECT(envVarsSEXP = R_lsInternal(R_GlobalEnv, allnames));
    for (int i = 0; i < Rf_length(envVarsSEXP); i++) {
        varName = CHAR(STRING_ELT(envVarsSEXP, i));
        if (R_BindingIsActive(Rf_install(varName), R_GlobalEnv)) {
            // See: https://github.com/jalvesaq/Vim-R/issues/686
            PROTECT(varSEXP = R_ActiveBindingFunction(Rf_install(varName),
                                                      R_GlobalEnv));
        } else {
            PROTECT(varSEXP = Rf_findVar(Rf_install(varName), R_GlobalEnv));
        }
        if (varSEXP != R_UnboundValue) {
            // should never be unbound
            p = vimcom_glbnv_line(&varSEXP, varName, "", p, 0);
        } else {
            REprintf("vimcom_globalenv_list: Unexpected R_UnboundValue.\n");
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);

    size_t len1 = strlen(glbnvbuf1);
    size_t len2 = strlen(glbnvbuf2);
    int changed = len1 != len2;
    if (verbose > 4)
        REprintf("globalenv_list(0) len1 = %zu, len2 = %zu\n", len1, len2);
    if (!changed) {
        if (memcmp(glbnvbuf1, glbnvbuf2, len1) != 0)
            changed = 1;
    }

    if (changed)
        needs_glbenv_msg = 1;

    double tmdiff = 1000 * ((double)clock() - tm) / CLOCKS_PER_SEC;
    if (tmdiff > timelimit || strlen(glbnvbuf1) > sizelimit) {
        maxdepth = curdepth - 1;
        if (verbose)
            REprintf(
                "vimcom:\n"
                "    Time to buiild list of objects: %g ms (max_time = %g ms)\n"
                "    List size: %zu bytes (max_size = %d bytes)\n"
                "    New max_depth: %d\n",
                tmdiff, timelimit, strlen(glbnvbuf1), sizelimit, maxdepth);
    }
}

/**
 * @brief Send to Vim-R the string containing the list of objects in
 * .GlobalEnv.
 */
static void send_glb_env(void) {
    clock_t t1;

    t1 = clock();

    strcpy(send_ge_buf, "+G");
    strcat(send_ge_buf, glbnvbuf2);
    send_to_vim(send_ge_buf);

    if (verbose > 3)
        REprintf("Time to send message to Vim-R: %f\n",
                 1000 * ((double)clock() - t1) / CLOCKS_PER_SEC);

    char *tmp = glbnvbuf1;
    glbnvbuf1 = glbnvbuf2;
    glbnvbuf2 = tmp;
}

/**
 * @brief Evaluate an R expression.
 *
 * @param buf The expression to be evaluated.
 */
static void vimcom_eval_expr(const char *buf) {
    if (verbose > 3)
        Rprintf("vimcom_eval_expr: '%s'\n", buf);

    char rep[256];

    SEXP cmdSexp, cmdexpr, ans;
    ParseStatus status;
    int er = 0;

    PROTECT(cmdSexp = allocVector(STRSXP, 1));
    SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
    PROTECT(cmdexpr = R_ParseVector(cmdSexp, -1, &status, R_NilValue));

    char buf2[80];
    vimcom_squo(buf, buf2, 80);
    if (status == PARSE_OK) {
        /* Only the first command will be executed if the expression includes
         * a semicolon. */
        PROTECT(ans = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv, &er));
        if (er && verbose > 1) {
            snprintf(rep, sizeof(rep), "g:RWarningMsg('Error running: %s')",
                     buf2);
            send_to_vim(rep);
        }
        UNPROTECT(1);
    } else {
        if (verbose > 1) {
            snprintf(rep, sizeof(rep), "g:RWarningMsg('Invalid command: %s')",
                     buf2);
            send_to_vim(rep);
        }
    }
    UNPROTECT(2);
}

/**
 * @brief Send the names and version numbers of currently loaded libraries to
 * Vim-R.
 */
static void send_libnames(void) {
    LibInfo *lib;
    unsigned long totalsz = 9;
    char *libbuf;
    lib = libList;
    do {
        totalsz += lib->strlen;
        lib = lib->next;
    } while (lib);

    libbuf = malloc(totalsz + 1);

    libbuf[0] = 0;
    vimcom_strcat(libbuf, "+L");
    lib = libList;
    do {
        vimcom_strcat(libbuf, lib->name);
        vimcom_strcat(libbuf, "\003");
        vimcom_strcat(libbuf, lib->version);
        vimcom_strcat(libbuf, "\004");
        lib = lib->next;
    } while (lib);
    libbuf[totalsz] = 0;
    send_to_vim(libbuf);
    free(libbuf);
}

/**
 * @brief Count how many libraries are loaded in R's workspace. If the number
 * differs from the previous count, add new libraries to LibInfo structure.
 */
static void vimcom_checklibs(void) {
    SEXP a;

    PROTECT(a = eval(lang1(install("search")), R_GlobalEnv));

    int newnlibs = Rf_length(a);
    if (nlibs == newnlibs) {
        UNPROTECT(1);
        return;
    }

    SEXP l, cmdSexp, cmdexpr, ans;
    const char *libname;
    char *libn;
    char buf[128];
    ParseStatus status;
    int er = 0;
    LibInfo *lib;

    nlibs = newnlibs;

    needs_lib_msg = 1;

    for (int i = 0; i < newnlibs; i++) {
        PROTECT(l = STRING_ELT(a, i));
        libname = CHAR(l);
        libn = strstr(libname, "package:");
        if (libn != NULL) {
            libn = strstr(libn, ":");
            libn++;
            lib = vimcom_get_lib(libn);
            if (!lib) {
                snprintf(buf, 127, "utils::packageDescription('%s')$Version",
                         libn);
                PROTECT(cmdSexp = allocVector(STRSXP, 1));
                SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
                PROTECT(cmdexpr =
                            R_ParseVector(cmdSexp, -1, &status, R_NilValue));
                if (status != PARSE_OK) {
                    REprintf("vimcom error parsing: %s\n", buf);
                } else {
                    PROTECT(ans = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv,
                                            &er));
                    if (er) {
                        REprintf("vimcom error executing: %s\n", buf);
                    } else {
                        vimcom_lib_info_add(libn, CHAR(STRING_ELT(ans, 0)));
                    }
                    UNPROTECT(1);
                }
                UNPROTECT(2);
            }
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);

    return;
}

/**
 * @brief Function registered to be called by R after completing each top-level
 * task. See R documentation on addTaskCallback.
 */
void vimcom_task(void) {
    if (verbose > 4)
        REprintf("vimcom_task()\n");
#ifdef WIN32
    FLAG_LOCK();
    r_is_busy = 1;
    busy_since = time(NULL);
    FLAG_UNLOCK();
#endif
    if (nrs_port[0] != 0) {
        vimcom_checklibs();
        if (autoglbenv)
            vimcom_globalenv_list();
        if (needs_lib_msg)
            send_libnames();
        if (needs_glbenv_msg)
            send_glb_env();
        needs_lib_msg = 0;
        needs_glbenv_msg = 0;
    }
    if (setwidth && getenv("COLUMNS")) {
        int columns = atoi(getenv("COLUMNS"));
        if (columns > 0 && columns != oldcolwd) {
            oldcolwd = columns;

            /* From R-exts: Evaluating R expressions from C */
            SEXP s, t;
            PROTECT(t = s = allocList(2));
            SET_TYPEOF(s, LANGSXP);
            SETCAR(t, install("options"));
            t = CDR(t);
            SETCAR(t, ScalarInteger((int)columns));
            SET_TAG(t, install("width"));
            eval(s, R_GlobalEnv);
            UNPROTECT(1);

            if (verbose > 2)
                Rprintf("vimcom: width = %d columns\n", columns);
        }
    }
#ifdef WIN32
    // Drain eval queue and flag_glbenv under lock
    FLAG_LOCK();
    eval_node_t *queue = eval_queue_drain();
    int local_glbenv = flag_glbenv;
    flag_glbenv = 0;
    FLAG_UNLOCK();

    // Execute all queued commands in FIFO order (outside lock)
    while (queue) {
        eval_node_t *tmp = queue;
        queue = queue->next;
        vimcom_eval_expr(tmp->cmd);
        free(tmp); // matches malloc in eval_queue_push
    }
    if (local_glbenv)
        vimcom_globalenv_list();

    // All R API work done. NOW signal idle.
    FLAG_LOCK();
    r_is_busy = 0;
    FLAG_UNLOCK();
#endif
}

#ifdef WIN32
/**
 * @brief R_PolledEvents hook for Windows.
 *
 * R calls R_PolledEvents periodically from its main thread during idle loops
 * (R_ProcessEvents in Rgui, ReadConsole in RStudio). This drains the eval
 * queue on the main thread, avoiding unsafe R API calls from the TCP thread.
 */
static void vimcom_polled_events_hook(void) {
    if (original_polled_events)
        original_polled_events();

    FLAG_LOCK();
    if (r_is_busy || (!eval_head && !flag_glbenv)) {
        FLAG_UNLOCK();
        return;
    }
    eval_node_t *queue = eval_queue_drain();
    int local_glbenv = flag_glbenv;
    flag_glbenv = 0;
    r_is_busy = 1;
    busy_since = time(NULL);
    FLAG_UNLOCK();

    while (queue) {
        eval_node_t *tmp = queue;
        queue = queue->next;
        vimcom_eval_expr(tmp->cmd);
        free(tmp);
    }
    if (local_glbenv)
        vimcom_globalenv_list();

    FLAG_LOCK();
    r_is_busy = 0;
    FLAG_UNLOCK();
}
#endif

#ifndef WIN32
/**
 * @brief Executed by R when idle.
 *
 * @param unused Unused parameter.
 */
static void vimcom_exec(__attribute__((unused)) void *nothing) {
    int local_glbenv = 0;

    FLAG_LOCK();
    eval_node_t *queue = eval_queue_drain();
    if (flag_glbenv) {
        local_glbenv = 1;
        flag_glbenv = 0;
    }
    FLAG_UNLOCK();

    // Execute all queued commands in FIFO order (outside lock)
    while (queue) {
        eval_node_t *tmp = queue;
        queue = queue->next;
        vimcom_eval_expr(tmp->cmd);
        free(tmp);
    }

    if (local_glbenv)
        vimcom_globalenv_list();

    if (flag_debug) {
        SrcrefInfo();
        flag_debug = 0;
    }
}

/**
 * @brief Check if there is anything in the pipe that we use to register that
 * there are commands to be evaluated. R only executes this function when it
 * can safely execute our commands. This functionality is not available on
 * Windows.
 *
 * @param unused Unused parameter.
 */
static void vimcom_uih(__attribute__((unused)) void *data) {
    /* Code adapted from CarbonEL.
     * Thanks to Simon Urbanek for the suggestion on r-devel mailing list. */
    if (verbose > 4)
        REprintf("vimcom_uih()\n");
    char buf[16];
    if (read(ifd, buf, 1) < 1)
        REprintf("vimcom error: read < 1\n");
    R_ToplevelExec(vimcom_exec, NULL);
    fired = 0;
}

/**
 * @brief Put a single byte in a pipe to register that we have commands
 * waiting to be executed. R will crash if we execute commands while it is
 * busy with other tasks.
 */
static void vimcom_fire(void) {
    if (verbose > 4)
        REprintf("vimcom_fire()\n");
    if (fired)
        return;
    fired = 1;
    char buf[16];
    *buf = 0;
    if (write(ofd, buf, 1) <= 0)
        REprintf("vimcom error: write <= 0\n");
}

/**
 * @brief Read an R's internal variable to get file name and line number of
 * function currently being debugged.
 */
static void SrcrefInfo(void) {
    // Adapted from SrcrefPrompt(), at src/main/eval.c
    if (debugging == 0) {
        send_to_vim("g:StopRDebugging()");
        return;
    }
    /* If we have a valid R_Srcref, use it */
    if (R_Srcref && R_Srcref != R_NilValue) {
        if (TYPEOF(R_Srcref) == VECSXP)
            R_Srcref = VECTOR_ELT(R_Srcref, 0);
        SEXP srcfile = getAttrib(R_Srcref, R_SrcfileSymbol);
        if (TYPEOF(srcfile) == ENVSXP) {
            SEXP filename = findVar(install("filename"), srcfile);
            if (isString(filename) && length(filename)) {
                size_t slen = strlen(CHAR(STRING_ELT(filename, 0)));
                char *buf = calloc(sizeof(char), (2 * slen + 32));
                char *buf2 = calloc(sizeof(char), (2 * slen + 32));
                snprintf(buf, 2 * slen + 1, "%s",
                         CHAR(STRING_ELT(filename, 0)));
                vimcom_squo(buf, buf2, 2 * slen + 32);
                snprintf(buf, 2 * slen + 31, "g:RDebugJump('%s', %d)", buf2,
                         asInteger(R_Srcref));
                send_to_vim(buf);
                free(buf);
                free(buf2);
            }
        }
    }
}

/**
 * @brief This function is called by R to process user input. The function
 * monitor R input and checks if we are within the `browser()` function before
 * passing the data to the R function that really process the input.
 *
 * @param prompt R prompt
 * @param buf Command inserted in the R console
 * @param len Length of command in bytes
 * @param addtohistory Should the command be included in `.Rhistory`?
 * @return The return value is defined and used by R.
 */
static int vimcom_read_console(const char *prompt, unsigned char *buf, int len,
                               int addtohistory) {
    if (debugging == 1) {
        if (prompt[0] != 'B')
            debugging = 0;
        flag_debug = 1;
        vimcom_fire();
    } else {
        if (prompt[0] == 'B' && prompt[1] == 'r' && prompt[2] == 'o' &&
            prompt[3] == 'w' && prompt[4] == 's' && prompt[5] == 'e' &&
            prompt[6] == '[') {
            debugging = 1;
            flag_debug = 1;
            vimcom_fire();
        }
    }
    return save_ptr_R_ReadConsole(prompt, buf, len, addtohistory);
}
#endif

/**
 * @brief This function is called after the TCP connection with the vimrserver
 * is established. Its goal is to pass to Vim-R information on the running R
 * instance.
 *
 * @param r_info Information on R (see `.onAttach()` at R/vimcom.R)
 */
static void vimcom_send_running_info(const char *r_info, const char *nvv) {
    char msg[2176];
    char r_info_escaped[2048];
    vimcom_squo(r_info, r_info_escaped, sizeof(r_info_escaped));
    pid_t R_PID = getpid();

#ifdef WIN32
#ifdef _WIN64
    snprintf(msg, 2175,
             "g:SetVimcomInfo('%s', %" PRId64 ", '%" PRId64 "', '%s')", nvv,
             R_PID, (long long)GetForegroundWindow(), r_info_escaped);
#else
    snprintf(msg, 2175, "g:SetVimcomInfo('%s', %d, '%ld', '%s')", nvv, R_PID,
             (long)GetForegroundWindow(), r_info_escaped);
#endif
#else
    if (getenv("WINDOWID"))
        snprintf(msg, 2175, "g:SetVimcomInfo('%s', %d, '%s', '%s')", nvv, R_PID,
                 getenv("WINDOWID"), r_info_escaped);
    else
        snprintf(msg, 2175, "g:SetVimcomInfo('%s', %d, '0', '%s')", nvv, R_PID,
                 r_info_escaped);
#endif
    send_to_vim(msg);
}

/**
 * @brief Parse messages received from vimrserver
 *
 * @param buf The message though the TCP connection
 */
static void vimcom_parse_received_msg(char *buf) {
    char *p;
    const char *vimr_id = getenv("VIMR_ID");
    if (!vimr_id) {
        REprintf("vimcom: VIMR_ID environment variable not set\n");
        return;
    }

    if (verbose > 3) {
        REprintf("vimcom received: %s\n", buf);
    } else if (verbose > 2) {
        p = buf + strlen(vimr_id) + 1;
        REprintf("vimcom Received: [%c] %s\n", buf[0], p);
    }

    switch (buf[0]) {
    case 'A':
        autoglbenv = 1;
        break;
    case 'N':
        autoglbenv = 0;
        break;
    case 'G':
        FLAG_LOCK();
        flag_glbenv = 1;
        FLAG_UNLOCK();
#ifndef WIN32
        vimcom_fire();
#endif
        break;
#ifdef WIN32
    case 'C': // Send command to Rgui Console
        p = buf;
        p++;
        if (strstr(p, vimr_id) == p) {
            p += strlen(vimr_id);
            FLAG_LOCK();
            r_is_busy = 1;
            busy_since = time(NULL);
            FLAG_UNLOCK();
            Rconsolecmd(p);
        }
        break;
#endif
    case 'L': // Evaluate lazy object
        p = buf;
        p++;
        if (strstr(p, vimr_id) == p) {
            p += strlen(vimr_id);
            char lazy_cmd[512];
            snprintf(lazy_cmd, sizeof(lazy_cmd), "%s <- %s", p, p);
            FLAG_LOCK();
            eval_queue_push(lazy_cmd);
            flag_glbenv = 1;
            FLAG_UNLOCK();
#ifndef WIN32
            vimcom_fire();
#endif
        }
        break;
    case 'E': // eval expression
        p = buf;
        p++;
        if (strstr(p, vimr_id) == p) {
            p += strlen(vimr_id);
            FLAG_LOCK();
            eval_queue_push(p);
            FLAG_UNLOCK();
#ifndef WIN32
            vimcom_fire();
#endif
        } else {
            REprintf("vimcom: received invalid VIMR_ID\n");
        }
        break;
    default: // do nothing
        REprintf("\nError [vimcom]: Invalid message received: %s\n", buf);
        break;
    }
}

/**
 * @brief Read exactly n bytes from a socket, looping on partial reads.
 * @return n on success, 0 on clean close, -1 on error.
 */
static int recv_exact(int fd, char *buf, int n) {
    int total = 0;
    while (total < n) {
        int r = recv(fd, buf + total, n - total, 0);
        if (r <= 0)
            return r;
        total += r;
    }
    return total;
}

#ifdef WIN32
/**
 * @brief Loop to receive TCP messages from vimrserver.
 * Messages are framed: 8-byte hex length header + body.
 *
 * @param unused Unused parameter.
 */
static DWORD WINAPI client_loop_thread(__attribute__((unused)) void *arg)
#else
/**
 * @brief Loop to receive TCP messages from vimrserver.
 * Messages are framed: 8-byte hex length header + body.
 *
 * @param unused Unused parameter.
 */
static void *client_loop_thread(__attribute__((unused)) void *arg)
#endif
{
    char header[9];
    char *body = NULL;
    size_t body_cap = 0;

    for (;;) {
        // 1. Read 8-byte hex length header
        if (recv_exact(sfd, header, 8) <= 0)
            break;
        header[8] = '\0';

        // 2. Parse length (hard upper limit: 64 KB)
        unsigned int msg_len = 0;
        if (sscanf(header, "%X", &msg_len) != 1 || msg_len == 0 ||
            msg_len > 65536)
            break;

        // 3. Grow buffer if needed
        if (msg_len + 1 > body_cap) {
            free(body);
            body_cap = msg_len + 1;
            body = malloc(body_cap);
            if (!body) {
                REprintf("vimcom: malloc failed for %u bytes\n", msg_len);
                break;
            }
        }

        // 4. Read exactly msg_len bytes
        if (recv_exact(sfd, body, (int)msg_len) <= 0)
            break;
        body[msg_len] = '\0';

        // 5. Check for shutdown command (Windows)
#ifdef WIN32
        if (strstr(body, "QuitNow") == body)
            break;
#endif

        // 6. Dispatch
        vimcom_parse_received_msg(body);
    }

    free(body);
    // Free any queued commands that will never be executed
    FLAG_LOCK();
    eval_node_t *abandoned = eval_queue_drain();
    FLAG_UNLOCK();
    eval_queue_free(abandoned);
#ifdef WIN32
    closesocket(sfd);
    WSACleanup();
    return 0;
#else
    close(sfd);
    return NULL;
#endif
}

/**
 * @brief Set variables that will control vimcom behavior and establish a TCP
 * connection with vimrserver in a new thread. This function is called when
 * vimcom package is attached (See `.onAttach()` at R/vimcom.R).
 *
 * @param vrb Verbosity level (`vimcom.verbose` in ~/.Rprofile).
 *
 * @param anm Should names with starting with a dot be included in completion
 * lists? (`R_objbr_allnames` in init.vim).
 *
 * @param swd Should vimcom set the option "width" after the execution of
 * each command? (`R_setwidth` in init.vim).
 *
 * @param age Should the list of objects in .GlobalEnv be automatically
 * updated? (`R_objbr_allnames` in init.vim)
 *
 * @param dbg Should detect when `broser()` is running and start debugging
 * mode? (`R_debug` in init.vim)
 *
 * @param nvv vimcom version
 *
 * @param rinfo Information on R to be passed to vim.
 */
SEXP vimcom_Start(SEXP vrb, SEXP anm, SEXP swd, SEXP age, SEXP dbg, SEXP imd,
                  SEXP szl, SEXP tml, SEXP nvv, SEXP rinfo) {
    verbose = *INTEGER(vrb);
    allnames = *INTEGER(anm);
    setwidth = *INTEGER(swd);
    autoglbenv = *INTEGER(age);
    debug_r = *INTEGER(dbg);

    maxdepth = *INTEGER(imd);
    sizelimit = *INTEGER(szl);
    timelimit = (double)*INTEGER(tml);

    if (getenv("VIMR_TMPDIR")) {
        strncpy(tmpdir, getenv("VIMR_TMPDIR"), 500);
        tmpdir[500] = '\0';
        if (getenv("VIMR_SECRET")) {
            strncpy(vimsecr, getenv("VIMR_SECRET"), 127);
            vimsecr[127] = '\0';
        } else
            REprintf("vimcom: Environment variable VIMR_SECRET is missing.\n");
    } else {
        if (verbose)
            REprintf("vimcom: It seems that R was not started by Vim. The "
                     "communication with Vim-R will not work.\n");
        tmpdir[0] = 0;
        SEXP ans;
        PROTECT(ans = NEW_LOGICAL(1));
        SET_LOGICAL_ELT(ans, 0, 0);
        UNPROTECT(1);
        return ans;
    }

    if (getenv("VIMR_PORT")) {
        strncpy(nrs_port, getenv("VIMR_PORT"), 15);
        nrs_port[15] = '\0';
    }

    if (verbose > 0)
        REprintf("vimcom %s loaded\n", CHAR(STRING_ELT(nvv, 0)));
    if (verbose > 1) {
        if (getenv("VIMR_IP_ADDRESS")) {
            REprintf("  VIMR_IP_ADDRESS: %s\n", getenv("VIMR_IP_ADDRESS"));
        }
        REprintf("  VIMR_PORT: %s\n", nrs_port);
        REprintf("  VIMR_ID: %s\n", getenv("VIMR_ID"));
        REprintf("  VIMR_TMPDIR: %s\n", tmpdir);
        REprintf("  VIMR_COMPLDIR: %s\n", getenv("VIMR_COMPLDIR"));
        REprintf("  R info: %s\n\n", CHAR(STRING_ELT(rinfo, 0)));
    }

    tcp_header_len = strlen(vimsecr) + 9;
    glbnvbuf1 = (char *)calloc(glbnvbufsize, sizeof(char));
    glbnvbuf2 = (char *)calloc(glbnvbufsize, sizeof(char));
    send_ge_buf = (char *)calloc(glbnvbufsize + 64, sizeof(char));
    if (!glbnvbuf1 || !glbnvbuf2 || !send_ge_buf)
        REprintf("vimcom: Error allocating memory.\n");

#ifndef WIN32
    int fds[2];
    if (pipe(fds) == 0) {
        ifd = fds[0];
        ofd = fds[1];
        ih = addInputHandler(R_InputHandlers, ifd, &vimcom_uih, 32);
    } else {
        REprintf("vimcom error: pipe != 0\n");
        ih = NULL;
    }
#endif

    static int failure = 0;

    if (atoi(nrs_port) > 0) {
        struct sockaddr_in servaddr;
#ifdef WIN32
        InitializeCriticalSection(&flag_mutex);
        WSADATA d;
        int wr = WSAStartup(MAKEWORD(2, 2), &d);
        if (wr != 0) {
            REprintf("WSAStartup failed: %d\n", wr);
        }
#endif
        // socket create and verification
        sfd = socket(AF_INET, SOCK_STREAM, 0);
        if (sfd != -1) {
            memset(&servaddr, '\0', sizeof(servaddr));

            // assign IP, PORT
            servaddr.sin_family = AF_INET;
            if (getenv("VIMR_IP_ADDRESS"))
                servaddr.sin_addr.s_addr = inet_addr(getenv("VIMR_IP_ADDRESS"));
            else
                servaddr.sin_addr.s_addr = inet_addr("127.0.0.1");
            servaddr.sin_port = htons(atoi(nrs_port));

            // connect the client socket to server socket
            if (connect(sfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) ==
                0) {
#ifdef WIN32
                DWORD ti;
                tid = CreateThread(NULL, 0, client_loop_thread, NULL, 0, &ti);
#else
                pthread_create(&tid, NULL, client_loop_thread, NULL);
#endif
                vimcom_send_running_info(CHAR(STRING_ELT(rinfo, 0)),
                                         CHAR(STRING_ELT(nvv, 0)));
            } else {
                REprintf("vimcom: connection with the server failed (%s)\n",
                         nrs_port);
                failure = 1;
            }
        } else {
            REprintf("vimcom: socket creation failed (%d)\n", atoi(nrs_port));
            failure = 1;
        }
    }

    if (failure == 0) {
        initialized = 1;
#ifdef WIN32
        r_is_busy = 0;
        original_polled_events = R_PolledEvents;
        R_PolledEvents = vimcom_polled_events_hook;
#else
        if (debug_r) {
            save_ptr_R_ReadConsole = ptr_R_ReadConsole;
            ptr_R_ReadConsole = vimcom_read_console;
        }
#endif
        vimcom_checklibs();
        needs_lib_msg = 0;
        send_libnames();
    }

    SEXP ans;
    PROTECT(ans = NEW_LOGICAL(1));
    if (initialized) {
        SET_LOGICAL_ELT(ans, 0, 1);
    } else {
        SET_LOGICAL_ELT(ans, 0, 0);
    }
    UNPROTECT(1);
    return ans;
}

/**
 * @brief Close the TCP connection with vimrserver and do other cleanup.
 * This function is called by `.onUnload()` at R/vimcom.R.
 */
void vimcom_Stop(void) {
#ifndef WIN32
    if (ih) {
        removeInputHandler(&R_InputHandlers, ih);
        close(ifd);
        close(ofd);
    }
#endif

    if (initialized) {
#ifdef WIN32
        // Signal the thread to exit by closing the socket, which causes
        // recv_exact to return -1, breaking client_loop_thread's loop.
        closesocket(sfd);
        sfd = -1;
        if (WaitForSingleObject(tid, 5000) == WAIT_TIMEOUT)
            TerminateThread(tid, 0);
        CloseHandle(tid);
        WSACleanup();
        R_PolledEvents = original_polled_events;
        // Free any queued commands that will never be executed
        FLAG_LOCK();
        eval_node_t *abandoned = eval_queue_drain();
        FLAG_UNLOCK();
        eval_queue_free(abandoned);
#else
        if (debug_r)
            ptr_R_ReadConsole = save_ptr_R_ReadConsole;
        close(sfd);
        pthread_cancel(tid);
        pthread_join(tid, NULL);
        // Free any queued commands that will never be executed
        FLAG_LOCK();
        eval_node_t *abandoned_unix = eval_queue_drain();
        FLAG_UNLOCK();
        eval_queue_free(abandoned_unix);
#endif

        LibInfo *lib = libList;
        LibInfo *tmp;
        while (lib) {
            tmp = lib->next;
            free(lib->name);
            free(lib->version);
            free(lib);
            lib = tmp;
        }

        if (glbnvbuf1)
            free(glbnvbuf1);
        if (glbnvbuf2)
            free(glbnvbuf2);
        if (send_ge_buf)
            free(send_ge_buf);
        if (verbose)
            REprintf("vimcom stopped\n");
    }
    initialized = 0;
}
