# 6MHz Interface Boards

Two small drop-in replacement boards that let the VideoULA CPLD supply the 6MHz clock to the SAA5050 teletext chip on a BBC Micro.

| Board | Fits | Replaces | Folder |
|---|---|---|---|
| IC37 board | BBC Model B | IC37 (74LS04) | [Rev01 - IC37 (Model B)](Rev01%20-%20IC37%20(Model%20B)) |
| IC25 board | BBC Master 128 | IC25 (74LS86) | [Rev01 - IC25 (Master)](Rev01%20-%20IC25%20(Master)) |

## Why these boards exist

In 48MHz mode the CPLD generates a clean 6MHz clock, phase-locked to the other video clocks (CLK_6M). Mode 7 gives its cleanest picture, and a correctly aligned cursor on both Model B and Master, when that clock is fed to the teletext IC instead of the motherboard's own 6MHz circuit.

The motherboard generates its 6MHz in the last gate of IC37 (Model B, pin 8) or IC25 (Master, pin 11). Each board replaces the original chip with a socketed 74HCT part, and lets you disconnect that final gate from the motherboard's 6MHz line and drive the line from the CPLD instead.

The boards are only needed to use the CPLD's CLK_6M. Without them the motherboard's own 6MHz circuit is used, as normal.

## Parts

The originals are 74LS parts, so the boards use **74HCT** parts, which run from 5V with TTL-compatible inputs. Do not substitute 3.3V logic (74LVC and similar).

| Board | Part | Package | JLCPCB |
|---|---|---|---|
| IC37 | 74HCT04 | TSSOP-14 | C131317 |
| IC25 | 74HCT86 | TSSOP-14 | C842458 |
| IC37 | 100nF decoupling capacitor (C37) | 0603 | C14663 |
| IC25 | 100nF decoupling capacitor (C25) | 0603 | C14663 |

The JLCPCB BOM covers only the SMD parts (the HCT chip and the capacitor). The through-hole parts are **not** in the BOM and must be fitted by hand:

- Two 7-pin round (machined) pin headers, soldered into the board's DIP pin positions. These plug into the motherboard socket.
- The 2-pin right-angle header J1, on the underside.

## Solder bridge settings

Both boards (IC37 and IC25) have two 3-pad solder bridges, JP1 and JP2, on the underside of the PCB, with identical settings. They are bridged 1-2 as shipped (the default). To change position, cut the thin track between pads 1 and 2 and bridge the pads you want with solder.

| Setting | JP1 | JP2 |
|---|---|---|
| **VideoULA 6MHz (default)**: CPLD drives the 6MHz line | bridge 1-2 | bridge 1-2 |
| **Inverted VideoULA 6MHz**: CPLD clock, inverted by the on-board gate | bridge 1-2 | bridge 2-3 |
| **Original 6MHz**: the motherboard's own circuit, as if the original chip were fitted | bridge 2-3 | bridge 2-3 |

For the default, the on-board gate is disconnected from the motherboard, and its input is tied to the CPLD clock so it does not float.

On the IC25 board the gate is an XOR with one input tied to 5V on the Master motherboard, so it acts as an inverter, just as the IC37 gate does.

## Connecting the CPLD

J1 is a 2-pin right-angle header fitted on the underside of the PCB. The labels are printed on the top silkscreen:

| J1 pin | Label | Use |
|---|---|---|
| 1 | 6MHz | Connect to the CPLD ULA's CLK_6M output |
| 2 | HSync | Added to aid testing; not needed in operation. Leave unconnected. (Silkscreen reads "HSyn" as there was no room for the full name.) |

## Fitting

1. Desolder the original chip (IC37 on a Model B, IC25 on a Master) from the motherboard, and fit a 14-pin DIP socket in its place. Note the orientation (pin 1).
2. Solder the round pin headers to the board, then plug the board into the socket, pin 1 matching.
3. Check the solder bridges (default is the VideoULA 6MHz).
4. Connect J1 to the CPLD ULA's CLK_6M.
5. Build the CPLD in either the 48MHz or the 16MHz mode (see the firmware READMEs).

### Without removing the chip

If you would rather not remove IC37 / IC25, you can cut the output leg of the gate that drives the 6MHz signal (pin 8 of IC37 on a Model B, pin 11 of IC25 on a Master) and connect the CPLD's CLK_6M to the teletext IC's 6MHz input with a clip lead (pin 19 of IC5 on a Model B, pin 19 of IC32 on a Master). Cutting the leg is a permanent modification to the chip.

## Status

Rev 01 has been built and tested in both the IC37 (Model B) and IC25 (Master) versions, on a Model B and a Master 128.

The 48MHz build gives the cleanest 6MHz. The 16MHz build now also works with the CPLD's 6MHz: it is generated from the 16MHz clock and phase-locked to the 1MHz clock. It has a small fixed jitter (about 10ns), so M7CALIB can show slightly more noise than in the 48MHz build. (An earlier 16MHz build generated the 6MHz from the 48MHz oscillator and could not be phase-locked to the 16MHz clock.)

## Files

Each folder is a KiCAD project (KiCAD 10) with schematic, PCB, a `3DModels` folder, and `Gerbers` for JLCPCB fabrication. The 3D model path is relative to the project, so keep the folder structure intact.
