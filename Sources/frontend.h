// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <IOKit/usb/IOUSBLib.h>
#include <stdbool.h>
#include <stdint.h>
bool kw_frontend(IOUSBDeviceInterface **device, uint32_t frequency);
