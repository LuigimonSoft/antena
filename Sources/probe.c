// SPDX-License-Identifier: GPL-2.0-only
// Native USB driver entry point for KWorld VS-ATSC 330U.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach_error.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include "frontend.h"
#include "capture.h"

static bool frontend_mode;
static uint32_t tune_frequency;
static unsigned capture_seconds;
static const char *capture_output;
static int stream_descriptor = -1;

static void error(const char *op, IOReturn result) {
    fprintf(stderr, "%s: %s (0x%08x)\n", op, mach_error_string(result),
            (unsigned int)result);
}

static bool number(io_service_t service, CFStringRef key, int *value) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(service, key,
                                                       kCFAllocatorDefault, 0);
    bool ok = property && CFGetTypeID(property) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)property, kCFNumberIntType, value);
    if (property) CFRelease(property);
    return ok;
}

static bool configurations(IOUSBDeviceInterface **device) {
    UInt8 count = 0;
    IOReturn result = (*device)->GetNumberOfConfigurations(device, &count);
    if (result != kIOReturnSuccess) { error("Configurations", result); return false; }
    for (UInt8 index = 0; index < count; ++index) {
        IOUSBConfigurationDescriptorPtr config = NULL;
        result = (*device)->GetConfigurationDescriptorPtr(device, index, &config);
        if (result != kIOReturnSuccess || !config) {
            error("Configuration descriptor", result); return false;
        }
        const UInt8 *bytes = (const UInt8 *)config;
        size_t total = USBToHostWord(config->wTotalLength);
        printf("Configuration %u: %zu bytes\n", config->bConfigurationValue, total);
        for (size_t offset = 0; offset < total;) {
            if (total - offset < 2 || bytes[offset] < 2 ||
                bytes[offset] > total - offset) {
                fprintf(stderr, "Malformed USB descriptor at %zu\n", offset);
                return false;
            }
            const UInt8 *d = bytes + offset;
            printf("  descriptor:");
            for (UInt8 n = 0; n < d[0]; ++n) printf(" %02x", d[n]);
            printf("\n");
            if (d[1] == kUSBInterfaceDesc && d[0] >= 9)
                printf("  interface=%u alternate=%u endpoints=%u class=%02x\n",
                       d[2], d[3], d[4], d[5]);
            if (d[1] == kUSBEndpointDesc && d[0] >= 7) {
                unsigned packet = d[4] | ((unsigned)d[5] << 8);
                printf("  endpoint=0x%02x type=%u packet=%u transactions=%u interval=%u\n",
                       d[2], d[3] & 3, packet & 0x7ff,
                       1 + ((packet >> 11) & 3), d[6]);
            }
            offset += d[0];
        }
    }
    return true;
}

static bool registers(IOUSBDeviceInterface **device) {
    // em28xx protocol: vendor IN, request 0, value 0, index=register.
    // See Linux em28xx_read_reg() and em28xx_read_reg_req_len().
    const UInt16 addresses[] = {0x0a, 0x04, 0x08};
    const char *names[] = {"CHIP_ID", "GPO", "GPIO"};
    for (size_t i = 0; i < sizeof(addresses)/sizeof(addresses[0]); ++i) {
        UInt8 value = 0;
        IOUSBDevRequestTO request = {0};
        request.bmRequestType = 0xc0;
        request.bRequest = 0;
        request.wIndex = addresses[i];
        request.wLength = 1;
        request.pData = &value;
        request.noDataTimeout = 1000;
        request.completionTimeout = 1000;
        IOReturn result = (*device)->DeviceRequestTO(device, &request);
        if (result != kIOReturnSuccess) { error(names[i], result); return false; }
        if (request.wLenDone != 1) {
            fprintf(stderr, "%s: short USB read (%u bytes)\n", names[i],
                    (unsigned)request.wLenDone);
            return false;
        }
        printf("Register 0x%02x (%s) = 0x%02x\n", addresses[i], names[i], value);
    }
    return true;
}

static bool probe(io_service_t service) {
    IOCFPlugInInterface **plugin = NULL;
    IOUSBDeviceInterface **device = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(service,
        kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (result != kIOReturnSuccess || !plugin) { error("USB plugin", result); return false; }
    HRESULT query = (*plugin)->QueryInterface(plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID *)&device);
    IODestroyPlugInInterface(plugin);
    if (query != S_OK || !device) {
        fprintf(stderr, "USB interface unavailable: 0x%08x\n", (unsigned)query);
        return false;
    }
    // Ordinary open; do not seize another driver's device or change configuration.
    result = (*device)->USBDeviceOpen(device);
    if (result != kIOReturnSuccess) {
        error("USBDeviceOpen", result);
        (*device)->Release(device);
        return false;
    }
    bool ok = registers(device);
    if (ok && frontend_mode) ok = kw_frontend(device, tune_frequency);
    if (ok && stream_descriptor >= 0) ok = kw_capture_pipe(device, stream_descriptor);
    if (ok && capture_seconds) ok = kw_capture(device, capture_seconds, capture_output);
    if (ok && !frontend_mode && !capture_seconds) ok = configurations(device);
    result = (*device)->USBDeviceClose(device);
    if (result != kIOReturnSuccess) { error("USBDeviceClose", result); ok = false; }
    (*device)->Release(device);
    return ok;
}

int main(int argc, const char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc > 1) {
        if (argc == 2 && strcmp(argv[1], "--frontend-probe") == 0) {
            frontend_mode = true;
        } else if ((argc == 3 && (strcmp(argv[1], "--tune") == 0 || strcmp(argv[1], "--stream") == 0)) ||
                   (argc == 5 && strcmp(argv[1], "--capture") == 0)) {
            char *end = NULL;
            errno = 0;
            unsigned long hz = strtoul(argv[2], &end, 10);
            if (errno || !end || *end || hz < 54000000 || hz > 858000000) {
                fprintf(stderr, "Frequency must be 54000000..858000000 Hz\n");
                return 64;
            }
            frontend_mode = true;
            tune_frequency = (uint32_t)hz;
            if (strcmp(argv[1], "--stream") == 0) {
                stream_descriptor = dup(STDOUT_FILENO);
                if (stream_descriptor < 0 || dup2(STDERR_FILENO, STDOUT_FILENO) < 0) {
                    perror("stream descriptor"); return 1;
                }
                signal(SIGPIPE, SIG_IGN);
            }
            if (argc == 5) {
                unsigned long seconds = strtoul(argv[3], &end, 10);
                if (!end || *end || seconds < 1 || seconds > 3600) {
                    fprintf(stderr, "Capture duration must be 1..3600 seconds\n"); return 64;
                }
                capture_seconds = (unsigned)seconds;
                capture_output = argv[4];
            }
        } else if (argc == 2 && strcmp(argv[1], "--transport-test") == 0) {
            capture_seconds = 2;
        } else {
        if (argc == 2 && strcmp(argv[1], "--help") == 0) {
            puts("kworld-tv: KWorld eb1a:a316 experimental ATSC driver for macOS.\n"
                 "No arguments: read USB descriptors and chip ID.\n"
                 "--frontend-probe: initialize bridge and identify S5H1409 over I2C.\n"
                 "--tune HZ: load verified XC3028 firmware and tune ATSC 8VSB.\n"
                 "--stream HZ: continuous live MPEG-TS on stdout; logs on stderr.\n"
                 "--capture HZ SECONDS OUTPUT.ts: tune and capture (never overwrites).\n"
                 "--transport-test: test USB isochronous reads for two seconds.\n"
                 "Exit: 0 success; 1 USB/firmware/signal/capture failure; 2 not connected; 64 usage.\n"
                 "Experimental user-space driver; real reception requires ATSC lock.");
            return 0;
        }
        fprintf(stderr, "Usage: %s [--help]\n", argv[0]);
        return 64;
        }
    }
    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn result = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostDevice"), &iterator);
    if (result != kIOReturnSuccess) { error("USB enumeration", result); return 1; }
    unsigned found = 0;
    bool ok = true;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        int vendor = 0, product = 0, revision = 0;
        if (number(service, CFSTR("idVendor"), &vendor) &&
            number(service, CFSTR("idProduct"), &product) &&
            vendor == 0xeb1a && product == 0xa316) {
            ++found;
            number(service, CFSTR("bcdDevice"), &revision);
            printf("KWorld 330U candidate: %04x:%04x bcdDevice=%04x\n",
                   vendor, product, revision);
            if (!probe(service)) ok = false;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (!found) {
        fprintf(stderr, "KWorld eb1a:a316 not connected. Connect USB and retry.\n");
        return 2;
    }
    if (!frontend_mode && !capture_seconds) puts("USB diagnostic only; no reception attempted.");
    if (stream_descriptor >= 0) close(stream_descriptor);
    return ok ? 0 : 1;
}
