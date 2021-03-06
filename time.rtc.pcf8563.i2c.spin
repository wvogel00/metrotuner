{
    --------------------------------------------
    Filename: time.rtc.pcf8563.i2c.spin
    Author: Jesse Burt
    Description: Driver for the PCF8563 Real Time Clock
    Copyright (c) 2020
    Started Sep 6, 2020
    Updated Sep 7, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SLAVE_WR            = core#SLAVE_ADDR
    SLAVE_RD            = core#SLAVE_ADDR|1

    DEF_SCL             = 28
    DEF_SDA             = 29
    DEF_HZ              = 100_000
    I2C_MAX_FREQ        = core#I2C_MAX_FREQ

' /INT pin active state
    WHEN_TF_ACTIVE      = 0
    INT_PULSES          = 1 << core#TI_TP

VAR

    byte _secs, _mins, _hours                           ' Vars to hold time
    byte _days, _wkdays, _months, _years                ' Order is important!

    byte _clkdata_ok                                    ' Clock data integrity

OBJ

    i2c : "com.i2c"                                     ' PASM I2C Driver
    core: "core.con.pcf8563.spin"                       ' Low-level constants
    time: "time"                                        ' Basic timing functions

PUB Null{}
' This is not a top-level object

PUB Start: okay
' Start using 'default' Propeller I2C pins,
'   at safest universal speed of 100kHz
    okay := startx (DEF_SCL, DEF_SDA, DEF_HZ)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ): okay

    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.setupx(SCL_PIN, SDA_PIN, I2C_HZ)
                time.msleep(1)
                if i2c.present (SLAVE_WR)               ' Response from device?
                    pollrtctime{}                       ' Initial RTC read
                    return okay

    return FALSE                                        ' Something above failed

PUB Stop{}

    i2c.terminate

PUB Defaults{}
' Factory default settings
    clockoutfreq(32768)

PUB ClockDataOk{}: flag
' Flag indicating battery voltage ok/clock data integrity ok
'   Returns:
'       TRUE (-1): Battery voltage ok, clock data integrity guaranteed
'       FALSE (0): Battery voltage low, clock data integrity not guaranteed
    pollrtctime{}
    return _clkdata_ok == 0

PUB ClockOutFreq(freq): curr_freq
' Set frequency of CLKOUT pin, in Hz
'   Valid values: 0, 1, 32, 1024, 32768
'   Any other value polls the chip and returns the current setting
    curr_freq := 0
    readreg(core#CTRL_CLKOUT, 1, @curr_freq)
    case freq
        0:
            freq := 1 << core#FE                        ' Turn off clock output
        1, 32, 1024, 32768:
            freq := lookdownz(freq: 32768, 1024, 32, 1)
        other:
            curr_freq &= core#FD_BITS
            return lookupz(curr_freq: 32768, 1024, 32, 1)

    freq := ((curr_freq & core#FD_MASK & core#FE_MASK) | freq) & core#CTRL_CLKOUT_MASK
    writereg(core#CTRL_CLKOUT, 1, @freq)

PUB Date(ptr_date)

PUB DeviceID{}: id

PUB Days(day): curr_day
' Set day of month
'   Valid values: 1..31
'   Any other value polls the RTC and returns the current day
    case day
        1..31:
            day := int2bcd(day)
            writereg(core#DAYS, 1, @day)
        other:
            pollrtctime{}
            return bcd2int(_days & core#DAYS_MASK)

PUB Hours(hr): curr_hr
' Set hours
'   Valid values: 0..23
'   Any other value polls the RTC and returns the current hour
    case hr
        0..23:
            hr := int2bcd(hr)
            writereg(core#HOURS, 1, @hr)
        other:
            pollrtctime{}
            return bcd2int(_hours & core#HOURS_MASK)

PUB IntClear(mask) | tmp
' Clear interrupts, using a bitmask
'   Valid values:
'       Bits: 1..0
'           1: clear alarm interrupt
'           0: clear timer interrupt
'           For each bit, 0 to leave as-is, 1 to clear
'   Any other value is ignored
    case mask
        %01, %10, %11:
            readreg(core#CTRLSTAT2, 1, @tmp)
            mask := (mask ^ %11) << core#TF             ' Reg bits are inverted
            tmp |= mask
            tmp &= core#CTRLSTAT2_MASK
            writereg(core#CTRLSTAT2, 1, @tmp)
        other:
            return

PUB Interrupt{}: flags
' Flag indicating one or more interrupts asserted
    readreg(core#CTRLSTAT2, 1, @flags)
    flags := (flags >> core#TF) & core#IF_BITS

PUB IntMask(mask): curr_mask
' Set interrupt mask
'   Valid values:
'       Bits: 1..0
'           1: enable alarm interrupt
'           0: enable timer interrupt
'   Any other value polls the chip and returns the current setting
    readreg(core#CTRLSTAT2, 1, @curr_mask)
    case mask
        %00..%11:
        other:
            return curr_mask & core#IE_BITS

    mask := ((curr_mask & core#IE_MASK) | mask) & core#CTRLSTAT2_MASK
    writereg(core#CTRLSTAT2, 1, @mask)

PUB IntPinState(state): curr_state
' Set interrupt pin active state
'   WHEN_TF_ACTIVE (0): /INT is active when timer interrupt asserted
'   INT_PULSES (1): /INT pulses at rate set by TimerClockFreq()
    curr_state := 0
    readreg(core#CTRLSTAT2, 1, @curr_state)
    case state
        WHEN_TF_ACTIVE, INT_PULSES:
        other:
            return (curr_state >> core#TI_TP) & %1

    state := ((curr_state & core#TI_TP_MASK) | state) & core#CTRLSTAT2_MASK
    writereg(core#CTRLSTAT2, 1, @state)

PUB Months(month): curr_month
' Set month
'   Valid values: 1..12
'   Any other value polls the RTC and returns the current month
    case month
        1..12:
            month := int2bcd(month)
            writereg(core#CENTMONTHS, 1, @month)
        other:
            pollrtctime{}
            return bcd2int(_months & core#CENTMONTHS_MASK)

PUB Minutes(minute): curr_min
' Set minutes
'   Valid values: 0..59
'   Any other value polls the RTC and returns the current minute
    case minute
        0..59:
            minute := int2bcd(minute)
            writereg(core#MINUTES, 1, @minute)
        other:
            pollrtctime{}
            return bcd2int(_mins & core#MINUTES_MASK)

PUB Seconds(second): curr_sec
' Set seconds
'   Valid values: 0..59
'   Any other value polls the RTC and returns the current second
    case second
        0..59:
            second := int2bcd(second)
            writereg(core#VL_SECS, 1, @second)
        other:
            pollrtctime{}
            return bcd2int(_secs & core#SECS_BITS)

PUB Timer(val): curr_val
' Set countdown timer value
'   Valid values: 0..255
'   Any other value polls the chip and returns the current setting
'   NOTE: The countdown period in seconds is equal to
'       Timer() / TimerClockFreq()
'       e.g., if Timer() is set to 255, and TimerClockFreq() is set to 1,
'       the period is 255 seconds
    case val
        0..255:
            val &= core#TIMER_MASK
            writereg(core#TIMER, 1, @val)
        other:
            repeat 2                                    ' Datasheet recommends
                curr_val := 0                           ' 2 reads to check for
                readreg(core#TIMER, 1, @curr_val.byte[0]) ' consistent results
                readreg(core#TIMER, 1, @curr_val.byte[1]) '
                if curr_val.byte[0] == curr_val.byte[1]
                    curr_val.byte[1] := 0
                    quit
            return curr_val & core#TIMER_MASK

PUB TimerClockFreq(freq): curr_freq
' Set timer source clock frequency, in Hz
'   Valid values:
'       1_60 (1/60Hz), 1, 64, 4096
'   Any other value polls the chip and returns the current setting
    curr_freq := 0
    readreg(core#CTRL_TIMER, 1, @curr_freq)
    case freq
        1_60, 1, 64, 4096:
            freq := lookdownz(freq: 4096, 64, 1, 1_60)
        other:
            curr_freq &= core#TD_BITS
            return lookupz(curr_freq: 4096, 64, 1, 1_60)

    freq := ((curr_freq & core#TD_MASK) | freq) & core#CTRL_TIMER_MASK
    writereg(core#CTRL_TIMER, 1, @freq)

PUB TimerEnabled(state): curr_state
' Enable timer
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#CTRL_TIMER, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#TE
        other:
            return ((curr_state >> core#TE) & 1) == 1

    if state == 0                                   ' If disabling the timer,
        timerclockfreq(1_60)                        ' set freq to 1/60Hz for
                                                    ' lowest power usage
    state := ((curr_state & core#TE_MASK) | state) & core#CTRL_TIMER_MASK
    writereg(core#CTRL_TIMER, 1, @state)

PUB Weekday(wkday): curr_wkday
' Set day of week
'   Valid values: 1..7
'   Any other value polls the RTC and returns the current day of week
    case wkday
        1..7:
            wkday := int2bcd(wkday-1)
            writereg(core#WEEKDAYS, 1, @wkday)
        other:
            pollrtctime{}
            return bcd2int(_wkdays & core#WEEKDAYS_MASK) + 1

PUB Year(yr): curr_yr
' Set 2-digit year
'   Valid values: 0..99
'   Any other value polls the RTC and returns the current year
    case yr
        0..99:
            yr := int2bcd(yr)
            writereg(core#YEARS, 1, @yr)
        other:
            pollrtctime{}
            return bcd2int(_years & core#YEARS_MASK)

PRI bcd2int(bcd): int
' Convert BCD (Binary Coded Decimal) to integer
    return ((bcd >> 4) * 10) + (bcd // 16)

PRI int2bcd(int): bcd
' Convert integer to BCD (Binary Coded Decimal)
    return ((int / 10) << 4) + (int // 10)

PRI pollRTCTime{}
' Read the time data from the RTC and store it in hub RAM
' Update the clock integrity status bit from the RTC
    readreg(core#VL_SECS, 7, @_secs)
    _clkdata_ok := (_secs >> core#VL) & 1               ' Clock integrity bit

PRI readReg(reg, nr_bytes, ptr_buff) | cmd_pkt, tmp
' Read nr_bytes from device
    case reg                                            ' Validate reg
        $00..$0f:
            cmd_pkt.byte[0] := SLAVE_WR
            cmd_pkt.byte[1] := reg

            i2c.start{}                                 ' Send reg to read
            i2c.wr_block (@cmd_pkt, 2)

            i2c.start{}
            i2c.write (SLAVE_RD)
            i2c.rd_block (ptr_buff, nr_bytes, TRUE)     ' Read it
            i2c.stop{}
        OTHER:
            return

PRI writeReg(reg, nr_bytes, ptr_buff) | cmd_pkt, tmp
' Write nr_bytes to device
    case reg
        $00..$0f:                                       ' Validate reg
            cmd_pkt.byte[0] := SLAVE_WR
            cmd_pkt.byte[1] := reg

            i2c.start{}                                 ' Send reg to write
            i2c.wr_block (@cmd_pkt, 2)

            repeat tmp from 0 to nr_bytes-1
                i2c.write (byte[ptr_buff][tmp])         ' Write it
            i2c.stop{}
        OTHER:
            return


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
