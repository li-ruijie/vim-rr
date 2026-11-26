#include <R.h> /* to include Rconfig.h */
#include <Rdefines.h>
#include <Rinternals.h>
#include <Rversion.h>
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
// TCP thread (case 'E' / 'S' / 'L') and drained by vimcom_exec on the main R
// thread.
#define MAX_EVAL_CMD 65536

typedef struct eval_node {
    struct eval_node *next;
    int now;    // May it run while R is evaluating something else?
    char cmd[]; // flexible array member — allocated inline with node
} eval_node_t;

static eval_node_t *eval_head = NULL;
static eval_node_t *eval_tail = NULL;

/**
 * @brief Enqueue a command for deferred execution.
 * Must be called under FLAG_LOCK.
 */
static void eval_queue_push(const char *cmd, int now) {
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
    node->now = now;
    node->next = NULL;
    if (eval_tail)
        eval_tail->next = node;
    else
        eval_head = node;
    eval_tail = node;
}

/**
 * @brief Detach commands from the queue and return them in their order.
 * Must be called under FLAG_LOCK. Caller owns the returned list.
 *
 * @param all Detach every command, or only the ones that may run while R is
 * evaluating something else?
 */
static eval_node_t *eval_queue_drain(int all) {
    eval_node_t *taken = NULL;
    eval_node_t **taken_tail = &taken;
    eval_node_t **link = &eval_head;
    eval_tail = NULL;
    while (*link) {
        eval_node_t *node = *link;
        if (all || node->now) {
            *link = node->next;
            node->next = NULL;
            *taken_tail = node;
            taken_tail = &node->next;
        } else {
            eval_tail = node;
            link = &node->next;
        }
    }
    return taken;
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
// R is not thread-safe, so the TCP thread only queues the requests of Vim-R
// and posts a message to a message-only window that belongs to the main
// thread. R dispatches the message wherever it processes Windows messages,
// which is while it waits for console input and also at every interrupt
// check of a running computation.
#define VIMCOM_WNDCLASS "vimcom_message_window"
#define VIMCOM_WM_FIRE (WM_APP + 1)
#define VIMCOM_TIMER_ID 1
#define VIMCOM_RETRY_MS 200
// The evaluation depth that base::Cstack_info() reports when R evaluates
// nothing else. Its help page says that the value includes "two calls for the
// call to Cstack_info".
#define VIMCOM_IDLE_DEPTH 2
static HWND vimcom_hwnd = NULL; // The message-only window.
static int vimcom_running = 0;  // Is the main thread executing requests?
static int vimcom_timer = 0;    // Is the retry timer set?
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
static void vimcom_exec(void *arg);

#ifdef WIN32
SOCKET sfd = INVALID_SOCKET; // File descriptor of socket used in the TCP
                             // connection with the vimrserver.
static HANDLE tid; // Identifier of thread running TCP connection loop.
extern void Rconsolecmd(char *cmd); // Defined in R: src/gnuwin32/rui.c.
// The connection was shut down after a failed send, and the socket stays open
// until vimcom_Stop() closes it. Used by the main thread only.
static int sfd_down;
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
 * @return Pointer to the NULL terminating byte of glbnvbuf2, or NULL if there
 * is no memory, in which case the buffers are left as they were.
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
        return NULL;
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
 * @brief Is there a connection through which send_to_vim() can send?
 */
static int vimcom_can_send(void) {
#ifdef WIN32
    return sfd != -1 && !sfd_down;
#else
    return sfd != -1;
#endif
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
    if (!vimcom_can_send())
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
        // The receiving thread may still be using the socket, which only
        // vimcom_Stop() closes.
        shutdown(sfd, SD_BOTH);
        sfd_down = 1;
#else
        close(sfd);
        sfd = -1;
#endif
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
            // Both quotes and the final NULL byte must fit.
            if (j + 2 >= bsize) {
                buf2[j] = 0;
                break;
            }
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
 * buffer, or NULL if the list was abandoned for lack of memory.
 *
 * @param depth Current number of levels in lists and S4 objects.
 *
 * @return The pointer p updated after the insertion of the new line, or NULL
 * if the list was abandoned.
 */
static char *vimcom_glbnv_line(SEXP *x, const char *xname, const char *curenv,
                               char *p, int depth) {
    if (!p)
        return NULL;

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
    if ((size_t)(p - glbnvbuf2) + 2048 > glbnvbufsize) {
        p = vimcom_grow_buffers();
        if (!p)
            return NULL;
    }

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
    } else if (Rf_isString(*x) && Rf_length(*x) > 0) {
        p = vimcom_strcat(p, "\006~\006");
    } else if (Rf_isFunction(*x)) {
        p = vimcom_strcat(p, "\006\003\006");
        xgroup = 1;
    } else if (Rf_inherits(*x, "data.frame")) {
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
        // A class name has no length limit, but only 2048 bytes are reserved
        // for the whole line.
        snprintf(buf, 127, "%s", CHAR(STRING_ELT(txt, 0)));
        p = vimcom_strcat(p, buf);
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
        if (Rf_isString(txt)) {
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
            escape_str(newenv);
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
            escape_str(newenv);
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

#if R_VERSION >= R_Version(4, 6, 0)
/**
 * @brief Add the line of an object of .GlobalEnv whose value must not be
 * read.
 *
 * @param xname The name of the object.
 * @param type The character that represents the type of the object.
 * @param p A pointer to the current NULL byte terminating the glbnvbuf2
 * buffer, or NULL if the list was abandoned for lack of memory.
 * @return The pointer p updated after the insertion of the new line, or NULL
 * if the list was abandoned.
 */
static char *vimcom_glbnv_noval(const char *xname, char type, char *p) {
    char ebuf[64];
    char buf[32];

    if (!p)
        return NULL;

    if ((size_t)(p - glbnvbuf2) + 2048 > glbnvbufsize) {
        p = vimcom_grow_buffers();
        if (!p)
            return NULL;
    }

    snprintf(ebuf, 63, "%s", xname);
    escape_str(ebuf);
    p = vimcom_strcat(p, ebuf);
    snprintf(buf, sizeof(buf), "\006%c\006\006.GlobalEnv\006\006\006\006\n",
             type);
    return vimcom_strcat(p, buf);
}
#endif

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

    PROTECT(envVarsSEXP = R_lsInternal3(R_GlobalEnv, allnames, TRUE));
    for (int i = 0; i < Rf_length(envVarsSEXP); i++) {
        varName = CHAR(STRING_ELT(envVarsSEXP, i));
        if (R_BindingIsActive(Rf_install(varName), R_GlobalEnv)) {
            // See: https://github.com/jalvesaq/Vim-R/issues/686
            PROTECT(varSEXP = R_ActiveBindingFunction(Rf_install(varName),
                                                      R_GlobalEnv));
        } else {
#if R_VERSION >= R_Version(4, 6, 0)
            // Rf_findVar() is no longer declared. R_getVarEx() forces a
            // delayed binding and signals an error for a missing one, so
            // both are listed without reading their values.
            R_BindingType_t bt =
                R_GetBindingType(Rf_install(varName), R_GlobalEnv);
            if (bt == R_BindingTypeDelayed || bt == R_BindingTypeMissing) {
                p = vimcom_glbnv_noval(
                    varName, bt == R_BindingTypeDelayed ? '&' : '*', p);
                continue;
            }
            PROTECT(varSEXP = R_getVarEx(Rf_install(varName), R_GlobalEnv,
                                         FALSE, R_UnboundValue));
#else
            PROTECT(varSEXP = Rf_findVar(Rf_install(varName), R_GlobalEnv));
#endif
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

    // An incomplete list is not sent. Vim-R keeps the last complete one.
    if (!p)
        return;

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
    if (tmdiff > timelimit || strlen(glbnvbuf1) > (size_t)sizelimit) {
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

    // The list is empty if no library could be recorded.
    if (!libList)
        return;

    lib = libList;
    do {
        totalsz += lib->strlen;
        lib = lib->next;
    } while (lib);

    libbuf = malloc(totalsz + 1);
    if (!libbuf) {
        REprintf("vimcom: malloc failed in send_libnames\n");
        return;
    }

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
    if (vimcom_can_send()) {
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
            SEXP s;
            PROTECT(s = lang2(install("options"), ScalarInteger((int)columns)));
            SET_TAG(CDR(s), install("width"));
            eval(s, R_GlobalEnv);
            UNPROTECT(1);

            if (verbose > 2)
                Rprintf("vimcom: width = %d columns\n", columns);
        }
    }
#ifdef WIN32
    // A task has just finished, so every request that is waiting can run.
    vimcom_running = 1;
    R_ToplevelExec(vimcom_exec, NULL);
    vimcom_running = 0;
#endif
}

/**
 * @brief Execute the requests that Vim-R has queued. It runs on the main R
 * thread, called through R_ToplevelExec().
 *
 * @param arg NULL to execute every request. Any other value to execute only
 * the requests that may run while R is evaluating something else.
 */
static void vimcom_exec(void *arg) {
    int all = arg == NULL;
    int local_glbenv = 0;

    FLAG_LOCK();
    eval_node_t *queue = eval_queue_drain(all);
    if (all && flag_glbenv) {
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

#ifndef WIN32
    if (flag_debug) {
        SrcrefInfo();
        flag_debug = 0;
    }
#endif
}

#ifdef WIN32
/**
 * @brief Is R evaluating nothing at the moment? That is the case while it
 * waits for input at the top level prompt, and at a browser prompt once an
 * expression was entered there. Each evaluation in progress adds to the
 * evaluation depth.
 */
static int vimcom_r_is_idle(void) {
    int depth = -1;
    int er = 0;
    SEXP call, ans;

    PROTECT(call = lang1(install("Cstack_info")));
    ans = R_tryEvalSilent(call, R_BaseEnv, &er);
    if (!er && TYPEOF(ans) == INTSXP && LENGTH(ans) >= 4)
        depth = INTEGER(ans)[3];
    UNPROTECT(1);
    if (verbose > 4)
        REprintf("vimcom_r_is_idle(): depth = %d\n", depth);
    return depth >= 0 && depth <= VIMCOM_IDLE_DEPTH;
}

/**
 * @brief Execute on the main thread what the state of R allows. A request
 * that has to wait stays in the queue, and the retry timer looks at it again.
 * vimcom_task() takes everything when the running task ends.
 */
static void vimcom_dispatch(void) {
    int pending, more;

    // A message that is dispatched while requests are being executed. The
    // loop below takes what it announces.
    if (vimcom_running)
        return;

    FLAG_LOCK();
    pending = eval_head != NULL || flag_glbenv;
    FLAG_UNLOCK();

    if (pending) {
        vimcom_running = 1;
        do {
            // A non-NULL argument limits vimcom_exec() to the requests that
            // may run during another evaluation.
            R_ToplevelExec(vimcom_exec,
                           vimcom_r_is_idle() ? NULL : (void *)&vimcom_running);
            FLAG_LOCK();
            more = 0;
            for (eval_node_t *node = eval_head; node; node = node->next)
                more = more || node->now;
            pending = eval_head != NULL || flag_glbenv;
            FLAG_UNLOCK();
        } while (more);
        vimcom_running = 0;
    }

    if (pending && !vimcom_timer) {
        vimcom_timer =
            SetTimer(vimcom_hwnd, VIMCOM_TIMER_ID, VIMCOM_RETRY_MS, NULL) != 0;
    } else if (!pending && vimcom_timer) {
        KillTimer(vimcom_hwnd, VIMCOM_TIMER_ID);
        vimcom_timer = 0;
    }
}

/**
 * @brief Window procedure of the message-only window. R calls it on the main
 * thread.
 */
static LRESULT CALLBACK vimcom_wndproc(HWND hwnd, UINT msg, WPARAM wparam,
                                       LPARAM lparam) {
    if (msg == VIMCOM_WM_FIRE ||
        (msg == WM_TIMER && wparam == VIMCOM_TIMER_ID)) {
        vimcom_dispatch();
        return 0;
    }
    return DefWindowProc(hwnd, msg, wparam, lparam);
}

/**
 * @brief Create the message-only window. It must be called on the main
 * thread, which is the thread that will receive the messages.
 */
static void vimcom_create_window(void) {
    WNDCLASSEXA wc;

    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = vimcom_wndproc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = VIMCOM_WNDCLASS;
    if (!RegisterClassExA(&wc) &&
        GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
        // Left by a copy of this library that was unloaded without a call to
        // vimcom_Stop(). Its window procedure is gone.
        UnregisterClassA(VIMCOM_WNDCLASS, wc.hInstance);
        RegisterClassExA(&wc);
    }
    vimcom_hwnd = CreateWindowExA(0, VIMCOM_WNDCLASS, NULL, 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, NULL, wc.hInstance, NULL);
    if (!vimcom_hwnd)
        REprintf("vimcom: could not create the message window (%lu). "
                 "Requests of Vim-R will only run after each command.\n",
                 (unsigned long)GetLastError());
}

/**
 * @brief Destroy the message-only window. It must be called on the main
 * thread.
 */
static void vimcom_destroy_window(void) {
    if (vimcom_hwnd) {
        KillTimer(vimcom_hwnd, VIMCOM_TIMER_ID);
        vimcom_timer = 0;
        DestroyWindow(vimcom_hwnd);
        vimcom_hwnd = NULL;
        UnregisterClassA(VIMCOM_WNDCLASS, GetModuleHandle(NULL));
    }
}

/**
 * @brief Tell the main thread that there are requests waiting to be
 * executed. It is called on the TCP thread.
 */
static void vimcom_fire(void) {
    if (vimcom_hwnd)
        PostMessage(vimcom_hwnd, VIMCOM_WM_FIRE, 0, 0);
}
#endif

#ifndef WIN32
/**
 * @brief Put a single byte in a pipe to register that we have commands
 * waiting to be executed. R will crash if we execute commands while it is
 * busy with other tasks. Both threads call this function.
 */
static void vimcom_fire(void) {
    if (verbose > 4)
        REprintf("vimcom_fire()\n");
    FLAG_LOCK();
    int waiting = fired;
    fired = 1;
    FLAG_UNLOCK();
    if (waiting)
        return;
    char buf[16];
    *buf = 0;
    if (write(ofd, buf, 1) <= 0)
        REprintf("vimcom error: write <= 0\n");
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
    // The flag stays set while the requests are executed, so that the pipe is
    // empty and this function is not entered again from within one of them.
    R_ToplevelExec(vimcom_exec, NULL);
    // A request that arrived meanwhile found the flag set and wrote nothing
    // to the pipe. It would stay in the queue until a later request fired,
    // so the queue is looked at again after the flag is cleared.
    FLAG_LOCK();
    fired = 0;
    int pending = eval_head != NULL || flag_glbenv || flag_debug;
    FLAG_UNLOCK();
    if (pending)
        vimcom_fire();
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
#if R_VERSION >= R_Version(4, 6, 0)
            SEXP filename =
                R_getVarEx(install("filename"), srcfile, FALSE, R_NilValue);
#else
            SEXP filename = findVar(install("filename"), srcfile);
#endif
            if (isString(filename) && length(filename)) {
                size_t slen = strlen(CHAR(STRING_ELT(filename, 0)));
                char *buf = calloc(2 * slen + 32, sizeof(char));
                char *buf2 = calloc(2 * slen + 32, sizeof(char));
                if (!buf || !buf2) {
                    REprintf("vimcom: calloc failed in SrcrefInfo\n");
                    free(buf);
                    free(buf2);
                    return;
                }
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
        vimcom_fire();
        break;
#ifdef WIN32
    case 'C': // Send command to Rgui Console
        p = buf;
        p++;
        if (strstr(p, vimr_id) == p) {
            p += strlen(vimr_id);
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
            eval_queue_push(lazy_cmd, 0);
            flag_glbenv = 1;
            FLAG_UNLOCK();
            vimcom_fire();
        }
        break;
    case 'E': // Evaluate an expression when R is evaluating nothing else
    case 'S': // Evaluate an expression that only passes text to the console
              // of the front end, such as rstudioapi::sendToConsole(). On
              // Windows it does not wait for a running evaluation, so that
              // it also reaches a prompt that R shows from within a function.
        p = buf;
        p++;
        if (strstr(p, vimr_id) == p) {
            p += strlen(vimr_id);
            FLAG_LOCK();
            eval_queue_push(p, buf[0] == 'S');
            FLAG_UNLOCK();
            vimcom_fire();
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
    eval_node_t *abandoned = eval_queue_drain(1);
    FLAG_UNLOCK();
    eval_queue_free(abandoned);
#ifdef WIN32
    // The main thread may still send through the socket, so it stays open
    // until vimcom_Stop() closes it. Shutting the connection down tells
    // vimrserver that it is over and makes every later send fail.
    shutdown(sfd, SD_BOTH);
    return 0;
#else
    // Forget the descriptor before closing it, so that the main thread
    // neither sends through its number nor closes it again.
    int fd = sfd;
    sfd = -1;
    close(fd);
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
    if (!glbnvbuf1 || !glbnvbuf2 || !send_ge_buf) {
        // Nothing else was set up yet. R goes on without vimcom.
        REprintf("vimcom: Error allocating memory.\n");
        free(glbnvbuf1);
        free(glbnvbuf2);
        free(send_ge_buf);
        glbnvbuf1 = glbnvbuf2 = send_ge_buf = NULL;
        return ScalarLogical(0);
    }

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

    int failure = 0;

    if (atoi(nrs_port) > 0) {
        struct sockaddr_in servaddr;
        int connected = 0;
#ifdef WIN32
        InitializeCriticalSection(&flag_mutex);
        vimcom_create_window();
        WSADATA d;
        int wr = WSAStartup(MAKEWORD(2, 2), &d);
        if (wr != 0) {
            REprintf("WSAStartup failed: %d\n", wr);
        }
        sfd_down = 0;
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
                connected = 1;
            } else {
                REprintf("vimcom: connection with the server failed (%s)\n",
                         nrs_port);
                failure = 1;
            }
        } else {
            REprintf("vimcom: socket creation failed (%d)\n", atoi(nrs_port));
            failure = 1;
        }
        if (!connected) {
            // Release what was set up for the connection that failed.
            // vimcom_Stop() only does it after a successful start.
            if (sfd != -1) {
#ifdef WIN32
                closesocket(sfd);
#else
                close(sfd);
#endif
                sfd = -1;
            }
#ifdef WIN32
            WSACleanup();
            vimcom_destroy_window();
            DeleteCriticalSection(&flag_mutex);
#endif
        }
    } else {
        // Without a port there is no connection, and on Windows flag_mutex
        // was not initialized.
        failure = 1;
    }

    if (failure == 0) {
        initialized = 1;
#ifndef WIN32
        if (debug_r) {
            save_ptr_R_ReadConsole = ptr_R_ReadConsole;
            ptr_R_ReadConsole = vimcom_read_console;
        }
#endif
        vimcom_checklibs();
        needs_lib_msg = 0;
        send_libnames();
    } else {
        // vimcom_Stop() frees the buffers only after a successful start.
        free(glbnvbuf1);
        free(glbnvbuf2);
        free(send_ge_buf);
        glbnvbuf1 = glbnvbuf2 = send_ge_buf = NULL;
#ifndef WIN32
        // The next start makes a new pipe and would lose this one.
        if (ih) {
            removeInputHandler(&R_InputHandlers, ih);
            ih = NULL;
            close(ifd);
            close(ofd);
        }
#endif
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
        // Signal the thread to exit without closing the socket that it is
        // using. After shutdown() every new recv() fails, and CancelIoEx()
        // ends the recv() that is already waiting, so recv_exact returns
        // and client_loop_thread's loop breaks. The socket is closed only
        // after the thread has ended.
        shutdown(sfd, SD_BOTH);
        CancelIoEx((HANDLE)sfd, NULL);
        if (WaitForSingleObject(tid, 5000) == WAIT_TIMEOUT)
            TerminateThread(tid, 0);
        CloseHandle(tid);
        closesocket(sfd);
        sfd = -1;
        WSACleanup();
        vimcom_destroy_window();
        // Free any queued commands that will never be executed
        FLAG_LOCK();
        eval_node_t *abandoned = eval_queue_drain(1);
        FLAG_UNLOCK();
        eval_queue_free(abandoned);
        // The thread and the window are gone, and the task callback is
        // switched off before this function is called.
        DeleteCriticalSection(&flag_mutex);
#else
        if (debug_r)
            ptr_R_ReadConsole = save_ptr_R_ReadConsole;
        close(sfd);
        pthread_cancel(tid);
        pthread_join(tid, NULL);
        // Free any queued commands that will never be executed
        FLAG_LOCK();
        eval_node_t *abandoned_unix = eval_queue_drain(1);
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
