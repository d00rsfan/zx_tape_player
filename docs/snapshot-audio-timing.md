# Snapshot audio timing reference

This document records the timing contract used to play `.z80` and `.sna`
snapshots. It also separates four frequencies that are easy to confuse:

1. the 3.5 MHz ZX Spectrum CPU clock used to express T-states;
2. the frequency of an audible signal, such as the pilot tone;
3. the sample rate written into a generated WAV file; and
4. the active Android output/mixer/DAC sample rate.

The first two describe the loading protocol. The last two describe how that
protocol is represented and played. The same snapshot profile can have
different data rates at 48 kHz and 44.1 kHz because the renderer rounds each
pulse to whole PCM frames at the selected rate.

## Current encoding paths

| Input path | WAV source format | Encoder | Filters |
| --- | --- | --- | --- |
| TAP/TZX | Selectable 48,000 Hz (default) or 44,100 Hz | `zx_tape_to_wav_x` through `ZxTape.toWavBytesWithBlocks` | Selected tape filter is applied |
| Raw ZX80/ZX81 tape images | Selectable 48,000 Hz (default) or 44,100 Hz | `zx_tape_to_wav_x` through `WavBuilder` | Selected tape filter is applied |
| Z80/SNA snapshot | Selectable 48,000 Hz (default) or 44,100 Hz, unsigned 8-bit mono | Dedicated snapshot edge renderer | Tape filter selection is ignored |

The global sample-rate setting applies to tape and snapshot WAVs. The two
snapshot bootstrap blocks are rendered at that rate and are loaded by the
Spectrum ROM. [Tape conversion](../lib/services/tape_conversion_service.dart)
[Snapshot renderer](../lib/snapshots/snapshot_renderer.dart).

## Snapshot quantization rule

All requested pulse durations use a nominal 3,500,000 Hz Spectrum clock. Each
edge is converted independently to a whole number of PCM frames at the
selected sample rate:

```text
frames = ceil(T-states * sample rate / 3,500,000)
48 kHz:   1 frame = 20.833333 us = 72.916667 T-states
44.1 kHz: 1 frame = 22.675737 us = 79.365079 T-states
```

Each edge rounds up independently, reproducing the upstream ZQLoader
quantization rule. The rounding error can be a large fraction of a short pulse.

The PCM levels are `0` and `255`. Every pulse ends by toggling the level. A
pause holds the current level, and phase is continuous across pilots, sync,
header, payload, and block boundaries. Standard polarity starts at level `0`.
Settings offers **Invert polarity** below the audio filters (snapshots only). When it is
checked, rendering starts at `255` and complements every PCM sample of the
complete stream—including the ROM bootstrap, receiver, pauses, and turbo
blocks—without moving an edge or changing a block offset. Polarity and sample
rate are part of the deterministic cache identity, so WAV files produced with
different signal settings cannot be confused.

After the final data edge, the renderer holds its new level for 2 ms, rounded
up to a whole PCM frame (96 frames at 48 kHz or 89 at 44.1 kHz). This gives
the EAR input time to register the transition. The renderer then writes one
neutral unsigned-PCM frame (`128` in standard polarity, `127`
in the exactly complemented stream). If the resulting `data` chunk is odd,
the RIFF container receives a zero pad byte which is not counted as audio or as
part of the last logical block.

## ROM-compatible snapshot bootstrap

These are the two TAP blocks that install the snapshot receiver. The pilot and
sync use standard ROM timing. Data uses the faster ZQLoader 700/1400-T
timing with two pulses per bit. Effective T-states are calculated as
`frames × 3,500,000 / sample rate`.

| Element | Requested edge | 48 kHz frames / effective T | 44.1 kHz frames / effective T |
| --- | ---: | ---: | ---: |
| Pilot half-wave | 2168 T | 30 / 2187.5 T | 28 / 2222.2 T |
| Sync 1 | 667 T | 10 / 729.2 T | 9 / 714.3 T |
| Sync 2 | 735 T | 11 / 802.1 T | 10 / 793.7 T |
| Quick zero half-wave | 700 T | 10 / 729.2 T | 9 / 714.3 T |
| Quick one half-wave | 1400 T | 20 / 1458.3 T | 18 / 1428.6 T |

The 2168-T pilot is ideally 807.196 Hz. It renders at 800.000 Hz at 48 kHz
and 787.500 Hz at 44.1 kHz. Both rates use the same cycle counts, calculated
by rounding down the requested duration to whole cycles. The 44.1 kHz pilots
take about 52 ms longer in total.

| Bootstrap part | Requested pilot duration | Encoded cycles | 48 kHz pilot | 44.1 kHz pilot |
| --- | ---: | ---: | ---: | ---: |
| Snapshot bootstrap/header | 1750 ms | 1412 | 1765.000 ms | 1793.016 ms |
| Snapshot receiver/data | 1500 ms | 1210 | 1512.500 ms | 1536.508 ms |

## Turbo stream

The leader, syncs, header, and payload use one of eight signal-speed profiles.
The fastest profile retains the original 91/231-T data timing. Turbo header
and payload bits are MSB-first and use **one edge per bit**. Tables identify
each profile by the labels shown in the player at 48 kHz and 44.1 kHz.

### Profile-scaled turbo acquisition

Every turbo leader contains exactly **1,400 half-wave pulses**, independent of
the selected speed. Slower presets widen each pulse, so the elapsed leader
duration grows while its edge count remains constant. The first sync occupies
half a leader pulse, rounded upward when the leader has an odd number of PCM
frames. The second/header sync and payload mini-sync have the same PCM width as
the leader pulse. This wider separation gives the receiver a clearer
leader-to-sync transition.

The requested T-states and acquisition limits apply at both sample rates.
Pulse columns list the leader half-wave, sync 1, sync 2, and payload
mini-sync in that order.

| Player labels at 48 / 44.1 kHz | Requested pulses (T-states) | Receiver `LEADER_MAX/MIN/SYNC_MIN` | Patched leader/sync `CP` bytes |
| --- | ---: | ---: | ---: |
| 11.3x / 12.6x | 500 / 250 / 499 / 501 | 13/8/4 | 7/11 |
| 6.9x / 6.5x | 729 / 364 / 729 / 729 | 19/13/5 | 8/16 |
| 5.7x / 5.3x | 1020 / 510 / 1020 / 1020 | 26/18/8 | 10/20 |
| 4.6x / 4.6x | 1239 / 619 / 1239 / 1239 | 32/23/11 | 11/23 |
| 3.3x / 3.2x | 1677 / 838 / 1677 / 1677 | 45/32/16 | 15/31 |
| 2.8x / 2.7x | 2041 / 1020 / 2041 / 2041 | 55/39/19 | 18/38 |
| 2.3x / 2.2x | 2552 / 1276 / 2552 / 2552 | 68/49/25 | 21/45 |
| 1.1x / 1.1x | 5104 / 2552 / 5104 / 5104 | 137/100/51 | 39/88 |

The last column contains the actual immediates used by the assembly expressions
`LEADER_MAX + 2 - LEADER_MIN` and
`LEADER_MAX + 2 - SYNC_MIN`. The first and second `LEADER_MAX` operands are
also patched. Both header and payload mini-sync waits use 255 instead of the
asset's original 200 timeout.

For a leader with `N` frames per half-wave, its square-wave frequency is
`sample rate / (2 × N)` and the full leader lasts `1,400 × N / sample rate`
seconds. Each sync is a single pulse with a duration of `frames / sample rate`.

| Player labels at 48 / 44.1 kHz | 48 kHz pulses (frames) | 44.1 kHz pulses (frames) | 48 kHz leader (Hz / ms) | 44.1 kHz leader (Hz / ms) |
| --- | ---: | ---: | ---: | ---: |
| 11.3x / 12.6x | 7 / 4 / 7 / 7 | 7 / 4 / 7 / 7 | 3428.571 / 204.167 | 3150.000 / 222.222 |
| 6.9x / 6.5x | 10 / 5 / 10 / 10 | 10 / 5 / 10 / 10 | 2400.000 / 291.667 | 2205.000 / 317.460 |
| 5.7x / 5.3x | 14 / 7 / 14 / 14 | 13 / 7 / 13 / 13 | 1714.286 / 408.333 | 1696.154 / 412.698 |
| 4.6x / 4.6x | 17 / 9 / 17 / 17 | 16 / 8 / 16 / 16 | 1411.765 / 495.833 | 1378.125 / 507.937 |
| 3.3x / 3.2x | 23 / 12 / 23 / 23 | 22 / 11 / 22 / 22 | 1043.478 / 670.833 | 1002.273 / 698.413 |
| 2.8x / 2.7x | 28 / 14 / 28 / 28 | 26 / 13 / 26 / 26 | 857.143 / 816.667 | 848.077 / 825.397 |
| 2.3x / 2.2x | 35 / 18 / 35 / 35 | 33 / 17 / 33 / 33 | 685.714 / 1020.833 | 668.182 / 1047.619 |
| 1.1x / 1.1x | 70 / 35 / 70 / 70 | 65 / 33 / 65 / 65 | 342.857 / 2041.667 | 339.231 / 2063.492 |

The stream pauses for 100 ms before the first turbo block. Later pauses use an
estimate of the preceding block's copy or RLE processing time.

Each sync 1 request is the integer half of its leader request. For every
current profile at either sample rate, its physical width is
`ceil(leader frames / 2)`. The fastest profile's 250-T sync 1 takes four
frames at both rates, or 83.333 µs at 48 kHz and 90.703 µs at 44.1 kHz.
The 48 kHz River Raid test used the four-frame sync and the revised data
threshold.

### Signal speeds at both WAV sample rates

The speed badge displays the balanced turbo data rate relative to standard ROM
loading, rounded to one decimal place. The ROM baseline is 20,520 T-states
for four zeros and four ones, with two pulses per bit.
[Timing catalog](../lib/snapshots/snapshot_timing.dart).

The renderer adds 64 T-states to the first bit of every byte after the first
byte of each header or payload. It adds this interval before rounding the bit
to whole frames. The speed calculation averages the two possible first-bit
values in a later byte using `F(T) = ceil(T × sample rate / 3,500,000)`.

```text
balanced byte frames = (7 × (F(zero) + F(one)) + F(zero + 64) + F(one + 64)) / 2
balanced bitrate = 8 × sample rate / balanced byte frames
speed multiplier = 20,520 × sample rate / (3,500,000 × balanced byte frames)
```

For all current profiles at 48 kHz, the 64-T interval adds one frame
regardless of the bit value. At 44.1 kHz the increment can be zero or one
frame, which is why some average byte lengths below are fractional.

| 48 kHz label | 48 kHz frames/byte | 48 kHz kbit/s | 44.1 kHz label | 44.1 kHz frames/byte | 44.1 kHz kbit/s |
| --- | ---: | ---: | --- | ---: | ---: |
| 11.3x | 25 | 15.360 | 12.6x | 20.5 | 17.210 |
| 6.9x | 41 | 9.366 | 6.5x | 40 | 8.820 |
| 5.7x (default) | 49 | 7.837 | 5.3x (default) | 49 | 7.200 |
| 4.6x | 61 | 6.295 | 4.6x | 56.5 | 6.244 |
| 3.3x | 85 | 4.518 | 3.2x | 80.5 | 4.383 |
| 2.8x | 101 | 3.802 | 2.7x | 97 | 3.637 |
| 2.3x | 125 | 3.072 | 2.2x | 117 | 3.015 |
| 1.1x | 249 | 1.542 | 1.1x | 233 | 1.514 |

At 44.1 kHz, only the fastest profile gains balanced data throughput. Its
ordinary one pulse drops from four frames to three. The default profile uses
49 frames per balanced later byte at both rates, so the longer 44.1 kHz
frames reduce its bitrate. The 4.6x and 1.1x labels coincide after rounding
even though their bitrates differ. Full WAV duration also includes the ROM
bootstrap, leader and sync pulses, processing pauses, and the actual bit mix
of each encoded block. See the [fixture durations](#representative-deterministic-metadata)
for full-stream examples.

The catalog revision is `snapshot-turbo-speeds-v0`. Each timing profile has
an internal identifier used in saved settings and cache keys. The cache key
also records the polarity, sample rate, WAV profile, and timing fingerprint.
[Snapshot cache](../lib/services/snapshot_cache_service.dart).

## What the Z80 receiver actually measures

The receiver does not measure Hertz. It repeatedly reads the EAR input and
classifies the number of polling iterations before the next edge.

There are two different polling loops:

| Receiver section | Interval | Purpose |
| --- | ---: | --- |
| `WAIT_FOR_EDGE` | 43 T between reads | Leader, sync, and mini-sync acquisition |
| Inline turbo data loop | 40 T between later reads | Header and payload bit classification |

The assembly comment that labels the inline loop as 43 T is stale. Its
instructions total 40 T because it uses `AND E` instead of the immediate-mask
instruction in `WAIT_FOR_EDGE`. Upstream `loader_defaults.h` also records 40 T.

The first EAR read is nominally 91 T after the previous detected edge, plus
64 T at a byte boundary. Later reads are 40 T apart. The receiver is patched
from the selected catalog entry.

| Parameter | Current value | Meaning |
| --- | ---: | --- |
| `BIT_LOOP_MAX` | 255 | Maximum nonzero byte timeout used by all profiles |
| `ZERO_MAX` | speed value, 3–59 | Latest poll classified as zero |
| `BIT_ONE_THRESHOLD` | 252–196 | Patched as `BIT_LOOP_MAX - ZERO_MAX`; a later edge is one |
| `IO_INIT` | `0x0a` | Initial EAR/border state |
| `IO_XOR` | `0x47` | Toggles remembered EAR state and border colour |

The profile also patches the acquisition loop. The catalog checks every phase
of the 43-T acquisition loop at 90%, 100%, and 110% of nominal signal speed
for both sample rates. It checks the 40-T data loop at nominal speed for
ordinary bits and byte-boundary bits. [Timing tests](../test/snapshots/snapshot_timing_test.dart).

| Receiver operand | Current values | Meaning |
| --- | --- | --- |
| both `LEADER_MAX` loads | 13–137 | Timeout/upper leader-pulse window |
| both leader-minimum comparisons | 7–39 | Encodes `LEADER_MAX + 2 - LEADER_MIN` |
| sync-minimum comparison | 11–88 | Encodes `LEADER_MAX + 2 - SYNC_MIN` |
| header/payload mini-sync timeout | 255 | Longest valid nonzero 8-bit wait |

The fastest profile uses `LEADER_MAX = 13` at both rates. The old value of
12 rejected the seven-frame 44.1 kHz leader at the slow boundary of the model.
The assets still contain the original acquisition bytes
`12/6/12/10/6/200`. The Dart patcher replaces the operands in the selected
48K or 128K receiver and recalculates the second TAP block's XOR checksum.

During turbo leader acquisition the intended border stripes are red/cyan.
After sync recognition, data loading changes them to blue/yellow. If the
border never leaves the leader colours, the receiver has not accepted the
leader-to-sync transition.

### Slowest receiver rates and byte-width limits

Requested acquisition/data T-states and inter-block pauses exist only in the
host WAV generator; they are not stored in the 18-byte turbo header. Matching
classification limits are patched directly into immediate operands in the
receiver machine code. The 1.1x profile's zero and one edges take 37–38 and
73–74 data polls at 48 kHz, and 38–39 and 74–75 polls at 44.1 kHz. The
timeout is 255 polls.

The Z80 loop uses 8-bit registers D and B. The largest meaningful patched
`BIT_LOOP_MAX` is therefore 255; zero is not a usable encoding for 256 because
the loader also uses D to force a successful nonzero return. Sweeping all 40
relative polling phases at 48 kHz gives these code-only limits:

| Receiver configuration | Pulse relationship | Zero/one request | Zero/one frames | `ZERO_MAX` / patched threshold | Balanced frames | Effective rate |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Previous `BIT_LOOP_MAX = 100` | exact 1:2 | 1931/3891 T | 27/54 | 78 / 22 | 325 | 7.69% |
| Previous `BIT_LOOP_MAX = 100` | narrowest separable classes | 3811/3891 T | 53/54 | 96 / 4 | 429 | 5.83% |
| Current maximum byte value 255 | exact 1:2 | 4971/10011 T | 69/138 | 204 / 51 | 829 | 3.02% |
| Current maximum byte value 255 | narrowest separable classes | 10011/10091 T | 138/139 | 251 / 4 | 1109 | 2.25% |

Each candidate also leaves one additional PCM frame for the 64-T byte-boundary
delay. The narrowest-class rows have only one receiver-poll count between zero
and one, so they are mathematical limits rather than sensible analogue
hardware profiles. With the current 255 receiver timeout and the catalog's 1:2
shape, approximately 3.02% of the 91/231-T maximum is the slowest theoretical
data profile. The 1.1x profile is about 10% of that maximum at 48 kHz and is
well above the code-only boundary. Raising the timeout from 100 to 255 changes
runtime receiver patches and cache identity but does not require recompiling
the Z80 asset.

## Historical speed tolerance with a three-poll zero limit

For the previous 48 kHz receiver threshold of 252, the conservative code-only
playback-speed range is approximately:

```text
0.853x to 1.126x nominal speed
-14.7% to +12.6%
```

This range accounts for arbitrary phase between a signal edge and the
receiver's 40/43-T polling grids. If playback speed is `s`, a generated pulse
of `P` T-states is observed as `P / s` T-states.

| Limiter | Quantized pulse at 48 kHz | Phase-safe receiver window | Allowed playback speed |
| --- | ---: | ---: | ---: |
| Leader | 510.417 T | 431–643 T | 0.794x–1.184x, or −20.6% to +18.4% |
| Sync (half-leader, four-frame value) | 291.667 T | 259–388 T | 0.752x–1.126x, or −24.8% to **+12.6%** |
| Zero | 145.833 T | no more than 171 T | at least 0.853x, or **not slower than −14.7%** |
| One | 291.667 T | at least 211 T | no more than 1.382x, or not faster than +38.2% |

The intersection of all four constraints is 0.853x–1.126x for the 91/231-T
profile at 48 kHz with the old threshold. Slow playback is limited by zero
classification. Fast playback is limited by the minimum width of sync 1.

The calculation covers the custom turbo receiver's polling loops. Hardware
results also depend on Android/DAC filtering and resampling, analogue EAR
threshold behaviour, ULA I/O contention, noise, and the initial ROM-loaded
bootstrap.

## Receiver and restored-state correctness revision

The committed receivers are built from ZQLoader revision `a6fdb6a` plus the
reviewed patch in [`tool/snapshot_receiver`](../tool/snapshot_receiver/). The
wire header now contains 17 state bytes and an 18th check byte. Its add/rotate
checksum residue must be zero before the receiver reads a length, address,
compression mode, bank command, or execution address.

After `CopyLoader` replaces the BASIC stack, an error can no longer safely
print through ROM and return to BASIC. The revised receiver stops with a stable
border instead: red for payload checksum failure, magenta for timeout or bad
header, and yellow for an invalid return request. Errors before relocation
retain the original printable BASIC-return path.

The register-restoration blob executes nine M1 fetches after `LD R,A` and
before entering the saved PC. The host therefore stores `R - 9` in the low
seven bits, preserving bit 7; a Z80 instruction emulator confirms that a saved
`R = 0xaa` arrives at the target as `0xaa`, rather than the previous `0xb3`.
Because the blob cannot independently reproduce unequal IFF1/IFF2 values,
those Z80 snapshots are rejected. Z80 v1 SamRom state is rejected for the same
reason: the base receiver cannot restore that ROM state.

For 128K SNA files whose current bank is 2 or 5, both serialized copies of that
physical RAM bank must agree. A contradictory file is rejected rather than
silently selecting one copy. The final upper-memory overwrite is always raw:
RLE expansion there would destroy the receiver's live RLE metadata before the
operation completed.

### Loader scratch footprint

The receiver necessarily leaves a temporary code/staging/register footprint
in RAM when it transfers control. Automatic placement uses only a sufficiently
long all-zero fixed-RAM run and now excludes the saved PC instruction, next SP
word, and the full IM2 vector page. If no such run exists, the established
screen fallback is used; if that fallback intersects one of those critical
ranges, conversion fails instead of emitting a stream known to be unsafe.

This is still not bit-for-bit restoration of every RAM byte: normally the
footprint replaces bytes that were all zero; the fallback replaces part of the
display. Tests compare all RAM outside this documented footprint and the full
normalized CPU/paging state. Eliminating the footprint completely would
require a different self-erasing final-stage receiver, not another host-side
range split.

## How upstream tuning adapts the loader

Upstream ZQLoader does not compile one Z80 receiver for every data setting. It
has two machine variants, one for 48K and one for 128K, plus exported data-patch
locations. ZX Tape Player bundles one reviewed receiver revision per machine.
At runtime the host patches a copy of the selected TAP asset and recalculates
its TAP checksum. The acquisition constants were compile-time values upstream;
the Dart port adds their integrity-pinned operand addresses to its local
receiver manifest and patches those existing instructions without producing a
different compiled receiver for every speed.

The host-side signal generator controls sample rate and requested zero/one
edge durations. The receiver-side patch controls the zero/one threshold,
timeout, I/O values, and relocation addresses. Consequently:

- changing PCM sample rate does not require a new receiver binary; the host
  re-quantizes the waveform and applies the catalog's validated receiver
  thresholds;
- changing zero/one timing can be paired with a receiver threshold patch;
- the current Dart port keeps fixed 48K/128K assets and patches them to
  `BIT_LOOP_MAX = 255`, the selected data threshold (252–196), selected
  leader/sync windows, mini-sync timeout 255, `0x0a`, and `0x47` in
  [`snapshot_restore_planner.dart`](../lib/snapshots/snapshot_restore_planner.dart).

Upstream direct playback defaults to the audio device's native rate
(`samplerate=0`), while its WAV writer defaults to 48 kHz. The Dart port writes
a deterministic snapshot WAV at the selected 48 kHz or 44.1 kHz source rate
and then asks `just_audio` to play that file.

## Source WAV rate versus Android/DAC rate

On Android, the current app gives the WAV file to `just_audio` with
`setFilePath`. The pinned Android implementation uses Media3 ExoPlayer. The app
does not create its own `AudioTrack`, query
`AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`, or request a bit-perfect mixer
format.

The resulting path is conceptually:

```text
44.1 or 48 kHz WAV
    -> Media3 WAV decoder / PCM track
    -> Android mixer and optional sample-rate converter
    -> active output route and audio HAL
    -> DAC or digital/Bluetooth/USB device
```

Android documents 44.1 kHz source audio being resampled to a 48 kHz internal
sink as a normal case. Its native/optimal low-latency output property commonly
reports 44,100 or 48,000 Hz; other values are possible. That property describes
the device's native or optimal low-latency stream, not a guarantee that every
active route, mixer, Bluetooth codec, USB adapter, and physical DAC is using
the same rate.

Therefore the exact output and DAC rate of the user's phone cannot be inferred
from this repository. The current app neither records nor exposes it, and the
rate can change with the selected output route.

Official Android references:

- [Sample rate conversion in Android](https://source.android.com/docs/core/audio/src)
- [`AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`](https://developer.android.com/reference/android/media/AudioManager#PROPERTY_OUTPUT_SAMPLE_RATE)
- [Android audio latency guidance](https://developer.android.com/ndk/guides/audio/audio-latency)

The app pins its `just_audio` fork at version 0.10.6. [Dependency lockfile](../pubspec.lock).

## 48 kHz versus 44.1 kHz at the Z80 receiver

The sample rate sets the PCM edge grid. The Z80 receiver sees the resulting
EAR transition after some number of 43-T acquisition polls or 40-T data polls.
The following tables describe the generated PCM before Android resampling,
reconstruction filtering, cable distortion, or EAR threshold shift.

Each `frames / effective T` entry applies the executable ceiling rule from the
start of this document. The effective duration is
`frames × 3,500,000 / sample-rate`; it is what a nominal 3.5 MHz Spectrum sees
if the analogue edge lands at the PCM transition.

### Turbo acquisition in effective CPU T-states

The pulse order matches the [acquisition frame table](#profile-scaled-turbo-acquisition).
Sync 2 and the payload mini-sync have the same effective width as the leader
half-wave.

| Player labels at 48 / 44.1 kHz | 48 kHz leader / sync 1 (T-states) | 44.1 kHz leader / sync 1 (T-states) |
| --- | ---: | ---: |
| 11.3x / 12.6x | 510.4 / 291.7 | 555.6 / 317.5 |
| 6.9x / 6.5x | 729.2 / 364.6 | 793.7 / 396.8 |
| 5.7x / 5.3x | 1020.8 / 510.4 | 1031.7 / 555.6 |
| 4.6x / 4.6x | 1239.6 / 656.3 | 1269.8 / 634.9 |
| 3.3x / 3.2x | 1677.1 / 875.0 | 1746.0 / 873.0 |
| 2.8x / 2.7x | 2041.7 / 1020.8 | 2063.5 / 1031.7 |
| 2.3x / 2.2x | 2552.1 / 1312.5 | 2619.0 / 1349.2 |
| 1.1x / 1.1x | 5104.2 / 2552.1 | 5158.7 / 2619.0 |

### Turbo data in PCM frames and CPU T-states

Pulse and frequency cells list zero first and one second. The square-wave
frequencies describe repetitions of the same ordinary bit pulse. They use
`sample rate / (2 × frames)` because a full cycle takes two half-waves. The
64-T byte-boundary delay is included separately in the balanced bitrate.

| Player labels at 48 / 44.1 kHz | Requested zero / one | 48 kHz frames / effective T | 44.1 kHz frames / effective T | 48 kHz repeated zero / one (Hz) | 44.1 kHz repeated zero / one (Hz) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 11.3x / 12.6x | 91 / 231 T | 2 / 145.8 T and 4 / 291.7 T | 2 / 158.7 T and 3 / 238.1 T | 12000.000 / 6000.000 | 11025.000 / 7350.000 |
| 6.9x / 6.5x | 250 / 411 T | 4 / 291.7 T and 6 / 437.5 T | 4 / 317.5 T and 6 / 476.2 T | 6000.000 / 4000.000 | 5512.500 / 3675.000 |
| 5.7x / 5.3x | 291 / 571 T | 4 / 291.7 T and 8 / 583.3 T | 4 / 317.5 T and 8 / 634.9 T | 6000.000 / 3000.000 | 5512.500 / 2756.250 |
| 4.6x / 4.6x | 331 / 691 T | 5 / 364.6 T and 10 / 729.2 T | 5 / 396.8 T and 9 / 714.3 T | 4800.000 / 2400.000 | 4410.000 / 2450.000 |
| 3.3x / 3.2x | 491 / 1011 T | 7 / 510.4 T and 14 / 1020.8 T | 7 / 555.6 T and 13 / 1031.7 T | 3428.571 / 1714.286 | 3150.000 / 1696.154 |
| 2.8x / 2.7x | 571 / 1211 T | 8 / 583.3 T and 17 / 1239.6 T | 8 / 634.9 T and 16 / 1269.8 T | 3000.000 / 1411.765 | 2756.250 / 1378.125 |
| 2.3x / 2.2x | 691 / 1531 T | 10 / 729.2 T and 21 / 1531.3 T | 9 / 714.3 T and 20 / 1587.3 T | 2400.000 / 1142.857 | 2450.000 / 1102.500 |
| 1.1x / 1.1x | 1531 / 2971 T | 21 / 1531.3 T and 41 / 2989.6 T | 20 / 1587.3 T and 38 / 3015.9 T | 1142.857 / 585.366 | 1102.500 / 580.263 |

At the fastest setting, the zero pulse takes two frames at each rate, so it
gets longer at 44.1 kHz. The one pulse drops from four frames to three and
gets shorter. This independent rounding also affects the leader and sync
pulses.

### What the receiver classifies

Acquisition values below are zero-based poll indices, matching the timing
simulation. The valid leader window is `LEADER_MIN - 1` through
`LEADER_MAX - 1`; the valid sync window is `SYNC_MIN - 1` through
`LEADER_MIN - 2`.

| Player labels at 48 / 44.1 kHz | Valid leader / sync indices | Observed at 48 kHz | Observed at 44.1 kHz |
| --- | ---: | ---: | ---: |
| 11.3x / 12.6x | 7–12 / 3–6 | 8–9 / 3–4 | 9–10 / 4–5 |
| 6.9x / 6.5x | 12–18 / 4–11 | 13–15 / 5–6 | 15–16 / 6–7 |
| 5.7x / 5.3x | 17–25 / 7–16 | 20–21 / 8–9 | 20–22 / 9–10 |
| 4.6x / 4.6x | 22–31 / 10–21 | 25–26 / 12–13 | 26–27 / 11–12 |
| 3.3x / 3.2x | 31–44 / 15–30 | 36–37 / 17–18 | 37–38 / 17–18 |
| 2.8x / 2.7x | 38–54 / 18–37 | 44–45 / 20–21 | 44–46 / 20–21 |
| 2.3x / 2.2x | 48–67 / 24–47 | 56–57 / 27–28 | 57–58 / 28–29 |
| 1.1x / 1.1x | 99–136 / 50–98 | 115–116 / 56–57 | 116–118 / 57–58 |

Data values are one-based poll counts collected over every phase of the 40-T
loop and both ordinary and byte-boundary paths. A value no greater than
`ZERO_MAX` is zero; a later edge is one.

| Player labels at 48 / 44.1 kHz | 48 kHz `ZERO_MAX` / patched threshold | 44.1 kHz `ZERO_MAX` / patched threshold | Zero / one polls at 48 kHz | Zero / one polls at 44.1 kHz |
| --- | ---: | ---: | ---: | ---: |
| 11.3x / 12.6x | 4 / 251 | 3 / 252 | 2–3 / 6–7 | 1–3 / 4–6 |
| 6.9x / 6.5x | 7 / 248 | 7 / 248 | 6–7 / 9–10 | 5–7 / 9–11 |
| 5.7x / 5.3x | 9 / 246 | 9 / 246 | 6–7 / 13–14 | 6–8 / 14–15 |
| 4.6x / 4.6x | 12 / 243 | 12 / 243 | 7–9 / 16–18 | 7–9 / 16–17 |
| 3.3x / 3.2x | 18 / 237 | 18 / 237 | 11–12 / 24–25 | 11–13 / 24–25 |
| 2.8x / 2.7x | 21 / 234 | 21 / 234 | 13–14 / 29–30 | 14–15 / 30–31 |
| 2.3x / 2.2x | 28 / 227 | 28 / 227 | 16–18 / 37–38 | 16–17 / 38–39 |
| 1.1x / 1.1x | 59 / 196 | 59 / 196 | 37–38 / 73–74 | 38–39 / 74–75 |

At 44.1 kHz and 12.6x, zero can arrive on poll 3 and one can arrive on
poll 4, so the receiver uses `ZERO_MAX = 3`. At 48 kHz and 11.3x, one first
appears on poll 6 in the model, and the receiver uses `ZERO_MAX = 4`. In a
48 kHz Spectrum Next test, River Raid failed its second payload checksum
with the three-poll limit and loaded with the four-poll limit. The default
profile has a larger gap between zero and one polls at both rates.

In a separate 48 kHz River Raid test, the four-frame zero used by the 6.9x
profile loaded at the initial volume. With the same receiver threshold,
the earlier three-frame zero loaded after a small volume increase.

No conventional audio rate represents every requested duration exactly. The
catalog contains coprime T-state values, so exact per-edge integer mapping
would require at least one PCM frame per CPU T-state, or 3.5 MHz. Fractional
error accumulation could reproduce the average duration at a normal audio
rate by alternating adjacent frame counts, but the current renderer
deliberately restarts ceiling quantization at every edge.

## Duty cycle, polarity, and edge asymmetry

For a repeated pilot or leader, the generated digital high and low halves are
exactly 1:1 because both use the same requested duration and frame count.
Standard versus inverted polarity complements every `0`/`255` sample without
moving an edge. The Spectrum border is a decoder indication, not a measurement
of the analogue waveform at the EAR socket; unequal-looking stripe widths do
not by themselves prove unequal electrical duty cycle.

The table shows the granularity of any hypothetical integer-frame duty
adjustment. “Half-width step” is one frame as a percentage of one leader half.
For an equal `N + N` leader period, moving one frame from one half to the other
changes duty by `50/N` percentage points. The zero column shows why data is
still more sensitive than the leader.

| Player labels at 48 / 44.1 kHz | Leader frames 48 / 44.1 | One-frame half-width step | Equal-leader duty step | Zero frames 48 / 44.1 | One-frame zero-width step |
| --- | ---: | ---: | ---: | ---: | ---: |
| 11.3x / 12.6x | 7 / 7 | 14.29% / 14.29% | ±7.14 / ±7.14 pp | 2 / 2 | 50.00% / 50.00% |
| 6.9x / 6.5x | 10 / 10 | 10.00% / 10.00% | ±5.00 / ±5.00 pp | 4 / 4 | 25.00% / 25.00% |
| 5.7x / 5.3x | 14 / 13 | 7.14% / 7.69% | ±3.57 / ±3.85 pp | 4 / 4 | 25.00% / 25.00% |
| 4.6x / 4.6x | 17 / 16 | 5.88% / 6.25% | ±2.94 / ±3.13 pp | 5 / 5 | 20.00% / 20.00% |
| 3.3x / 3.2x | 23 / 22 | 4.35% / 4.55% | ±2.17 / ±2.27 pp | 7 / 7 | 14.29% / 14.29% |
| 2.8x / 2.7x | 28 / 26 | 3.57% / 3.85% | ±1.79 / ±1.92 pp | 8 / 8 | 12.50% / 12.50% |
| 2.3x / 2.2x | 35 / 33 | 2.86% / 3.03% | ±1.43 / ±1.52 pp | 10 / 9 | 10.00% / 11.11% |
| 1.1x / 1.1x | 70 / 65 | 1.43% / 1.54% | ±0.71 / ±0.77 pp | 21 / 20 | 4.76% / 5.00% |

A 1% per-edge duty adjustment is therefore not directly representable at
either rate. It would require fractional-error accumulation or a later
resampling stage. An analogue path can nevertheless move rising and falling
threshold crossings in opposite directions. That makes alternating intervals
effectively longer and shorter even though the source is exactly 50:50; an
inverted source swaps which electrical half receives each distortion. The risk
increases at higher profiles because one PCM frame and one Z80 poll represent
a larger fraction of the shortest pulse. The adjacent 12.6x data
classes are the clearest current example.

The leader has zero digital duty imbalance: its 1,400 equal half-waves contain
700 high and 700 low intervals. Arbitrary data does not guarantee equal total
time at each level because short and long bit intervals can occur in a
content-dependent order. Consequently, the complete finite stream is not
forced to a mathematically zero DC mean; its final neutral sample terminates
the waveform but does not rebalance preceding data. Adding compensating edges
inside the protocol would itself change what the receiver decodes.

The timing-critical receiver loops execute from uncontended upper RAM:
`0xff38` on 48K and `0xbf38` in fixed bank 2 on 128K. They therefore do not
inherit instruction-fetch delays from 48K screen RAM or odd 128K banks.
Contention or analogue asymmetry can still enter through ULA/EAR I/O and is not
modeled by the fixed 40/43-T simulations above.

## Player selection behavior

On first use, the app uses **48 kHz**, the **5.7x** snapshot profile, and
standard polarity. The sample-rate selector and **Invert polarity** checkbox
live in Settings below the audio filters. Sample rate applies to all
conversions. Polarity inversion applies to snapshots. The settings service
migrates valid `snapshotSignalSettings` preferences to `audioSignalSettings`.
[Settings service](../lib/services/zx_control/zx_settings_service.dart).

The snapshot speed badge and picker use the [labels for the active WAV sample rate](#signal-speeds-at-both-wav-sample-rates).
For ordinary tape media, the badge shows a media-player multiplier and opens
the continuous playback-speed slider.

Changing snapshot speed, polarity, or sample rate stops and rewinds playback,
prepares or reuses a settings-specific WAV/sidecar pair, binds it at position
zero, and remains paused. Active snapshot settings commit only after binding
succeeds. A failed switch restores the previous valid audio when possible.
Global choices made in Settings are saved immediately for subsequent conversions;
a speed change is saved after successful binding and preserves any newer global
frequency/polarity choices made while conversion was in progress.

When snapshot playback completes, the carousel unlocks and the position stays
at the end of the WAV. Snapshot playback starts from the bootstrap and runs
through the restore blocks in order. The player disables seeking to internal
snapshot blocks.

Snapshot media-player speed and Android pitch are **1x for every profile**
and sample rate. The generated waveform determines the signal rate. The app
remembers the ordinary-tape speed and restores it on return to tape media.
Profile and sample rate determine the quantized waveform and runtime receiver
operands. The restore commands and RLE payloads are the same across signal
settings. [Player implementation](../lib/ui/widgets/tape_player/tape_player.dart).

## Representative deterministic metadata

These synthetic fixtures use standard polarity. The metadata test pins the
48 kHz rows. The same converter and fixtures were used to generate the 44.1 kHz
rows. “Turbo frames” counts the leaders, sync, pauses, data, and terminal
tail after the two ROM blocks. Runtime patches can change the bytes in the
second ROM block and therefore its frame length. Logical SHA-256 covers
every turbo header and payload byte. [Metadata test](../test/snapshots/snapshot_profile_metadata_test.dart).

| Fixture | Player label | WAV rate | Total frames | Duration (s) | Turbo frames | Turbo blocks | Threshold | Logical SHA-256 | WAV SHA-256 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 48K Z80 v1 | 11.3x | 48 kHz | 386925 | 8.061 | 119523 | 4 | 251 | `aa66c5f2…38fef` | `7887e951…83fb9` |
| 48K Z80 v1 | 12.6x | 44.1 kHz | 356668 | 8.088 | 110762 | 4 | 252 | `aa66c5f2…38fef` | `f653ddf0…40a89` |
| 48K Z80 v1 | 5.7x | 48 kHz | 450627 | 9.388 | 183305 | 4 | 246 | `aa66c5f2…38fef` | `b882e4e2…27086` |
| 48K Z80 v1 | 5.3x | 44.1 kHz | 419091 | 9.503 | 173257 | 4 | 246 | `aa66c5f2…38fef` | `057d4f31…78036` |
| 128K SNA | 11.3x | 48 kHz | 559926 | 11.665 | 290044 | 9 | 251 | `92a68c9a…10894` | `07f36a45…183a4` |
| 128K SNA | 12.6x | 44.1 kHz | 515435 | 11.688 | 267261 | 9 | 252 | `92a68c9a…10894` | `34e10305…1725d` |
| 128K SNA | 5.7x | 48 kHz | 708301 | 14.756 | 438499 | 9 | 246 | `92a68c9a…10894` | `0d34d378…a7840` |
| 128K SNA | 5.3x | 44.1 kHz | 662647 | 15.026 | 414581 | 9 | 246 | `92a68c9a…10894` | `fc6fd7aa…04f32` |

With the fastest profile, the full WAV is slightly longer at 44.1 kHz for
both fixtures despite the higher balanced data bitrate. The ROM pilots and
turbo leaders take more time at 44.1 kHz, and each fixture's data has its own
mix of zeros and ones.
The hardware notes above refer to the 48K River Raid snapshot played on a
Spectrum Next.

Record these fields for physical acceptance.

| Snapshot/machine | WAV rate, player label, polarity | Leader/sync/data timing | Receiver acquisition/data values | Phone/output route | Cable/volume | Attempts/successes | Starts from bootstrap, paused before start? | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| _fill during test_ | _48 kHz, 2.3x, standard_ | _35/18 leader/sync 1 frames, 10/21 data frames_ | _68/49/25, threshold 227_ | | | | | |

## Source baseline

The app bundles receiver assets built from ZQLoader commit
`a6fdb6a889f0ca4a928c37d030527b577a941793` with the local correctness patch.
The asset documentation records the sjasmplus version, rebuild commands,
and expected hashes. [Receiver asset revision](../tool/snapshot_receiver/README.md).
