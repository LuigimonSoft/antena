# Provenance of xc3028-v27.fw

The firmware was extracted locally from the Windows package referenced by the
official Linux extractor. It is neither a current download from KWorld nor an
official firmware release for macOS.

## Sources

- Official extractor: https://github.com/torvalds/linux/blob/master/scripts/extract_xc3028.pl
- Historical URL listed in that extractor:
  http://www.steventoth.net/linux/xc5000/HVR-12x0-14x0-17x0_1_25_25271_WHQL.zip
- Archived copy used:
  https://web.archive.org/web/20240116213210id_/http://www.steventoth.net/linux/xc5000/HVR-12x0-14x0-17x0_1_25_25271_WHQL.zip
- Current Hauppauge Linux support page consulted:
  https://www.hauppauge.com/site/support/linux.html

When checked, the historical link over HTTPS returned HTML from a site unrelated
to the driver. That content was not used. The archived copy does contain a ZIP file.

## Verification performed

| File | Check |
| --- | --- |
| Archived ZIP | SHA-256 `ccbe3bc8b8545ecf00cf3fc47af1b33f312a6f2e873a3e29ce1e8b82adef49d9` |
| `Driver85/hcw85bda.sys` | MD5 `0e44dbf63bb0169d57446aec21881ff2`, matching the value expected by the Linux extractor |
| `Reference/extract_xc3028.pl` | SHA-256 `1e6f3f6412b55b3651a8fe414e61cc757a55b8547ba4506b6f5c406e5fb924ae` |
| `xc3028-v27.fw` | SHA-256 `0d4cfd7974a19a94f4d42eb2d160d5a3e71cca1cfa61bd2cc063cf3f36ffd32e` |

The MD5 check establishes a match with the file expected by Linux; it does not
validate a cryptographic signature from the manufacturer. The SHA-256 hashes
identify the exact files used during this session.

The generated file is 66,220 bytes long. Its header specifies `xc2028 firmware`,
version 2.7, and 80 images. The length and boundaries of each image are validated
with `./script/antena_tools.sh verify-firmware`.

The Windows drivers were treated as data and were not executed. The firmware was
subsequently loaded into the tuner's RAM: the XC3028 reported model 3028 and
version `0x1027` (firmware 2.7). MPEG-TS reception from CBMT-DT was verified on
macOS 27.0.1; see `docs/reception-test.txt` and `docs/reception-programs.json`.

The firmware binary and the original Windows file are excluded from Git.
The extractor's GPL license does not, by itself, grant redistribution rights
for the extracted firmware.
