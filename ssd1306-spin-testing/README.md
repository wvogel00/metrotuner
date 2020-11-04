# ssd1306-spin
--------------

This is a P8X32A/Propeller 1, P2X8C4M64P/Propeller 2 driver object for Solomon Systech's SSD1306 line of OLED display controllers.

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P). Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* I2C connection at up to approx 1MHz (P1), _TBD_ kHz (P2)
* Supports 128x32 and 128x64 displays
* Display mirroring (horizontal and vertical)
* Inverted display
* Variable contrast
* Low-level display control: Logic voltages, oscillator frequency, addressing mode, row/column mapping
* Supports display modules without discrete RESET pin
* Integration with the generic bitmap graphics library

## Requirements

P1/SPIN1:
* spin-standard-library
* P1/SPIN1: 1 extra core/cog for the PASM I2C driver

P2/SPIN2:
* p2-spin-standard-library

Presence of lib.gfx.bitmap library

## Compiler Compatibility

* P1/SPIN1: OpenSpin (tested with 1.00.81)
* P2/SPIN2: FastSpin (tested with 4.2.5-beta)
* ~~BST~~ (incompatible - no preprocessor)
* ~~Propeller Tool~~ (incompatible - no preprocessor)
* ~~PNut~~ (incompatible - no preprocessor)

## Limitations

* Doesn't support display modules that have the RESET pin broken out
* Doesn't support parallel interface-connected displays (currently unplanned)
* Doesn't support hardware-accelerated scrolling features

## TODO

- [ ] Support hw-accelerated scrolling
- [ ] Support SPI-connected displays
- [ ] Support display modules that have a discrete RESET pin
