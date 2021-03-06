{
    --------------------------------------------
    Filename: sensor.temp_rh.si70xx.i2c.spin
    Author: Jesse Burt
    Description: Driver for Silicon Labs Si70xx-series temperature/humidity sensors
    Copyright (c) 2020
    Started Jul 20, 2019
    Updated Aug 9, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SLAVE_WR          = core#SLAVE_ADDR
    SLAVE_RD          = core#SLAVE_ADDR|1

    DEF_SCL           = 28
    DEF_SDA           = 29
    DEF_HZ            = 100_000
    I2C_MAX_FREQ      = core#I2C_MAX_FREQ

' Temperature scales
    C = 0
    F = 1

VAR

    byte _temp_scale

OBJ

    i2c : "com.i2c"                                             'PASM I2C Driver
    core: "core.con.si70xx.spin"                           'File containing your device's register set
    time: "time"                                                'Basic timing functions
    crc : "math.crc"

PUB Null{}
' This is not a top-level object

PUB Start{}: okay                                                 'Default to "standard" Propeller I2C pins and 400kHz

    okay := Startx (DEF_SCL, DEF_SDA, DEF_HZ)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ): okay

    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.setupx (SCL_PIN, SDA_PIN, I2C_HZ)    'I2C Object Started?
                time.msleep(core#TPU)                           ' wait tPU ms for startup
                if i2c.present(SLAVE_WR)                        'Response from device?
                    reset{}
                    if lookdown(deviceid{}: $0D, $14, $15, $00, $FF)
                        return okay

    return FALSE                                                'If we got here, something went wrong

PUB Stop{}

    i2c.terminate{}

PUB ADCRes(bits): curr_setting
' Set resolution of readings, in bits
'   Valid values:
'                   RH  Temp
'      *12_14:      12  14 bits
'       8_12:       8   12
'       10_13:      10  13
'       11_11:      11  11
'   Any other value polls the chip and returns the current setting
'   NOTE: The underscore in the setting isn't necessary - it only serves as a visual aid to separate the two fields
    curr_setting := 0
    readreg(core#RD_RH_T_USER1, 1, @curr_setting)
    case bits
        12_14, 8_12, 10_13, 11_11:
            bits := lookdownz(bits: 12_14, 8_12, 10_13, 11_11)
            bits := lookupz(bits: $00, $01, $80, $81)

        OTHER:
            curr_setting := lookdownz(curr_setting & core#BITS_RES: $00, $01, $80, $81)
            return lookupz(curr_setting: 12_14, 8_12, 10_13, 11_11)

    bits := (curr_setting & core#MASK_RES) | bits
    writereg(core#WR_RH_T_USER1, 1, @bits)

PUB DeviceID{} | tmp[2]
' Read the Part number portion of the serial number
'   Returns:
'       $00/$FF: Engineering samples
'       $0D (13): Si7013
'       $14 (20): Si7020
'       $15 (21): Si7021
    SerialNum(@tmp)
    return tmp.byte[3]

PUB FirmwareRev{}
' Read sensor internal firmware revision
'   Returns:
'       $FF: Version 1.0
'       $20: Version 2.0
    readreg(core#RD_FIRMWARE_REV, 1, @result)

PUB HeaterCurrent(mA): curr_setting
' Set heater current, in milliamperes
'   Valid values: *3, 9, 15, 21, 27, 33, 40, 46, 52, 58, 64, 70, 76, 82, 88, 94
'   Any other value polls the chip and returns the current setting
'   NOTE: Values are approximate, and typical
    case mA
        3, 9, 15, 21, 27, 33, 40, 46, 52, 58, 64, 70, 76, 82, 88, 94:
            mA := lookdownz(mA: 3, 9, 15, 21, 27, 33, 40, 46, 52, 58, 64, 70, 76, 82, 88, 94)
            mA &= core#BITS_HEATER
            writereg(core#WR_HEATER, 1, @mA)
        OTHER:
            curr_setting := 0
            readreg(core#RD_HEATER, 1, @curr_setting)
            curr_setting &= core#BITS_HEATER
            return lookupz(curr_setting: 3, 9, 15, 21, 27, 33, 40, 46, 52, 58, 64, 70, 76, 82, 88, 94)

PUB HeaterEnabled(state): curr_state
' Enable the on-chip heater
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#RD_RH_T_USER1, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#FLD_HTRE
        OTHER:
            return ((curr_state >> core#FLD_HTRE) & 1) == 1

    state := ((curr_state & core#MASK_HTRE) | state) & core#RD_RH_T_USER1_MASK
    writereg(core#WR_RH_T_USER1, 1, @state)

PUB Humidity{}: rh
' Read humidity
'   Returns: Relative Humidity, in hundreths of a percent
    rh := 0
    readreg(core#MEAS_RH_NOHOLD, 2, @rh)
    return ((125_00 * result) / 65536) - 6_00

PUB Reset{}
' Perform soft-reset
    writereg(core#RESET, 0, 0)
    time.msleep (15)

PUB SerialNum(buff_addr) | sna[2], snb[2]
' Read the 64-bit serial number of the device
    longfill(@sna, 0, 4)
    readreg(core#RD_SERIALNUM_1, 8, @sna)
    readreg(core#RD_SERIALNUM_2, 6, @snb)
    byte[buff_addr][7] := sna.byte[0]
    byte[buff_addr][6] := sna.byte[2]
    byte[buff_addr][5] := sna.byte[4]
    byte[buff_addr][4] := sna.byte[6]
    byte[buff_addr][3] := snb.byte[0]                       ' Device ID
    byte[buff_addr][2] := snb.byte[1]
    byte[buff_addr][1] := snb.byte[3]
    byte[buff_addr][0] := snb.byte[4]

PUB Temperature{}: temp
' Current Temperature, in hundredths of a degree
'   Returns: Integer
'   (e.g., 2105 is equivalent to 21.05 deg C)
    temp := 0
    readreg(core#READ_PREV_TEMP, 2, @temp)
    temp := ((175_72 * temp) / 65536) - 46_85
    case _temp_scale
        F:
            if temp > 0
                temp := temp * 9 / 5 + 32_00
            else
                temp := 32_00 - (||(temp) * 9 / 5)
        OTHER:
            return

PUB TempScale(temp_scale): curr_scale
' Set scale of temperature data returned by Temperature method
'   Valid values:
'      *C (0): Celsius
'       F (1): Fahrenheit
'   Any other value returns the current setting
    case temp_scale
        F, C:
            _temp_scale := temp_scale
        OTHER:
            return _temp_scale

PRI readReg(reg_nr, nr_bytes, buff_addr) | cmd_packet, tmp, crc_in, rt
' Read nr_bytes from the slave device into the address stored in buff_addr
    case reg_nr
        core#READ_PREV_TEMP:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.wait(SLAVE_RD)
            repeat tmp from nr_bytes-1 to 0
                byte[buff_addr][tmp] := i2c.read(tmp == 0)  ' Return NAK if tmp == 0 (last byte)
            i2c.stop{}

        core#MEAS_RH_NOHOLD:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.wait(SLAVE_RD)
            repeat tmp from nr_bytes-1 to 0
                byte[buff_addr][tmp] := i2c.read(tmp == 0)
' XXX CRC check here
            i2c.stop{}

        core#MEAS_TEMP_HOLD:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.start{}
            i2c.write(SLAVE_RD)
            time.msleep(11)
            repeat tmp from nr_bytes-1 to 0
                byte[buff_addr][tmp] := i2c.read(tmp == 0)
            i2c.stop{}

        core#MEAS_TEMP_NOHOLD:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.wait(SLAVE_RD)
            repeat tmp from nr_bytes-1 to 0
                byte[buff_addr][tmp] := i2c.read(tmp == 0)
            i2c.stop{}

        core#RD_RH_T_USER1, core#RD_HEATER:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.wait(SLAVE_RD)
            i2c.rd_block(buff_addr, nr_bytes, TRUE)         ' TRUE: NAK last byte
            i2c.stop{}

        core#RD_SERIALNUM_1, core#RD_SERIALNUM_2, core#RD_FIRMWARE_REV:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr.byte[1]
            cmd_packet.byte[2] := reg_nr.byte[0]
            i2c.start{}
            i2c.wr_block(@cmd_packet, 3)
            i2c.wait(SLAVE_RD)
            i2c.rd_block(buff_addr, nr_bytes, TRUE)
            i2c.stop{}
        OTHER:
            return

PRI writeReg(reg_nr, nr_bytes, buff_addr) | cmd_packet, tmp
' Write nr_bytes to the slave device from the address stored in buff_addr
    case reg_nr                                             ' Basic register validation
        core#RESET:
            i2c.start{}
            i2c.write(SLAVE_WR)
            i2c.write(reg_nr)
            i2c.stop{}

        core#WR_RH_T_USER1, core#WR_HEATER:
            cmd_packet.byte[0] := SLAVE_WR
            cmd_packet.byte[1] := reg_nr
            cmd_packet.byte[2] := byte[buff_addr][0]
            i2c.start{}
            i2c.wr_block(@cmd_packet, 3)
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
