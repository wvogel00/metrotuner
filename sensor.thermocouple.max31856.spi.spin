{
    --------------------------------------------
    Filename: sensor.thermocouple.max31856.spi.spin
    Author: Jesse Burt
    Description: Driver object for Maxim's MAX31856 thermocouple amplifier (4W SPI)
    Copyright (c) 2018
    Created: Sep 30, 2018
    Updated: Jun 11, 2019
    See end of file for terms of use.
    --------------------------------------------
}

CON

' Sensor resolution (deg C per LSB, scaled up)
    TC_RES          = 78125 ' 0.0078125 * 10_000_000)
    CJ_RES          = 15625 ' 0.15625 * 100_000

' Conversion modes
    CMODE_OFF       = 0
    CMODE_AUTO      = 1

' Fault modes
    FAULTMODE_COMP  = 0
    FAULTMODE_INT   = 1

' Thermocouple types
    B               = %0000
    E               = %0001
    J               = %0010
    K               = %0011
    N               = %0100
    R               = %0101
    S               = %0110
    T               = %0111
    VOLTMODE_GAIN8  = %1000
    VOLTMODE_GAIN32 = %1100

' Fault mask bits (OR together any combination for use with FaultMask)
    FAULT_CJ_HIGH   = 1 << core#FLD_CJ_HIGH
    FAULT_CJ_LOW    = 1 << core#FLD_CJ_LOW
    FAULT_TC_HIGH   = 1 << core#FLD_TC_HIGH
    FAULT_TC_LOW    = 1 << core#FLD_TC_LOW
    FAULT_OV_UV     = 1 << core#FLD_OV_UV
    FAULT_OPEN      = 1 << core#FLD_OPEN

' Temperature scales
    SCALE_C         = 0
    SCALE_F         = 1

VAR

    byte _CS, _MOSI, _MISO, _SCK
    byte _temp_scale

OBJ

    core    : "core.con.max31856"
    spi     : "com.spi.4w"
    types   : "system.types"
    u64     : "math.unsigned64"

PUB Null
''This is not a top-level object

PUB Start (CS_PIN, SDI_PIN, SDO_PIN, SCK_PIN): okay

    if okay := spi.start (core#CLK_DELAY, core#CPOL)
        _CS := CS_PIN
        _MOSI := SDI_PIN
        _MISO := SDO_PIN
        _SCK := SCK_PIN
        dira[_CS] := 1
        outa[_CS] := 1
    else
        return FALSE

PUB Stop

    spi.stop

PUB ColdJuncHighFault(thresh) | tmp
' Set Cold-Junction HIGH fault threshold
'   Valid values: 0..255
'   Any other value polls the chip and returns the current setting
    readRegX (core#CJHF, 1, @tmp)
    case thresh
        0..255:
        OTHER:
            return tmp & $FF

    writeRegX (core#CJHF, 1, @thresh)

PUB ColdJuncLowFault(thresh) | tmp
' Set Cold-Junction LOW fault threshold
'   Valid values: 0..255
'   Any other value polls the chip and returns the current setting
    readRegX (core#CJLF, 1, @tmp)
    case thresh
        0..255:
        OTHER:
            return tmp & $FF

    writeRegX (core#CJLF, 1, @thresh)

PUB ColdJuncOffset(offset) | tmp  'XXX Make param units degrees
' Set Cold-Junction temperature sensor offset
    readRegX (core#CJTO, 1, @tmp)
    case offset
        0..255:
        OTHER:
            return tmp

    writeRegX (core#CJTO, 1, @offset)

PUB ColdJuncSensor(enabled) | tmp
' Enable the on-chip Cold-Junction temperature sensor
'   Valid values: TRUE (-1 or 1), FALSE
'   Any other value polls the chip and returns the current setting
    readRegX (core#CR0, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := (||enabled ^ 1) << core#FLD_CJ
        OTHER:
            result := (((tmp >> core#FLD_CJ) & %1) ^ 1) * TRUE
            return

    tmp &= core#MASK_CJ
    tmp := (tmp | enabled) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB ColdJuncTemp
' Read the Cold-Junction temperature sensor
    readRegX (core#CJTH, 2, @result)
    result.byte[2] := result.byte[0]
    result.byte[0] := result.byte[1]
    result.byte[1] := result.byte[2]
    result.byte[2] := 0
    result >>=2
    result := u64.multdiv (result, CJ_RES, 10_000)
    case _temp_scale
        SCALE_F:
            if result > 0
                result := result * 9 / 5 + 32_00
            else
                result := 32_00 - (||result * 9 / 5)
        OTHER:
            return result


PUB ConversionMode(mode) | tmp
' Enable automatic conversion mode
'   Valid values: CMODE_OFF (0): Normally Off (default), CMODE_AUTO (1): Automatic Conversion Mode
'   Any other value polls the chip and returns the current setting
'   NOTE: In Automatic mode, conversions occur continuously approx. every 100ms
    readRegX (core#CR0, 1, @tmp)
    case mode
        CMODE_OFF, CMODE_AUTO:
            mode := (mode << core#FLD_CMODE)
        OTHER:
            result := (tmp >> core#FLD_CMODE) & %1
            return

    tmp &= core#MASK_CMODE
    tmp := (tmp | mode) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB FaultClear | tmp
' Clear fault status
'   NOTE: This has no effect when FaultMode is set to FAULTMODE_COMP
    readRegX (core#CR0, 1, @tmp)
    tmp &= core#MASK_FAULTCLR
    tmp := (tmp | (1 << core#FLD_FAULTCLR)) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB FaultMask(mask) | tmp
' Set fault output mask
'   Valid values: (for each individual bit)
'       0: /FAULT output asserted
'      *1: /FAULT output masked
'   Bit: 5    0
'       %000000
'       Bit 5   Cold-junction HIGH fault threshold
'           4   Cold-junction LOW fault threshold
'           3   Thermocouple temperature HIGH fault threshold
'           2   Thermocouple temperature LOW fault threshold
'           1   Over-voltage or Under-voltage input
'           0   Thermocouple open-circuit
'   Example: %111101 would assert the /FAULT pin when an over-voltage or under-voltage condition is detected
'   Any other value polls the chip and returns the current setting
    readRegX (core#MASK, 1, @tmp)
    case mask
        %000000..%111111:
        OTHER:
            return tmp & core#MASK_MASK

    tmp := mask & core#MASK_MASK
    writeRegX (core#MASK, 1, @tmp)

PUB FaultMode(mode) | tmp
' Defines behavior of fault flag
'   Valid values:
'       *FAULTMODE_COMP (0): Comparator mode - fault flag will be asserted when fault condition is true, and will clear
'           when the condition is no longer true, with a 2deg C hysteresis.
'       FAULTMODE_INT (1): Interrupt mode - fault flag will be asserted when fault condition is true, and will remain
'           asserted until fault status is explicitly cleared with FaultClear.
'           NOTE: If the fault condition is still true when the status is cleared, the flag will be asserted again immediately.
'   Any other value polls the chip and returns the current setting
    readRegX (core#CR0, 1, @tmp)
    case mode
        FAULTMODE_COMP, FAULTMODE_INT:
            mode := mode << core#FLD_FAULT
        OTHER:
            result := ((tmp >> core#FLD_FAULT) & 1)
            return

    tmp &= core#MASK_FAULT
    tmp := (tmp | mode) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB FaultStatus
' Return fault status, as bitfield
'   Returns: (for each individual bit)
'       0: No fault detected
'       1: Fault detected
'
'   Bit 7   Cold-junction out of normal operating range
'       6   Thermcouple out of normal operating range
'       5   Cold-junction above HIGH temperature threshold
'       4   Cold-junction below LOW temperature threshold
'       3   Thermocouple temperature above HIGH temperature threshold
'       2   Thermocouple temperature below LOW temperature threshold
'       1   Over-voltage or Under-voltage
'       0   Thermocouple open-circuit
    readRegX(core#SR, 1, @result)

PUB FaultTestTime(time_ms) | tmp 'XXX Note recommendations based on circuit design
' Sets open-circuit fault detection test time, in ms
'   Valid values: 0 (disable fault detection), 10, 32, 100
'   Any other value polls the chip and returns the current setting
    readRegX (core#CR0, 1, @tmp)
    case time_ms
        0, 10, 32, 100:
            time_ms := lookdownz(time_ms: 0, 10, 32, 100) << core#FLD_OCFAULT
        OTHER:
            result := ((tmp >> core#FLD_OCFAULT) & core#BITS_OCFAULT)
            return lookupz(result: 0, 10, 32, 100)

    tmp &= core#MASK_OCFAULT
    tmp := (tmp | time_ms) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB Measure | tmp
' Perform single cold-junction and thermocouple conversion
' NOTE: Single conversion is performed only if ConversionMode is set to CMODE_OFF (Normally Off)
' Approximate conversion times:
'   Filter Setting      Time
'   60Hz                143ms
'   50Hz                169ms
    readRegX (core#CR0, 1, @tmp)
    tmp &= core#MASK_ONESHOT
    tmp := (tmp | (1 << core#FLD_ONESHOT)) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

PUB NotchFilter(Hz) | tmp, cmode_tmp
' Select noise rejection filter frequency, in Hz
'   Valid values: 50, 60*
'   Any other value polls the chip and returns the current setting
'   NOTE: The conversion mode will be temporarily set to Normally Off when changing notch filter settings
'       per MAX31856 datasheet, if it isn't already.
    if cmode_tmp := ConversionMode (-2)
        ConversionMode (CMODE_OFF)
    readRegX (core#CR0, 1, @tmp)
    case Hz
        50, 60:
            Hz := lookdownz(Hz: 60, 50)
        OTHER:
            if cmode_tmp
                ConversionMode (CMODE_AUTO)
            result := tmp & %1
            return lookupz(result: 60, 50)

    tmp &= core#MASK_NOTCHFILT
    tmp := (tmp | Hz) & core#CR0_MASK
    writeRegX (core#CR0, 1, @tmp)

    if cmode_tmp
        ConversionMode (CMODE_AUTO)

PUB Scale(temp_scale)
' Set scale of temperature data returned by Temperature method
'   Valid values:
'      *SCALE_C (0): Celsius
'       SCALE_F (1): Fahrenheit
'   Any other value returns the current setting
    case temp_scale
        SCALE_F, SCALE_C:
            _temp_scale := temp_scale
            return _temp_scale
        OTHER:
            return _temp_scale

PUB ThermoCoupleAvg(samples) | tmp
' Set number of samples averaged during thermocouple conversion
'   Valid values: 1*, 2, 4, 8, 16
'   Any other value polls the chip and returns the current setting
    readRegX (core#CR1, 1, @tmp)
    case samples
        1, 2, 4, 8, 16:
            samples := lookdownz(samples: 1, 2, 4, 8, 16) << core#FLD_AVGSEL
        OTHER:
            result := (tmp >> core#FLD_AVGSEL) & core#BITS_AVGSEL
            return lookupz(result: 1, 2, 4, 8, 16)

    tmp &= core#MASK_AVGSEL
    tmp := (tmp | samples) & core#CR1_MASK
    writeRegX(core#CR1, 1, @tmp)

PUB ThermocoupleHighFault(thresh) | tmp
' Set Thermocouple HIGH fault threshold
'   Valid values: 0..32767
'   Any other value polls the chip and returns the current setting
    readRegX (core#LTHFTH, 2, @tmp)
    case thresh
        0..32767:
        OTHER:
            return tmp & $7FFF

    writeRegX (core#LTHFTH, 2, @thresh)

PUB ThermocoupleLowFault(thresh) | tmp
' Set Thermocouple LOW fault threshold
'   Valid values: 0..32767
'   Any other value polls the chip and returns the current setting
    readRegX (core#LTLFTH, 2, @tmp)
    case thresh
        0..32767:
        OTHER:
            return tmp & $7FFF

    writeRegX (core#LTLFTH, 2, @thresh)

PUB ThermoCoupleTemp | tmp
' Read the Thermocouple temperature
    result := 0
    tmp := 0
    readRegX (core#LTCBH, 3, @result)
    swapByteOrder(@result)
    result >>= 5
    if result & $40000
        result |= $FFFF0000

    tmp := u64.multdiv (result, TC_RES, 100_000)
    case _temp_scale
        SCALE_F:
            result := 0
            if tmp > 0
                result := tmp * 9 / 5 + 32_00
            else
                tmp |= $FFFF0000
                result := 32_00 - ||tmp * 9 / 5
        OTHER:
            tmp |= $FFFF0000
            return tmp

    return result

PUB ThermoCoupleType(type) | tmp
' Set type of thermocouple
'   Valid values: B (0), E (1), J (2), K* (3), N (4), R (5), S (6), T (7)
'   Any other value polls the chip and returns the current setting
    readRegX (core#CR1, 1, @tmp)
    case type
        B, E, J, K, N, R, S, T:
        OTHER:
            result := tmp & core#BITS_TC_TYPE
            return

    tmp &= core#MASK_TC_TYPE
    tmp := (tmp | type) & core#CR1_MASK
    writeRegX(core#CR1, 1, @tmp)

PRI swapByteOrder(buff_addr)

    byte[buff_addr][3] := byte[buff_addr][0]
    byte[buff_addr][0] := byte[buff_addr][2]
    byte[buff_addr][2] := byte[buff_addr][3]
    byte[buff_addr][3] := 0

PRI writeRegX(reg, nr_bytes, buf_addr) | tmp
' Write reg to MOSI
    outa[_CS] := 0
    case nr_bytes
        1..4:
            spi.SHIFTOUT (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg | core#WRITE_REG)     'Command w/nr_bytes data bytes following
            repeat tmp from 0 to nr_bytes-1
                spi.SHIFTOUT (_MOSI, _SCK, core#MOSI_BITORDER, 8, byte[buf_addr][tmp])
        OTHER:
            result := FALSE
            buf_addr := 0
    outa[_CS] := 1

PRI readRegX(reg, nr_bytes, buf_addr) | tmp
' Read reg from MISO
    outa[_CS] := 0
    spi.SHIFTOUT (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)              'Which register to query

    case nr_bytes
        1..4:
            repeat tmp from 0 to nr_bytes-1
                byte[buf_addr][tmp] := spi.SHIFTIN (_MISO, _SCK, core#MISO_BITORDER, 8)
        OTHER:
            result := FALSE
            buf_addr := 0
    outa[_CS] := 1

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
