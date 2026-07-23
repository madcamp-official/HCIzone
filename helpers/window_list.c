// Prints the rectangles of all normal on-screen windows as JSON, front-to-back.
// Usage: window_list [pid-to-exclude]
// Bounds come from CGWindowListCopyWindowInfo: global desktop coordinates,
// origin at the top-left of the primary display, y increasing downward —
// the same space Godot's DisplayServer uses on macOS.
//
// Build: clang -O2 -framework CoreGraphics -framework CoreFoundation window_list.c -o window_list

#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    long exclude_pid = argc > 1 ? atol(argv[1]) : -1;
    CFArrayRef list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!list) {
        printf("[]\n");
        return 1;
    }
    printf("[");
    int first = 1;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        CFDictionaryRef w = CFArrayGetValueAtIndex(list, i);
        CFNumberRef n;
        int layer = -1;
        n = CFDictionaryGetValue(w, kCGWindowLayer);
        if (n) CFNumberGetValue(n, kCFNumberIntType, &layer);
        if (layer != 0) continue;  // 0 = normal app windows (skips dock, menu bar, overlays)
        long pid = -1;
        n = CFDictionaryGetValue(w, kCGWindowOwnerPID);
        if (n) CFNumberGetValue(n, kCFNumberLongType, &pid);
        if (pid == exclude_pid) continue;  // don't let the pet stand on itself
        double alpha = 1.0;
        n = CFDictionaryGetValue(w, kCGWindowAlpha);
        if (n) CFNumberGetValue(n, kCFNumberDoubleType, &alpha);
        if (alpha < 0.1) continue;
        CFDictionaryRef bd = CFDictionaryGetValue(w, kCGWindowBounds);
        CGRect r;
        if (!bd || !CGRectMakeWithDictionaryRepresentation(bd, &r)) continue;
        long wid = 0;
        n = CFDictionaryGetValue(w, kCGWindowNumber);
        if (n) CFNumberGetValue(n, kCFNumberLongType, &wid);
        printf("%s{\"id\":%ld,\"x\":%g,\"y\":%g,\"w\":%g,\"h\":%g}",
               first ? "" : ",", wid, r.origin.x, r.origin.y, r.size.width, r.size.height);
        first = 0;
    }
    printf("]\n");
    CFRelease(list);
    return 0;
}
