// Prints the rectangles of all normal on-screen windows as JSON, front-to-back.
// Windows counterpart of window_list.c (macOS); the output format is identical:
//   [{"id":..,"x":..,"y":..,"w":..,"h":..}, ...]
// Coordinates are physical pixels with the origin at the top-left of the
// primary display — the same space Godot's DisplayServer uses on Windows.
//
// Build (MinGW): gcc -O2 helpers/window_list_win.c -o helpers/window_list.exe
// Usage: window_list.exe [pid-to-exclude]

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Modern APIs are loaded dynamically so this compiles against old MinGW
// headers and still runs (with graceful fallbacks) on any Windows version.
#define DWMWA_EXTENDED_FRAME_BOUNDS_ 9
#define DWMWA_CLOAKED_ 14

typedef HRESULT (WINAPI *DwmGetWindowAttribute_t)(HWND, DWORD, PVOID, DWORD);
static DwmGetWindowAttribute_t dwm_get = NULL;

typedef struct {
    DWORD exclude_pid;
    int first;
} EnumCtx;

static BOOL CALLBACK on_window(HWND hwnd, LPARAM lp) {
    EnumCtx *ctx = (EnumCtx *)lp;
    if (!IsWindowVisible(hwnd) || IsIconic(hwnd))
        return TRUE;
    LONG ex = GetWindowLongA(hwnd, GWL_EXSTYLE);
    // Tool windows and click-through overlays are not standable surfaces.
    if ((ex & WS_EX_TOOLWINDOW) || (ex & WS_EX_TRANSPARENT))
        return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == ctx->exclude_pid)  // don't let the pet stand on itself
        return TRUE;
    // The desktop and taskbar are the pet's floor already (usable rect).
    char cls[64] = {0};
    GetClassNameA(hwnd, cls, sizeof(cls));
    if (!strcmp(cls, "Progman") || !strcmp(cls, "WorkerW") ||
        !strcmp(cls, "Shell_TrayWnd") || !strcmp(cls, "Shell_SecondaryTrayWnd"))
        return TRUE;
    if (dwm_get) {
        // Cloaked = invisible UWP shells and windows on other virtual desktops.
        DWORD cloaked = 0;
        if (SUCCEEDED(dwm_get(hwnd, DWMWA_CLOAKED_, &cloaked, sizeof(cloaked))) && cloaked)
            return TRUE;
    }
    // Extended frame bounds = the frame the user actually sees; GetWindowRect
    // would include the invisible resize borders Win10 draws around windows,
    // leaving the pet hovering in mid-air beside them.
    RECT r;
    if (!(dwm_get && SUCCEEDED(dwm_get(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS_, &r, sizeof(r))))) {
        if (!GetWindowRect(hwnd, &r))
            return TRUE;
    }
    long w = r.right - r.left, h = r.bottom - r.top;
    if (w < 2 || h < 2)
        return TRUE;
    printf("%s{\"id\":%lu,\"x\":%ld,\"y\":%ld,\"w\":%ld,\"h\":%ld}",
           ctx->first ? "" : ",", (unsigned long)(ULONG_PTR)hwnd,
           (long)r.left, (long)r.top, w, h);
    ctx->first = 0;
    return TRUE;
}

int main(int argc, char **argv) {
    // Per-monitor DPI awareness, so bounds come back in physical pixels even
    // under display scaling. Fall back through older APIs on older systems.
    HMODULE user32 = GetModuleHandleA("user32.dll");
    typedef BOOL (WINAPI *SetCtx_t)(HANDLE);
    typedef BOOL (WINAPI *SetAware_t)(void);
    SetCtx_t set_ctx = user32 ? (SetCtx_t)GetProcAddress(user32, "SetProcessDpiAwarenessContext") : NULL;
    if (!set_ctx || !set_ctx((HANDLE)-4 /* PER_MONITOR_AWARE_V2 */)) {
        SetAware_t set_aware = user32 ? (SetAware_t)GetProcAddress(user32, "SetProcessDPIAware") : NULL;
        if (set_aware)
            set_aware();
    }
    HMODULE dwm = LoadLibraryA("dwmapi.dll");
    if (dwm)
        dwm_get = (DwmGetWindowAttribute_t)GetProcAddress(dwm, "DwmGetWindowAttribute");
    EnumCtx ctx;
    ctx.exclude_pid = argc > 1 ? (DWORD)strtoul(argv[1], NULL, 10) : 0;
    ctx.first = 1;
    printf("[");
    EnumWindows(on_window, (LPARAM)&ctx);  // EnumWindows walks the Z order, front-to-back
    printf("]\n");
    return 0;
}
