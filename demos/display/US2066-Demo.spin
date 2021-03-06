{
    --------------------------------------------
    Filename: OLED-US2066-Demo.spin
    Description: Demonstrates functionality of the
     US2066 OLED Display object
    Author: Jesse Burt
    Copyright (c) 2020
    Created Dec 30, 2017
    Updated May 24, 2020
    See end of file for terms of use.
    --------------------------------------------
}
CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User modifiable constants
    LED         = cfg#LED1
    SER_RX      = 31
    SER_TX      = 30
    SER_BAUD    = 115_200

    WIDTH       = 20        ' Your display's dimensions, in character cells
    HEIGHT      = 4

    SCL_PIN     = 28
    SDA_PIN     = 29
    RESET_PIN   = 25        ' I/O pin attached to display's RESET pin
    I2C_HZ      = 400_000
    SLAVE_BIT   = 0         ' Default slave address
' --

    DEMO_DELAY  = 2         ' Delay (sec) between different demos
    MODE_DELAY  = 1         ' Delay (sec) between different modes within a particular demo

VAR

    byte _ser_cog

OBJ

    cfg : "core.con.boardcfg.flip"
    time: "time"
    io  : "io"
    oled: "display.oled.us2066.i2c"
    ser : "com.serial.terminal.ansi"

PUB Main

    Setup

    Greet_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Count_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    DoubleHeight_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Contrast_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Position_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Cursor_demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Invert_demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    FontWidth_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    Mirror_Demo
    time.Sleep (DEMO_DELAY)
    oled.Clear

    oled.Stop
    FlashLED (LED, 100)

PUB Contrast_Demo | i

    oled.Position (0, 0)
    oled.printf(string("Change contrast\nlevel:"), 0, 0, 0, 0, 0, 0)
    case HEIGHT
        2:
            repeat i from -255 to 255 step 1
                oled.Position (7, 1)
                oled.Contrast (||i)
                oled.DecUns (||i, 3)
                oled.Char(" ")
                oled.Hex(||i, 2)
                time.MSleep (10)
        4:
            oled.Newline
            oled.DoubleHeight (1)

            repeat i from -255 to 255 step 1
                oled.Position (0, 2)
                oled.Contrast (||i)
                oled.DecUns(||i, 3)
                oled.Char(" ")
                oled.Hex(||i, 2)
                oled.Char(" ")
                oled.Bin(||i, 8)
                time.MSleep (10)

    oled.DoubleHeight (0)

PUB Count_Demo | i

    case HEIGHT
        2:
            oled.Position (0, 0)
            oled.printf(string("Rapidly changing\ndisplay contents"), 0, 0, 0, 0, 0, 0)
            time.sleep (3)
            oled.clear
            oled.printf(string("Compare to LCD!\ni = "), 0, 0, 0, 0, 0, 0)
            repeat i from 0 to 3000
                oled.Position (4, 1)
                oled.Dec (i)
        4:
            oled.Position (0, 0)
            oled.printf(string("Rapidly changing\ndisplay contents\n(compare to LCD!)\ni = "), 0, 0, 0, 0, 0, 0)
            repeat i from 0 to 3000
                oled.Position (4, 3)
                oled.Dec (i)

PUB Cursor_demo | delay, dbl_mode

    delay := 25
    case HEIGHT
        2:
            repeat dbl_mode from 0 to 3 step 3
                oled.Clear
                oled.DoubleHeight (dbl_mode)
                oled.CursorMode (0)
                oled.Position (0, 0)
                oled.StrDelay (string("No cursor   (0)"), delay)
                time.Sleep (2)
                oled.ClearLine (0)

                oled.CursorMode (1)
                oled.Position (0, 0)
                oled.StrDelay (string("Block/blink (1)"), delay)
                time.Sleep (2)
                oled.ClearLine (0)

                oled.CursorMode (2)
                oled.Position (0, 0)
                oled.StrDelay (string("Underscore  (2)"), delay)
                time.Sleep (2)
                oled.ClearLine (0)

                oled.CursorMode (3)
                oled.Position (0, 0)
                oled.StrDelay (string("Under./blink(3)"), delay)
                time.Sleep (2)
        4:
            repeat dbl_mode from 0 to 2 step 2
                oled.Clear
                oled.DoubleHeight (dbl_mode)
                oled.CursorMode (0)
                oled.Position (0, 0)
                oled.StrDelay (string("Cursor:"), delay)

                oled.Position (0, 1)
                oled.StrDelay (string("None            (0)"), delay)
                time.Sleep (2)
                oled.ClearLine (1)

                oled.CursorMode (1)
                oled.Position (0, 1)
                oled.StrDelay (string("Block/blink     (1)"), delay)
                time.Sleep (2)
                oled.ClearLine (1)

                oled.CursorMode (2)
                oled.Position (0, 1)
                oled.StrDelay (string("Underscore      (2)"), delay)
                time.Sleep (2)
                oled.ClearLine (1)

                oled.CursorMode (3)
                oled.Position (0, 1)
                oled.StrDelay (string("Underscore/blink(3)"), delay)
                time.Sleep (2)

    oled.DoubleHeight (0)
    oled.CursorMode (0)

PUB DoubleHeight_Demo | mode, line

    case HEIGHT
        2:
            mode := 0
            repeat 6
                oled.DoubleHeight (mode)
                repeat line from 0 to 1
                    oled.Position (0, line)
                    oled.Str (string("Double-height"))
                time.Sleep (MODE_DELAY)
                mode += 3
                if mode > 3
                    mode  := 0
            oled.DoubleHeight (0)
        4:
            repeat mode from 0 to 4
                oled.DoubleHeight (mode)
                oled.Position (14, 0)
                oled.printf(string("Mode %d"), mode, 0, 0, 0, 0, 0)
                repeat line from 0 to 3
                    oled.Position (0, line)
                    oled.Str (string("Double-height"))
                time.Sleep (MODE_DELAY)

PUB FontWidth_demo | px, dbl_mode

    oled.Clear

    repeat dbl_mode from 0 to 3 step 3
        oled.DoubleHeight (dbl_mode)
        repeat 2
            repeat px from 6 to 5
                oled.FontWidth (px)
                oled.Position (0, 0)
                oled.printf(string("%d-pixel width"), px, 0, 0, 0, 0, 0)
                time.Sleep (MODE_DELAY)

    oled.FontWidth (5)
    oled.DoubleHeight (0)

PUB Greet_Demo

    case HEIGHT
        2:
            oled.Position (0, 0)
            oled.Str (@w16l1)
            time.Sleep (1)

            oled.Position (0, 1)
            oled.Str (@w16l2)
            time.Sleep (1)

        4:
            oled.Position (0, 0)
            oled.Str (@w20l1)
            time.Sleep (1)

            oled.Position (0, 1)
            oled.Str (@w20l2)
            time.Sleep (1)

            oled.Position (0, 2)
            oled.Str (@w20l3)
            time.Sleep (1)

            oled.Position (0, 3)
            oled.Str (@w20l4)

    time.Sleep (1)

PUB Invert_demo | i

    oled.Clear
    oled.Position (0, 0)
    oled.Str (string("Display"))

    repeat i from 1 to 3
        oled.DisplayInverted (TRUE)
        oled.Position (WIDTH-8, HEIGHT-1)
        oled.Str (string("INVERTED"))
        time.Sleep (MODE_DELAY)
        oled.DisplayInverted (FALSE)
        oled.Position (WIDTH-8, HEIGHT-1)
        oled.Str (string("NORMAL  "))
        time.Sleep (MODE_DELAY)

PUB Mirror_Demo | row, col

    oled.Clear

    case HEIGHT
        2:
            row := 2
            col := WIDTH-12
        4:
            row := 0
            col := WIDTH-13

    oled.MirrorH (FALSE)
    oled.MirrorV (FALSE)
    oled.ClearLine (0)
    oled.Position (0, 0)
    oled.Str (string("Mirror OFF"))
    time.Sleep (2)

    oled.MirrorH (TRUE)
    oled.MirrorV (FALSE)
    oled.ClearLine (0)
    oled.Position (col, 0)
    oled.Str (string("Mirror HORIZ."))
    time.Sleep (2)

    oled.MirrorH (FALSE)
    oled.MirrorV (TRUE)
    oled.ClearLine (0)
    oled.Position (0, row)
    oled.Str (string("Mirror VERT."))
    time.Sleep (2)

    oled.MirrorH (TRUE)
    oled.MirrorV (TRUE)
    oled.ClearLine (0)
    oled.Position (col, row)
    oled.Str (string("Mirror BOTH"))
    time.Sleep (2)

    oled.Clear
    oled.MirrorH (FALSE)
    oled.MirrorV (FALSE)

PUB Position_Demo | x, y

    repeat y from 0 to HEIGHT-1
        repeat x from 0 to WIDTH-1
            oled.Position(0, 0)
            oled.printf(string("Position %d,%d "), x, y, 0, 0, 0, 0)
            oled.Position((x-1 #> 0), y)
            oled.Char(" ")
            oled.Char("-")
            time.MSleep (25)

PUB Setup

    repeat until _ser_cog := ser.StartRXTX (SER_RX, SER_TX, 0, SER_BAUD)
    time.MSleep(30)
    ser.Clear
    ser.Str (string("Serial terminal started", ser#CR, ser#LF))
'    if oled.Start (RESET_PIN)                                        ' Use default I2C I/O pin and freq. settings. Just specify RESET_PIN
    if oled.Startx (SCL_PIN, SDA_PIN, RESET_PIN, I2C_HZ, SLAVE_BIT)   ' Use this line instead of the above to use all custom settings
        ser.Str (string("US2066 driver started", ser#CR, ser#LF))
    else
        ser.Str (string("US2066 driver failed to start - halting", ser#CR, ser#LF))
        oled.stop
        time.MSleep (500)
        ser.Stop
        FlashLED (cfg#LED1, 500)

    oled.MirrorH (FALSE)
    oled.MirrorV (FALSE)
    oled.Clear
    oled.Position (0, 0)
    oled.DisplayVisibility (oled#NORMAL)
    time.MSleep (100)

#include "lib.utility.spin"

DAT

'                  0|    |    |    |15
    w16l1   byte{0}"Parallax P8X32A", 0
    w16l2   byte{1}"(US2066 2x16)  ", 0

'                  0|    |    |    |   |19
    w20l1   byte{0}"  Parallax P8X32A   ", 0
    w20l2   byte{1}"       on the       ", 0
    w20l3   byte{2}"    US2066 OLED     ", 0
    w20l4   byte{3}"        4x20        ", 0


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
