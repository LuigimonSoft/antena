// SPDX-License-Identifier: GPL-2.0-only
// macOS port of the ATSC-only path from Linux em28xx, s5h1409 and xc2028.
// Linux reference authors: Mauro Carvalho Chehab, Steven Toth,
// Ludovico Cavedon, Markus Rechberger, Sascha Sommer, Frank Schäfer,
// Michel Ludwig. Original sources and notices are retained in Reference/.
#include "frontend.h"
#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach_error.h>

struct board { IOUSBDeviceInterface **usb; };
struct image { uint32_t type, size; uint64_t id; uint16_t intermediate; const uint8_t *data; };
struct firmware { uint8_t data[66220]; struct image images[80]; };
static uint16_t le16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static uint32_t le32(const uint8_t *p) { return le16(p) | (uint32_t)le16(p + 2) << 16; }
static uint64_t le64(const uint8_t *p) { return le32(p) | (uint64_t)le32(p + 4) << 32; }
static void delay(unsigned ms) { usleep(ms * 1000); }

static bool transfer(struct board *b, bool input, uint8_t command, uint16_t index,
                     void *data, uint16_t length) {
    IOUSBDevRequestTO req = {0};
    req.bmRequestType = input ? 0xc0 : 0x40;
    req.bRequest = command; req.wIndex = index;
    req.wLength = length; req.pData = data;
    req.noDataTimeout = 1000; req.completionTimeout = 1000;
    IOReturn r = (*b->usb)->DeviceRequestTO(b->usb, &req);
    if (r != kIOReturnSuccess || req.wLenDone != length) {
        fprintf(stderr, "USB %s req=%u index=%04x: %s (0x%08x), length=%u/%u\n",
                input ? "IN" : "OUT", command, index, mach_error_string(r),
                (unsigned)r, (unsigned)req.wLenDone, length);
        return false;
    }
    return true;
}
static bool readreg(struct board *b, uint8_t reg, uint8_t *value) {
    return transfer(b, true, 0, reg, value, 1);
}
static bool writereg(struct board *b, uint8_t reg, uint8_t value) {
    return transfer(b, false, 0, reg, &value, 1);
}
static bool bits(struct board *b, uint8_t reg, uint8_t value, uint8_t mask) {
    uint8_t old;
    return readreg(b, reg, &old) && writereg(b, reg, (old & ~mask) | (value & mask));
}
static bool i2cstatus(struct board *b) {
    for (unsigned n = 0; n < 9; ++n) {
        uint8_t status;
        if (!readreg(b, 5, &status)) return false;
        if (status == 0) return true;
        if (status == 0x10) { fprintf(stderr, "I2C NACK\n"); return false; }
        delay(5);
    }
    fprintf(stderr, "I2C completion timed out\n"); return false;
}
static bool send(struct board *b, uint8_t addr, const uint8_t *data, uint16_t n, bool stop) {
    if (n == 0 || n > 64 || addr > 0x7f) return false;
    return transfer(b, false, stop ? 2 : 3, addr << 1, (void *)data, n) && i2cstatus(b);
}
static bool receive(struct board *b, uint8_t addr, uint8_t *data, uint16_t n) {
    if (n == 0 || n > 64 || addr > 0x7f) return false;
    return transfer(b, true, 2, addr << 1, data, n) && i2cstatus(b);
}
static bool demod_read(struct board *b, uint8_t reg, uint16_t *value) {
    uint8_t d[2];
    if (!send(b, 0x19, &reg, 1, false) || !receive(b, 0x19, d, 2)) return false;
    *value = (uint16_t)d[0] << 8 | d[1]; return true;
}
static bool demod_write(struct board *b, uint8_t reg, uint16_t value) {
    uint8_t d[] = {reg, value >> 8, value & 255};
    return send(b, 0x19, d, sizeof d, true);
}
static bool tuner_read(struct board *b, uint16_t reg, uint16_t *value) {
    uint8_t address[] = {reg >> 8, reg & 255}, d[2];
    if (!send(b, 0x61, address, 2, false) || !receive(b, 0x61, d, 2)) return false;
    *value = (uint16_t)d[0] << 8 | d[1]; return true;
}
static bool tuner_reset(struct board *b) {
    if (!writereg(b, 0x48, 0) || !writereg(b, 0x12, 0x37)) return false;
    delay(10);
    for (unsigned i = 0; i < 3; ++i) {
        if (!bits(b, 8, i == 1 ? 0 : 0x10, 0x10)) return false;
        delay(10);
    }
    return true;
}
static bool bridge_init(struct board *b) {
    uint8_t chip;
    if (!readreg(b, 0x0a, &chip) || chip != 0x24) {
        fprintf(stderr, "Expected EM2883 chip ID 0x24; initialization refused\n"); return false;
    }
    if (!writereg(b, 0x0f, 0x07) || !writereg(b, 6, 0x4c)) return false;
    delay(50);
    if (!writereg(b, 0x48, 0) || !writereg(b, 0x12, 0x37)) return false;
    delay(10);
    if (!bits(b, 8, 0x6e, 0xef)) return false;
    delay(10);
    if (!writereg(b, 4, 8)) return false;
    delay(10);
    return tuner_reset(b);
}
static bool demod_init(struct board *b) {
    // s5h1409 init_tab; parallel TS, noninverted continuous clock, VSB IF 5380 kHz.
    static const struct { uint8_t reg; uint16_t value; } table[] = {
        {0x00,0x0071},{0x01,0x3213},{0x09,0x0025},{0x1c,0x001d},
        {0x1f,0x002d},{0x20,0x001d},{0x22,0x0022},{0x23,0x0020},
        {0x29,0x110f},{0x2a,0x10b4},{0x2b,0x10ae},{0x2c,0x0031},
        {0x31,0x010d},{0x32,0x0100},{0x44,0x0510},{0x54,0x0104},
        {0x58,0x2222},{0x59,0x1162},{0x5a,0x3211},{0x5d,0x0370},
        {0x5e,0x0296},{0x61,0x0010},{0x63,0x4a00},{0x65,0x0800},
        {0x71,0x0003},{0x72,0x0470},{0x81,0x0002},{0x82,0x0600},
        {0x86,0x0002},{0x8a,0x2c38},{0x8b,0x2a37},{0x92,0x302f},
        {0x93,0x3332},{0x96,0x000c},{0x99,0x0101},{0x9c,0x2e37},
        {0x9d,0x2c37},{0x9e,0x2c37},{0xab,0x0100},{0xac,0x1003},
        {0xad,0x103f},{0xe2,0x0100},{0xe3,0x1000},{0x28,0x1010},{0xb1,0x000e}
    };
    if (!demod_write(b, 0xf2, 0) || !demod_write(b, 0xfa, 0)) return false;
    for (size_t i = 0; i < sizeof table / sizeof table[0]; ++i)
        if (!demod_write(b, table[i].reg, table[i].value)) return false;
    uint16_t value;
    if (!demod_read(b, 0xab, &value) || !demod_write(b, 0xab, value & 0xfeff) ||
        !demod_write(b, 0x1b, 0x0110) || !demod_write(b, 0x87, 0x01be) ||
        !demod_write(b, 0x88, 0x0436) || !demod_write(b, 0x89, 0x054d) ||
        !demod_read(b, 0xe3, &value) || !demod_write(b, 0xe3, value & 0xfeff) ||
        !demod_read(b, 0xac, &value) || !demod_write(b, 0xac, (value & 0xcfff) | 0x1000) ||
        !demod_write(b, 0xf5, 0) || !demod_write(b, 0xf5, 1)) return false;
    return demod_write(b, 0xf3, 1);
}
static bool firmware_read(struct firmware *fw) {
    FILE *f = fopen("firmware/xc3028-v27.fw", "rb");
    if (!f) { perror("firmware/xc3028-v27.fw"); return false; }
    size_t size = fread(fw->data, 1, sizeof fw->data, f);
    bool ok = size == sizeof fw->data && fgetc(f) == EOF && !ferror(f);
    fclose(f);
    if (!ok) { fprintf(stderr, "Firmware size mismatch\n"); return false; }
    static const uint8_t expected[] = {
        0x0d,0x4c,0xfd,0x79,0x74,0xa1,0x9a,0x94,0xf4,0xd4,0x2e,0xb2,0xd1,0x60,0xd5,0xa3,
        0xe7,0x1c,0xca,0x1c,0xfa,0x61,0xbd,0x2c,0xc0,0x63,0xcf,0x3f,0x36,0xff,0xd3,0x2e
    };
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(fw->data, (CC_LONG)size, digest);
    if (memcmp(digest, expected, sizeof expected) || le16(fw->data + 32) != 0x207 ||
        le16(fw->data + 34) != 80) {
        fprintf(stderr, "Unverified firmware refused\n"); return false;
    }
    size_t offset = 36;
    for (unsigned i = 0; i < 80; ++i) {
        struct image *im = &fw->images[i];
        if (offset + 12 > size) return false;
        im->type = le32(fw->data + offset); im->id = le64(fw->data + offset + 4);
        offset += 12; im->intermediate = 0;
        if (im->type & (1u << 30)) {
            if (offset + 2 > size) return false;
            im->intermediate = le16(fw->data + offset); offset += 2;
        }
        if (offset + 4 > size) return false;
        im->size = le32(fw->data + offset); offset += 4;
        if (!im->size || im->size > size - offset) return false;
        im->data = fw->data + offset; offset += im->size;
    }
    return offset == size;
}
static const struct image *select_image(const struct firmware *fw, uint32_t type, uint16_t intermediate) {
    for (unsigned i = 0; i < 80; ++i) {
        const struct image *im = &fw->images[i];
        if (intermediate ? (im->intermediate == intermediate && (im->type & (1u << 30))) :
            (im->type == type && im->id == 0)) return im;
    }
    return NULL;
}
static bool image_load(struct board *b, const struct image *im) {
    if (!im) { fprintf(stderr, "Required firmware image missing\n"); return false; }
    printf("Loading firmware type=0x%08x bytes=%u\n", im->type, im->size);
    size_t offset = 0;
    while (offset + 2 <= im->size) {
        uint16_t size = le16(im->data + offset); offset += 2;
        if (size == 0xffff) return true;
        if (size == 0) { if (!tuner_reset(b)) return false; continue; }
        if (size >= 0xff00) {
            if (size != 0xff00) return false;
            continue; // EM2883 callback does not require clock reset.
        }
        if (size & 0x8000) { delay(size & 0x7fff); continue; }
        if (size > im->size - offset || size < 2) return false;
        uint8_t buffer[64]; buffer[0] = im->data[offset++]; --size;
        while (size) {
            uint16_t n = size > 63 ? 63 : size;
            memcpy(buffer + 1, im->data + offset, n);
            if (!send(b, 0x61, buffer, n + 1, true)) return false;
            offset += n; size -= n;
        }
    }
    return offset == im->size;
}
static bool tuner_load(struct board *b, const struct firmware *fw) {
    // KWorld board sets MTS. ATSC 6 MHz uses D2633; std-specific image ignores MTS.
    if (!tuner_reset(b) || !image_load(b, select_image(fw, 0x5, 0)) ||
        !image_load(b, select_image(fw, 0x10030, 0))) return false;
    const struct image *scode = select_image(fw, 0, 5400); // CHINA (5200) + 200 kHz
    if (!scode || scode->size != 192) return false;
    const uint8_t begin[] = {0xa0,0,0,0}, end[] = {0,0x8c};
    if (!send(b, 0x61, begin, sizeof begin, true) ||
        !send(b, 0x61, scode->data, 12, true) || !send(b, 0x61, end, sizeof end, true)) return false;
    uint16_t version, model;
    if (!tuner_read(b, 4, &version) || !tuner_read(b, 8, &model)) return false;
    printf("XC tuner model=%u version=0x%04x\n", model, version);
    if ((model != 2028 && model != 3028) || (((version & 0xf0) << 4) | (version & 15)) != 0x207) {
        fprintf(stderr, "Tuner firmware readback mismatch\n"); return false;
    }
    return true;
}
bool kw_frontend(IOUSBDeviceInterface **device, uint32_t frequency) {
    struct board b = {device};
    struct firmware *fw = NULL;
    if (frequency) {
        fw = calloc(1, sizeof *fw);
        if (!fw || !firmware_read(fw)) { free(fw); return false; }
    }
    bool ok = false, gate = false;
    if (!bridge_init(&b)) goto done;
    uint16_t id;
    if (!demod_read(&b, 4, &id)) goto done;
    printf("S5H1409 ID=0x%04x\n", id);
    if (id != 0x66 && id != 0x7f) { fprintf(stderr, "Unknown demodulator; refusing initialization\n"); goto done; }
    if (!frequency) { ok = true; goto done; }
    if (!demod_init(&b)) goto done;
    gate = true;
    if (!tuner_load(&b, fw)) goto done;
    uint32_t divisor = (frequency - 1750000 + 15625 / 2) / 15625;
    const uint8_t command[] = {0x80,2,0,0};
    uint8_t d[] = {divisor >> 24, divisor >> 16, divisor >> 8, divisor};
    if (!send(&b, 0x61, command, sizeof command, true)) goto done;
    delay(10);
    if (!send(&b, 0x61, d, sizeof d, true)) goto done;
    delay(100);
    if (!demod_write(&b, 0xf3, 0)) goto done;
    gate = false;
    if (!demod_write(&b, 0xf4, 0) || !demod_write(&b, 0xf5, 0) || !demod_write(&b, 0xf5, 1)) goto done;
    printf("ATSC 8VSB tuned to %u Hz; waiting for lock\n", frequency);
    for (unsigned n = 0; n < 50; ++n) {
        uint16_t status;
        if (!demod_read(&b, 0xf1, &status)) goto done;
        if (status & 0x8000) { printf("DEMOD LOCK: 0x%04x\n", status); ok = true; goto done; }
        delay(100);
    }
    fprintf(stderr, "No ATSC lock after 5 seconds. Verify antenna and RF frequency.\n");
done:
    if (gate && !demod_write(&b, 0xf3, 0)) ok = false;
    free(fw);
    return ok;
}
