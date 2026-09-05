# Snapshot audio timing reference

Status: current implementation and investigation notes, 2026-09-05.

This document records the timing contract used to play `.z80` and `.sna`
snapshots. It also separates four frequencies that are easy to confuse:

1. the 3.5 MHz ZX Spectrum CPU clock used to express T-states;
2. the frequency of an audible signal, such as the pilot tone;
3. the sample rate written into a generated WAV file; and
4. the active Android output/mixer/DAC sample rate.

The first two describe the loading protocol. The last two describe how that
protocol is represented and played. A 48 kHz WAV does **not** contain a 48 kHz
loading tone.

## Current encoding paths

| Input path | WAV source format | Encoder | Filters |
| --- | --- | --- | --- |
| TAP/TZX | 44,100 Hz | `tap_to_wav_x` through `ZxTape.toWavBytesWithBlocks` | Selected tape filter is applied |
| Z80/SNA snapshot | Selectable 48,000 Hz (default) or 44,100 Hz, unsigned 8-bit mono | Dedicated snapshot edge renderer | Tape filter selection is ignored |

The values are set in [`definitions.dart`](../lib/utils/definitions.dart) and
[`snapshot_renderer.dart`](../lib/snapshots/snapshot_renderer.dart). The two
snapshot bootstrap blocks are also rendered by the snapshot renderer, so their
WAV source rate follows the selected snapshot setting even though the Spectrum
loads them through its ROM loader.

## Snapshot quantization rule

All requested pulse durations use a nominal 3,500,000 Hz Spectrum clock. Each
edge is converted independently to a whole number of PCM frames at the
selected sample rate:

```text
frames = ceil(T-states * sample rate / 3,500,000)
48 kHz:   1 frame = 20.833333 us = 72.916667 T-states
44.1 kHz: 1 frame = 22.675737 us = 79.365079 T-states
```

Fractional time is discarded after every edge; it is not carried into the next
edge. This deliberately reproduces the upstream ZQLoader compatibility
behavior. It also means short pulses can become much longer than their nominal
T-state duration.

The PCM levels are `0` and `255`. Every pulse ends by toggling the level. A
pause holds the current level, and phase is continuous across pilots, sync,
header, payload, and block boundaries. Standard polarity starts at level `0`.
The snapshot signal-settings sheet also offers **Invert polarity**. When it is
checked, rendering starts at `255` and complements every PCM sample of the
complete stream—including the ROM bootstrap, receiver, pauses, and turbo
blocks—without moving an edge or changing a block offset. Polarity and sample
rate are part of the deterministic cache identity, so WAV files produced with
different signal settings cannot be confused.

After the final requested pulse duration, the renderer writes one PCM frame at
the post-edge level so the receiver can observe the last data transition. It
then writes one neutral unsigned-PCM frame (`128` in standard polarity, `127`
in the exactly complemented stream). If the resulting `data` chunk is odd,
the RIFF container receives a zero pad byte which is not counted as audio or as
part of the last logical block.

## ROM-compatible snapshot bootstrap

The tables in this section show the default 48 kHz setting. Selecting 44.1 kHz
re-quantizes every edge in the complete stream, including both ROM blocks; it
does not merely change the WAV header.

These are the two TAP blocks that install the snapshot receiver. The pilot and
sync values are standard ROM values, while data uses ZQLoader's faster
700/1400-T variant rather than the standard ROM 855/1710-T data pulses.

| Element | Requested edge | 48 kHz frames | Actual edge | Effective T-states | Useful frequency/rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pilot half-wave | 2168 T | 30 | 625.000 us | 2187.500 T | 800.000 Hz square wave; ideal 807.196 Hz |
| Sync 1 | 667 T | 10 | 208.333 us | 729.167 T | one edge |
| Sync 2 | 735 T | 11 | 229.167 us | 802.083 T | one edge |
| Quick zero, each of two edges | 700 T | 10 | 208.333 us | 729.167 T | 2400 bit/s for repeated zeros |
| Quick one, each of two edges | 1400 T | 20 | 416.667 us | 1458.333 T | 1200 bit/s for repeated ones |

The visible pilot is therefore about 0.89% lower in frequency than the ideal
2168-T pilot. This is caused by independent ceiling to 30 frames, not by a
different requested pilot constant.

| Bootstrap part | Requested pilot setting | Encoded cycles | Actual 48 kHz duration |
| --- | ---: | ---: | ---: |
| Snapshot bootstrap/header | 1750 ms | 1412 | 1765.000 ms |
| Snapshot receiver/data | 1500 ms | 1210 | 1512.500 ms |

## Turbo stream

The original 91/231-T data timing is retained as the maximum **10x preset**.
The complete custom turbo stream—leader, syncs, header, and payload—uses one of
eight reviewed signal-speed presets. The displayed `x` values describe the
nearest supported balanced-payload speed relative to standard tape loading;
independent frame rounding means they are preset names, not exact rates.

Turbo header and payload bits are MSB-first and use **one edge per bit**, not
the two edges per bit used by ROM/TAP data.

### Profile-scaled turbo acquisition

Every turbo leader contains exactly **1,400 half-wave pulses**, independent of
the selected speed. Slower presets widen each pulse, so the elapsed leader
duration grows while its edge count remains constant. The first sync occupies
half a leader pulse, rounded upward when the leader has an odd number of PCM
frames. The second/header sync and payload mini-sync have the same PCM width as
the leader pulse. This wider separation gives the receiver a clearer
leader-to-sync transition.

| Speed | Leader T / frames | Leader frequency | 1,400-pulse duration | Sync 1 T / frames | Header / payload mini-sync | Receiver `LEADER_MAX/MIN/SYNC_MIN` | Patched leader/sync `CP` bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10x | 500 T / 7 f | 3428.571 Hz | 204.167 ms | 250 T / 4 f | 499 / 501 T (7/7 f) | 13/8/4 | 7/11 |
| 7x | 729 T / 10 f | 2400.000 Hz | 291.667 ms | 364 T / 5 f | 729 / 729 T (10/10 f) | 19/13/5 | 8/16 |
| 5x | 1020 T / 14 f | 1714.286 Hz | 408.333 ms | 510 T / 7 f | 1020 / 1020 T (14/14 f) | 26/18/8 | 10/20 |
| 4x | 1239 T / 17 f | 1411.765 Hz | 495.833 ms | 619 T / 9 f | 1239 / 1239 T (17/17 f) | 32/23/11 | 11/23 |
| 3x | 1677 T / 23 f | 1043.478 Hz | 670.833 ms | 838 T / 12 f | 1677 / 1677 T (23/23 f) | 45/32/16 | 15/31 |
| 2.5x | 2041 T / 28 f | 857.143 Hz | 816.667 ms | 1020 T / 14 f | 2041 / 2041 T (28/28 f) | 55/39/19 | 18/38 |
| 2x | 2552 T / 35 f | 685.714 Hz | 1020.833 ms | 1276 T / 18 f | 2552 / 2552 T (35/35 f) | 68/49/25 | 21/45 |
| 1x | 5104 T / 70 f | 342.857 Hz | 2041.667 ms | 2552 T / 35 f | 5104 / 5104 T (70/70 f) | 137/100/51 | 39/88 |

The last column contains the actual immediates used by the assembly expressions
`LEADER_MAX + 2 - LEADER_MIN` and
`LEADER_MAX + 2 - SYNC_MIN`. The first and second `LEADER_MAX` operands are
also patched. Both header and payload mini-sync waits use 255 instead of the
asset's original 200 timeout.

At 1x, the receiver sees a 70-frame leader pulse in 115–116 iterations of its
43-T acquisition loop, depending on phase. This remains comfortably below its
patched `LEADER_MAX` value 137 and the maximum nonzero byte counter 255.

The temporary forced 1000 ms pause minimum was removed on 2026-09-05. The
stream retains its original receiver-processing schedule: 100 ms before the
first turbo block, then an estimate based on the preceding block's copy or RLE
work. No artificial one-second minimum remains.

Each first-sync request is the integer half of its leader request. Independent
ceiling quantization makes the physical width `ceil(leader frames / 2)`, so an
odd-width leader uses the longer of the two nearest integer choices. The 10x
entry therefore restores the upstream 250-T/four-frame sync. The earlier
five-frame 10x experiment did not isolate sync recognition from the same
profile's two/four-frame data pulses, which the tested hardware could not load,
so it is not evidence that a four-frame sync is independently unsuitable.

For the 10x preset, before PCM quantization, a balanced data stream has an
average of 169 T-states
per bit: `(91 + 231) / 2 + 64 / 8`. That is about 20.71 kbit/s. After current
48 kHz quantization, a balanced later byte normally occupies 25 frames: four
2-frame zeros, four 4-frame ones, and one extra frame for byte processing. The
effective balanced rate is therefore about 15.36 kbit/s.

### Selectable signal-speed catalog

The fixed 64-T receiver work interval adds one frame before every byte after
the first. Thus a balanced later byte occupies
`4 × (zero frames + one frames) + 1` frames.

| Label / stable ID | Requested zero/one | Actual zero/one at 48 kHz | Balanced byte | Effective speed | Balanced bitrate | `ZERO_MAX` / threshold |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10x / `10x` | 91/231 T | 2/4 frames (41.667/83.333 us) | 25 frames | 10.00x | 15.360 kbit/s | 3 / 252 |
| 7x / `7x` | 211/411 T | 3/6 frames (62.500/125.000 us) | 37 frames | 6.76x | 10.378 kbit/s | 6 / 249 |
| 5x / `5x` | 291/571 T | 4/8 frames (83.333/166.667 us) | 49 frames | 5.10x | 7.837 kbit/s | 9 / 246 |
| 4x / `4x` | 331/691 T | 5/10 frames (104.167/208.333 us) | 61 frames | 4.10x | 6.295 kbit/s | 12 / 243 |
| 3x / `3x` | 491/1011 T | 7/14 frames (145.833/291.667 us) | 85 frames | 2.94x | 4.518 kbit/s | 18 / 237 |
| 2.5x / `2.5x` | 571/1211 T | 8/17 frames (166.667/354.167 us) | 101 frames | 2.48x | 3.802 kbit/s | 21 / 234 |
| 2x / `2x` | 691/1531 T | 10/21 frames (208.333/437.500 us) | 125 frames | 2.00x | 3.072 kbit/s | 28 / 227 |
| 1x / `1x` | 1531/2971 T | 21/41 frames (437.500/854.167 us) | 249 frames | 1.00x | 1.542 kbit/s | 59 / 196 |

The 7x, 5x, 4x, 3x, 2.5x, 2x, and 1x balanced-data spans are respectively
1.48, 1.96, 2.44, 3.40, 4.04, 5.00, and 9.96 times the 10x span. Total snapshot
duration does not scale by that ratio because ROM bootstrap, processing pauses,
bit distribution, and RLE are unchanged, while acquisition segments follow
their own whole-frame table above.

### 44.1 kHz quantization

The requested T-state durations and receiver code remain the same, but the
integer PCM representation differs. These are the executable 44.1 kHz values:

| Preset | Leader / sync 1 frames | Zero / one frames | Balanced byte frames | Balanced bitrate |
| --- | ---: | ---: | ---: | ---: |
| **10x** | 7 / 4 | 2 / 3 | 21 | 16.800 kbit/s |
| **7x** | 10 / 5 | 3 / 6 | 37 | 9.535 kbit/s |
| **5x** | 13 / 7 | 4 / 8 | 49 | 7.200 kbit/s |
| **4x** | 16 / 8 | 5 / 9 | 57 | 6.189 kbit/s |
| **3x** | 22 / 11 | 7 / 13 | 81 | 4.356 kbit/s |
| **2.5x** | 26 / 13 | 8 / 16 | 97 | 3.637 kbit/s |
| **2x** | 33 / 17 | 9 / 20 | 117 | 3.015 kbit/s |
| **1x** | 65 / 33 | 20 / 38 | 233 | 1.514 kbit/s |

All eight profiles are swept over every receiver polling phase at both sample
rates and at 90%, 100%, and 110% signal rate. The shared 10x acquisition
window uses `LEADER_MAX = 13`; 12 was sufficient at 48 kHz but rejected the
slow boundary of the seven-frame 44.1 kHz leader.

The finalized catalog revision is reset to
`snapshot-turbo-speeds-v0`. Cache metadata records the
stable ID, polarity, sample rate, WAV profile, and canonical timing
fingerprint, so a waveform made with another signal setting or future catalog
revision cannot be reused.

### Historical percentage-preset reference

The experimental UI previously labelled rates as percentages of the 91/231-T
maximum. The 90% button remains removed; the former 70% timing returned as the
final `7x` preset and the 40% timing returned as `4x`. The former 7.5x timing is
also retained here so results from the hardware experiments remain
interpretable.

| Final state | Former preset | Requested zero/one | Actual zero/one at 48 kHz | Repeated zero/one square-wave frequency | Balanced byte | Exact relative rate | Balanced bitrate | `ZERO_MAX` | Threshold with old `BIT_LOOP_MAX=100` / current 255 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Removed | 90% / `90` | 131/331 T | 2/5 frames (41.667/104.167 us) | 12,000/4,800 Hz | 29 frames | 86.21% | 13.241 kbit/s | 4 | 96 / 251 |
| Removed | 7.5x / `7.5x` | 211/331 T | 3/5 frames (62.500/104.167 us) | 8,000/4,800 Hz | 33 frames | 75.76% | 11.636 kbit/s | 5 | 95 / 250 |
| Returned as `7x` | 70% / `70` | 211/411 T | 3/6 frames (62.500/125.000 us) | 8,000/4,000 Hz | 37 frames | 67.57% | 10.378 kbit/s | 6 | 94 / 249 |
| Returned as `4x` | 40% / `40` | 331/691 T | 5/10 frames (104.167/208.333 us) | 4,800/2,400 Hz | 61 frames | 40.98% | 6.295 kbit/s | 12 | 88 / 243 |

The frequency columns describe the audible square-wave frequency for a stream
of identical bits. One data bit occupies one half-wave, so the corresponding
repeated-bit rates are twice those frequencies.

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

For each turbo data bit, the first EAR read is nominally 91 T after the
previous detected edge; later reads are 40 T apart. The receiver is patched
from the selected catalog entry:

| Parameter | Current value | Meaning |
| --- | ---: | --- |
| `BIT_LOOP_MAX` | 255 | Maximum nonzero byte timeout retained for all final presets |
| `ZERO_MAX` | speed value, 3–59 | Latest poll classified as zero |
| `BIT_ONE_THRESHOLD` | 252–196 | Patched as `BIT_LOOP_MAX - ZERO_MAX`; a later edge is one |
| `IO_INIT` | `0x0a` | Initial EAR/border state |
| `IO_XOR` | `0x47` | Toggles remembered EAR state and border colour |

The same selected profile now patches the acquisition loop as well. Every row
is phase-safe in the 43-T model at nominal rate and at both ends of a reviewed
90%–110% whole-signal rate envelope:

| Receiver operand | Current values | Meaning |
| --- | --- | --- |
| both `LEADER_MAX` loads | 12–137 | Timeout/upper leader-pulse window |
| both leader-minimum comparisons | 6–39 | Encodes `LEADER_MAX + 2 - LEADER_MIN` |
| sync-minimum comparison | 10–88 | Encodes `LEADER_MAX + 2 - SYNC_MIN` |
| header/payload mini-sync timeout | 255 | Longest valid nonzero 8-bit wait |

The assets still contain the original `12/6/12/10/6/200` bytes. The Dart
patcher replaces all six immediate operands for each conversion and then
recalculates the second TAP block's XOR checksum. The 48K and 128K binaries
share the same instruction layout relative to their relocated upper code, but
only 48K physical acceptance is currently in scope.

During turbo leader acquisition the intended border stripes are red/cyan.
After sync recognition, data loading changes them to blue/yellow. If the
border never leaves the leader colours, the receiver has not accepted the
leader-to-sync transition.

### Slowest receiver rates and byte-width limits

Requested acquisition/data T-states and inter-block pauses exist only in the
host WAV generator; they are not stored in the 18-byte turbo header. Matching
classification limits are patched directly into immediate operands in the
receiver machine code. The final 1x preset's zero edges take 37–38 data polls
and its one edges take 73–74, versus a timeout before poll 255. Its leader takes
115–116 acquisition polls, leaving substantially more 8-bit counter margin
than the removed 5% experiment.

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
data profile. The final 1x preset is about 10% of that maximum and therefore
well above the code-only boundary. Raising the timeout from 100 to 255 changes
runtime receiver patches and cache identity but does not require recompiling
the Z80 asset.

## Theoretical 10x preset speed tolerance

For the independently quantized 10x waveform, the conservative code-only
playback-speed range is approximately:

```text
0.853x to 1.126x nominal speed
-14.7% to +12.6%
```

This range accounts for arbitrary phase between a signal edge and the
receiver's 40/43-T polling grids. If playback speed is `s`, a generated pulse
of `P` T-states is observed as `P / s` T-states.

| Limiter | Current quantized pulse | Phase-safe receiver window | Allowed playback speed |
| --- | ---: | ---: | ---: |
| Leader | 510.417 T | 431–643 T | 0.794x–1.184x, or −20.6% to +18.4% |
| Sync (half-leader, four-frame value) | 291.667 T | 259–388 T | 0.752x–1.126x, or −24.8% to **+12.6%** |
| Zero | 145.833 T | no more than 171 T | at least 0.853x, or **not slower than −14.7%** |
| One | 291.667 T | at least 211 T | no more than 1.382x, or not faster than +38.2% |

The intersection of all four constraints is therefore 0.853x–1.126x for the
10x preset. Slow playback is limited by zero classification, while fast
playback is limited by the short sync falling below its minimum acquisition
window. This code-only result does not make the 10x data pulses acceptable to
the tested analogue hardware path.

This is a mathematical limit of the custom turbo receiver, not a reliable
hardware operating range. It excludes Android/DAC filtering and resampling,
analogue EAR threshold behaviour, ULA I/O contention, noise, and the initial
ROM-loaded bootstrap. Those effects reduce the usable margin. A ±10% control
fits inside the receiver's theoretical range, but the code alone does not
guarantee loading at either extreme.

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
- [`just_audio` 0.10.5 local-file API](https://pub.dev/documentation/just_audio/0.10.5/just_audio/AudioPlayer/setFilePath.html)

## 48 kHz versus 44.1 kHz at the Z80 receiver

Changing the snapshot sample rate changes the actual edge grid, not just the
WAV header. The Z80 receiver never observes that source rate directly: it sees
an EAR transition after some number of 43-T acquisition polls or 40-T data
polls. The following tables describe the generated PCM before any Android
resampling, reconstruction filtering, cable distortion, or EAR threshold
shift.

Each `frames / effective T` entry applies the executable ceiling rule from the
start of this document. The effective duration is
`frames × 3,500,000 / sample-rate`; it is what a nominal 3.5 MHz Spectrum sees
if the analogue edge lands at the PCM transition.

### ROM bootstrap comparison

| Element | Requested duration | 48 kHz frames / effective T (error) | 44.1 kHz frames / effective T (error) |
| --- | ---: | ---: | ---: |
| Pilot half-wave | 2168 T | 30 / 2187.5 T (+0.90%) | 28 / 2222.2 T (+2.50%) |
| Sync 1 | 667 T | 10 / 729.2 T (+9.32%) | 9 / 714.3 T (+7.09%) |
| Sync 2 | 735 T | 11 / 802.1 T (+9.13%) | 10 / 793.7 T (+7.98%) |
| Quick zero half-wave | 700 T | 10 / 729.2 T (+4.17%) | 9 / 714.3 T (+2.04%) |
| Quick one half-wave | 1400 T | 20 / 1458.3 T (+4.17%) | 18 / 1428.6 T (+2.04%) |

The ideal 2168-T pilot is 807.196 Hz. Its rendered frequency is 800.000 Hz at
48 kHz and 787.500 Hz at 44.1 kHz, so the lower-rate pilot is audibly and
measurably 1.56% slower than the 48 kHz version. With the fixed cycle counts,
the bootstrap/header pilot lasts 1765.000 ms versus 1793.016 ms, and the
receiver/data pilot lasts 1512.500 ms versus 1536.508 ms. Some of the shorter
ROM pulses happen to round closer at 44.1 kHz, but the visible pilot is closer
to its requested timing at 48 kHz.

### Turbo acquisition in PCM frames and CPU T-states

The first duration in each cell is the leader and the second is sync 1.
Sync 2 and the payload mini-sync quantize to the same frame width as the leader
for every current profile.

| Profile | Requested leader / sync 1 | 48 kHz frames / effective T | 44.1 kHz frames / effective T |
| --- | ---: | ---: | ---: |
| **10x** | 500 / 250 T | 7 / 510.4 T; 4 / 291.7 T | 7 / 555.6 T; 4 / 317.5 T |
| **7x** | 729 / 364 T | 10 / 729.2 T; 5 / 364.6 T | 10 / 793.7 T; 5 / 396.8 T |
| **5x** | 1020 / 510 T | 14 / 1020.8 T; 7 / 510.4 T | 13 / 1031.7 T; 7 / 555.6 T |
| **4x** | 1239 / 619 T | 17 / 1239.6 T; 9 / 656.3 T | 16 / 1269.8 T; 8 / 634.9 T |
| **3x** | 1677 / 838 T | 23 / 1677.1 T; 12 / 875.0 T | 22 / 1746.0 T; 11 / 873.0 T |
| **2.5x** | 2041 / 1020 T | 28 / 2041.7 T; 14 / 1020.8 T | 26 / 2063.5 T; 13 / 1031.7 T |
| **2x** | 2552 / 1276 T | 35 / 2552.1 T; 18 / 1312.5 T | 33 / 2619.0 T; 17 / 1349.2 T |
| **1x** | 5104 / 2552 T | 70 / 5104.2 T; 35 / 2552.1 T | 65 / 5158.7 T; 33 / 2619.0 T |

### Turbo data in PCM frames and CPU T-states

The first duration in each cell is zero and the second is one. These are edge
intervals: turbo data emits one edge per bit.

| Profile | Requested zero / one | 48 kHz frames / effective T | 44.1 kHz frames / effective T |
| --- | ---: | ---: | ---: |
| **10x** | 91 / 231 T | 2 / 145.8 T; 4 / 291.7 T | 2 / 158.7 T; 3 / 238.1 T |
| **7x** | 211 / 411 T | 3 / 218.8 T; 6 / 437.5 T | 3 / 238.1 T; 6 / 476.2 T |
| **5x** | 291 / 571 T | 4 / 291.7 T; 8 / 583.3 T | 4 / 317.5 T; 8 / 634.9 T |
| **4x** | 331 / 691 T | 5 / 364.6 T; 10 / 729.2 T | 5 / 396.8 T; 9 / 714.3 T |
| **3x** | 491 / 1011 T | 7 / 510.4 T; 14 / 1020.8 T | 7 / 555.6 T; 13 / 1031.7 T |
| **2.5x** | 571 / 1211 T | 8 / 583.3 T; 17 / 1239.6 T | 8 / 634.9 T; 16 / 1269.8 T |
| **2x** | 691 / 1531 T | 10 / 729.2 T; 21 / 1531.3 T | 9 / 714.3 T; 20 / 1587.3 T |
| **1x** | 1531 / 2971 T | 21 / 1531.3 T; 41 / 2989.6 T | 20 / 1587.3 T; 38 / 3015.9 T |

Independent ceiling is especially coarse at the fast end. For 10x, the
48 kHz zero is already 60.26% longer than its 91-T request; at 44.1 kHz it is
74.43% longer. Conversely, the 10x one is closer to its request at 44.1 kHz
because it changes from four 48 kHz frames to three 44.1 kHz frames. Therefore
switching sample rate is not a uniform speed change: leader, sync, zero, and
one can move by different percentages.

### What the receiver classifies

Acquisition values below are zero-based poll indices, matching the timing
simulation. The valid leader window is `LEADER_MIN - 1` through
`LEADER_MAX - 1`; the valid sync window is `SYNC_MIN - 1` through
`LEADER_MIN - 2`.

| Profile | Valid leader / sync indices | Observed at 48 kHz | Observed at 44.1 kHz |
| --- | ---: | ---: | ---: |
| **10x** | 7–12 / 3–6 | 8–9 / 3–4 | 9–10 / 4–5 |
| **7x** | 12–18 / 4–11 | 13–15 / 5–6 | 15–16 / 6–7 |
| **5x** | 17–25 / 7–16 | 20–21 / 8–9 | 20–22 / 9–10 |
| **4x** | 22–31 / 10–21 | 25–26 / 12–13 | 26–27 / 11–12 |
| **3x** | 31–44 / 15–30 | 36–37 / 17–18 | 37–38 / 17–18 |
| **2.5x** | 38–54 / 18–37 | 44–45 / 20–21 | 44–46 / 20–21 |
| **2x** | 48–67 / 24–47 | 56–57 / 27–28 | 57–58 / 28–29 |
| **1x** | 99–136 / 50–98 | 115–116 / 56–57 | 116–118 / 57–58 |

Data values are one-based poll counts collected over every phase of the 40-T
loop and both ordinary and byte-boundary paths. A value no greater than
`ZERO_MAX` is zero; a later edge is one.

| Profile | `ZERO_MAX` | Zero / one polls at 48 kHz | Zero / one polls at 44.1 kHz |
| --- | ---: | ---: | ---: |
| **10x** | 3 | 2–3 / 6–7 | 1–3 / 4–6 |
| **7x** | 6 | 4–5 / 9–10 | 4–6 / 9–11 |
| **5x** | 9 | 6–7 / 13–14 | 6–8 / 14–15 |
| **4x** | 12 | 7–9 / 16–18 | 7–9 / 16–17 |
| **3x** | 18 | 11–12 / 24–25 | 11–13 / 24–25 |
| **2.5x** | 21 | 13–14 / 29–30 | 14–15 / 30–31 |
| **2x** | 28 | 16–18 / 37–38 | 16–17 / 38–39 |
| **1x** | 59 | 37–38 / 73–74 | 38–39 / 74–75 |

Both rates pass the complete digital phase model. However, at 10x/44.1 kHz
the observed zero class reaches 3 and the one class begins immediately at 4:
there is no unused receiver count between them. At 48 kHz the one class begins
at 6. The default 5x profile has comfortable separation at both rates, but its
48 kHz timings are much closer to the requested catalog values. Among the two
supported source rates, **48 kHz is the timing baseline and the better general
condition for the current receiver**; 44.1 kHz is a separately validated
hardware-path alternative, not an equivalent grid.

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

| Profile | Leader frames 48 / 44.1 | One-frame half-width step | Equal-leader duty step | Zero frames 48 / 44.1 | One-frame zero-width step |
| --- | ---: | ---: | ---: | ---: | ---: |
| **10x** | 7 / 7 | 14.29% / 14.29% | ±7.14 / ±7.14 pp | 2 / 2 | 50.00% / 50.00% |
| **7x** | 10 / 10 | 10.00% / 10.00% | ±5.00 / ±5.00 pp | 3 / 3 | 33.33% / 33.33% |
| **5x** | 14 / 13 | 7.14% / 7.69% | ±3.57 / ±3.85 pp | 4 / 4 | 25.00% / 25.00% |
| **4x** | 17 / 16 | 5.88% / 6.25% | ±2.94 / ±3.13 pp | 5 / 5 | 20.00% / 20.00% |
| **3x** | 23 / 22 | 4.35% / 4.55% | ±2.17 / ±2.27 pp | 7 / 7 | 14.29% / 14.29% |
| **2.5x** | 28 / 26 | 3.57% / 3.85% | ±1.79 / ±1.92 pp | 8 / 8 | 12.50% / 12.50% |
| **2x** | 35 / 33 | 2.86% / 3.03% | ±1.43 / ±1.52 pp | 10 / 9 | 10.00% / 11.11% |
| **1x** | 70 / 65 | 1.43% / 1.54% | ±0.71 / ±0.77 pp | 21 / 20 | 4.76% / 5.00% |

A 1% per-edge duty adjustment is therefore not directly representable at
either rate. It would require fractional-error accumulation or a later
resampling stage. An analogue path can nevertheless move rising and falling
threshold crossings in opposite directions. That makes alternating intervals
effectively longer and shorter even though the source is exactly 50:50; an
inverted source swaps which electrical half receives each distortion. The risk
increases at higher profiles because one PCM frame and one Z80 poll represent
a larger fraction of the shortest pulse. The adjacent 10x/44.1 kHz data
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

On first use, the snapshot signal starts at **5x**, standard polarity, and
**48 kHz**. After a different speed, polarity, or sample rate is applied
successfully, the app remembers all three values as one device-local settings
triple and restores them in later player and application sessions. A missing,
malformed, or obsolete triple falls back as a unit. For a ready snapshot, the
existing speed badge shows the selected speed and opens a button-only list of
`10x`, `7x`, `5x`, `4x`, `3x`, `2.5x`, `2x`, and `1x`, a segmented
**48 kHz / 44.1 kHz** selector, and an **Invert polarity** checkbox. The `x`
values are transfer speeds relative to standard tape loading. For ordinary tape
media, the same badge continues to show a media-player `x` multiplier and opens
the continuous playback-speed slider.

Changing snapshot speed, polarity, or sample rate stops and rewinds playback,
prepares or reuses a settings-specific WAV/sidecar pair, binds it at position
zero, and remains paused. The visible settings are committed only after binding
succeeds; the committed speed ID, polarity, and sample rate are persisted together.
A conversion, binding, or persistence failure restores the previous
valid audio and settings at zero when possible and does not overwrite the
previously stored triple.

When snapshot playback reaches the completed state, the media carousel is
unlocked even though the player position remains at the end of the WAV. This
does not make the dependent snapshot restore blocks seekable.

Snapshot media-player speed and Android pitch remain **1x for every preset**.
The waveform itself controls the physical rate. The ordinary-tape speed is
remembered independently and restored when returning to tape media. Snapshot
RLE decisions, compressed bytes, restore commands, ROM bootstrap, receiver
asset files, and filters are unchanged; selected tape filters remain ignored
for snapshot generation. The custom turbo acquisition waveform and matching
runtime receiver immediates now come from the selected profile.

## Representative deterministic metadata

These synthetic acceptance fixtures are pinned by
`snapshot_profile_metadata_test.dart`. “Turbo frames” excludes the two
ROM-speed receiver-installation blocks but still includes leaders, sync,
pauses, and processing time. Runtime receiver patches can change the second
ROM block's encoded bytes and therefore its frame length. Logical SHA-256
covers every turbo header and payload byte;
matching hashes across profiles prove that timing selection does not alter RLE
or restore semantics.

| Fixture | Speed | Polarity | Total frames | Turbo frames | Turbo blocks | Threshold | Logical SHA-256 | WAV SHA-256 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| 48K Z80 v1 | 10x | standard | 386830 | 119428 | 4 | 252 | `aa66c5f2…38fef` | `f4581693…bbabc` |
| 48K Z80 v1 | 5x | standard | 450532 | 183210 | 4 | 246 | `aa66c5f2…38fef` | `75d5ac4d…0ce54` |
| 128K SNA | 10x | standard | 559871 | 289949 | 9 | 252 | `92a68c9a…10894` | `564e49fd…361c7` |
| 128K SNA | 5x | standard | 708206 | 438404 | 9 | 246 | `92a68c9a…10894` | `e3f81729…da10b` |

The 128K rows above are deterministic software regressions only. They are not
128K physical-hardware acceptance; physical work remains focused on obtaining
a successful 48K load first.

For physical acceptance, record at least:

| Snapshot/machine | Speed label/ID and polarity | Leader/sync/data timing | Receiver acquisition/data values | Phone/output route | Cable/volume | Attempts/successes | Starts from bootstrap, paused before start? | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| _fill during test_ | _for example 2x / `2x`, standard_ | _35/25 leader/sync frames; 10/21 data frames_ | _68/49/30; threshold 227_ | | | | | |

## Source baseline

The implementation values above were checked against the current ZX Tape
Player working tree and sibling ZQLoader revision
`a6fdb6a889f0ca4a928c37d030527b577a941793`, with the reproducible correctness
patch assembled by `/usr/local/bin/sjasmplus` 1.24.0, particularly:

- `lib/snapshots/snapshot_renderer.dart`;
- `lib/snapshots/snapshot_timing.dart`;
- `lib/snapshots/snapshot_restore_planner.dart`;
- `lib/ui/widgets/tape_player/tape_player.dart`;
- `tool/snapshot_receiver/zqloader-a6fdb6a-correctness.patch`;
- ZQLoader `loader_defaults.h`, `sampletowav.h`, `samplesender.h`, and
  `z80/zqloader.z80asm`.
