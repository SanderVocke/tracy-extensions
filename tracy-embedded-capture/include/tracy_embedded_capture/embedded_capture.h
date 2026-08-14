#ifndef TRACY_EMBEDDED_CAPTURE_H
#define TRACY_EMBEDDED_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { TRACY_EMBEDDED_CAPTURE_ABI_VERSION = 3 };

typedef enum tracy_embedded_capture_disposition {
    TRACY_EMBEDDED_CAPTURE_SAVE = 1,
    TRACY_EMBEDDED_CAPTURE_DISCARD = 2
} tracy_embedded_capture_disposition;

typedef enum tracy_embedded_capture_status {
    TRACY_EMBEDDED_CAPTURE_OK = 0,
    TRACY_EMBEDDED_CAPTURE_INVALID_ARGUMENT = 1,
    TRACY_EMBEDDED_CAPTURE_INVALID_STATE = 2,
    TRACY_EMBEDDED_CAPTURE_OUTPUT_EXISTS = 3,
    TRACY_EMBEDDED_CAPTURE_IO_ERROR = 4,
    TRACY_EMBEDDED_CAPTURE_TRANSPORT_ERROR = 5,
    TRACY_EMBEDDED_CAPTURE_NO_DATA = 6,
    TRACY_EMBEDDED_CAPTURE_INTERNAL_ERROR = 7
} tracy_embedded_capture_status;

typedef enum tracy_embedded_capture_state {
    TRACY_EMBEDDED_CAPTURE_UNCONFIGURED = 0,
    TRACY_EMBEDDED_CAPTURE_CONFIGURED = 1,
    TRACY_EMBEDDED_CAPTURE_CAPTURING = 2,
    TRACY_EMBEDDED_CAPTURE_FINISHING = 3,
    TRACY_EMBEDDED_CAPTURE_FINISHED = 4,
    TRACY_EMBEDDED_CAPTURE_FAILED = 5,
    TRACY_EMBEDDED_CAPTURE_DISCARDED = 6,
    /* The reusable profiler is running without an active capture Worker. */
    TRACY_EMBEDDED_CAPTURE_IDLE = 7
} tracy_embedded_capture_state;

typedef struct tracy_embedded_capture_statistics {
    uint64_t client_to_server_bytes;
    uint64_t server_to_client_bytes;
    uint64_t client_to_server_high_water;
    uint64_t server_to_client_high_water;
    uint64_t writer_open_count;
    uint64_t worker_write_count;
    uint64_t publish_count;
} tracy_embedded_capture_statistics;

/* Configure one process-global capture. Call before Tracy manual startup.
 * `path` is copied and must point to `path_len` UTF-8 bytes. `channel_capacity`
 * must be non-zero. Existing output files are never overwritten. */
int32_t ___tracy_embedded_capture_configure(const char* path, size_t path_len,
                                             size_t channel_capacity,
                                             int64_t worker_memory_limit);

/* Start one capture in the reusable lifecycle. On the first call, start the
 * Tracy profiler separately after this function returns (for example with
 * tracy_client::Client::start()). Later calls reuse that running profiler.
 * Only one process-global capture Worker can be active at a time. */
int32_t ___tracy_embedded_capture_start(const char* path, size_t path_len,
                                        size_t channel_capacity,
                                        int64_t worker_memory_limit);

/* Stop a reusable capture while leaving the Tracy profiler running and idle,
 * ready for another start. Producers and active guards must first quiesce.
 * SAVE publishes atomically; DISCARD destroys the captured model. */
int32_t ___tracy_embedded_capture_stop_with_disposition(int32_t disposition);
int32_t ___tracy_embedded_capture_stop(void);

/* Shut down the reusable profiler after the last stop. No capture may be
 * active. This is the final Tracy operation in the process. */
int32_t ___tracy_embedded_capture_shutdown(void);

/* Finalize after every instrumentation-producing thread and active zone/guard
 * has quiesced. SAVE publishes atomically; DISCARD drains and destroys the
 * in-memory model without opening an output file. */
int32_t ___tracy_embedded_capture_finish_with_disposition(int32_t disposition);

/* Backward-compatible shorthand for SAVE. */
int32_t ___tracy_embedded_capture_finish(void);

uint32_t ___tracy_embedded_capture_abi_version(void);
int32_t ___tracy_embedded_capture_get_state(void);

/* Approximate bytes currently allocated for Tracy server-side event storage.
 * This exposes Tracy 0.13.1's process-global atomic allocation counter. It does
 * not include the transport buffers, profiler client, or unrelated process
 * memory. This backend supports at most one active capture Worker. */
int64_t ___tracy_embedded_capture_get_event_storage_bytes(void);

int32_t ___tracy_embedded_capture_get_statistics(
    tracy_embedded_capture_statistics* statistics);

/* Copies a NUL-terminated diagnostic when capacity is non-zero and returns the
 * full diagnostic byte length excluding NUL. */
size_t ___tracy_embedded_capture_get_error(char* destination, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
