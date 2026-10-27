# Headless command line

Every machine's executable accepts `--headless`. It runs the VM at full speed with no window or host audio. Actions
are scheduled by frame number, and the results are written to a new output directory. The code is
`src/cli/headless.cpp`, shared by the macOS and Linux builds. On Linux the executable is `build/<machine>`; the same
command line produces the same frames, traces and JSON on both systems.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target fm7 -j 8
build/fm7.app/Contents/MacOS/fm7 --help
build/fm7.app/Contents/MacOS/fm7 --headless --rom-dir ~/roms/fm7 --out /tmp/fm7-run \
    --stop-at-frame 4000 --paste 600:listing.bas --stop-after-paste 180 --final-screenshot
```

The X1, SMC-777 and Basic Master Jr. keep the ROM checks, trace formats and JSON fields of their original CLIs.
[MAC_X1_CLI.md](MAC_X1_CLI.md), [MAC_SMC777_CLI.md](MAC_SMC777_CLI.md) and [MAC_BMJR_CLI.md](MAC_BMJR_CLI.md)
describe those details. For those three machines the merged front end produces byte-identical output to the
original CLIs.

## Rules

- `--rom-dir DIR` is the only place ROMs are read from. No saved `.ini` and no global ROM fallback is used. Files
  the VM tried to read there but could not find are listed in the JSON as `rom_files_not_found`. Some are
  optional, such as extra ROM banks and drive sound WAVs.
- `--out NEW_DIR` must not exist yet; its parent must. Relative output names resolve under it, and existing files
  are never overwritten.
- Frames are numbered 0..N inclusive. Scheduled actions happen before a frame; captures happen after it.
- Success prints one JSON line and exits 0. Any error prints `[headless] ERROR: ...` and exits 2.

## Options

| Option | Effect |
| --- | --- |
| `--stop-at-frame N` | Required upper bound |
| `--disk-a FILE` .. `--disk-d FILE` | Floppy images, mounted as private copies `OUT/disk-a.<ext>`. D88 copies are write-protected |
| `--disk-output-a NEW_COPY` .. | That drive's copy is writable and kept at `NEW_COPY` (use it to save a program to disk) |
| `--writable-disks` | Every drive's copy is writable |
| `--tape FILE` | Play from frame 0, in any format the VM reads (`.wav .cas .mzt .p6 .p6t .t77 .tap .cmt` ...) |
| `--tape-at FRAME` | Insert the tape before FRAME instead. MZ machines start playback only if the motor is already on, so insert after the load command |
| `--record-tape FILE` | Record to a new file: `.wav` or `.tap` on most machines, `.t77` on FM-7. PC-8001/8801 always write a `.cmt` byte stream |
| `--qd FILE`, `--cart FILE` | Quick Disk, cartridge |
| `--paste FRAME:FILE` | Type a UTF-8 text file through the VM's auto key, one line at a time (see below) |
| `--paste-text FRAME:TEXT` | The same for inline text; `\n` separates lines |
| `--paste-line-gap FRAMES` | Extra frames between pasted lines (default 0) |
| `--stop-after-paste FRAMES` | End the run this many frames after the last pasted line |
| `--type FRAME:TEXT` | Scheduled virtual keys: letters, digits, space, `\n`, `{RETURN}` `{SPACE}` `{ESC}` `{BS}` `{DEL}` `{TAB}` `{HOME}` `{INS}` arrows `{BREAK}` `{F1}`..`{F12}` `{SHIFT}x` `{Vxx}` `{WAITn}` |
| `--type-rate PRESS:RELEASE` | Frames a typed key is held / released (default 4:4) |
| `--key-down FRAME:VK`, `--key-up FRAME:VK` | Explicit Windows virtual keys |
| `--joy FRAME:PORT:BITS` | Joystick state from FRAME |
| `--reset-at FRAME`, `--special-reset-at FRAME` | Reset; the machine's special reset |
| `--screenshot FRAME`, `--dump-every N`, `--final-screenshot` | `OUT/frame_NNNNNN.png` |
| `--trace-cpu FILE` | Every instruction (Z80 and MC6800 machines) |
| `--trace-io FILE` | Every I/O access (X1, SMC-777, Basic Master Jr.) |
| `--trace-from F`, `--trace-to F`, `--watch-pc ADDR,...` | Trace window; instruction counts at addresses |
| `--poke ADDR=BYTES@FRAME`, `--dump-mem ADDR:LEN@FRAME`, `--dump-memory FILE` | 64 KiB through the CPU's debugger view (hex) |
| `--wav FILE` | The mixed sound output |
| `--monitor-type N` | The machine's Monitor Type menu item, 0 = first (machines with that menu) |
| `--host-time YYYY-MM-DDTHH:MM:SS` | Clock chips read this time plus the emulated time instead of the host clock, so runs are reproducible (`TIME$`, and the PC-8001's calendar bit on port 40h) |

`OUT/frames.csv` has one row per frame: frame, emulator clock, width, height, next PC and an FNV-1a-64 hash of
the RGB picture.

## Pasting listings

`--paste` uses CSCP's auto key, the Windows version's Paste command. Each machine's table maps characters to its
keys, including shift, kana lock and caps lock. The front end feeds one line at a time once the previous line is
finished. A long listing never overruns the auto-key buffer, and each line gets the VM's end-of-line wait.

The input is UTF-8:

- Full-width ASCII, hiragana and katakana are converted to the half-width JIS X 0201 characters the machines use.
  Voiced kana are split into kana plus dakuten or handakuten.
- `¥` becomes `\`. Line ends may be LF or CRLF.
- A character with no key (for example kanji, or a machine-specific graphic character) stops the run with its line
  and column.

`OUT/paste.csv` records each line's start and end frame. The JSON `paste` field reports `lines`, `lines_typed`,
`complete` and `finished_frame`.

Typing speed is the machine's: with default settings a line of 30 characters takes several seconds of emulated
time. The emulator runs much faster than real time, so this costs little wall-clock time.

## Machine notes

Frames at which BASIC is ready, measured with the ROM sets noted. With a disk ROM present, the PC-80/88 family
waits for the drive before BASIC starts.

| Machine | Ready at | Notes |
| --- | --- | --- |
| fm7 | ~600 | |
| msx1 | ~600 | Needs a disk ROM written for CSCP's pseudo disk BIOS, or none. A `DISK.ROM` that polls a TC8566AF at 7FFAh hangs at the logo |
| mz700 | ~13450 | Boots to the monitor. BASIC 1Z-013B from tape: `--type 300:L\n --tape 1Z-013B.mzf --tape-at 360`. "Ready" shows as kana with the Japanese `FONT.ROM` |
| pc6001 | ~600 | Stops at `How Many Pages?`. Needs `SUBCPU.60`; MAME's `upd8049.ic17` is a bad dump. PC6001VX's compatible `SUBCPU.60` works. `--paste` selects katakana mode (SHIFT+PAGE) before the first line |
| pc8001, pc8001mk2 | ~1100 (~260 without `DISK.ROM`) | Font from `KANJI1.ROM`, or MAME's 2 KB `FONT.ROM` |
| pc8801, pc8801mk2, pc8801ma | ~2750 (~1060 without `DISK.ROM`) | Stops at `How many files(0-15)?`: send `--type FRAME:{RETURN}` first |
| x1 | ~1500 | HuBASIC CZ-8FB01 from `--disk-a`. Some boot disks leave text on the input line: send `{RETURN}` before pasting |
| x1turbo | ~1500 | HuBASIC CZ-8CB01. Use `--monitor-type 1` (Standard): in High Resolution mode 8x16 text draws only the top half of each glyph |

X1 ROM names: the CLI accepts the names the VM itself tries, `IPLROM.X1`/`IPLROM.X1T` or `IPL.ROM`, `ANK8.ROM` or
`FNT0808.X1`, `ANK16.ROM` or `FNT0816.X1`. `KANJI.ROM` or `FNT1616.X1` is optional; without it the JSON has
`"kanji_rom":false`. With all four standard files the output is unchanged from cli_revision 4.

Tested end to end with `--paste` (type a listing, `RUN`, check the output): FM-7, MSX1 (no disk ROM), MZ-700
(1Z-013B from tape), PC-6001, PC-8001, PC-8001mkII, PC-8801, PC-8801mkII, PC-8801MA, X1 and X1turbo (HuBASIC
from disk).
