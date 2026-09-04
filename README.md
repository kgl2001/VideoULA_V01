# VideoULA V01 — BBC Micro Video ULA Replacement
## 44-pin Xilinx XC9572XL CPLD Version

This repository contains the hardware design and firmware for the VideoULA V01, a drop-in replacement for the VC2069 Video ULA (IC6) in the Acorn BBC Micro Model B.

---

## Project Overview

The original BBC Micro Video ULA (IC6) is a custom ASIC that is no longer manufactured. Failed or missing ULAs result in a non-functional machine. This project provides a modern replacement using a CPLD and a small external SRAM for palette storage.

There are three hardware versions of this replacement, each in a separate repository:

| Version | CPLD | Macrocells | Tool | Repository |
|---|---|---|---|---|
| **V01** | Xilinx XC9572XL-10-VQ44 | 72 | ISE 14.7 | This repo |
| V02 | Xilinx XC9572XL-10-VQ64 | 72 | ISE 14.7 | [VideoULA_V02](https://github.com/kgl2001/VideoULA_V02) |
| V03 | Atmel ATF1504AS-10AU44 | 64 | Quartus 13.0 SP1 | [VideoULA_V03](https://github.com/kgl2001/VideoULA_V03) |

All three versions share the same 28-pin DIP footprint as the original ULA and are pin-compatible with the BBC Micro motherboard.

---

## V01 Hardware

- **CPLD**: Xilinx XC9572XL-10-VQ44 (72 macrocells, 3.3V core, 5V tolerant I/O)
- **SRAM**: ISSI IS62C256AL-45TLI (32K×8, 5V, TSOP-28, 45ns) — only locations 0-15 and bits 0-3 used
- **Oscillator**: 48MHz SMD oscillator (3225 package, 5V) — for 48MHz operating mode only
- **LDO**: XC6206P332MR (SOT-23, 3.3V) — powers CPLD core

### Hardware Revisions

| Revision | Status | Changes |
|---|---|---|
| Rev01 | Built and tested | Initial release |
| Rev02 | PCB designed, not yet built | Added 47Ω series resistor and 74LVC1G17 Schmitt trigger buffer on CLK_IN; CPLD pin assignments updated |
| Rev03 | PCB designed, not yet built | Added 74LV6T17 to buffer all clock outputs (8/4/2/1MHz, CRTC) for Master 128 compatibility |
| Rev04 | PCB designed, not yet built | Repositioned JTAG header |

Note: Only Rev01 has been built and tested. Rev02 onwards incorporate improvements identified during Rev01 testing.

### CLK_IN Reliability Daughterboard

During testing of Rev01 on BBC Micro machines with the original 16MHz clock circuit, some machines showed reliability issues in 16MHz operating mode — particularly on cold startup. Investigation revealed that the BBC's 16MHz crystal oscillator circuit produces a noisy clock signal that the CPLD occasionally misinterprets as spurious edges, causing display glitches.

To address this without waiting for a new PCB revision, a small standalone buffer board was developed. This daughterboard:

- Plugs into the BBC Micro motherboard in place of the VideoULA V01
- The VideoULA V01 then plugs into the daughterboard
- Intercepts the 16MHz clock signal from the BBC motherboard
- Passes it through a 47Ω series resistor and 74HCT14E Schmitt trigger buffer before it reaches the CPLD
- Passes all other signals through unchanged

The 74HCT14E was chosen as a through-hole part for ease of hand soldering. Rev02+ PCB designs use the smaller surface-mount 74LVC1G17 in conjunction with a series resistor to achieve the same signal conditioning in a more compact form.

This fix was confirmed to resolve the cold startup reliability issues on affected machines. The improvement has been incorporated into Rev02 of the V01 PCB and all subsequent hardware versions.

The daughterboard design files are included in this repository.

---

## Firmware

The firmware is written in Verilog and built using Xilinx ISE 14.7.

### Operating Modes

Two firmware builds are required — one per operating mode. To switch modes, reprogram the CPLD with the appropriate `.jed` file. A solder bridge on the PCB selects whether the 48MHz oscillator or the BBC's 16MHz clock is connected to the CPLD clock input.

#### 48MHz Mode (recommended)
- Uses the onboard 48MHz oscillator as the master clock
- Generates all BBC clock outputs (8/4/2/1MHz, CRTC, 6MHz) internally
- Provides clean, phase-locked 6MHz output for the SAA5050 teletext chip (tD ≈ 20ns ✓)
- Works reliably on all machines from cold power-up, including those with noisy clock circuits
- Build: uncomment `` `define CLK_48MHZ `` in `VideoULA.v`

#### 16MHz Mode
- Uses the BBC motherboard's 16MHz clock as the master clock
- No onboard oscillator required
- May show brief display noise on cold startup on machines with noisy 16MHz clock circuits
- The CLK_IN daughterboard resolves this on Rev01; Rev02+ has the fix built in
- Build: uncomment `` `define CLK_16MHZ `` in `VideoULA.v`

### ISE Fitter Settings (critical)

| Setting | Value | Notes |
|---|---|---|
| Implementation Template | **Optimise Speed** | Density causes timing failures at temperature |
| Macrocell Power | **Std** | Low Power prevents BBC from booting |
| Output Slew Rate | Fast | |
| Default Powerup Value | Low | |
| Pterms | **14** (16MHz build only) | Default 25 causes silent fit failure in 16MHz build |

### Build Instructions

1. Open Xilinx ISE 14.7
2. Create a new project targeting `XC9572XL-10-VQ44`
3. Add `src/VideoULA.v` and `src/VideoULA.ucf` to the project
4. Select the operating mode by uncommenting the appropriate `define` in `VideoULA.v`
5. Set fitter options as above
6. Run `Implement Design` to generate the `.jed` file
7. Program the CPLD using iMPACT or a compatible JTAG programmer

---

## SRAM Wiring

The external SRAM stores the 16-entry colour palette (4 bits per entry):

| SRAM Pin | Connection |
|---|---|
| A0-A3 | CPLD SRAM_ADDR[0:3] |
| A4-A14 | GND (tie low) |
| D0-D3 | CPLD SRAM_DATA[0:3] (bidirectional) |
| D4-D7 | Leave unconnected |
| /WE | CPLD SRAM_nWE |
| /OE | GND (always output enabled) |
| /CS | GND (always selected) |

---

## 6MHz Clock for Mode 7 (Teletext)

The SAA5050 teletext chip requires a 6MHz clock with a specific phase relationship to the 1MHz system clock (tD = 6-60ns from 6MHz rising edge to 1MHz falling edge).

- **48MHz mode**: The CPLD generates a clean, phase-locked 6MHz output on the CLK_6M pin (tD ≈ 20ns ✓). This can be connected to the SAA5050 via an IC37 replacement board.
- **16MHz mode**: The BBC motherboard's existing 6MHz generation circuit is used. The CPLD CLK_6M output is held high-Z.

---

## PCB Design Notes

The PCB has been designed using KiCAD V10 as a 2-layer board. It can easily be changed to a 4-layer board with GND/Power planes on the inner layers if signal integrity is a concern.

### JLCPCB Fabrication

The board design includes a 5×5mm silkscreen box on the underside of the PCB. This is used by JLCPCB to position a QR code serial number. When ordering from JLCPCB:

- Select **Specify position** in the QR code / 2D barcode options during the ordering process
- If this option is not selected, JLCPCB will print the 5×5mm silkscreen box as-is and attempt to place the QR code at a different location of their choosing

If not using JLCPCB, the chosen fabricator will likely print the 5×5mm box as a plain white square on the PCB. To avoid this, remove the silkscreen box from the PCB design and regenerate the Gerber files before submitting.

### Assembly

A combined CPL (Component Placement List) and BOM (Bill of Materials) Excel file is included in the Gerbers folder. This can be used directly with the JLCPCB PCBA (PCB Assembly) service.

Note that the JLCPCB Economy PCBA process only assembles components on one side of the PCB. Select the **top side** for assembly — this leaves only the SRAM and its associated decoupling capacitor to be hand soldered to the underside of the board.

---

## Known Limitations

- **Cold startup noise (16MHz mode, standard clock machines)**: Machines with noisy 16MHz clock circuits may show brief display noise on cold power-up. Use the CLK_IN daughterboard (Rev01) or upgrade to Rev02+ which has the fix built in. The 48MHz operating mode is not affected.
- **Master 128 compatibility**: V01 has not been tested on the Master 128. Clock output buffering (added in Rev03) may be required for full Master 128 compatibility.
- **SCART/HDMI adapter compatibility**: Some SCART→HDMI display adapters may show minor pixel artefacts with non-standard screen modes. RGBtoHDMI and direct CRT connections are not affected.

---

## Compatibility

Tested on BBC Micro Model B with original clock circuit and with clock fixer modification. Not tested on BBC Master 128.

---

## Credits

- **Ken Lowe** — PCB design, Verilog development and testing
- **hoglet (Stardot forums)** — Clock architecture analysis, DRAM timing analysis, community testing
- **Stardot community** — Testing, feedback and suggestions

---

## Licence

Hardware: [Creative Commons BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

Firmware: [MIT Licence](https://opensource.org/licenses/MIT)
