/* Wrapper: include original main.c but add iOS logging around init */
#include <os/log.h>
#include "wine_log_ios.h"
#define main wineserver_main_original
#include "main.c"
#undef main

/* Our replacement that adds logging */

/* State flags consumed by the app (WineServerBridge.m / HUD) to distinguish
 * wineserver lifecycle stages: alive (thread), entered (wineserver_main),
 * in_mainloop (ready to serve). Volatile because read from other threads. */
int g_ws_main_entered = 0;
int g_ws_in_mainloop = 0;

int wineserver_main(int argc, char *argv[])
{
    ws_log("[wineserver] starting init...");
    g_ws_main_entered = 1;
    setvbuf( stderr, NULL, _IOLBF, 0 );
    server_argv0 = argv[0];
    parse_options( argc, argv, "d::fhk::p::vw", long_options, option_callback );

    signal( SIGPIPE, SIG_IGN );
    /* iOS: Don't install sigterm_handler — it calls exit(1) which kills the whole app.
     * Signals are process-wide, so the Wine client thread could trigger them. */
    signal( SIGHUP, SIG_IGN );
    signal( SIGINT, SIG_IGN );
    signal( SIGQUIT, SIG_IGN );
    signal( SIGTERM, SIG_IGN );
    /* Don't ignore SIGABRT — it's useful for crash debugging */

    /* iOS: wineserver runs as a thread in the same process as the client.
     * Don't exit(0) when no clients connect within 3 seconds — the client
     * thread may take a while to start. Also, exit() would kill the whole app. */
    master_socket_timeout = TIMEOUT_INFINITE;
    ws_log("[wineserver] master_socket_timeout set to INFINITE (%lld)", (long long)master_socket_timeout);
    ws_log("[wineserver] init_limits...");
    init_limits();

    ws_log("[wineserver] sock_init...");
    sock_init();
    ws_log("[wineserver] open_master_socket...");
    open_master_socket();

    ws_log("[wineserver] init_signals...");
    set_current_time();
    init_signals();
    ws_log("[wineserver] init_memory...");
    init_memory();
    ws_log("[wineserver] load_intl_file + init_directories...");
    init_directories( load_intl_file() );
    ws_log("[wineserver] init_threading...");
    init_threading();
    ws_log("[wineserver] init_registry...");
    init_registry();
    ws_log("[wineserver] entering main_loop!");
    g_ws_in_mainloop = 1;
    main_loop();
    ws_log("[wineserver] main_loop returned");
    return 0;
}
