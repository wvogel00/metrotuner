{
    --------------------------------------------
    Filename: MXD2125-Graphics-Demo.spin
    Author: Jesse Burt
    Description: Graphical demo of the
        Memsic MXD2125 driver
        (based on demo originally by Beau Schwabe)
    Started 2009
    Updated Sep 8, 2020
    See end of file for terms of use.
    --------------------------------------------
}

'***************************************
'*  Memsic 2125 Accelerometer DEMO     *
'*  Author: Beau Schwabe               *
'*  Copyright (c) 2009 Parallax, Inc.  *
'*  See end of file for terms of use.  *
'***************************************


CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' accomodate display memory and stack
    _stack      = ($3000 + $3000 + 100) >> 2

    X_TILES     = 16
    Y_TILES     = 12

    PARAMCOUNT  = 14
    BITMAP_BASE = $2000
    DISPLAY_BASE= $5000

' -- User-modifiable constants
    MXD_XPIN    = 0
    MXD_YPIN    = 1

' --

{
         ┌──────────┐
Tout ──│1  6│── VDD
         │  ┌────┐  │
Yout ──│2 │ /\ │ 5│── Xout
         │  │/  \│  │
 VSS ──│3 └────┘ 4│── VSS
         └──────────┘

}

VAR

    long tv_status     '0/1/2 = off/visible/invisible           read-only
    long tv_enable     '0/? = off/on                            write-only
    long tv_pins       '%ppmmm = pins                           write-only
    long tv_mode       '%ccinp = chroma,interlace,ntsc/pal,swap write-only
    long tv_screen     'pointer to screen (words)               write-only
    long tv_colors     'pointer to colors (longs)               write-only
    long tv_hc         'horizontal cells                        write-only
    long tv_vc         'vertical cells                          write-only
    long tv_hx         'horizontal cell expansion               write-only
    long tv_vx         'vertical cell expansion                 write-only
    long tv_ho         'horizontal offset                       write-only
    long tv_vo         'vertical offset                         write-only
    long tv_broadcast  'broadcast frequency (Hz)                write-only
    long tv_auralcog   'aural fm cog                            write-only

    word screen[X_TILES * Y_TILES]
    long colors[64]

OBJ

    cfg     : "core.con.boardcfg.demoboard"
    tv      : "display.tv"
    gr      : "display.tv.graphics"
    mxd2125 : "sensor.accel.2dof.mxd2125.pwm"

PUB Start{} | i, dx, dy, d, e, f, fdeg, offset, bar, dx1, dy1, dx2, dy2, cordlength, size

    setup{}

    size := 95
    repeat
        gr.clear{}                                      ' clear bitmap

        d := mxd2125.theta{}                            ' Get raw 32-bit deg
        d := d >> 19                                    ' 32-bit angle > 13-Bit

        mxd2125.acceltilt(@fdeg, @e, 0)
        f := 180 - fdeg                                 ' Get xTilt Deg
        f := (f * 1024) / 45                            ' Deg to 13-Bit Angle
        e := 180 - e                                    ' Get yTilt Deg
        e := (e * 1024) / 45                            ' Deg to 13-Bit Angle

        gr.color(2)

        gr.arc(0, 0, size, size, 0, 256, 33, 2)         ' Great Circle
        offset := -fdeg                                 ' Horizon and Ticks
        repeat i from (-180 + offset) to (180 + offset)
            if (i - offset) // 5 == 0
                if i => -size and i =< size
                    dx := (sin(-e + 4096) * i) ~> 16
                    dy := (cos(-e + 4096) * i) ~> 16
                    if i == offset                      ' Draw moving Horizon
                        cordlength := ^^((size * size)-(fdeg * fdeg))
                        dx1 := dx + (sin(-e + 2048) * cordlength) ~> 16
                        dy1 := dy + (cos(-e + 2048) * cordlength) ~> 16
                        dx2 := dx + (sin(-e - 2048) * cordlength) ~> 16
                        dy2 := dy + (cos(-e - 2048) * cordlength) ~> 16
                        gr.plot(dx1, dy1)
                        gr.line(dx2, dy2)
                        gr.text(dx, dy, string("0 "))
                    else                                'Draw Horizon Ticks...
                        if (i-offset) // 5 == 0         ' small every 5 deg
                            bar := 3
                        if (i-offset) // 45 == 0        ' large every 45 deg
                            bar := 10

                            case i-offset
                                -180:
                                    gr.text(dx, dy, string("-180 "))
                                -135:
                                    gr.text(dx, dy, string("-135 "))
                                -90:
                                    gr.text(dx, dy, string("-90 "))
                                -45:
                                    gr.text(dx, dy, string("-45 "))
                                45:
                                    gr.text(dx, dy, string("45 "))
                                90:
                                    gr.text(dx, dy, string("90 "))
                                135:
                                    gr.text(dx, dy, string("135 "))
                                180:
                                    gr.text(dx, dy, string("180 "))

                        dx1 := dx + (sin(-e + 2048) * bar) ~> 16
                        dy1 := dy + (cos(-e + 2048) * bar) ~> 16
                        dx2 := dx + (sin(-e - 2048) * bar) ~> 16
                        dy2 := dy + (cos(-e - 2048) * bar) ~> 16
                        gr.plot(dx1, dy1)
                        gr.line(dx2, dy2)

                    dx := (sin(-e + 4096){*i}) ~> 16  ' Draw fixed Horizon
                    dy := (cos(-e + 4096){*i}) ~> 16
                    dx1 := dx + (sin(-e + 2048) * size) ~> 16
                    dy1 := dy + (cos(-e + 2048) * size) ~> 16
                    dx2 := dx + (sin(-e - 2048) * size) ~> 16
                    dy2 := dy + (cos(-e - 2048) * size) ~> 16
                    gr.color(1)
                    gr.plot(dx1, dy1)
                    gr.line(dx2, dy2)
                    gr.color(2)

        gr.colorwidth(3, 1)
        repeat i from 0 to 8192 step 1024               ' Draw Rotational Ticks
            'Draw Ticks in motion
            gr.arc(0, 0, ((size * 70) / 90), ((size * 70) / 90), i-d, 0, 1, 0)
            gr.arc(0, 0, ((size * 65) / 90), ((size * 65) / 90), i-d, 0, 1, 1)
        gr.width(0)

        'Draw reference '0' Deg in motion
        dx1 := 8 + (sin(d + 2048) * ((size * 50) / 90)) ~> 16
        dy1 := 8 + (cos(d + 2048) * ((size * 50) / 90)) ~> 16
        gr.text(dx1, dy1, string("0"))

        gr.color(1)
        repeat i from 0 to 8192 step 128                ' Rotational Ticks Text
            if (i / 8) // 128 == 0
                dx1 := 8 + (sin(-i + 2048) * ((size * 65) / 90)) ~> 16
                dy1 := 8 + (cos(-i + 2048) * ((size * 65) / 90)) ~> 16
                case i
                    0:
                        gr.text(dx1, dy1, string("0"))
                    1024:
                        gr.text(dx1, dy1, string("45"))
                    2048:
                        gr.text(dx1, dy1, string("90"))
                    3072:
                        gr.text(dx1, dy1, string("135"))
                    4096:
                        gr.text(dx1, dy1, string("180"))
                    5120:
                        gr.text(dx1, dy1, string("225"))
                    6144:
                        gr.text(dx1, dy1, string("270"))
                    7168:
                        gr.text(dx1, dy1, string("315"))

                ' fixed Rotational Ticks
                gr.arc(0, 0, ((size * 75) / 90), ((size * 75) / 90), i, 0, 1, 0)
            else
                gr.arc(0, 0, ((size * 85) / 90), ((size * 85) / 90), i, 0, 1, 0)
            gr.arc(0, 0, size, size, i, 0, 1, 1 )
        gr.color(2)
        gr.copy(DISPLAY_BASE)

PUB Cos(angle): x
' Get cosine of angle (0-8191)
    x := sin(angle + $800)

PUB Sin(angle): y
' Get sine of angle (0-8191)
    y := angle << 1 & $FFE
    if angle & $800
        y := word[$F000 - y]
    else
        y := word[$E000 + y]
    if angle & $1000
        -y

PUB Setup{} | i, dx, dy, clk_scale

    'start tv
    longmove(@tv_status, @tvparams, PARAMCOUNT)
    tv_screen := @screen
    tv_colors := @colors
    tv.start(@tv_status)

    'init colors
    repeat i from 0 to 63
        colors[i] := $9D_07_1C_02

    'init tile screen
    repeat dx from 0 to tv_hc - 1
        repeat dy from 0 to tv_vc - 1
            screen[dy * tv_hc + dx] := DISPLAY_BASE >> 6 + dy + dx * tv_vc + ((dy & $3F) << 10)

    'start and setup graphics
    gr.start
    gr.setup(16, 12, 128, 96, BITMAP_BASE)

    mxd2125.start(MXD_XPIN, MXD_YPIN)                   ' Initialize Mx2125

    clk_scale := clkfreq / 500_000                      ' based on system clock

    gr.textmode(1, 1, 6, %%22)

DAT

tvparams                long    0                       ' status
                        long    1                       ' enable

                        long    %001_0101               ' pins

                        long    %0000                   ' mode
                        long    0                       ' screen
                        long    0                       ' colors
                        long    X_TILES                 ' hc
                        long    Y_TILES                 ' vc
                        long    10                      ' hx
                        long    1                       ' vx
                        long    0                       ' ho
                        long    0                       ' vo
                        long    0                       ' broadcast
                        long    0                       ' auralcog

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

