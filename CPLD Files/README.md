# VideoULA V01 – CPLD firmware

Firmware for the XC9572XL-VQ44 (V01 hardware). Current release: **V01 Build 38**.

Note: firmware build numbers are independent of hardware versions and revisions. The
V01 firmware (Build 38) and the V02/V03 firmware (Build 7) use separate numbering.

## Files

The Verilog source is common to all V01 hardware revisions. The pin assignments
(`.ucf`) differ between revisions, so each hardware revision has its own folder
containing its `.ucf` and ISE project file.

| Hardware revision | Folder | Pin file |
|---|---|---|
| Rev01 | `Rev01/` | `VideoULA.ucf` |
| Rev02 | `Rev02/` | `VideoULA.ucf` |
| Rev03 | `Rev03/` | `VideoULA.ucf` (same pinout as Rev04) |
| Rev04 | `Rev04/` | `VideoULA.ucf` (same pinout as Rev03) |

| File | Purpose |
|---|---|
| `src/VideoULA.v` | Verilog source (common to all revisions) |
| `RevNN/VideoULA.ucf` | Pin assignments for that hardware revision |
| `RevNN/VideoULA.xise` | Xilinx ISE project file for that hardware revision |

Use the folder that matches the revision marked on your board. Each `.xise` refers
to `../src/VideoULA.v` and its own `.ucf` by relative path. Keep this layout.

ISE writes its generated files to the `working/` folder inside each revision folder.
The folder must exist before you build, so keep it (it contains a placeholder
`README.txt`).

## Toolchain

The tools below are for a **Windows** build environment.

- Xilinx ISE Design Suite 14.7 (WebPACK)
- Device: XC9572XL, VQ44 package, speed grade -10

## Choosing the 16MHz or 48MHz build

Near the top of `src/VideoULA.v`, enable exactly one of:

    `define CLK_48MHZ
    //`define CLK_16MHZ

For the 16MHz build, swap the comment markers so `CLK_16MHZ` is active and
`CLK_48MHZ` is commented out. Do not enable both.

In both builds the CPLD generates `CLK_6M`. In the 16MHz build it is derived
from the 16MHz clock (using both clock edges) and is phase-locked to the 1MHz
clock. It has a small fixed jitter (about 10ns), so M7CALIB can show slightly
more noise than in the 48MHz build. To use the CPLD's `CLK_6M`, connect it to
the SAA5050 (see the main README); otherwise the machine's own 6MHz is used.

### CLK_AUTO (experimental)

`CLK_AUTO` is a third option, for the unified Rev02 to Rev04 boards. It reads
the mode at power-up from the `SRAM_nWE` pin (JP2), so one build covers both
clocks. Comment out `CLK_48MHZ` and enable `CLK_AUTO` instead. It has only been
tested on Rev01 hardware (with `CLK_AUTO_INVERT_STRAP` choosing the mode on
boards that have no strap jumper). It uses 70 to 72 of the 72 macrocells, so
there is no headroom, and because the strap is read at power-up it may
occasionally pick the wrong mode. Power-cycle to recover. The fixed builds are
smaller and have had more testing.

## ISE settings

The design is close to the device's capacity, so these settings matter:

- Fitter Implementation Template: **Optimise Speed** (the Density option caused
  timing problems).
- Macrocell Power Mode: **Std**. Low Power did not boot.
- 16MHz build: the fitter needs `-pterms 14` (set it in the fitter options in ISE).

## Programming

Create the JED file in ISE (Implement Design, then Generate Programming File)
and program the CPLD over JTAG. All V01 boards have a JTAG header.

## Status

V01 Build 38 is tested on V01 Rev01 hardware, on a Model B and a Master 128.

| Build | Macrocells used |
|---|---|
| 48MHz (`CLK_48MHZ`) | 50/72 |
| 16MHz (`CLK_16MHZ`) | 53/72 |
| `CLK_AUTO` | 70 to 72/72 (depends on fitter settings) |

### Build 38

Back-port of the V02/V03 improvements:

- Palette write timing (V02/V03 Build 6): a three-cycle write (capture, prepare,
  write) so the SRAM address is stable for a full cycle before nWE falls. The data
  bus is only driven during the write cycle, using a registered enable. Early or
  late write timing can be chosen with `SRAM_WRITE_LATE`.
- Cursor alignment (V02/V03 Builds 4 and 5): modes 0 to 6 use no cursor delay,
  and mode 7 uses one stage (62.5ns).
- 16MHz mode generates `CLK_6M` from the 16MHz clock. Its edge terms come directly
  from the main clock counter, so the 6MHz stays phase-locked to the 1MHz after every
  power-up.
- New experimental `CLK_AUTO` option (see above).

The SRAM write fix was identified by hoglet and radiofan, and the 16MHz-derived
6MHz approach is based on radiofan's.

### Model B results (V01 Rev01)

Cursor and mode 7 test screen (M7CALIB), with the build and 6MHz source shown.

| Build | 6MHz source | Cursor | M7CALIB |
|---|---|---|---|
| 48MHz | CPLD | Correct, modes 0 to 7 | Pixel perfect |
| 48MHz | Motherboard | Correct, modes 0 to 7 | A bit noisy |
| 16MHz | CPLD | Correct, modes 0 to 7 | A little noisy |
| 16MHz | Motherboard | Correct, modes 0 to 7 | A bit noisy |

RGBtoHDMI calibration survived a power cycle in every case. Exile, Lancelot,
Planetoid and Zork loaded and ran with no sparkles or other corruption. `CLK_AUTO`
was also tested on the Model B in both modes with the CPLD 6MHz (cursors correct,
games working, calibration surviving power cycles).

### Master 128 results (V01 Rev01)

Mode 7 cursor, with the build and 6MHz source shown. Modes 0 to 6 were correct in
every case.

| Build | 6MHz source | Mode 7 cursor | M7CALIB |
|---|---|---|---|
| 48MHz | CPLD | Correct | Clean |
| 48MHz | Motherboard | One column (half a pixel) left | Clean |
| 16MHz | CPLD | Correct | Minor noise |
| 16MHz | Motherboard | One column (half a pixel) left | Clean |

RGBtoHDMI calibration survived a power cycle in every case. `CLK_AUTO` gave the same
results as the matching fixed build. The noise on M7CALIB with the CPLD 6MHz in the
16MHz build is small and can depend on how well RGBtoHDMI calibrated. The results
depend on the machine's own 6MHz circuit.

See the main README for the known limitations.
