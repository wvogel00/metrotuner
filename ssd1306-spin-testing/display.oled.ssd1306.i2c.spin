{
    --------------------------------------------
    Filename: display.oled.ssd1306.i2c.spin
    Description: Driver for Solomon Systech SSD1306 I2C OLED display drivers
    Author: Jesse Burt
    Copyright (c) 2020
    Created: Apr 26, 2018
    Updated: Mar 28, 2020
    See end of file for terms of use.
    --------------------------------------------
}
#define SSD130X
#include "lib.gfx.bitmap.spin"

CON

    SLAVE_WR        = core#SLAVE_ADDR
    SLAVE_RD        = core#SLAVE_ADDR|1

    DEF_HZ          = 400_000
    MAX_COLOR       = 1
    BYTESPERPX      = 1

' Display visibility modes
    NORMAL          = 0
    ALL_ON          = 1
    INVERTED        = 2

OBJ

    core    : "core.con.ssd1306"
    time    : "time"
    i2c     : "com.i2c"

VAR

    long _ptr_drawbuffer
    word _buff_sz
    word BYTESPERLN
    byte _disp_width, _disp_height, _disp_xmax, _disp_ymax
    byte _sa0

PUB Null
' This is not a top-level object

PUB Start(width, height, SCL_PIN, SDA_PIN, I2C_HZ, dispbuffer_address, SLAVE_LSB): okay
' Start the driver with custom settings
' Valid values:
'       width: 0..128
'       height: 32, 64
'       SCL_PIN: 0..63
'       SDA_PIN: 0..63
'       I2C_HZ: ~1200..1_000_000
'       SLAVE_LSB: 0, 1
    _sa0 := ||(SLAVE_LSB == 1) << 1
    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            i2c.SetupX (SCL_PIN, SDA_PIN, I2C_HZ)    'I2C Object Started?
            time.MSleep (20)
            if i2c.Present (SLAVE_WR | _sa0)                                         'Response from device?
                _disp_width := width
                _disp_height := height
                _disp_xmax := _disp_width-1
                _disp_ymax := _disp_height-1
                _buff_sz := (_disp_width * _disp_height) / 8
                BYTESPERLN := _disp_width * BYTESPERPX

                Address(dispbuffer_address)
                return TRUE
    return FALSE                                                'If we got here, something went wrong

PUB Stop

    Powered(FALSE)
    i2c.Terminate

PUB Defaults
' Apply power-on-reset default settings
    Powered(FALSE)
    ClockFreq (372)
    DisplayLines(_disp_height)
    DisplayOffset(0)
    DisplayStartLine(0)
    ChargePumpReg(TRUE)
    AddrMode (0)
    MirrorH(FALSE)
    MirrorV(FALSE)
    case _disp_height
        32:
            COMPinCfg(0, 0)
        64:
            COMPinCfg(1, 0)
        OTHER:
            COMPinCfg(0, 0)
    Contrast(127)
    PrechargePeriod (1, 15)
    COMLogicHighLevel (0_77)
    DisplayVisibility(NORMAL)
    DisplayBounds(0, 0, _disp_xmax, _disp_ymax)
    Powered(TRUE)

PUB Address(addr)
' Set framebuffer address
    case addr
        $0004..$7FFF-_buff_sz:
            _ptr_drawbuffer := addr
        OTHER:
            return _ptr_drawbuffer

PUB AddrMode(mode)
' Set Memory Addressing Mode
'   Valid values:
'       0: Horizontal addressing mode
'       1: Vertical
'      *2: Page
'   Any other value is ignored
    case mode
        0, 1:
        OTHER:
            return

    writeReg(core#CMD_MEM_ADDRMODE, 1, mode)

PUB ChargePumpReg(enabled)
' Enable Charge Pump Regulator when display power enabled
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value is ignored
    case ||enabled
        0, 1:
            enabled := lookupz(||enabled: $10, $14)
        OTHER:
            return

    writeReg(core#CMD_CHARGEPUMP, 1, enabled)

PUB ClearAccel
' Dummy method

PUB ClockFreq(kHz)
' Set display internal oscillator frequency, in kHz
'   Valid values: 333, 337, 342, 347, 352, 357, 362, 367, 372, 377, 382, 387, 392, 397, 402, 407
'   Any other value is ignored
'   NOTE: Range is interpolated, based solely on the range specified in the datasheet, divided into 16 steps
    case kHz
        core#FOSC_MIN..core#FOSC_MAX:
            kHz := lookdownz(kHz: 333, 337, 342, 347, 352, 357, 362, 367, 372, 377, 382, 387, 392, 397, 402, 407) << core#FLD_OSCFREQ
        OTHER:
            return

    writeReg(core#CMD_SETOSCFREQ, 1, kHz)

PUB COMLogicHighLevel(level)
' Set COMmon pins high logic level, relative to Vcc
'   Valid values:
'       0_65: 0.65 * Vcc
'      *0_77: 0.77 * Vcc
'       0_83: 0.83 * Vcc
'   Any other value sets the default value
    case level
        0_65:
            level := %000 << 4
        0_77:
            level := %010 << 4
        0_83:
            level := %011 << 4
        OTHER:
            level := %010 << 4

    writeReg(core#CMD_SETVCOMDESEL, 1, level)

PUB COMPinCfg(pin_config, remap) | config
' Set COM Pins Hardware Configuration and Left/Right Remap
'   Valid values:
'       pin_config: 0: Sequential                      1: Alternative (POR)
'       remap:      0: Disable Left/Right remap (POR)  1: Enable remap
'   Any other value sets the default value
    config := %0000_0010
    case pin_config
        0:
        OTHER:
            config := config | (1 << 4)

    case remap
        1:
            config := config | (1 << 5)
        OTHER:

    writeReg(core#CMD_SETCOM_CFG, 1, config)

PUB Contrast(level)
' Set Contrast Level
'   Valid values: 0..255 (default: 127)
'   Any other value sets the default value
    case level
        0..255:
        OTHER:
            level := 127

    writeReg(core#CMD_CONTRAST, 1, level)

PUB DisplayBounds(sx, sy, ex, ey)
' Set displayable area
    ifnot lookup(sx: 0..127) or lookup(sy: 0..63) or lookup(ex: 0..127) or lookup(ey: 0..63)
        return

    sy >>= 3
    ey >>= 3
    writeReg(core#CMD_SET_COLADDR, 2, (ex << 8) | sx)
    writeReg(core#CMD_SET_PAGEADDR, 2, (ey << 8) | sy)

PUB DisplayInverted(enabled) | tmp
' Invert display colors
    case ||enabled
        0:
            DisplayVisibility(NORMAL)
        1:
            DisplayVisibility(INVERTED)
        OTHER:
            return FALSE

PUB DisplayLines(lines)
' Set total number of display lines
'   Valid values: 16..64
'   Typical values: 32, 64
'   Any other value is ignored
    case lines
        16..64:
            lines -= 1
        OTHER:
            return

    writeReg(core#CMD_SETMUXRATIO, 1, lines)

PUB DisplayOffset(offset)
' Set display offset/vertical shift
'   Valid values: 0..63 (default: 0)
'   Any other value sets the default value
    case offset
        0..63:
        OTHER:
            offset := 0

    writeReg(core#CMD_SETDISPOFFS, 1, offset)

PUB DisplayStartLine(start_line)
' Set Display Start Line
'   Valid values: 0..63 (default: 0)
'   Any other value sets the default value
    case start_line
        0..63:
        OTHER:
            start_line := 0

    writeReg($40, 0, start_line)

PUB DisplayVisibility(mode) | tmp
' Set display visibility
    case mode
        NORMAL:
            writeReg (core#CMD_RAMDISP_ON, 0, 0)
            writeReg (core#CMD_DISP_NORM, 0, 0)
        ALL_ON:
            writeReg (core#CMD_RAMDISP_ON, 0, 1)
        INVERTED:
            writeReg (core#CMD_DISP_NORM, 0, 1)
        OTHER:
            return FALSE

PUB MirrorH(enabled)
' Mirror display, horizontally
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value is ignored
'   NOTE: Takes effect only after next display update
    case ||enabled
        0, 1: enabled := ||enabled
        OTHER:
            return

    writeReg(core#CMD_SEG_MAP0, 0, enabled)

PUB MirrorV(enabled)
' Mirror display, vertically
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value is ignored
'   NOTE: Takes effect only after next display update
    case ||enabled
        0:
        1: enabled := 8
        OTHER:
            return

    writeReg(core#CMD_COMDIR_NORM, 0, enabled)

PUB Powered(enabled) | tmp
' Enable display power
    case ||enabled
        0, 1:
            enabled := ||enabled + core#CMD_DISP_OFF
        OTHER:
            return
    writeReg(enabled, 0, 0)

PUB PrechargePeriod(phs1_clks, phs2_clks)
' Set display refresh pre-charge period, in display clocks
'   Valid values: 1..15 (default: 2, 2)
'   Any other value sets the default value
    case phs1_clks
        1..15:
        OTHER:
            phs1_clks := 2

    case phs2_clks
        1..15:
        OTHER:
            phs2_clks := 2

    writeReg(core#CMD_SETPRECHARGE, 1, (phs2_clks << 4) | phs1_clks)

PUB Update | tmp
' Write display buffer to display
    DisplayBounds(0, 0, _disp_xmax, _disp_ymax)

    i2c.start
    i2c.write (SLAVE_WR | _sa0)
    i2c.write (core#CTRLBYTE_DATA)
    i2c.Wr_Block(_ptr_drawbuffer, _buff_sz)
    i2c.stop

PUB WriteBuffer(buff_addr, buff_sz) | tmp
' Write alternate buffer to display
'   buff_sz: bytes to write
'   buff_addr: address of buffer to write to display
    DisplayBounds(0, 0, _disp_xmax, _disp_ymax)

    i2c.start
    i2c.write (SLAVE_WR | _sa0)
    i2c.write (core#CTRLBYTE_DATA)
    i2c.Wr_Block(buff_addr, _buff_sz)
    i2c.stop

PRI writeReg(reg, nr_bytes, val) | cmd_packet[2], tmp, ackbit
' Write to device internal registers
    cmd_packet.byte[0] := SLAVE_WR | _sa0
    cmd_packet.byte[1] := core#CTRLBYTE_CMD
    case nr_bytes
        0:
            cmd_packet.byte[2] := reg | val 'Simple command
        1:
            cmd_packet.byte[2] := reg       'Command w/1-byte argument
            cmd_packet.byte[3] := val
        2:
            cmd_packet.byte[2] := reg       'Command w/2-byte argument
            cmd_packet.byte[3] := val & $FF
            cmd_packet.byte[4] := (val >> 8) & $FF
        OTHER:
            return FALSE

    i2c.start
    repeat tmp from 0 to 2 + nr_bytes
        ackbit := i2c.write (cmd_packet.byte[tmp])
        if ackbit == i2c#NAK
          i2c.stop
          return ($DEAD << 16)|tmp
    i2c.stop

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}
