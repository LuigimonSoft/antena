// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
struct kw_ts {
    uint8_t buffer[8192]; size_t used;
    int8_t continuity[8192];
    uint64_t packets, discarded, transport_errors, continuity_errors, pat_packets;
    bool synchronized, failed;
    FILE *output;
};
void kw_ts_init(struct kw_ts *ts, FILE *output);
void kw_ts_feed(struct kw_ts *ts, const uint8_t *data, size_t length);
