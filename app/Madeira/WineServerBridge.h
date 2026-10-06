// WineServerBridge.h - Run Wine's wineserver as a thread on iOS
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Start the wineserver on a background thread.
// prefix_path: absolute path to the Wine prefix directory (e.g. app's Documents/wine)
// Returns 0 on success, -1 on failure.
int wineserver_start(const char *prefix_path);

// Check if wineserver is running
int wineserver_is_running(void);

// Stop the wineserver (signals the thread to exit)
void wineserver_stop(void);

// ios socketpair bypass: inject a pre-connected client fd into the wineserver.
// Called from the app bridge after socketpair() — the wineserver event loop
// picks this up and calls create_process/create_thread on it.
void wineserver_inject_client_fd(int fd);

// Wineserver lifecycle stage flags (set from build/wineserver/main_ios.c).
// 0/not set until the corresponding stage is reached.
extern int g_ws_main_entered;   // wineserver_main() entered
extern int g_ws_in_mainloop;    // main_loop() entered (ready to serve)

// Suppress os_log output from wineserver (file logging continues).
// Prevents os_log buffer contention from blocking the main thread.
extern volatile int ws_log_quiet;

#ifdef __cplusplus
}
#endif
