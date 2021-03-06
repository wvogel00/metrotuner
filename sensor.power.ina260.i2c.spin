{
    --------------------------------------------
    Filename: sensor.power.ina260.i2c.spin2
    Author: Jesse Burt
    Description: Driver for the TI INA260 Precision Current and Power Monitor IC
    Copyright (c) 2020
    Started Nov 13, 2019
    Updated Jan 18, 2020
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

' Operating modes
    POWERDN         = %000
    CURR_TRIGD      = %001
    VOLT_TRIGD      = %010
    CURR_VOLT_TRIGD = %011
    POWERDN2        = %100
    CURR_CONT       = %101
    VOLT_CONT       = %110
    CURR_VOLT_CONT  = %111

' Interrupt/alert pin sources
    INT_CONV_READY  = 1
    INT_POWER_HI    = 2
    INT_BUSVOLT_LO  = 4
    INT_BUSVOLT_HI  = 8
    INT_CURRENT_LO  = 16
    INT_CURRENT_HI  = 32

' Interrupt/alert pin level/polarity
    INTLVL_LO       = 0
    INTLVL_HI       = 1

VAR


OBJ

    i2c : "com.i2c"
    core: "core.con.ina260"
    time: "time"

PUB Null
''This is not a top-level object

PUB Start: okay

    okay := Startx(DEF_SCL, DEF_SDA, DEF_HZ)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ): okay

    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.Setupx (SCL_PIN, SDA_PIN, I2C_HZ)     'I2C Object Started?
                time.MSleep (1)
                if i2c.Present (SLAVE_WR)                       'Response from device?
                    Reset
                    if DeviceID == core#DEVID_RESP
                    return okay

    return FALSE                                                'If we got here, something went wrong

PUB Stop
' Put any other housekeeping code here required/recommended by your device before shutting down
    i2c.Stop

PUB BusVoltage
' Read the measured bus voltage, in microvolts
'   NOTE: If averaging is enabled, this will return the averaged value
'   NOTE: Full-scale range is 40_960_000uV
    result := $0000
    readReg(core#BUS_VOLTAGE, 2, @result)
    result &= $7FFF
    result *= 1_250
    return result

PUB ConversionReady
' Indicates data from the last conversion is available for reading
'   Returns: TRUE if data available, FALSE otherwise
    readReg(core#MASK_ENABLE, 2, @result)
    result >>= core#FLD_CVRF
    result &= %1
    result *= TRUE

PUB Current
' Read the measured current, in microamperes
'   NOTE: If averaging is enabled, this will return the averaged value
    result := $0000
    readReg(core#CURRENT, 2, @result)
    if result > 32767
        result := 65536-result
    result *= 1_250
    return

PUB CurrentConvTime(microseconds) | tmp
' Set conversion time for shunt current measurement, in microseconds
'   Valid values: 140, 204, 332, 588, *1100, 2116, 4156, 8244
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#CONFIG, 2, @tmp)
    case microseconds
        140, 204, 332, 588, 1100, 2116, 4156, 8244:
            microseconds := lookdownz(microseconds: 140, 204, 332, 588, 1100, 2116, 4156, 8244) << core#FLD_ISHCT
        OTHER:
            tmp >>= core#FLD_ISHCT
            tmp &= core#BITS_ISHCT
            result := lookupz(tmp: 140, 204, 332, 588, 1100, 2116, 4156, 8244)
            return result

    tmp &= core#MASK_ISHCT
    tmp := (tmp | microseconds) & core#CONFIG_MASK
    writeReg(core#CONFIG, 2, @tmp)

PUB DeviceID
' Read device ID
'   Returns:
'       Most-significant word: Die ID
'       Least-significant word: Mfr ID
    return (DieID << 16) | MfrID

PUB DieID
' Read the Die ID from the chip
'   Returns: $2270
    result := $0000
    readReg(core#DIE_ID, 2, @result)
    return

PUB IntLevel (level) | tmp
' Set interrupt active level/polarity
'   Valid values:
'      *INTLVL_LO   (0) Active low
'       INTLVL_HI   (1) Active high
'   Any other value polls the chip and returns the current setting
'   NOTE: The ALERT pin is open collector
    tmp := $0000
    readReg(core#MASK_ENABLE, 2, @tmp)
    case level
        INTLVL_LO, INTLVL_HI:
            level <<= core#FLD_APOL
        OTHER:
            tmp >>= core#FLD_APOL
            return tmp

    tmp &= core#MASK_APOL
    tmp := (tmp | level) & core#MASK_ENABLE_MASK
    writeReg(core#MASK_ENABLE, 2, @tmp)

PUB IntsLatched(enabled) | tmp
' Enable latching of interrupts
'   Valid values:
'       TRUE (-1 or 1): Active interrupts remain asserted until cleared manually
'       FALSE (0): Active interrupts clear when the fault has been cleared
    tmp := $0000
    readReg(core#MASK_ENABLE, 2, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled & %1
        OTHER:
            return (tmp & %1) * TRUE

    tmp &= core#MASK_LEN
    tmp := (tmp | enabled) & core#MASK_ENABLE_MASK
    writeReg(core#MASK_ENABLE, 2, @tmp)

PUB IntSource (src) | tmp
' Set interrupt/alert pin assertion source
'   Valid values:
'       INT_CURRENT_HI  (32)    Over current limit
'       INT_CURRENT_LO  (16)    Under current limit
'       INT_BUSVOLT_HI  (8)     Bus voltage over-voltage
'       INT_BUSVOLT_LO  (4)     Bus voltage under-voltage
'       INT_POWER_HI    (2)     Power over-limit
'       INT_CONV_READY  (1)     Conversion ready
'       Example:
'           IntSource(INT_BUSVOLT_HI) or IntSource(8)
'               would trigger an alert when the bus voltage exceeded the set threshold
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#MASK_ENABLE, 2, @tmp)
    case src
        INT_CONV_READY, INT_POWER_HI, INT_BUSVOLT_LO, INT_BUSVOLT_HI, INT_CURRENT_LO, INT_CURRENT_HI:
            src <<= core#FLD_ALERTS
        OTHER:
            tmp >>= core#FLD_ALERTS
            return tmp

    tmp &= core#MASK_ALERTS
    tmp := (tmp | src) & core#MASK_ENABLE_MASK
    writeReg(core#MASK_ENABLE, 2, @tmp)

PUB IntThresh(threshold) | tmp
' Set interrupt/alert threshold
'   Valid values: 0..65535
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#ALERT_LIMIT, 2, @tmp)
    case threshold
        0..65535:
        OTHER:
            return tmp

    writeReg(core#ALERT_LIMIT, 2, @threshold)

PUB MfrID
' Read the Manufacturer ID from the chip
'   Returns: $5449
    result := $0000
    readReg(core#MFR_ID, 2, @result)
    return

PUB OpMode(mode) | tmp
' Set operation mode
'   Valid values:
'       POWERDN (0): Power-down/shutdown
'       CURR_TRIGD (1): Shunt current, triggered
'       VOLT_TRIGD (2): Bus voltage, triggered
'       CURR_VOLT_TRIGD (3): Shunt current and bus voltage, triggered
'       POWERDN2 (4): Power-down/shutdown
'       CURR_CONT (5): Shunt current, continuous
'       VOLT_CONT (6): Bus voltage, continuous
'      *CURR_VOLT_CONT (7): Shunt current and bus voltage, continuous
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#CONFIG, 2, @tmp)
    case mode
        POWERDN, CURR_TRIGD, VOLT_TRIGD, CURR_VOLT_TRIGD, POWERDN2, CURR_CONT, VOLT_CONT, CURR_VOLT_CONT:
            mode := lookdownz(mode: POWERDN, CURR_TRIGD, VOLT_TRIGD, CURR_VOLT_TRIGD, POWERDN2, CURR_CONT, VOLT_CONT, CURR_VOLT_CONT)
        OTHER:
            tmp &= core#BITS_MODE
            return tmp

    tmp &= core#MASK_MODE
    tmp := (tmp | mode) & core#CONFIG_MASK
    writeReg(core#CONFIG, 2, @tmp)

PUB Power
' Read the power measured by the chip, in microwatts
'   NOTE: If averaging is enabled, this will return the averaged value
'   NOTE: The maximum value returned is 419_430_000
    result := $0000
    readReg(core#POWER, 2, @result)
    result *= 10_000
    return

PUB PowerOverflowed
' Indicates the power data exceeded the maximum measurable value (419_430_000uW/419.43W)
    readReg(core#MASK_ENABLE, 2, @result)
    result >>= core#FLD_OVF
    result &= %1
    result *= TRUE

PUB Reset | tmp
' Reset the chip
'   NOTE: Equivalent to Power-On Reset
    tmp := 1 << core#FLD_RESET
    writeReg(core#CONFIG, 2, @tmp)

PUB SamplesAveraged(samples) | tmp
' Set number of samples used for averaging measurements
'   Valid values: *1, 4, 16, 64, 128, 256, 512, 1024
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#CONFIG, 2, @tmp)
    case samples
        1, 4, 16, 64, 128, 256, 512, 1024:
            samples := lookdownz(samples: 1, 4, 16, 64, 128, 256, 512, 1024) << core#FLD_AVG
        OTHER:
            tmp >>= core#FLD_AVG
            tmp &= core#BITS_AVG
            result := lookupz(tmp: 1, 4, 16, 64, 128, 256, 512, 1024)
            return result

    tmp &= core#MASK_AVG
    tmp := (tmp | samples) & core#CONFIG_MASK
    writeReg(core#CONFIG, 2, @tmp)

PUB VoltageConvTime(microseconds) | tmp
' Set conversion time for bus voltage measurement, in microseconds
'   Valid values: 140, 204, 332, 588, *1100, 2116, 4156, 8244
'   Any other value polls the chip and returns the current setting
    tmp := $0000
    readReg(core#CONFIG, 2, @tmp)
    case microseconds
        140, 204, 332, 588, 1100, 2116, 4156, 8244:
            microseconds := lookdownz(microseconds: 140, 204, 332, 588, 1100, 2116, 4156, 8244) << core#FLD_VBUSCT
        OTHER:
            tmp >>= core#FLD_VBUSCT
            tmp &= core#BITS_VBUSCT
            result := lookupz(tmp: 140, 204, 332, 588, 1100, 2116, 4156, 8244)
            return result

    tmp &= core#MASK_VBUSCT
    tmp := (tmp | microseconds) & core#CONFIG_MASK
    writeReg(core#CONFIG, 2, @tmp)

PRI readReg(reg, nr_bytes, buff_addr) | cmd_packet, tmp
'' Read num_bytes from the slave device into the address stored in buff_addr
    case reg                                                    'Basic register validation
        $00..$FF:                                               ' Consult your device's datasheet!
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg
            i2c.start                                               ' S
            repeat tmp from 0 to 1
                i2c.Write (cmd_packet.byte[tmp])                    ' SL|W, reg

            i2c.Start                                               ' Rs
            i2c.Write (SLAVE_RD)                                    ' SL|R
            repeat tmp from 0 to nr_bytes-1
                byte[buff_addr][nr_bytes-1-tmp] := i2c.Read(tmp == nr_bytes-1) ' R 0..n, NAK last byte to signal complete
            i2c.Stop                                                ' P
        OTHER:
            return

PRI writeReg(reg, nr_bytes, buff_addr) | cmd_packet, tmp
'' Write num_bytes to the slave device from the address stored in buff_addr
    case reg                                                ' Basic register validation
        $00:
            word[buff_addr][0] |= core#BITS_RSVD            ' Make sure the reserved bits are set correctly
        $06, $07:
        OTHER:
            return

    cmd_packet.byte[0] := SLAVE_WR
    cmd_packet.byte[1] := reg
    i2c.Start                                               ' S
    repeat tmp from 0 to 1
        i2c.Write(cmd_packet.byte[tmp])                     ' SL|W, reg

    repeat tmp from nr_bytes-1 to 0
        i2c.Write (byte[buff_addr][tmp])                    ' W 0..n
    i2c.Stop                                                ' P

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
