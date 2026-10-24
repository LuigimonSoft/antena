// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <IOKit/usb/IOUSBLib.h>
#include <stdbool.h>
// NULL output performs a transport-only diagnostic, never reports TV reception.
bool kw_capture(IOUSBDeviceInterface **device, unsigned seconds, const char *output);
// Continuous MPEG-TS to an already-open pipe descriptor; no disk recording.
bool kw_capture_pipe(IOUSBDeviceInterface **device, int descriptor);
