# macOS X1 comparison CLI

The X1, X1turbo and X1turboZ app executables accept `--headless`. This path
runs the existing emulator VM synchronously without creating NSApplication,
a Metal window or host audio. The existing GUI and Sharp MZ `--script` mode
remain separate. X1twin is link-checked but does not expose this CLI route.

Build only the desired targets in a separate directory:

```sh
cmake -S . -B /tmp/csp-x1-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/csp-x1-build --target x1 x1turbo x1turboz -j 4
/tmp/csp-x1-build/x1.app/Contents/MacOS/x1 --help
```

A bounded run, using an existing isolated ROM directory and a **new** output
directory whose parent already exists:

```sh
/tmp/csp-x1-build/x1.app/Contents/MacOS/x1 --headless \
  --rom-dir /absolute/private/x1-roms --out /tmp/x1-run-001 \
  --disk-a /absolute/private/game.d88 --stop-at-frame 1599 \
  --type '1100:{SPACE}' --screenshot 900 --screenshot 1599 \
  --trace-cpu cpu.csv --trace-io io.csv --trace-from 0 --trace-to 2 \
  --dump-memory memory.bin
```

The required files and exact sizes in `--rom-dir` are:

| File | Bytes |
| --- | ---: |
| `IPLROM.X1` (X1) | 4,096 |
| `IPLROM.X1T` (Turbo/Z) | 32,768 |
| `ANK8.ROM` | 2,048 |
| `ANK16.ROM` | 4,096 |
| `KANJI.ROM` | 306,176 |

`KANJI.ROM` uses this emulator's virtual glyph layout. It is **not** a raw
256-KiB physical Turbo Z ROM. This interface does not convert, pad or truncate
native font files. The FPGA comparison's generated all-zero font fixtures
qualify CPU/interface behavior only. Native fonts/ROMs are not distributed.
If both `SUBROM.X1[T]` and `KBDROM.X1[T]` are present, the existing VM selects
its MCU path; otherwise it selects its existing pseudo-sub-CPU. Record this
choice with the input inventory. This frontend does not invent controller data.

ROM/data lookup stays inside the explicit directory. Global user ROM aliases
and saved `.ini` settings are not loaded or saved. The CLI initializes the
existing default config, disables scanline presentation and selects PSG-only
sound (`sound_type=0`). Full FM/native model qualification is separate. The
private `RETROPC_CLI_DATA_DIR` environment marker is set by the frontend before
VM construction; ordinary GUI launches do not set it.

Disk inputs are D88 containers, volume zero. The header chain is checked
before emulation so a zero-length volume cannot hang the existing scanner.
By default each disk is copied into the new output directory as `disk-a.d88`
or `disk-b.d88`; every volume's protection byte is set to `10`, and the VM's
protection input is enabled. **The caller's disk is never mounted directly.**
The existing disk backend persists its protection bit on close, which is why
setting the protection flag alone is insufficient.

Revision 4 adds explicit `--disk-output-a NEW_COPY` and
`--disk-output-b NEW_COPY`. Each requires its corresponding disk input and
creates a **new** writable private copy, with protection bytes cleared only
in that copy. Relative paths resolve under the new `--out`; absolute paths
are allowed when their parent exists. Existing files, directories, symlinks,
hardlinks, original paths, duplicate output options and shared drive output
paths are rejected. Exclusive creation also guards a race after preflight.
To reload a saved image, pass it as a new disk input; the frontend still
mounts another private copy. No option mounts the input itself writable.
These rules do not qualify every malformed sector table or native filesystem.

Frames are numbered **0..N inclusive**. Scheduled reset/key actions happen
before the named frame; draw, frame log and screenshots happen after it.
`--stop-at-frame N` must complete exactly N+1 VM frames. A multi-frame `EMU::run`
result is rejected rather than mislabeled. Native frame frequency is the
selected CSP model's frequency, not the FPGA's frame count or clock origin.

Options:

- `--disk-a FILE`, `--disk-b FILE`: protected private D88 copies by default.
- `--disk-output-a NEW_COPY`, `--disk-output-b NEW_COPY`: explicitly writable,
  exclusively created copies of the corresponding inputs.
- `--reset-at FRAME`: repeatable public `EMU::reset`, with retained assets.
- `--type FRAME:TEXT`: letters/digits/space, `\n`, `{RETURN}`, `{SPACE}`, `{ESC}`,
  `{UP}`, `{DOWN}`, `{LEFT}`, `{RIGHT}`, `{F1}`..`{F12}`, `{Vxx}` virtual-key codes.
- `--type-rate PRESS:RELEASE`: positive frame durations, default `4:4`.
- `--key-down FRAME:VK`, `--key-up FRAME:VK`: explicit Windows virtual-key values
  (decimal or `0x` hexadecimal); use these for held modifiers and chords.
- `--screenshot FRAME`, `--dump-every N`: actual emulator RGB PNGs.
- `--trace-cpu FILE`: instruction-boundary frame/clock/PC/SP/AF/BC/DE/HL/opcode.
  The existing Z80 trace hook is reused. Opcode is a debug memory observation,
  not a new physical fetch. HALT PC conventions can differ between CPU models.
- `--trace-io FILE`: completed CPU I/O function calls, actual address/data and
  emulator wait count. DMA calls are separate and are not included.
- `--trace-from FRAME`, `--trace-to FRAME`: inclusive CPU/I/O trace window.
- `--dump-memory FILE`: final 64-KiB **CPU-visible** map through the debug-read
  interface. A physical FPGA RAM dump differs beneath an enabled IPL overlay.

Relative output filenames are resolved under `--out`; existing outputs are
refused. `frames.csv` always records frame, emulator clock, dimensions, next
PC and FNV-1a-64 over RGB8 bytes in raster order. Clock values are the emulator's
32-bit event-clock observations, not hardware pin timestamps. Success prints
one JSON completion record with `cli_revision=4`, per-drive `writable_drives`,
`disks_protected` and `disk_policy` (`protected_private_copy` or
`explicit_writable_copy`); failures return 2 and do not
print a completion record. Missing/invalid ROMs, unsupported tokens and events
after the stop frame are rejected before VM construction.

The separate SharpX1_Mister `scripts/qualify_csp_x1.py` freezes binaries/source
inputs and compares an original CPU/RAM/IPL-overlay/PSG diagnostic with the RTL,
including bad-ROM, no-reset and retained-reset controls. It also checks cold
repeatability and the actual generated-disk open/close path. Passing that
bounded fixture is not native software, exact ASIC WAIT or physical acceptance.

Revision 3 repairs the macOS OSD adapter to forward key-down/up events to the
VM after updating its key-state array, matching the existing VM callback
contract. This is required by the X1 pseudo-controller. The comparison gate
requires the CPU to consume F then R through the real controller mailbox;
the no-key control and the frozen previous adapter reject the same oracle.

Revision 4 changes only the CLI copy policy and completion identity. Default
CPU/RAM/keyboard/reset/model artifacts are checked against the frozen revision
3 binaries. The VM calendar still initializes from host time; raw native SAVE
directory timestamps and RAM can differ between launches. Preserve those
files unmodified and distinguish exact RGB/frame repeats from disk/RAM byte
identity.
