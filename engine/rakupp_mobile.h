/* rakupp_mobile.h — the slice of Raku++ the Learn Raku app calls through
 * dart:ffi.
 *
 * Dart cannot block its UI isolate on rk_run, and an output callback that
 * crosses into Dart asynchronously would read buffers the engine has already
 * reused. So this shim owns the threading: rkm_start runs the program on a
 * big-stack thread of its own and returns at once, output is buffered here,
 * and the app polls rkm_take_output / rkm_state on a timer. Nothing in the
 * engine's own sources changes for this; the Stop button needs rk_interrupt,
 * which engine/patches/rk-interrupt.patch adds.
 */
#ifndef RAKUPP_MOBILE_H
#define RAKUPP_MOBILE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RKM_API __attribute__((visibility("default")))

/* States reported by rkm_state(). */
#define RKM_IDLE     0   /* nothing has run yet */
#define RKM_RUNNING  1
#define RKM_FINISHED 2

/* Start `source` as a whole program on a background thread. `input` is what
 * `get`/`lines`/`prompt` read first (may be NULL). Then, if `interactive` is 0,
 * the program sees end of input; if it is 1, a read waits until the host sends
 * more with rkm_send_input, or ends the input with rkm_end_input — the way a
 * terminal behaves. `file_name` is how error messages name the program.
 * `workdir` becomes the current directory, so relative file IO lands somewhere
 * writable (may be NULL).
 * Returns 0, or -1 if a run is still in progress, -2 if no thread could start. */
RKM_API int rkm_start(const char* source, const char* input,
                      const char* file_name, const char* workdir,
                      int interactive);

/* Interactive input: more text for the program to read (send whole lines,
 * newline included), and end of input (what ^D is in a terminal). */
RKM_API void rkm_send_input(const char* text);
RKM_API void rkm_end_input(void);

/* 1 while the program is blocked waiting for input that has not been sent. */
RKM_API int rkm_waiting_input(void);

/* Ask the running program to stop (no-op when idle). */
RKM_API void rkm_stop(void);

RKM_API int rkm_state(void);

/* The finished run's exit code: 0 fine, 1 error, 130 stopped, 3 internal. */
RKM_API int rkm_exit_code(void);

/* Output produced since the previous call, or NULL if there is none.
 * Encoded as segments: 1 byte stream ('o' stdout, 'e' stderr), 4 bytes
 * little-endian length, then that many UTF-8 bytes. *len receives the total
 * size. Free with rkm_free. */
RKM_API uint8_t* rkm_take_output(int32_t* len);

/* Syntax classes for rkm_highlight, from the engine's own tokenizer. Encoded
 * as segments: 1 byte class (below), 4 bytes little-endian length, bytes.
 * Concatenating every segment's bytes gives back `source`. Free with rkm_free. */
#define RKM_HL_PLAIN    0
#define RKM_HL_KEYWORD  1
#define RKM_HL_BUILTIN  2
#define RKM_HL_NAME     3
#define RKM_HL_VARIABLE 4
#define RKM_HL_STRING   5
#define RKM_HL_REGEX    6
#define RKM_HL_COMMENT  7
#define RKM_HL_NUMBER   8
#define RKM_HL_TYPE     9
RKM_API uint8_t* rkm_highlight(const char* source, int32_t* len);

RKM_API void rkm_free(void* p);

/* The engine's version string, e.g. "5.4.1". Static. */
RKM_API const char* rkm_version(void);

#ifdef __cplusplus
}
#endif

#endif /* RAKUPP_MOBILE_H */
