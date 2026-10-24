# Broadcast program guide

Antena reads ATSC 1.0 PSIP metadata directly from the tuned transport in memory. It does not need a recording, online TV listings or a subscription.

## Interface

When usable data arrives, the dashboard and player show the current program title, start/end times and elapsed progress. **On now & next** is a horizontally scrollable six-hour timeline. Program widths and gaps follow the transmitted times, and a vertical marker indicates the current time. Selecting a program opens its title and full date/time range; it does not schedule a recording or change channels.

The interface initially shows **Reading broadcast schedule…**. If no usable schedule arrives within 25 seconds, it shows **Schedule unavailable**, while continuing to listen for later updates. An event with an unsupported or missing title uses **Title unavailable**. Broadcast titles retain their original language; interface labels are localized in English, Spanish and French.

## Decoder

`ProgramGuideDecoder` implements the relevant uncompressed-text paths of [ATSC A/65:2013](https://www.atsc.org/wp-content/uploads/2021/04/A65_2013.pdf):

- MGT discovers the EIT packet identifiers.
- VCT maps the selected virtual channel number to a source ID in the current transport.
- STT supplies the GPS/UTC offset used to convert event timestamps.
- EIT supplies event IDs, start times, durations and multilingual titles.

Complete sections require valid MPEG CRCs and the current-table flag. The reader handles arbitrary pipe chunking, pointer fields, adaptation fields, duplicate packets and continuity loss. Table versions replace canceled or changed events within the relevant EIT PID/source, independently of other future slots.

The decoder does not guess a source ID or assume a fixed GPS/UTC offset. Until both mapping and clock information arrive, events are withheld rather than assigned to another channel or shown at an incorrect time. Event dates use the Mac's local time zone for presentation.

A decoder belongs to one tuned transport and is discarded on retuning. Only metadata PIDs are assembled. Bounds include 4096-byte sections, 256 stored EIT sections, 256 channel mappings and 256 displayed event candidates within 48 hours. The timeline displays the first six-hour window from the current program’s start, omitting expired programs and empty earlier hours. Nothing in this pipeline writes video to disk.

## Scope and limitations

Reception and schedule availability depend on the station. Only the currently tuned frequency is read; Antena does not interrupt viewing to collect listings from other frequencies. There is no cross-channel persistent guide cache, scheduled recording or Internet fallback.

Supported title encodings include uncompressed Unicode-page modes and big-endian UTF-16. Huffman-compressed titles, SCSU and extended ETT descriptions are not decoded in this version. Unsupported text is not displayed as corrupted characters. A station can provide valid times without a decodable title.

The guide is for live television. Saved recordings do not currently feed this metadata reader. Caption/audio language selection is independent of the program guide.

## Validation

```sh
make test
```

`Tests/ProgramGuideTests.swift` checks MGT/VCT/EIT/STT discovery, GPS-to-UTC conversion, current/next events, channel isolation, changed and canceled events, invalid CRCs, split sections, continuity loss, language preference, Unicode text, fresh-tune isolation and malformed transport input. It uses deterministic synthetic metadata and does not need the USB device. The existing firmware check still requires the local firmware dependency.

Live integration was also observed on CBC Montréal (6.1, 515 MHz), displaying titles including “Cirque Life”, “Dragons' Den” and “Fridge Wars” from the received EIT. This observation confirms that metadata reached the interface for that broadcast; it does not guarantee availability on every station.

With the optional `--diagnostics` argument, the app's JSON includes a `guide` object containing table counts, source count, clock availability, unsupported-title and CRC counts, and decoded program timestamps. This is metadata diagnostics, not a video recording.
