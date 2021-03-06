{
    --------------------------------------------
    Filename: PCF8563-Demo.spin
    Author: Jesse Burt
    Description: Demo of the PCF8563 driver
    Copyright (c) 2020
    Started Sep 6, 2020
    Updated Sep 7, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User-modifiable constants
    SER_RX      = 31
    SER_TX      = 30
    SER_BAUD    = 115_200

    I2C_SCL     = 28
    I2C_SDA     = 29
    I2C_HZ      = 400_000
' --

OBJ

    cfg     : "core.con.boardcfg.flip"
    ser     : "com.serial.terminal.ansi"
    time    : "time"
    int     : "string.integer"
    rtc     : "time.rtc.pcf8563.i2c"

PUB Main{} | wkday, mon, day, yr

    setup{}

    repeat{}
        wkday := @weekday[(rtc.weekday(-2) - 1) * 4]    ' Pull strings from
        mon := @month[(rtc.months(-2) - 1) * 4]         ' DAT table below
        day := int.deczeroed(rtc.days(-2), 2)           '
        yr := rtc.year(-2)

        ser.position(0, 3)
        ser.str(wkday)
        ser.printf(string(" %s %s 20%d "), day, mon, yr, 0, 0, 0)

        ser.str(int.deczeroed(rtc.hours(-2), 2))        ' Discrete statements
        ser.char(":")                                   ' due to a bug in
        ser.str(int.deczeroed(rtc.minutes(-2), 2))      ' string.integer
        ser.char(":")
        ser.str(int.deczeroed(rtc.seconds(-2), 2))

PUB Setup{}

    repeat until ser.startrxtx(SER_RX, SER_TX, 0, SER_BAUD)
    time.msleep(30)
    ser.clear{}
    ser.str(string("Serial terminal started", ser#CR, ser#LF))
    if rtc.startx(I2C_SCL, I2C_SDA, I2C_HZ)
        ser.str(string("PCF8563 driver started", ser#CR, ser#LF))
    else
        ser.str(string("PCF8563 driver failed to start - halting", ser#CR, ser#LF))
        rtc.stop{}
        time.msleep(50)
        ser.stop{}

DAT

    weekday
            byte    "Sun", 0
            byte    "Mon", 0
            byte    "Tue", 0
            byte    "Wed", 0
            byte    "Thu", 0
            byte    "Fri", 0
            byte    "Sat", 0

    month
            byte    "Jan", 0
            byte    "Feb", 0
            byte    "Mar", 0
            byte    "Apr", 0
            byte    "May", 0
            byte    "Jun", 0
            byte    "Jul", 0
            byte    "Aug", 0
            byte    "Sep", 0
            byte    "Oct", 0
            byte    "Nov", 0
            byte    "Dec", 0

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
