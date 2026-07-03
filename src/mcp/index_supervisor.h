/*
 * index_supervisor.h — run index_repository in a supervised worker subprocess.
 *
 * A single pathological file can hard-crash (SIGSEGV / stack overflow / abort) or
 * hang the native indexer, and today that takes down the whole MCP server or CLI.
 * The supervisor runs the actual index in a CHILD process (the same binary
 * re-invoked as `cli --index-worker index_repository …`), reaps it, and classifies
 * how it ended. A crash/hang is contained to the child; the parent survives and
 * reports it instead of dying.
 *
 * This module owns only the spawn/reap MECHANISM and the worker-role state. The
 * MCP handler (mcp.c) owns the gate placement and the response building, so this
 * module has no dependency on the response format.
 *
 * fork+exec only (never fork-and-run-in-child): the server holds persistent
 * threads plus mimalloc/sqlite/libgit2 global state with no pthread_atfork, so a
 * fork without exec would be a latent deadlock. Recursion is prevented by an argv
 * flag (`--index-worker`), never an ambient env var.
 */
#ifndef CBM_INDEX_SUPERVISOR_H
#define CBM_INDEX_SUPERVISOR_H

#include <stdbool.h>

#include "foundation/subprocess.h" /* cbm_proc_outcome_t */

/* Worker-role state, set once from the CLI arg parser (main.c) when this process
 * was spawned as a supervised worker. When active, indexing must run in-process
 * (the gate must NOT re-supervise). response_out (may be NULL) is the file the
 * worker writes its final result string to, for the parent to read back. */
void cbm_index_set_worker_role(bool is_worker, const char *response_out);
bool cbm_index_worker_active(void);
const char *cbm_index_worker_response_out(void);

/* True when handle_index_repository should wrap the run in a supervised child:
 * this process is not itself a worker AND the kill switch (CBM_INDEX_SUPERVISOR=0)
 * is not set. */
bool cbm_index_supervisor_should_wrap(void);

typedef struct {
    cbm_proc_outcome_t outcome; /* how the worker ended */
    int exit_code;              /* worker exit code (-1 if signalled) */
    int term_signal;            /* POSIX terminating signal, else 0 */
    char *response;             /* worker's result string on CLEAN exit (caller frees); else NULL */
} cbm_index_worker_result_t;

/* Spawn `<self> cli --index-worker index_repository <args_json> --response-out <tmp>
 * [--exclude-file <exclude_file>]`, supervise it (quiet-timeout for hangs), reap,
 * and classify. On a clean exit, result->response holds the worker's response
 * string (read from the temp file). Returns 0 if a worker was spawned and reaped
 * (result filled), or -1 if the child could not be spawned (caller degrades to
 * in-process). exclude_file may be NULL. */
int cbm_index_spawn_worker(const char *args_json, const char *exclude_file,
                           cbm_index_worker_result_t *result);

void cbm_index_worker_result_free(cbm_index_worker_result_t *result);

#endif /* CBM_INDEX_SUPERVISOR_H */
