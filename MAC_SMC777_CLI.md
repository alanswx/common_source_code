# macOS SMC-777 headless CLI

The `smc777` (and `smc70`) app executable accepts `--headless` (the shared front end, src/cli/headless.cpp; see CLI.md). Like the X1 CLI it runs the
existing VM synchronously with no NSApplication, Metal window or host audio, and with no saved config or global ROM
fallback. It exists to compare the SMC777_MiSTer core and its Verilator simulation against eSMC-777.

```sh
cmake -S . -B /tmp/csp-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/csp-build --target smc777 -j 8
/tmp/csp-build/smc777.app/Contents/MacOS/smc777 --help
/tmp/csp-build/smc777.app/Contents/MacOS/smc777 --headless --rom-dir /path/roms --out /tmp/smc-run \
    --disk-a "system 11.1dd" --stop-at-frame 900 --screenshot 900 --trace-io io.csv --trace-to 120
```

- `--rom-dir DIR`: `SMCROM.DAT` or `SMC777ROM.DAT` (16384 bytes) required, `KANJIROM.DAT` optional.
- `--out NEW_DIR`: must not exist (its parent must). Relative trace/dump names resolve under it.
- `--disk-a/--disk-b FILE`: any format the VM opens (the `.1dd` library images are D88). Always mounted as a private
  copy `OUT/disk-a.<ext>`; D88 volumes get their protection byte set unless `--writable-disks`.
- `--type FRAME:TEXT`, `--type-rate P:R`, `--key-down/--key-up FRAME:VK`: Windows virtual keys, as the VM's key table.
  Text: lower case letters plain and capitals shifted (the SMC-777 keyboard is ASCII: unshifted letters are lower
  case), digits, ASCII-layout punctuation, `\n`, `{RETURN}` `{SPACE}` `{ESC}` `{BS}` `{DEL}` `{TAB}` `{HOME}`
  `{INS}` arrows, `{F1}`..`{F12}`, `{SHIFT}x`, `{Vxx}`, `{WAITn}`.
- `--reset-at FRAME` (cold), `--special-reset-at FRAME` (warm: port 1Ch bit 7).
- `--screenshot FRAME` (repeatable), `--dump-every N`: `OUT/frame_NNNNNN.png` (640x400).
- `--trace-cpu FILE`: frame,clock,pc,sp,af,bc,de,hl,opcode per instruction (the shared Z80 trace hook).
- `--trace-io FILE`: frame,clock,pc,kind,address,data for every IN/OUT (hook in `vm/smc777/memory.cpp`).
- `--trace-from/--trace-to FRAME`, `--dump-memory FILE` (final 64 KiB CPU view).
- `--joy FRAME:PORT:BITS`: joystick 0/1 state from FRAME (the VM's bits: 1 up, 2 down, 4 left, 8 right, 16/32
  triggers), written to the OSD joystick buffer.
- `--wav FILE`: the mixed sound output (16-bit stereo at the VM's rate), from the `cli_sound_hook` in
  `OSD::update_sound` (null for the GUI).

Frames are 0..N inclusive; scheduled actions precede a frame, captures follow it. `OUT/frames.csv` records
frame, clock, width, height, next PC and FNV-1a-64 over the RGB8 picture. Success prints one JSON line
(`cli_revision` 1); failures return 2.
