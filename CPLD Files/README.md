# VideoULA V01 – CPLD firmware

Firmware for the XC9572XL-VQ44 (V01 hardware). Current release: **V01 Build 37**.

Note: firmware build numbers are independent of hardware versions and revisions. The
V01 firmware (Build 37) and the V02/V03 firmware (Build 3) use separate numbering.

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

In the 16MHz build, `CLK_6M` is high-Z and the SAA5050 keeps using the
machine's own 6MHz.

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

V01 Build 37 is tested on V01 hardware in both 16MHz and 48MHz modes.
See the main README for the testing status and known limitations.
