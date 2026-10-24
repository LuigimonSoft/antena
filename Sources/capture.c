// SPDX-License-Identifier: GPL-2.0-only
// EM2883 digital capture setup adapted from Linux em28xx-core.c.
#include "capture.h"
#include "transport_stream.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <mach/mach_error.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#define FRAMES 128
#define PACKET 752
#define SLOTS 4
struct capture;
struct slot { struct capture *capture; IOUSBIsocFrame frames[FRAMES]; uint8_t data[FRAMES*PACKET]; };
struct capture {
    IOUSBInterfaceInterface **interface;
    UInt8 pipe;
    UInt64 next;
    unsigned pending;
    bool stopping, failed;
    uint64_t bytes, errors, completions;
    struct kw_ts ts;
    struct slot slots[SLOTS];
};
static volatile sig_atomic_t interrupted;
static void on_signal(int signal) { (void)signal; interrupted = 1; }
static bool checked(const char *operation, IOReturn result) {
    if (result == kIOReturnSuccess) return true;
    fprintf(stderr, "%s: %s (0x%08x)\n", operation, mach_error_string(result), (unsigned)result);
    return false;
}
static bool submit(struct slot *slot);
static void complete(void *context, IOReturn result, void *arg) {
    (void)arg;
    struct slot *slot = context;
    struct capture *c = slot->capture;
    --c->pending; ++c->completions;
    if (c->stopping) return;
    if (result != kIOReturnSuccess && result != kIOReturnUnderrun) {
        checked("Isochronous completion", result); c->failed = true; return;
    }
    for (unsigned i = 0; i < FRAMES; ++i) {
        IOUSBIsocFrame *f = &slot->frames[i];
        if (f->frStatus != kIOReturnSuccess && f->frStatus != kIOReturnUnderrun) {
            ++c->errors; continue;
        }
        if (f->frActCount > PACKET) { c->failed = true; return; }
        c->bytes += f->frActCount;
        kw_ts_feed(&c->ts, slot->data + i*PACKET, f->frActCount);
    }
    if (c->ts.failed || !submit(slot)) c->failed = true;
}
static bool submit(struct slot *slot) {
    struct capture *c = slot->capture;
    memset(slot->frames, 0, sizeof slot->frames);
    for (unsigned i = 0; i < FRAMES; ++i) slot->frames[i].frReqCount = PACKET;
    IOReturn r = (*c->interface)->ReadIsochPipeAsync(c->interface, c->pipe,
        slot->data, c->next, FRAMES, slot->frames, complete, slot);
    if (!checked("ReadIsochPipeAsync", r)) return false;
    c->next += FRAMES / 8; // High-speed endpoint interval 1: eight microframes per bus frame.
    ++c->pending; return true;
}
static bool reg(IOUSBDeviceInterface **device, bool input, UInt8 index, UInt8 *value) {
    IOUSBDevRequestTO r = {0}; r.bmRequestType = input ? 0xc0 : 0x40;
    r.wIndex = index; r.wLength = 1; r.pData = value;
    r.noDataTimeout = r.completionTimeout = 1000;
    return checked("Capture register", (*device)->DeviceRequestTO(device, &r)) && r.wLenDone == 1;
}
static bool enable(IOUSBDeviceInterface **device, bool start) {
    UInt8 value;
    if (start) {
        // SET_INTERFACE may reset bridge state. Reapply kworld_330u_digital
        // after selecting the alternate, in the same order as Linux.
        value = 0;
        if (!reg(device, false, 0x48, &value)) return false;
        value = 0x37;
        if (!reg(device, false, 0x12, &value)) return false;
        usleep(10000);
        if (!reg(device, true, 0x08, &value)) return false;
        value = (value & 0x10) | 0x6e;
        if (!reg(device, false, 0x08, &value)) return false;
        usleep(10000);
        value = 8;
        if (!reg(device, false, 0x04, &value)) return false;
        usleep(10000);
    }
    if (!reg(device, true, 0x0c, &value)) return false;
    value = (value & ~0x10) | (start ? 0x10 : 0);
    if (!reg(device, false, 0x0c, &value)) return false;
    if (start) {
        value = 0x37;
        if (!reg(device, false, 0x12, &value)) return false;
        const UInt8 addresses[] = {0, 1, 4, 8, 0x0c, 0x0f, 0x12};
        for (size_t i = 0; i < sizeof addresses; ++i) {
            if (!reg(device, true, addresses[i], &value)) return false;
            printf("Capture bridge register %02x=%02x\n", addresses[i], value);
        }
    }
    else {
        value = 0x27;
        if (!reg(device, false, 0x12, &value)) return false;
    }
    return true;
}
static IOUSBInterfaceInterface **open_interface(IOUSBDeviceInterface **device) {
    IOUSBFindInterfaceRequest request = {0xff, kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare};
    io_iterator_t iterator = 0;
    if (!checked("CreateInterfaceIterator", (*device)->CreateInterfaceIterator(device, &request, &iterator))) return NULL;
    io_service_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!service) { fprintf(stderr, "USB interface 0 missing\n"); return NULL; }
    IOCFPlugInInterface **plugin = NULL; SInt32 score = 0;
    IOReturn r = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (!checked("Interface plugin", r) || !plugin) return NULL;
    IOUSBInterfaceInterface **interface = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID942), (LPVOID *)&interface);
    IODestroyPlugInInterface(plugin);
    if (hr != S_OK || !interface) return NULL;
    if (!checked("USBInterfaceOpen", (*interface)->USBInterfaceOpen(interface))) {
        (*interface)->Release(interface); return NULL;
    }
    return interface;
}
static bool capture(IOUSBDeviceInterface **device, unsigned seconds, const char *output, int descriptor) {
    struct capture *c = calloc(1, sizeof *c);
    if (!c) return false;
    FILE *file = NULL; CFRunLoopSourceRef source = NULL; bool ok = false, started = false;
    c->interface = open_interface(device);
    if (!c->interface) goto done;
    if (!checked("SetAlternateInterface", (*c->interface)->SetAlternateInterface(c->interface, 1))) goto done;
    UInt32 interval;
    if (!checked("GetFrameListTime", (*c->interface)->GetFrameListTime(c->interface, &interval)) || interval != 125) {
        fprintf(stderr, "High-speed USB (125 us) required\n"); goto done;
    }
    UInt8 count;
    if (!checked("GetNumEndpoints", (*c->interface)->GetNumEndpoints(c->interface, &count))) goto done;
    for (UInt8 pipe = 1; pipe <= count; ++pipe) {
        UInt8 direction, endpoint, type, period; UInt16 maxpacket;
        if (!checked("GetPipeProperties", (*c->interface)->GetPipeProperties(c->interface,
            pipe, &direction, &endpoint, &type, &maxpacket, &period))) goto done;
        if (direction == kUSBIn && endpoint == 4 && type == kUSBIsoc && maxpacket == PACKET && period == 1)
            c->pipe = pipe;
    }
    if (!c->pipe) { fprintf(stderr, "Expected digital endpoint 0x84 not available\n"); goto done; }
    if (!checked("CreateInterfaceAsyncEventSource", (*c->interface)->CreateInterfaceAsyncEventSource(c->interface, &source))) goto done;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    if (descriptor >= 0) {
        int copy = dup(descriptor);
        if (copy < 0) { perror("dup stream pipe"); goto done; }
        file = fdopen(copy, "wb");
        if (!file) { close(copy); perror("stream pipe"); goto done; }
        setvbuf(file, NULL, _IOFBF, 32768);
    } else if (output) {
        int fd = open(output, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (fd < 0) { perror(output); goto done; }
        file = fdopen(fd, "wb");
        if (!file) { close(fd); perror("fdopen"); goto done; }
    }
    kw_ts_init(&c->ts, file);
    if (!enable(device, true)) goto done;
    started = true;
    AbsoluteTime at;
    if (!checked("GetBusFrameNumber", (*c->interface)->GetBusFrameNumber(c->interface, &c->next, &at))) goto done;
    c->next += 32;
    interrupted = 0;
    void (*previous_int)(int) = signal(SIGINT, on_signal);
    void (*previous_term)(int) = signal(SIGTERM, on_signal);
    for (unsigned i = 0; i < SLOTS; ++i) {
        c->slots[i].capture = c;
        if (!submit(&c->slots[i])) { c->failed = true; break; }
    }
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
    while (!interrupted && !c->failed && (!seconds || CFAbsoluteTimeGetCurrent() < deadline))
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    signal(SIGINT, previous_int); signal(SIGTERM, previous_term);
    ok = !c->failed && c->completions > 0;
done:
    c->stopping = true;
    if (started && !enable(device, false)) ok = false;
    if (c->interface) {
        if (c->pending && !checked("AbortPipe", (*c->interface)->AbortPipe(c->interface, c->pipe))) ok = false;
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 5;
        while (c->pending && CFAbsoluteTimeGetCurrent() < deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        if (c->pending) {
            // Preserve callback storage until process exit instead of freeing live buffers.
            fprintf(stderr, "USB cancellation did not drain; buffers retained until exit\n");
            if (file) fclose(file);
            c->ts.output = NULL;
            return false;
        }
        if (!checked("Restore alternate 0", (*c->interface)->SetAlternateInterface(c->interface, 0))) ok = false;
        if (!checked("USBInterfaceClose", (*c->interface)->USBInterfaceClose(c->interface))) ok = false;
        (*c->interface)->Release(c->interface);
    }
    if (source) { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode); CFRelease(source); }
    if (file && fclose(file) != 0) { perror("Capture output"); ok = false; }
    printf("USB capture: %llu completions, %llu bytes, %llu frame errors\n",
        (unsigned long long)c->completions, (unsigned long long)c->bytes, (unsigned long long)c->errors);
    printf("MPEG-TS: %llu packets, %llu PID-0 packets, %llu transport errors, %llu continuity errors\n",
        (unsigned long long)c->ts.packets, (unsigned long long)c->ts.pat_packets,
        (unsigned long long)c->ts.transport_errors, (unsigned long long)c->ts.continuity_errors);
    if (output && (!c->ts.packets || !c->ts.pat_packets)) {
        fprintf(stderr, "No television transport stream verified\n"); ok = false;
    }
    free(c);
    return ok;
}
bool kw_capture(IOUSBDeviceInterface **device, unsigned seconds, const char *output) {
    return capture(device, seconds, output, -1);
}
bool kw_capture_pipe(IOUSBDeviceInterface **device, int descriptor) {
    return capture(device, 0, NULL, descriptor);
}
