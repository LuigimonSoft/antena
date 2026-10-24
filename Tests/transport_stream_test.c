#include "transport_stream.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
static void make_packet(uint8_t *p, unsigned counter) {
    memset(p, 0xab, 188);
    p[0] = 0x47; p[1] = 0; p[2] = 100; p[3] = 0x10 | counter;
}
int main(void) {
    uint8_t input[4*188];
    for (unsigned i = 0; i < 4; ++i) make_packet(input + i*188, i);
    struct kw_ts ts;
    FILE *output = tmpfile(); assert(output);
    kw_ts_init(&ts, output);
    const uint8_t junk[] = {1,2,3,4,5};
    kw_ts_feed(&ts, junk, sizeof junk);
    // Every packet header and sync boundary must survive arbitrary USB fragments.
    for (unsigned i = 0; i < sizeof input; ++i) kw_ts_feed(&ts, input + i, 1);
    assert(ts.packets == 4 && ts.discarded == 5);
    assert(ts.continuity_errors == 0 && ts.transport_errors == 0 && !ts.failed);
    rewind(output);
    uint8_t copy[sizeof input];
    assert(fread(copy, 1, sizeof copy, output) == sizeof copy);
    assert(memcmp(copy, input, sizeof input) == 0);
    fclose(output);
    ts.output = NULL;
    // Missing packets must be observable rather than hidden by resynchronization.
    uint8_t packet[188]; make_packet(packet, 8);
    kw_ts_feed(&ts, packet, sizeof packet);
    assert(ts.continuity_errors == 1);
    // Explicit discontinuity permits a new continuity sequence.
    make_packet(packet, 13);
    packet[3] = 0x30 | 13; packet[4] = 1; packet[5] = 0x80;
    kw_ts_feed(&ts, packet, sizeof packet);
    assert(ts.continuity_errors == 1);
    packet[1] |= 0x80;
    kw_ts_feed(&ts, packet, sizeof packet);
    assert(ts.transport_errors == 1);
    puts("MPEG-TS fragment, output, continuity, discontinuity and TEI checks passed");
    return 0;
}
