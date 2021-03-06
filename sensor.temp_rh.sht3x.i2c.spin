{
    --------------------------------------------
    Filename: sensor.temp_rh.sht3x.i2c.spin
    Author: Jesse Burt
    Description: Driver for Sensirion SHT3x series Temperature/Relative Humidity sensors
    Copyright (c) 2020
    Started Nov 19, 2017
    Updated Aug 9, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SLAVE_WR        = core#SLAVE_ADDR
    SLAVE_RD        = core#SLAVE_ADDR|1

    DEF_SCL         = 28
    DEF_SDA         = 29
    DEF_HZ          = 100_000
    I2C_MAX_FREQ    = core#I2C_MAX_FREQ

    MSB             = 1
    LSB             = 0

    NODATA_AVAIL    = $E000_0000

' Measurement repeatability
    LOW             = 0
    MED             = 1
    HIGH            = 2

' Measurement modes
    SINGLE          = 0
    CONT            = 1

' Temperature scales
    C               = 0
    F               = 1

VAR

    word _lasttemp, _lastrh
    byte _temp_scale
    byte _repeatability
    byte _addr_bit
    byte _measure_mode
    byte _drate_hz

OBJ

    i2c : "com.i2c"
    core: "core.con.sht3x"
    time: "time"
    crc : "math.crc"

PUB Null{}
' This is not a top-level object

PUB Start{}: okay                                               ' Default to "standard" Propeller I2C pins and 100kHz

    return startx(DEF_SCL, DEF_SDA, DEF_HZ, 0)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ, ADDR_BIT): okay

    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.setupx (SCL_PIN, SDA_PIN, I2C_HZ)    'I2C Object Started?
                time.msleep (1)
                case ADDR_BIT
                    0:
                        _addr_bit := 0
                    other:
                        _addr_bit := 1 << 1
                if i2c.present (SLAVE_WR | _addr_bit)           'Response from device?
                    if serialnum{}
                        reset{}
                        clearstatus{}
                        return okay

    return FALSE                                                'If we got here, something went wrong

PUB Stop{}

    i2c.terminate{}

PUB ClearStatus{}
' Clears the status register
    writereg(core#CLEARSTATUS, 0, 0)
    time.msleep(1)

PUB DataRate(Hz): curr_rate | tmp
' Output data rate, in Hz
'   Valid values: 0_5 (0.5Hz), 1, 2, 4, 10
'   Any other value returns the current setting
'   NOTE: Applies to continuous (CONT) OpMode, only
'   NOTE: Sensirion notes that at the highest measurement rate (10Hz), self-heating of the sensor might occur
    case Hz
        0, 5, 0.5:
            tmp := core#MEAS_PERIODIC_0_5 | lookupz(_repeatability: core#RPT_LO_0_5, core#RPT_MED_0_5, core#RPT_HI_0_5)         ' Measurement rate and repeatability are configured in the same register
            _drate_hz := Hz
        1:
            tmp := core#MEAS_PERIODIC_1 | lookupz(_repeatability: core#RPT_LO_1, core#RPT_MED_1, core#RPT_HI_1)
            _drate_hz := Hz
        2:
            tmp := core#MEAS_PERIODIC_2 | lookupz(_repeatability: core#RPT_LO_2, core#RPT_MED_2, core#RPT_HI_2)
            _drate_hz := Hz
        4:
            tmp := core#MEAS_PERIODIC_4 | lookupz(_repeatability: core#RPT_LO_4, core#RPT_MED_4, core#RPT_HI_4)
            _drate_hz := Hz
        10:
            tmp := core#MEAS_PERIODIC_10 | lookupz(_repeatability: core#RPT_LO_10, core#RPT_MED_10, core#RPT_HI_10)
            _drate_hz := Hz
        other:
            return _drate_hz
    stopcontmeas{}                                              ' Stop any measurements that might be ongoing
    writereg(tmp, 0, 0)
    _measure_mode := CONT

PUB HeaterEnabled(state): curr_state
' Enable/Disable built-in heater
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: Per SHT3x datasheet, this is for plausability checking only
    case ||(state)
        0, 1:
            state := lookupz(||(state): core#HEATERDIS, core#HEATEREN)
            writereg(state, 0, 0)
        other:
            curr_state := 0
            readreg(core#STATUS, 3, @curr_state)
            curr_state >>= 8                                                   ' Chop off CRC
            return ((curr_state >> core#FLD_HEATER) & %1) == 1

PUB Humidity{}: rh | tmp[2]
' Current Relative Humidity, in hundredths of a percent
'   Returns: Integer
'   (e.g., 4762 is equivalent to 47.62%)
    case _measure_mode
        SINGLE:
            oneshotmeasure(@tmp)

        CONT:
            pollmeasure(@tmp)

    _lastrh := (tmp.byte[2] << 8) | tmp.byte[1]

    return calcrh(_lastrh)

PUB IntRHHiClear(level): curr_lvl
' High RH interrupt: clear level, in percent
'   Valid values: 0..100
'   Any other value polls the chip and returns the current setting, in hundredths of a percent
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_HI_CLR, 2, @curr_lvl)
    case level
        0..100:
            level := rhpct_7bit (level)
        other:
            return rh7bit_pct (curr_lvl)

    level := (curr_lvl & core#MASK_ALERTLIM_RH) | level
    writereg(core#ALERTLIM_WR_HI_CLR, 2, @level)

PUB IntRHHiThresh(level): curr_lvl
' High RH interrupt: trigger level, in percent
'   Valid values: 0..100
'   Any other value polls the chip and returns the current setting, in hundredths of a percent
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_HI_SET, 2, @curr_lvl)
    case level
        0..100:
            level := rhpct_7bit (level)
        other:
            return rh7bit_pct (curr_lvl)

    level := (curr_lvl & core#MASK_ALERTLIM_RH) | level
    writereg(core#ALERTLIM_WR_HI_SET, 2, @level)

PUB IntRHLoClear(level): curr_lvl
' Low RH interrupt: clear level, in percent
'   Valid values: 0..100
'   Any other value polls the chip and returns the current setting, in hundredths of a percent
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_LO_CLR, 2, @curr_lvl)
    case level
        0..100:
            level := rhpct_7bit (level)
        other:
            return rh7bit_pct (curr_lvl)

    level := (curr_lvl & core#MASK_ALERTLIM_RH) | level
    writereg(core#ALERTLIM_WR_LO_CLR, 2, @level)

PUB IntRHLoThresh(level): curr_lvl
' Low RH interrupt: trigger level, in percent
'   Valid values: 0..100
'   Any other value polls the chip and returns the current setting, in hundredths of a percent
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_LO_SET, 2, @curr_lvl)
    case level
        0..100:
            level := rhpct_7bit (level)
        other:
            return rh7bit_pct (curr_lvl)

    level := (curr_lvl & core#MASK_ALERTLIM_RH) | level
    writereg(core#ALERTLIM_WR_LO_SET, 2, @level)

PUB IntTempHiClear(level): curr_lvl
' High temperature interrupt: clear level, in degrees C
'   Valid values: -45..130
'   Any other value polls the chip and returns the current setting, in hundredths of a degree C
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_HI_CLR, 2, @curr_lvl)
    case level
        -45..130:
            level := tempc_9bit (level)
        other:
            return temp9bit_c (curr_lvl & $1ff)

    level := (curr_lvl & core#MASK_ALERTLIM_TEMP) | level
    writereg(core#ALERTLIM_WR_HI_CLR, 2, @level)

PUB IntTempHiThresh(level): curr_lvl
' High temperature interrupt: trigger level, in degrees C
'   Valid values: -45..130
'   Any other value polls the chip and returns the current setting, in hundredths of a degree C
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_HI_SET, 2, @curr_lvl)
    case level
        -45..130:
            level := tempc_9bit (level)
        other:
            return temp9bit_c (curr_lvl & $1ff)

    level := (curr_lvl & core#MASK_ALERTLIM_TEMP) | level
    writereg(core#ALERTLIM_WR_HI_SET, 2, @level)

PUB IntTempLoClear(level): curr_lvl
' Low temperature interrupt: clear level, in degrees C
'   Valid values: -45..130
'   Any other value polls the chip and returns the current setting, in hundredths of a degree C
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_LO_CLR, 2, @curr_lvl)
    case level
        -45..130:
            level := tempc_9bit (level)
        other:
            return temp9bit_c (curr_lvl)

    level := (curr_lvl & core#MASK_ALERTLIM_TEMP) | level
    writereg(core#ALERTLIM_WR_LO_CLR, 2, @level)

PUB IntTempLoThresh(level): curr_lvl
' Low temperature interrupt: trigger level, in degrees C
'   Valid values: -45..130
'   Any other value polls the chip and returns the current setting, in hundredths of a degree C
    curr_lvl := 0
    readreg(core#ALERTLIM_RD_LO_SET, 2, @curr_lvl)
    case level
        -45..130:
            level := tempc_9bit (level)
        other:
            return temp9bit_c (curr_lvl & $1ff)

    level := (curr_lvl & core#MASK_ALERTLIM_TEMP) | level
    writereg(core#ALERTLIM_WR_LO_SET, 2, @level)

PUB LastHumidity{}: rh
' Previous Relative Humidity measurement, in hundredths of a percent
'   Returns: Integer
'   (e.g., 4762 is equivalent to 47.62%)
    return calcrh(_lastrh)

PUB LastTemperature{}: temp
' Previous Temperature measurement, in hundredths of a degree
'   Returns: Integer
'   (e.g., 2105 is equivalent to 21.05 deg C)
    return calctemp(_lasttemp)

PUB OpMode(mode): curr_mode
' Set device operating mode
'   Valid values
'      *SINGLE (0): single-shot measurements
'       CONT (1): continuously measure
'   Any other value returns the current setting
    case mode
        SINGLE:
            stopcontmeas{}
        CONT:
            stopcontmeas{}
            datarate (_drate_hz)
        other:
            return _measure_mode

    _measure_mode := mode

PUB Repeatability(level): result | tmp
' Set measurement repeatability/stability
'   Valid values: LOW (0), MED (1), HIGH (2)
'   Any other value returns the current setting
    case level
        LOW, MED, HIGH:
            _repeatability := level
        other:
            return _repeatability

PUB Temperature{}: temp | tmp[2]
' Current Temperature, in hundredths of a degree
'   Returns: Integer
'   (e.g., 2105 is equivalent to 21.05 deg C)
    case _measure_mode
        SINGLE:
            oneshotmeasure(@tmp)

        CONT:
            pollmeasure(@tmp)

    _lasttemp := (tmp.byte[5] << 8) | tmp.byte[4]

    return calctemp(_lasttemp)

PUB TempScale(scale): curr_scale
' Set temperature scale used by Temperature method
'   Valid values:
'       C (0): Celsius
'       F (1): Fahrenheit
'   Any other value returns the current setting
    case scale
        C, F:
            _temp_scale := scale
        other:
            return _temp_scale

PUB SerialNum{}: result
' Return device Serial Number
    readreg(core#READ_SERIALNUM, 4, @result)

PUB Reset{}
' Perform Soft Reset
    writereg(core#SOFTRESET, 0, 0)
    time.msleep (1)

PUB LastCRCOK{}: flag
' Flag indicating CRC of last command was good
'   Returns: TRUE (-1) if CRC was good, FALSE (0) otherwise
    flag := 0
    readreg(core#STATUS, 2, @flag)
    return (flag & %1) == 0

PUB LastCMDOK{}: flag
' Flag indicating last command executed without error
'   Returns: TRUE (-1) if no error, FALSE (0) otherwise
    flag := 0
    readreg(core#STATUS, 2, @flag)
    return ((flag >> 1) & %1) == 0

PRI calcRH(rh_word): rh_cal

    return (100 * (rh_word * 100)) / core#ADC_MAX

PRI calcTemp(temp_word): temp_cal

    case _temp_scale
        C:
            return ((175 * (temp_word * 100)) / core#ADC_MAX)-(45 * 100)
        F:
            return ((315 * (temp_word * 100)) / core#ADC_MAX)-(49 * 100)
        other:
            return FALSE

PRI oneShotMeasure(buff_addr)

    case _repeatability
        LOW, MED, HIGH:
            readreg(lookupz(_repeatability: core#MEAS_LOWREP, core#MEAS_MEDREP, core#MEAS_HIGHREP), 6, buff_addr)
        other:
            return

PRI pollMeasure(buff_addr)

    if readreg(core#FETCHDATA, 6, buff_addr) == NODATA_AVAIL
        return

PRI rhPct_7bit(rh_pct): result
' Converts Percent RH to 7-bit value, for use with alert threshold setting
'   Valid values: 0..100
'   Any other value is ignored
'   NOTE: Value is left-justified in MSB of word
    case rh_pct
        0..100:
            result := (((rh_pct * 100) / 100 * core#ADC_MAX) / 100) & $FE00
            return
        other:
            return

PRI rh7bit_Pct(rh_7b): result
' Converts 7-bit value to Percent RH, for use with alert threshold settings
'   Valid values: $02xx..$FExx (xx = 00)
'   NOTE: Value must be left-justified in MSB of word
    rh_7b &= $FE00                                              ' Mask off temperature
    rh_7b *= 10000                                              ' Scale up
    rh_7b /= core#ADC_MAX                                       ' Scale to %
    result := rh_7b
    return

PRI stopContMeas{}
' Stop continuous measurement mode
    writereg(core#BREAK_STOP, 0, 0)

PRI swap (word_addr)
' Swap byte order of a WORD
    byte[word_addr][2] := byte[word_addr][0]
    byte[word_addr][0] := byte[word_addr][1]
    byte[word_addr][1] := byte[word_addr][2]
    byte[word_addr][2] := 0

PRI tempC_9bit(temp_c): result | scale
' Converts degrees C to 9-bit value, for use with alert threshold settings
'   Valid values: -45..130
    case temp_c
        -45..130:
            scale := 10_000                                     ' Fixed-point scale
            result := ((((temp_c * scale) + (45 * scale)) / 175 * core#ADC_MAX)) / scale
            result := (result >> 7) & $001FF
            return
        other:
            return

PRI temp9bit_C(temp_9b): result | scale
' Converts raw 9-bit value to temperature in
'   Returns: hundredths of a degree C (0..511 ror -4500..12966 or -45.00C 129.66C)
'   Valid values: 0..511
'   Any other value is ignored
    scale := 100
    case temp_9b
        0..511:
            result := (temp_9b << 7)
            result := ((175 * (result * scale)) / core#ADC_MAX)-(45 * scale)
            return
        other:
            return

PRI readReg(reg_nr, nr_bytes, buff_addr): result | cmd_packet, tmp, ackbit, delay
' Read nr_bytes from the slave device into the address stored in buff_addr
    delay := 0
    case reg_nr                                             ' Basic register validation
        core#READ_SERIALNUM:                                ' S/N Read Needs delay before repeated start
            delay := 500
        core#MEAS_HIGHREP..core#MEAS_LOWREP, core#STATUS, core#FETCHDATA, core#ALERTLIM_WR_LO_SET..core#ALERTLIM_WR_HI_SET, core#ALERTLIM_RD_LO_SET..core#ALERTLIM_RD_HI_SET:
        other:
            return

    cmd_packet.byte[0] := (SLAVE_WR | _addr_bit)
    cmd_packet.byte[1] := reg_nr.byte[MSB]
    cmd_packet.byte[2] := reg_nr.byte[LSB]

    i2c.start{}
    repeat tmp from 0 to 2
        i2c.write (cmd_packet.byte[tmp])

    time.usleep(delay)                                      ' Delay before repeated start

    i2c.start{}
    ackbit := i2c.write (SLAVE_RD | _addr_bit)
    if ackbit == i2c#NAK                                    ' If NAK received from sensor,
        i2c.stop{}                                          '   Stop early. It means there's
        return NODATA_AVAIL                                 '   no data available.
    repeat tmp from nr_bytes-1 to 0
        byte[buff_addr][tmp] := i2c.read (tmp == 0)
    i2c.stop{}

PRI writeReg(reg_nr, nr_bytes, buff_addr) | cmd_packet, tmp, chk, delay
' Write nr_bytes to the slave device from the address stored in buff_addr
    delay := chk := 0
    case reg_nr                                             ' Basic register validation
        core#CLEARSTATUS, core#HEATEREN, core#HEATERDIS:
        core#ALERTLIM_WR_LO_SET..core#ALERTLIM_WR_HI_SET, core#ALERTLIM_RD_LO_SET..core#ALERTLIM_RD_HI_SET:
            chk := crc.sensirioncrc8 (buff_addr, 2)         ' Interrupt threshold writes require
            swap(buff_addr)                                 '   CRC byte after thresholds
            byte[buff_addr][2] := chk
        core#MEAS_HIGHREP..core#MEAS_LOWREP:
            delay := 20                                     ' Post-write delay
        core#SOFTRESET:
            delay := 10
        other:
            return

    cmd_packet.byte[0] := (SLAVE_WR | _addr_bit)
    cmd_packet.byte[1] := reg_nr.byte[MSB]
    cmd_packet.byte[2] := reg_nr.byte[LSB]

    i2c.start{}
    repeat tmp from 0 to 2
        i2c.write (cmd_packet.byte[tmp])

    if chk                                                  ' Interrupt thresholds need CRC byte after
        repeat tmp from 0 to nr_bytes
            i2c.write (byte[buff_addr][tmp])
    i2c.stop{}
    time.msleep(delay)

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
