# Common Source Code Project machines vs. MiSTer cores

Date: 2026-10-16

Sources:
- Machines: build targets in `vc++2017/*.vcxproj` and `DEVICE_NAME` in `src/vm/*/*.h` (140 targets, about 80 distinct machines).
- MiSTer: `_Computer` and `_Console` cores in `MiSTer-devel/Distribution_MiSTer`, plus the MiSTer wiki core list.
- Our own cores: repos in `~/dev2` and `~/Documents/development`.

This only checks whether a core exists. It does not check whether that core runs this exact model.

## 1. Already covered

| CSCP target(s) | MiSTer core | Notes |
|---|---|---|
| colecovision | ColecoVision | Also ColecoAdam (ours) |
| sc3000 | ColecoVision (SG-1000 mode) | SC-3000 keyboard and BASIC are only partly covered |
| mastersystem, gamegear | SMS, GameGear2P | |
| pcengine | TurboGrafx16 | |
| familybasic | NES | Family BASIC keyboard |
| fm7, fm77, fm77av (+ variants) | FM-7 (ours: FM-7_MiSTer_alanswx) | FM77AV is experimental. FM-8, FM77L4 and AV40/EX are not confirmed |
| jr100 | JR100 | |
| m5 | SordM5 | |
| msx1, msx2, msx2p, fsa1, hx20 (Toshiba HX-20+), HB-F1XDJ | MSX, MSX1 | |
| mz80k, mz1200, mz80a, mz700, mz700pal, mz800, mz1500, mz80b, MZ-2000 | SharpMZ (ours) | MZ-2200 is close to the MZ-2000 |
| pc8801, pc8801mk2, pc8801ma | PC88 | PC-8801MA extras not confirmed |
| pv1000, pv2000 | Casio_PV-1000, Casio_PV-2000 | |
| rx78 | RX78 (ours, with Pierco) | |
| scv | SCV | |
| svi3x8 | Svi328 | |
| pyuta | TomyTutor | The PyuTa is the Japanese Tomy Tutor |

## 2. We have our own core, still in progress

| CSCP target(s) | Our repo | State |
|---|---|---|
| mz2500 | SharpMZ2500_MiSTer | Has its own README and release steps |
| x1, x1twin, x1turbo, x1turboz | SharpX1_Mister | Bring-up; basic X1 boots, Turbo/Z not qualified |
| smc777 | SMC777_MiSTer | WIP |
| bmjr | BasicMasterJr_MiSTer | BASIC and tape load work; tape save not done |

## 3. Partly covered by a related core

| CSCP target(s) | Nearest core | Gap |
|---|---|---|
| pc8001, pc8001mk2, pc8001mk2sr | PC88 (N mode) | No dedicated PC-8001 core |
| px7 (Pioneer PX-7) | MSX | LaserDisc overlay hardware missing |
| jx (IBM JX) | PCjr | JX is a Japanese PCjr derivative |
| pc9801 family, pc98do | Unofficial PC-98 core (forum reports) | Not in the official distribution |
| fmr30/50/60/70/80 | FM Towns Marty | Different machine, related lineage |
| mz2200 | SharpMZ | Not listed as a separate model |

## 4. No MiSTer core found

### 8-bit home computers (best candidates)
- **NEC PC-6001 / mkII / mkIISR, PC-6601 / SR** (pc6001 family): large game library, Z80 + MC6847-style video
- **Toshiba Pasopia, Pasopia 7** (pasopia, pasopia7, LCD variants)
- **Mitsubishi MULTI 8** (multi8)
- **Sony SMC-70** (smc70): sister machine to the SMC-777
- **Sanyo PHC-20, PHC-25** (phc20, phc25)
- **Hitachi Basic Master Jr** is covered above; **National JR-800** handheld (jr800) is not
- **Systems Formulate BUBCOM80** (bubcom80)
- **Hino CEFUCOM-21** (cefucom21)
- **Hudson HuX-883** (hux883)
- **Japan Electronics College MYCOMZ-80A** (mycomz80a)
- **Yuasa YALKY** (yalky)
- **Yamaha YIS** (yis)
- **Casio FP-1100** (fp1100)

### Portables, pocket computers and handhelds
- **NEC PC-8201 / PC-8201A** (Kyotronic 85 family, same as the TRS-80 Model 100)
- **Epson HC-20 / HC-40 / HC-80** (HX-20 / PX-4 / PX-8)
- **Canon X-07** (x07)
- **Casio FP-200**, **FX-9000P**
- **NEC PC-2001**
- **NEC PC-98HA, PC-98LT**
- **Toshiba J-3100GT / SL**
- **Toshiba T-200 / T-250**

### 16-bit and business machines
- **Sharp MZ-2800, MZ-3500, MZ-5500, MZ-6500, MZ-6550**
- **NEC PC-100**, **NEC N5200**
- **Fujitsu FM-8** (if the FM-7 core does not run it), **FM16beta (i186/i286)**, **FM16pi**
- **Fujitsu FMR-30 / 50 / 60 / 70 / 80 / 250 / 280** (no native core)
- **Sord M23, M68**
- **Epson QC-10** (with and without the colour board)
- **Seiko MAP-1010**

### Trainer and single-board kits
- **NEC TK-80, TK-80BS, TK-85**
- **Toshiba EX-80BS**
- **Sharp SM-B-80TE**
- **Gijutsu Hyoron Sha Babbage-2nd**
- **Computer Research CRC-80**
- **Mitec MP-85**
- **ESP TRN Junior**
- **Shinko Sangyo YS-6464A**
- **Canon AX-1 / BX-1** (bx1)

### Consoles, toys and others
- **Gakken TV Boy** (tvboy)
- **Micom Mahjong** (micom_mahjong)
- **Homebrew Z80 TV Game** (z80tvgame_i8255, z80tvgame_z80pio)

## Not yet checked
- Third-party and unofficial cores outside the MiSTer distribution (for example PC-98 and any PC-6001 work in progress) are not fully surveyed. A web search found no PC-6001 or PC-8201 core.
