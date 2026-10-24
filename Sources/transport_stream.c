// SPDX-License-Identifier: GPL-2.0-only
#include "transport_stream.h"
#include <string.h>
void kw_ts_init(struct kw_ts *ts, FILE *output) {
    memset(ts, 0, sizeof *ts);
    memset(ts->continuity, -1, sizeof ts->continuity);
    ts->output = output;
}
static void packet(struct kw_ts *ts, const uint8_t *p) {
    unsigned pid = ((p[1] & 31) << 8) | p[2];
    unsigned control = (p[3] >> 4) & 3, counter = p[3] & 15;
    bool bad = (p[1] & 0x80) || control == 0;
    bool discontinuity = false;
    if (control & 2) {
        if (p[4] > 183 || (control == 3 && p[4] > 182)) bad = true;
        else if (p[4] >= 1) discontinuity = (p[5] & 0x80) != 0;
    }
    if (bad) { ++ts->transport_errors; ts->continuity[pid] = -1; }
    else if (pid != 0x1fff && (control & 1)) {
        int old = ts->continuity[pid];
        // Repeated continuity is permitted for duplicate packets.
        if (!discontinuity && old >= 0 && counter != (unsigned)old &&
            counter != (unsigned)((old + 1) & 15)) ++ts->continuity_errors;
        ts->continuity[pid] = (int8_t)counter;
    } else if (discontinuity) ts->continuity[pid] = -1;
    ++ts->packets;
    if (pid == 0 && !bad) ++ts->pat_packets;
    if (ts->output && fwrite(p, 1, 188, ts->output) != 188) ts->failed = true;
}
void kw_ts_feed(struct kw_ts *ts, const uint8_t *data, size_t length) {
    while (length && !ts->failed) {
        size_t n = sizeof ts->buffer - ts->used;
        if (n > length) n = length;
        memcpy(ts->buffer + ts->used, data, n);
        ts->used += n; data += n; length -= n;
        size_t at = 0;
        while (ts->used - at >= 188) {
            if (!ts->synchronized) {
                if (ts->used - at < 377) break;
                if (ts->buffer[at] != 0x47 || ts->buffer[at+188] != 0x47 ||
                    ts->buffer[at+376] != 0x47) { ++at; ++ts->discarded; continue; }
                ts->synchronized = true;
            }
            if (ts->buffer[at] != 0x47) {
                ts->synchronized = false;
                memset(ts->continuity, -1, sizeof ts->continuity);
                continue;
            }
            packet(ts, ts->buffer + at); at += 188;
        }
        if (at) { memmove(ts->buffer, ts->buffer + at, ts->used - at); ts->used -= at; }
    }
}
