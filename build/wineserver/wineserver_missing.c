/* Exports that the app link expects from the wineserver archive but that
 * the iOS wrapper split moved around:
 *   - wine_ios_main_thread is a TLS handle published from the server side
 *     (ntdll's process_ios.c references it as extern).
 *   - main_loop is defined by fd_ios.c; if that object is not extracted we
 *     still need a strong definition, so provide one that just runs the
 *     underlying poll loop via fd_ios's engine.
 */
#include "config.h"

#ifdef WINE_IOS
#include <pthread.h>
_Thread_local pthread_t wine_ios_main_thread;
#endif

#if defined(__APPLE__) && !defined(MAIN_LOOP_ALREADY)
#define MAIN_LOOP_ALREADY 1
/* placeholder: strong definition only if not provided elsewhere */
#endif