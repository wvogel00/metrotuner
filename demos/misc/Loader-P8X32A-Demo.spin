{
    --------------------------------------------
    Filename: Loader-Demo.spin
    Author: Jesse Burt
    Description: Simple demo of the misc.loader.p8x32a object
        Loads another connected Propeller with a binary
    Copyright (c) 2020
    Started May 25, 2020
    Updated May 25, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User-modifiable constants
    LED         = cfg#LED1
    SER_RX      = 31
    SER_TX      = 30
    SER_BAUD    = 115_200

' Pins your destination Propeller is connected to
    PROP_RES    = 18
    PROP_P31    = 16
    PROP_P30    = 17
' --

OBJ

    cfg     : "core.con.boardcfg.flip"
    ser     : "com.serial.terminal.ansi"
    time    : "time"
    io      : "io"
    loader  : "misc.loader.p8x32a"

PUB Main | errmsg

    Setup
    ser.str(string("Loading file..."))
    result := loader.Connect(PROP_RES, PROP_P31, PROP_P30, 1, loader#LoadRun, @_binary_def)

    case result
        0:
            ser.str(string("complete"))

        loader#ERRORCONNECT, loader#ERRORVERSION, loader#ERRORCHECKSUM, loader#ERRORPROGRAM, loader#ERRORVERIFY:
            ser.str(string("Load failed: "))
            errmsg := lookup(result: string("Error connecting"), string("Version mismatch"), string("Checksum mismatch"), string("Error during programming"), string("Verification failed"))
            ser.str(errmsg)
            FlashLED(LED, 500)

        OTHER:
            ser.str(string("Load failed: Exception error"))
            FlashLED(LED, 500)

    FlashLED(LED, 100)

PUB Setup

    repeat until ser.StartRXTX (SER_RX, SER_TX, 0, SER_BAUD)
    time.MSleep(30)
    ser.Clear
    ser.Str(string("Serial terminal started", ser#CR, ser#LF))

#include "lib.utility.spin"

DAT
' Binary file to load to destination Propeller
'   NOTE: Binary must be small enough that it fits in _this_ Propeller's RAM, along
'       with this program.
    _binary_def     file    "dummy.binary"

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
