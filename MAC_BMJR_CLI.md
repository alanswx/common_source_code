# macOS Basic Master Jr. headless CLI

The `bmjr` app executable accepts `--headless` (the shared front end, src/cli/headless.cpp; see CLI.md). Like the X1 and SMC-777 CLIs it runs the
existing VM synchronously with no NSApplication, Metal window or host audio, and with no saved config or global ROM
fallback. It exists to compare the BasicMasterJr_MiSTer core and its Verilator simulation against eBASICMasterJr.

```sh
cmake -S . -B /tmp/csp-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/csp-build --target bmjr -j 8
/tmp/csp-build/bmjr.app/Contents/MacOS/bmjr --help
# ROMs from the FPGA repo's rtl/*.mem:  BasicMasterJr_MiSTer/vsim/csp/make_roms.py /path/roms
/tmp/csp-build/bmjr.app/Contents/MacOS/bmjr --headless --rom-dir /path/roms --out /tmp/bmjr-run \
    --tape mazy.s.bin --type '75:MON\n' --type '200:L' --type '260:MAZY' --type '340: ' \
    --dump-mem 1000:15B8@17000 --type '17100:G' --type '17200:1000' --type '17300: ' \
    --screenshot 18000 --stop-at-frame 18000
```

- `--rom-dir DIR`: `BASIC.ROM` (12288), `MONITOR.ROM` (4096), `FONT.ROM` (2048) required; `PRINTER.ROM` (2048) optional.
- `--out NEW_DIR`: must not exist (its parent must). Relative trace/dump names resolve under it.
- `--tape FILE`: `.bin` or `.cmt` (bm2 byte stream; the core's `.s.bin` images; a `.cmt` is copied to `OUT/tape.bin`) or `.wav`, playing from frame 0. The motor is
  the ROM's `$EE20`/`$EE00` reads. Real 300 baud: there is no fast-tape mode, but the CLI runs ~2,600 frames/s.
- `--record-tape FILE.wav`: records `$EE80` bit 0 to a new WAV in OUT. Exclusive with `--tape` (one drive).
- `--type FRAME:TEXT`, `--type-rate P:R`, `--key-down/--key-up FRAME:VK`: Windows virtual keys, as the VM's key table.
  The VM reads its modifier columns from VK `0xA0`-`0xA3`, so `{SHIFT}x` presses L-SHIFT (英記号). Text: letters,
  digits, JIS punctuation, `\n`, `{RETURN}` `{SPACE}` `{DEL}` `{BREAK}` (NMI), `{SHIFT}x` `{KANAKIGO}x` `{EISU}`
  `{KANA}` `{Vxx}` `{WAITn}`.
- `--reset-at FRAME`, `--screenshot FRAME` (repeatable), `--dump-every N`: `OUT/frame_NNNNNN.png` (256x192).
- `--poke ADDR=BYTES@FRAME`, `--dump-mem ADDR:LEN@FRAME`: same syntax and `memdump_*.bin` names as the Verilator sim.
  Both act on the VM's 64 KiB RAM array; `--dump-memory FILE` writes all of it at the end.
- `--watch-pc ADDR,...`: counts instructions started at those addresses (reported in the JSON record).
- `--trace-cpu FILE`: frame,clock,pc,a,b,x,sp,cc,opcode per instruction (hook in `vm/mc6800.cpp`).
- `--trace-io FILE`: frame,clock,pc,kind,address,data for every `$E800-$EFFF` I/O access (hook in `vm/bmjr/memory.cpp`).
- `--trace-from/--trace-to FRAME`.

Frames are 0..N inclusive; scheduled actions precede a frame, captures follow it. `OUT/frames.csv` records
frame, clock, width, height, next PC and FNV-1a-64 over the RGB8 picture. Success prints one JSON line
(`cli_revision` 1); failures return 2.

This VM is a simpler model than the FPGA core: 754,560 Hz CPU, no timer IRQ, `$EF80` as the BREAK flag, no
`$40-$4F` mixed mode, blink or border. Frame numbers therefore drift against the core's ~59 Hz frames; compare
by screen content and RAM, not by frame index.
