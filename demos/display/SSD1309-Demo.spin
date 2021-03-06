{
    --------------------------------------------
    Filename: SSD1309-Demo.spin
    Description: Demo of the SSD1309 driver
    Author: Jesse Burt
    Copyright (c) 2020
    Created: Apr 26, 2018
    Updated: May 6, 2020
    See end of file for terms of use.
    --------------------------------------------
}


CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

    BUFFSZ      = (WIDTH * HEIGHT) / 8
    XMAX        = WIDTH-1
    YMAX        = HEIGHT-1

' -- User-modifiable constants:
    SER_RX      = 31
    SER_TX      = 30
    SER_BAUD    = 115_200
    LED         = cfg#LED1

    CS_PIN      = 3
    SCK_PIN     = 0
    SDA_PIN     = 1
    DC_PIN      = 2
    RES_PIN     = 4

    WIDTH       = 128
    HEIGHT      = 64
' --

OBJ

    cfg         : "core.con.boardcfg.flip"
    ser         : "com.serial.terminal.ansi"
    time        : "time"
    io          : "io"
    oled        : "display.oled.ssd1309.spi"
    int         : "string.integer"
    fnt5x8      : "font.5x8"

VAR

    long _stack_timer[50]
    long _timer_set
    long _rndSeed
    byte _framebuff[BUFFSZ]
    byte _timer_cog, _ser_cog

PUB Main | time_ms

    Setup
    oled.ClearAll

    oled.MirrorH(TRUE)
    oled.MirrorV(TRUE)

    Demo_Greet
    time.Sleep (5)
    oled.ClearAll

    time_ms := 5_000

    ser.position (0, 3)

    Demo_SineWave (time_ms)
    oled.ClearAll

    Demo_TriWave (time_ms)
    oled.ClearAll

    Demo_MEMScroller(time_ms, $0000, $FFFF-BUFFSZ)
    oled.ClearAll

    Demo_Bitmap (time_ms, @Beanie)
    oled.ClearAll

    Demo_LineSweepX(time_ms)
    oled.ClearAll

    Demo_LineSweepY(time_ms)
    oled.ClearAll

    Demo_Line (time_ms)
    oled.ClearAll

    Demo_Plot (time_ms)
    oled.ClearAll

    Demo_BouncingBall (time_ms, 5)
    oled.ClearAll

    Demo_Circle(time_ms)
    oled.ClearAll

    Demo_Wander (time_ms)
    oled.ClearAll

    Demo_SeqText (time_ms)
    oled.ClearAll

    Demo_RndText (time_ms)

    Demo_Contrast(2, 1)
    oled.ClearAll

    Stop
    FlashLED(LED, 100)

PUB Demo_BouncingBall(testtime, radius) | iteration, bx, by, dx, dy
' Draws a simple ball bouncing off screen edges
    bx := (rnd(XMAX) // (WIDTH - radius * 4)) + radius * 2  'Pick a random screen location to
    by := (rnd(YMAX) // (HEIGHT - radius * 4)) + radius * 2 ' start from
    dx := rnd(4) // 2 * 2 - 1                               'Pick a random direction to
    dy := rnd(4) // 2 * 2 - 1                               ' start moving

    ser.str(string("Demo_BouncingBall - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        bx += dx
        by += dy
        if (by =< radius OR by => HEIGHT - radius)          'If we reach the top or bottom of the screen,
            dy *= -1                                        ' change direction
        if (bx =< radius OR bx => WIDTH - radius)           'Ditto with the left or right sides
            dx *= -1

        oled.Circle (bx, by, radius, 1)
        oled.Update
        iteration++
        oled.Clear

    Report(testtime, iteration)
    return iteration

PUB Demo_Bitmap(testtime, bitmap_addr) | iteration
' Continuously redraws bitmap at address bitmap_addr
    ser.str(string("Demo_Bitmap - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        oled.Bitmap (bitmap_addr, BUFFSZ, 0)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_Circle(testtime) | iteration, x, y, r
' Draws circles at random locations
    ser.str(string("Demo_Circle - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        x := rnd(XMAX)
        y := rnd(YMAX)
        r := rnd(YMAX/2)
        oled.Circle (x, y, r, -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_Contrast(reps, delay_ms) | contrast_level
' Fades out and in display contrast
    ser.str(string("Demo_Contrast - N/A"))

    repeat reps
        repeat contrast_level from 255 to 1
            oled.Contrast (contrast_level)
            time.MSleep (delay_ms)
        repeat contrast_level from 0 to 254
            oled.Contrast (contrast_level)
            time.MSleep (delay_ms)

    ser.newline

PUB Demo_Greet
' Display the banner/greeting on the OLED
    oled.FGColor(1)
    oled.BGColor(0)
    oled.Position (0, 0)
    oled.Str (string("SSD1309 on the"))

    oled.Position (0, 1)
    oled.Str (string("Parallax"))

    oled.Position (0, 2)
    oled.Str (string("P8X32A @ "))
    oled.Str (int.Dec(clkfreq/1_000_000))
    oled.Str (string("MHz"))

    oled.Position (0, 3)
    oled.Str (int.DecPadded (WIDTH, 3))

    oled.Position (3, 3)
    oled.Str (string("x"))

    oled.Position (4, 3)
    oled.Str (int.DecPadded (HEIGHT, 2))
    oled.Update

PUB Demo_Line (testtime) | iteration
' Draws random lines with color -1 (invert)
    ser.str(string("Demo_Line - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        oled.Line (rnd(XMAX), rnd(YMAX), rnd(XMAX), rnd(YMAX), -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_LineSweepX (testtime) | iteration, x
' Draws lines top left to lower-right, sweeping across the screen, then
'  from the top-down
    x := 0

    ser.str(string("Demo_LineSweepX - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        x++
        if x > XMAX
            x := 0
        oled.Line (x, 0, XMAX-x, YMAX, -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_LineSweepY (testtime) | iteration, y
' Draws lines top left to lower-right, sweeping across the screen, then
'  from the top-down
    y := 0

    ser.str(string("Demo_LineSweepY - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        y++
        if y > YMAX
            y := 0
        oled.Line (XMAX, y, 0, YMAX-y, -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_MEMScroller(testtime, start_addr, end_addr) | iteration, pos, st, en
' Dumps Propeller Hub RAM (and/or ROM) to the display buffer
    pos := start_addr

    ser.str(string("Demo_MEMScroller - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        pos += 128
        if pos >end_addr
            pos := start_addr
        oled.Bitmap (pos, BUFFSZ, 0)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_Plot(testtime) | iteration, x, y
' Draws random pixels to the screen, with color -1 (invert)
    ser.str(string("Demo_Plot - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        oled.Plot (rnd(XMAX), rnd(YMAX), -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_Sinewave(testtime) | iteration, x, y, modifier, offset, div
' Draws a sine wave the length of the screen, influenced by the system counter
    ser.str(string("Demo_Sinewave - "))

    case HEIGHT
        32:
            div := 4096
        64:
            div := 2048
        OTHER:
            div := 2048

    offset := YMAX/2                                    ' Offset for Y axis

    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        repeat x from 0 to XMAX
            modifier := (||cnt / 1_000_000)           ' Use system counter as modifier
            y := offset + sin(x * modifier) / div
            oled.Plot(x, y, 1)

        oled.Update
        iteration++
        oled.Clear

    Report(testtime, iteration)
    return iteration

PUB Demo_SeqText(testtime) | iteration, col, row, maxcol, maxrow, ch, st
' Sequentially draws the whole font table to the screen, then random characters
    oled.FGColor(1)
    oled.BGColor(0)
    maxcol := (WIDTH/oled.FontWidth)-1
    maxrow := (HEIGHT/oled.FontHeight)-1
    ch := $20

    ser.str(string("Demo_SeqText - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        repeat row from 0 to maxrow
            repeat col from 0 to maxcol
                ch++
                if ch > $7F
                    ch := $20
                oled.Position (col, row)
                oled.Char (ch)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_RndText(testtime) | iteration, col, row, maxcol, maxrow, st

    oled.FGColor(1)
    oled.BGColor(0)
    maxcol := (WIDTH/oled.FontWidth)-1
    maxrow := (HEIGHT/oled.FontHeight)-1

    ser.str(string("Demo_RndText - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        repeat row from 0 to maxrow
            repeat col from 0 to maxcol
                oled.Position (col, row)
                oled.Char (32 #> rnd(127))
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration

PUB Demo_TriWave(testtime) | iteration, x, y, ydir
' Draws a simple triangular wave
    ydir := 1
    y := 0

    ser.str(string("Demo_TriWave - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        repeat x from 0 to XMAX
            if y == YMAX
                ydir := -1
            if y == 0
                ydir := 1
            y := y + ydir
            oled.Plot (x, y, 1)
        oled.Update
        iteration++
        oled.Clear

    Report(testtime, iteration)
    return iteration

PUB Demo_Wander(testtime) | iteration, x, y, d
' Draws randomly wandering pixels
    _rndSeed := cnt
    x := XMAX/2
    y := YMAX/2

    ser.str(string("Demo_Wander - "))
    _timer_set := testtime
    iteration := 0

    repeat while _timer_set
        case d := rnd(4)
            1:
                x += 2
                if x > XMAX
                    x := 0
            2:
                x -= 2
                if x < 0
                    x := XMAX
            3:
                y += 2
                if y > YMAX
                    y := 0
            4:
                y -= 2
                if y < 0
                    y := YMAX
        oled.Plot (x, y, -1)
        oled.Update
        iteration++

    Report(testtime, iteration)
    return iteration


PUB Sin(angle)
' Return the sine of angle
    result := angle << 1 & $FFE
    if angle & $800
       result := word[$F000 - result]   ' Use sine table from ROM
    else
       result := word[$E000 + result]
    if angle & $1000
       -result

PUB RND(maxval) | i
' Return random number up to maxval
    i :=? _rndSeed
    i >>= 16
    i *= (maxval + 1)
    i >>= 16

    return i

PRI Report(testtime, iterations)

    ser.str(string("Total iterations: "))
    ser.dec(iterations)

    ser.str(string(", Iterations/sec: "))
    ser.dec(iterations / (testtime/1000))

    ser.str(string(", Iterations/ms: "))
    Decimal( (iterations * 1_000) / testtime, 1_000)
    ser.newline

PRI Decimal(scaled, divisor) | whole[4], part[4], places, tmp
' Display a fixed-point scaled up number in decimal-dot notation - scale it back down by divisor
'   e.g., Decimal (314159, 100000) would display 3.14159 on the termainl
'   scaled: Fixed-point scaled up number
'   divisor: Divide scaled-up number by this amount
    whole := scaled / divisor
    tmp := divisor
    places := 0

    repeat
        tmp /= 10
        places++
    until tmp == 1
    part := int.DecZeroed(||(scaled // divisor), places)

    ser.Dec (whole)
    ser.Char (".")
    ser.Str (part)

PRI cog_Timer | time_left

    repeat
        repeat until _timer_set
        time_left := _timer_set

        repeat
            time_left--
            time.MSleep(1)
        while time_left > 0
        _timer_set := 0

PUB Setup

    repeat until ser.StartRXTX (SER_RX, SER_TX, %0000, SER_BAUD)
    time.MSleep(30)
    ser.Clear
    ser.Str (string("Serial terminal started", ser#CR, ser#LF))

    if oled.Start (WIDTH, HEIGHT, CS_PIN, SCK_PIN, SDA_PIN, DC_PIN, RES_PIN, @_framebuff)
        ser.Str (string("SSD1309 driver started. Draw buffer @ $"))
        ser.Hex (oled.Address (-2), 8)
        oled.Defaults
        oled.ClockFreq (540)
        oled.FontSize (6, 8)
        oled.FontAddress (fnt5x8.BaseAddr)
    else
        ser.Str (string("SSD1309 driver failed to start - halting"))
        Stop
        FlashLED (LED, 500)

    _timer_cog := cognew(cog_Timer, @_stack_timer)

PUB Stop

    oled.Powered(FALSE)
    oled.Stop
    cogstop(_timer_cog)
    ser.Stop

#include "lib.utility.spin"
#include "propeller-beanie-1bpp.spin"

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
