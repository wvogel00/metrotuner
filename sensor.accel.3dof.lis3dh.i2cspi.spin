{
    --------------------------------------------
    Filename: sensor.accel.3dof.lis3dh.spi.spin
    Author: Jesse Burt
    Description: Driver for the ST LIS3DH 3DoF accelerometer
    Copyright (c) 2020
    Started Mar 15, 2020
    Updated Jul 19, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

' Constants used for I2C mode only
    SLAVE_WR        = core#SLAVE_ADDR
    SLAVE_RD        = core#SLAVE_ADDR|1

    DEF_SCL         = 28
    DEF_SDA         = 29
    DEF_HZ          = 100_000
    I2C_MAX_FREQ    = core#I2C_MAX_FREQ

' Indicate to user apps how many Degrees of Freedom each sub-sensor has
'   (also imply whether or not it has a particular sensor)
    ACCEL_DOF       = 3
    GYRO_DOF        = 0
    MAG_DOF         = 0
    BARO_DOF        = 0
    DOF             = ACCEL_DOF + GYRO_DOF + MAG_DOF + BARO_DOF

    R               = 0
    W               = 1

' ADC resolution symbols
    LOWPOWER        = 8
    NORMAL          = 10
    FULL            = 12

' XYZ axis constants used throughout the driver
    X_AXIS          = 0
    Y_AXIS          = 1
    Z_AXIS          = 2

' Operating modes (dummy)
    STANDBY         = 0
    MEASURE         = 1

' FIFO modes
    BYPASS          = %00
    FIFO            = %01
    STREAM          = %10
    STREAM2FIFO     = %11

VAR

    long _ares
    long _abias[3], _abiasraw[3]
    byte _sa0

OBJ

#ifdef LIS3DH_SPI
    spi : "com.spi.bitbang"
#elseifdef LIS3DH_I2C
    i2c : "com.i2c"
#else
#error "One of LIS3DH_SPI or LIS3DH_I2C must be defined"
#endif
    core: "core.con.lis3dh"
    time: "time"                                                'Basic timing functions
    io  : "io"

PUB Null
''This is not a top-level object

#ifdef LIS3DH_SPI

PUB Start(CS_PIN, SCL_PIN, SDA_PIN, SDO_PIN): okay
    if lookdown(CS_PIN: 0..31) and lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31) and lookdown(SDO_PIN: 0..31)
        if okay := spi.start (CS_PIN, SCL_PIN, SDA_PIN, SDO_PIN)
            time.MSleep (core#TPOR)
            if DeviceID == core#WHO_AM_I_RESP
                return okay
    return FALSE                                                ' If we got here, something went wrong

#elseifdef LIS3DH_I2C

PUB Start: okay

    return Startx(DEF_SCL, DEF_SDA, DEF_HZ, 0)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ, SA0_BIT): okay
    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31) and I2C_HZ =< core#I2C_MAX_FREQ
        if okay := i2c.Setupx(SCL_PIN, SDA_PIN, I2C_HZ)
            _sa0 := (||(SA0_BIT <> 0)) << 1                     ' If SA0_BIT is nonzero, consider it set
            time.MSleep (core#TPOR)
            if DeviceID == core#WHO_AM_I_RESP
                return okay
    return FALSE                                                ' If we got here, something went wrong
#endif

PUB Stop

#ifdef LIS3DH_SPI
    spi.Stop
#elseifdef LIS3DH_I2C
    i2c.terminate
#endif

PUB Defaults
' Factory defaults
    AccelScale(2)
    AccelDataRate(0)
    AccelAxisEnabled(%111)

PUB AccelADCRes(bits) | tmp1, tmp2
' Set accelerometer ADC resolution, in bits
'   Valid values:
'       8:  8-bit data output, Low-power mode
'       10: 10-bit data output, Normal mode
'       12: 12-bit data output, High-resolution mode
'   Any other value polls the chip and returns the current setting
    tmp1 := tmp2 := $00
    readReg(core#CTRL_REG1, 1, @tmp1)
    readReg(core#CTRL_REG4, 1, @tmp2)
    case bits
        8:
            tmp1 &= core#MASK_LPEN
            tmp2 &= core#MASK_HR
            tmp1 := (tmp1 | (1 << core#FLD_LPEN))
        10:
            tmp1 &= core#MASK_LPEN
            tmp2 &= core#MASK_HR
        12:
            tmp1 &= core#MASK_LPEN
            tmp2 &= core#MASK_HR
            tmp2 := (tmp2 | (1 << core#FLD_HR))
        OTHER:
            tmp1 := (tmp1 >> core#FLD_LPEN) & %1
            tmp2 := (tmp2 >> core#FLD_HR) & %1
            tmp1 := (tmp1 << 1) | tmp2
            result := lookupz(tmp1: 10, 12, 8)
            return

    writeReg(core#CTRL_REG1, 1, @tmp1)
    writeReg(core#CTRL_REG4, 1, @tmp2)

PUB AccelAxisEnabled(xyz_mask) | tmp
' Enable data output for Accelerometer - per axis
'   Valid values: 0 or 1, for each axis:
'       Bits    210
'               XYZ
'   Any other value polls the chip and returns the current setting
    readReg(core#CTRL_REG1, 1, @tmp)
    case xyz_mask
        %000..%111:
            xyz_mask := (xyz_mask >< 3) & core#BITS_XYZEN
        OTHER:
            return tmp & core#BITS_XYZEN

    tmp &= core#MASK_XYZEN
    tmp := (tmp | xyz_mask) & core#CTRL_REG1_MASK
    writeReg(core#CTRL_REG1, 1, @tmp)

PUB AccelBias(axBias, ayBias, azBias, rw)
' Read or write/manually set accelerometer calibration offset values
'   Valid values:
'       rw:
'           R (0), W (1)
'       axBias, ayBias, azBias:
'           -32768..32767
'   NOTE: When rw is set to READ, axBias, ayBias and azBias must be addresses of respective variables to hold the returned calibration offset values.
    case rw
        R:
            long[axBias] := _abiasraw[X_AXIS]
            long[ayBias] := _abiasraw[Y_AXIS]
            long[azBias] := _abiasraw[Z_AXIS]

        W:
            case axBias
                -32768..32767:
                    _abiasraw[X_AXIS] := axBias
                OTHER:

            case ayBias
                -32768..32767:
                    _abiasraw[Y_AXIS] := ayBias
                OTHER:

            case azBias
                -32768..32767:
                    _abiasraw[Z_AXIS] := azBias
                OTHER:

PUB AccelData(ptr_x, ptr_y, ptr_z) | tmp[2]
' Reads the Accelerometer output registers
    bytefill(@tmp, $00, 8)
    readReg(core#OUT_X_L, 6, @tmp)

    long[ptr_x] := ~~tmp.word[0]
    long[ptr_y] := ~~tmp.word[1]
    long[ptr_z] := ~~tmp.word[2]

    long[ptr_x] -= _abiasraw[X_AXIS]
    long[ptr_y] -= _abiasraw[Y_AXIS]
    long[ptr_z] -= _abiasraw[Z_AXIS]

PUB AccelDataOverrun
' Indicates previously acquired data has been overwritten
'   Returns:
'       Bits 3210 (decimal val):
'           3 (8): X, Y, and Z-axis data overrun
'           2 (4): Z-axis data overrun
'           1 (2): Y-axis data overrun
'           0 (1): X-axis data overrun
'       Returns 0 otherwise
    result := $00
    readReg(core#STATUS_REG, 1, @result)
    result := (result >> core#FLD_XOR) & %1111

PUB AccelDataRate(Hz) | tmp
' Set accelerometer output data rate, in Hz
'   Valid values: See case table below
'   Any other value polls the chip and returns the current setting
'   NOTE: A value of 0 powers down the device
    tmp := $00
    readReg(core#CTRL_REG1, 1, @tmp)
    case Hz
        0, 1, 10, 25, 50, 100, 200, 400, 1344, 1600:
            Hz := lookdownz(Hz: 0, 1, 10, 25, 50, 100, 200, 400, 1344, 1600) << core#FLD_ODR
        OTHER:
            tmp := (tmp >> core#FLD_ODR) & core#BITS_ODR
            result := lookupz(tmp: 0, 1, 10, 25, 50, 100, 200, 400, 1344, 1600)
            return

    tmp &= core#MASK_ODR
    tmp := (tmp | Hz) & core#CTRL_REG1_MASK
    writeReg(core#CTRL_REG1, 1, @tmp)

PUB AccelDataReady
' Indicates data is ready
'   Returns: TRUE (-1) if data ready, FALSE otherwise
    result := $00
    readReg(core#STATUS_REG, 1, @result)
    result := ((result >> core#FLD_ZYXDA) & %1) * TRUE

PUB AccelG(ptr_x, ptr_y, ptr_z) | tmpx, tmpy, tmpz
' Reads the Accelerometer output registers and scales the outputs to micro-g's (1_000_000 = 1.000000 g = 9.8 m/s/s)
    AccelData(@tmpx, @tmpy, @tmpz)
    long[ptr_x] := tmpx * _ares
    long[ptr_y] := tmpy * _ares
    long[ptr_z] := tmpz * _ares

PUB AccelOpMode(mode)
' Dummy method

PUB AccelScale(g) | tmp
' Set measurement range of the accelerometer, in g's
'   Valid values: 2, 4, 8, 16
'   Any other value polls the chip and returns the current setting
    tmp := $00
    readReg(core#CTRL_REG4, 1, @tmp)
    case g
        2, 4, 8, 16:
            g := lookdownz(g: 2, 4, 8, 16)
            _ares := lookupz(g: 61, 122, 244, 732)
            g <<= core#FLD_FS
        OTHER:
            tmp := (tmp >> core#FLD_FS) & core#BITS_FS
            return lookupz(tmp: 2, 4, 8, 16)

    tmp &= core#MASK_FS
    tmp := (tmp | g) & core#CTRL_REG4_MASK
    writeReg(core#CTRL_REG4, 1, @tmp)
{
PUB AccelSelfTest(enabled) | tmp
' Enable self-test mode
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    tmp := $00
    readReg(core#ST_REG, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_
        OTHER:
            tmp >>= core#FLD_
            return (tmp & %1) * TRUE

    tmp &= core#MASK_
    tmp := (tmp | enabled) & core#ST_REG_MASK
    writeReg(core#ST_REG, 1, @tmp)
}

PUB Calibrate | tmpx, tmpy, tmpz, tmpbiasraw[3], axis, samples
' Calibrate the accelerometer
'   NOTE: The accelerometer must be oriented with the package top facing up for this method to be successful
    tmpx := tmpy := tmpz := axis := samples := 0
    longfill(@tmpbiasraw, $00000000, 3)

    FIFOEnabled(TRUE)
    FIFOMode(FIFO)
    FIFOThreshold (32)
    samples := FIFOThreshold (-2)
    repeat until FIFOFull

    repeat samples
' Read the accel data stored in the FIFO
        AccelData(@tmpx, @tmpy, @tmpz)
        tmpbiasraw[X_AXIS] += tmpx
        tmpbiasraw[Y_AXIS] += tmpy
        tmpbiasraw[Z_AXIS] += tmpz - (1_000_000 / _ares) ' Assumes sensor facing up!

    repeat axis from X_AXIS to Z_AXIS
        _abias[axis] := tmpbiasraw[axis] / _ares

    accelbias(tmpbiasraw[X_AXIS]/samples, tmpbiasraw[Y_AXIS]/samples, tmpbiasraw[Z_AXIS]/samples, W)

    FIFOEnabled(FALSE)
    FIFOMode (BYPASS)

PUB CalibrateGyro
' Dummy method

PUB CalibrateXLG

    calibrate

PUB CalibrateMag(samples)
' Dummy method

PUB ClickAxisEnabled(mask): enabled_axes
' Enable click detection per axis, and per click type
'   Valid values:
'       Bits: 5..0
'       [5..4]: Z-axis double-click..single-click
'       [3..2]: Y-axis double-click..single-click
'       [1..0]: X-axis double-click..single-click
'   Any other value polls the chip and returns the current setting
    readReg(core#CLICK_CFG, 1, @enabled_axes)
    case mask
        %000000..%111111:
        OTHER:
            return

    writeReg(core#CLICK_CFG, 1, @mask)

PUB Clicked: bool
' Flag indicating the sensor was single or double-clicked
'   Returns: TRUE (-1) if sensor was single-clicked or double-clicked
'            FALSE (0) otherwise
    bool := ((clickedint >> core#FLD_SCLICK) & %11) <> 0

PUB ClickedInt: active_ints
' Clicked interrupt status
'   Bits: 6..0
'       6: Interrupt active
'       5: Double-clicked
'       4: Single-clicked
'       3: Click sign (0: positive, 1: negative)
'       2: Z-axis clicked
'       1: Y-axis clicked
'       0: X-axis clicked
    readReg(core#CLICK_SRC, 1, @active_ints)

PUB ClickIntEnabled(enabled): curr_setting
' Enable click interrupts on INT1
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    readReg(core#CTRL_REG3, 1, @curr_setting)
    case ||(enabled)
        0, 1:
            enabled := ||(enabled) << core#FLD_I1_CLICK
        OTHER:
            return (curr_setting >> core#FLD_I1_CLICK) == 1

    curr_setting &= core#MASK_I1_CLICK
    curr_setting := (curr_setting | enabled)
    writeReg(core#CTRL_REG3, 1, @curr_setting)

PUB ClickLatency(usec): curr_setting | time_res
' Set maximum elapsed interval between start of click and end of click, in uSec
'   (i.e., time from set ClickThresh exceeded to falls back below threshold)
'   Valid values:
'       AccelDataRate:  Min time (uS, also step size)  Max time (uS)   (equiv. range in mS)
'       1               1_000_000                   .. 255_000_000     1,000 .. 255,000
'       10              100_000                     .. 25_500_000        100 .. 25,500
'       25              40_000                      .. 10_200_000       40.0 .. 10,200
'       50              20_000                      .. 5_100_000        20.0 .. 5,100
'       100             10_000                      .. 2_550_000        10.0 .. 2,550
'       200             5_000                       .. 1_275_000         5.0 .. 1,275
'       400             2_500                       .. 637_500           2.5 .. 637.5
'       1344            744                         .. 189_732         0.744 .. 189.732
'       1600            625                         .. 159_375         0.625 .. 159.375
'   Any other value polls the chip and returns the current setting
'   NOTE: Minimum unit is dependent on the current output data rate (AccelDataRate)
'   NOTE: ST application note example uses AccelDataRate(400)
    time_res := 1_000000 / acceldatarate(-2)                ' Resolution is (1 / AccelDataRate)
    readReg(core#TIME_LATENCY, 1, @curr_setting)
    case usec
        0..(time_res * 255):
            usec := (usec / time_res)
        OTHER:
            return (curr_setting * time_res)

    writeReg(core#TIME_LATENCY, 1, @usec)

PUB ClickThresh(level): curr_thresh | ares
' Set threshold for recognizing a click, in micro-g's
'   Valid values:
'       AccelScale  Max thresh
'       2           1_984375 (= 1.984375g)
'       4           3_968750 (= 3.968750g)
'       8           7_937500 (= 7.937500g)
'       16         15_875000 (= 15.875000g)
'   NOTE: Each LSB = (AccelScale/128)*1M (e.g., 4g scale lsb=31250ug = 0_031250ug = 0.03125g)
    ares := (accelscale(-2) * 1_000000) / 128               ' Resolution is current scale / 128
    readReg(core#CLICK_THS, 1, @curr_thresh)
    case level
        0..(127*ares):
            level := (level / ares)
        OTHER:
            return curr_thresh * ares

    writeReg(core#CLICK_THS, 1, @level)

PUB ClickTime(usec): curr_setting | time_res
' Set maximum elapsed interval between start of click and end of click, in uSec
'   (i.e., time from set ClickThresh exceeded to falls back below threshold)
'   Valid values:
'       AccelDataRate:  Min time (uS, also step size)  Max time (uS)   (equiv. mS)
'       1               1_000_000                   .. 127_000_000     127,000
'       10              100_000                     .. 12_700_000       12,700
'       25              40_000                      .. 5_080_000         5,080
'       50              20_000                      .. 2_540_000         2,540
'       100             10_000                      .. 1_270_000         1,127
'       200             5_000                       .. 635_000             635
'       400             2_500                       .. 317_500             317
'       1344            744                         .. 94_494               94
'       1600            625                         .. 79_375               79
'   Any other value polls the chip and returns the current setting
'   NOTE: Minimum unit is dependent on the current output data rate (AccelDataRate)
'   NOTE: ST application note example uses AccelDataRate(400)
    time_res := 1_000000 / acceldatarate(-2)                ' Resolution is (1 / AccelDataRate)
    readReg(core#TIME_LIMIT, 1, @curr_setting)
    case usec
        0..(time_res * 127):
            usec := (usec / time_res)
        OTHER:
            return (curr_setting * time_res)

    writeReg(core#TIME_LIMIT, 1, @usec)

PUB DeviceID
' Read device identification
    result := $00
    readReg(core#WHO_AM_I, 1, @result)

PUB DoubleClickWindow(usec): curr_setting | time_res
' Set maximum elapsed interval between two consecutive clicks, in uSec
'   Valid values:
'       AccelDataRate:  Min time (uS, also step size)  Max time (uS)   (equiv. range in mS)
'       1               1_000_000                   .. 255_000_000     1,000 .. 255,000
'       10              100_000                     .. 25_500_000        100 .. 25,500
'       25              40_000                      .. 10_200_000       40.0 .. 10,200
'       50              20_000                      .. 5_100_000        20.0 .. 5,100
'       100             10_000                      .. 2_550_000        10.0 .. 2,550
'       200             5_000                       .. 1_275_000         5.0 .. 1,275
'       400             2_500                       .. 637_500           2.5 .. 637.5
'       1344            744                         .. 189_732         0.744 .. 189.732
'       1600            625                         .. 159_375         0.625 .. 159.375
'   Any other value polls the chip and returns the current setting
'   NOTE: Minimum unit is dependent on the current output data rate (AccelDataRate)
'   NOTE: ST application note example uses AccelDataRate(400)
    time_res := 1_000000 / acceldatarate(-2)                ' Resolution is (1 / AccelDataRate)
    readReg(core#TIME_WINDOW, 1, @curr_setting)
    case usec
        0..(time_res * 255):
            usec := (usec / time_res)
        OTHER:
            return (curr_setting * time_res)

    writeReg(core#TIME_WINDOW, 1, @usec)

PUB FIFOEnabled(enabled) | tmp
' Enable FIFO memory
'   Valid values: FALSE (0), TRUE(1 or -1)
'   Any other value polls the chip and returns the current setting
    tmp := $00
    readReg(core#CTRL_REG5, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := (||enabled << core#FLD_FIFO_EN)
        OTHER:
            tmp := (tmp >> core#FLD_FIFO_EN) & %1
            return tmp * TRUE

    tmp &= core#MASK_FIFO_EN
    tmp := (tmp | enabled) & core#CTRL_REG5_MASK
    writeReg(core#CTRL_REG5, 1, @tmp)

PUB FIFOEmpty | tmp
' Flag indicating FIFO is empty
'   Returns: FALSE (0): FIFO contains at least one sample, TRUE(-1): FIFO is empty
    readReg(core#FIFO_SRC_REG, 1, @result)
    result := ((result >> core#FLD_EMPTY) & %1) * TRUE

PUB FIFOFull | tmp
' Flag indicating FIFO is full
'   Returns: FALSE (0): FIFO contains less than 32 samples, TRUE(-1): FIFO contains 32 samples
    readReg(core#FIFO_SRC_REG, 1, @result)
    result := ((result >> core#FLD_OVRN_FIFO) & %1) * TRUE

PUB FIFOMode(mode) | tmp
' Set FIFO behavior
'   Valid values:
'       BYPASS      (%00) - Bypass mode - FIFO off
'       FIFO        (%01) - FIFO mode
'       STREAM      (%10) - Stream mode
'       STREAM2FIFO (%11) - Stream-to-FIFO mode
'   Any other value polls the chip and returns the current setting
    readReg(core#FIFO_CTRL_REG, 1, @tmp)
    case mode
        BYPASS, FIFO, STREAM, STREAM2FIFO:
            mode <<= core#FLD_FM
        OTHER:
            return (tmp >> core#FLD_FM) & core#BITS_FM

    tmp &= core#MASK_FM
    tmp := (tmp | mode) & core#FIFO_CTRL_REG_MASK
    writeReg(core#FIFO_CTRL_REG, 1, @tmp)

PUB FIFOThreshold(level) | tmp
' Set FIFO threshold level
'   Valid values: 1..32
'   Any other value polls the chip and returns the current setting
    readReg(core#FIFO_CTRL_REG, 1, @tmp)
    case level
        1..32:
            level -= 1
        OTHER:
            return (tmp & core#BITS_FTH) + 1

    tmp &= core#MASK_FTH
    tmp := (tmp | level) & core#FIFO_CTRL_REG_MASK
    writeReg(core#FIFO_CTRL_REG, 1, @tmp)

PUB FIFOUnreadSamples
' Number of unread samples stored in FIFO
'   Returns: 0..32
    readReg(core#FIFO_SRC_REG, 1, @result)
    result &= core#BITS_FSS

PUB GyroAxisEnabled(xyzmask)
' Dummy method

PUB GyroBias(x, y, z, rw)
' Dummy method

PUB GyroData(x, y, z)
' Dummy method

PUB GyroDataRate(hz)
' Dummy method

PUB GyroDataReady
' Dummy method

PUB GyroDPS(x, y, z)
' Dummy method

PUB GyroOpMode(mode)
' Dummy method

PUB GyroScale(scale)
' Dummy method

PUB Interrupt
' Read interrupt state
'   Bit 6543210 (For each bit, 0: No interrupt, 1: Interrupt has been generated)
'       6: One or more interrupts have been generated
'       5: Z-axis high event
'       4: Z-axis low event
'       3: Y-axis high event
'       2: Y-axis low event
'       1: X-axis high event
'       0: X-axis low event
    readReg(core#INT1_SRC, 1, @result)

PUB IntMask(mask) | tmp
' Set interrupt mask
'   Bits:   543210
'       5: Z-axis high event
'       4: Z-axis low event
'       3: Y-axis high event
'       2: Y-axis low event
'       1: X-axis high event
'       0: X-axis low event
'   Valid values: %000000..%111111
'   Any other value polls the chip and returns the current setting
    tmp := $00
    readReg(core#INT1_CFG, 1, @tmp)
    case mask
        %000000..%111111:
        OTHER:
            return tmp

    writeReg(core#INT1_CFG, 1, @mask)

PUB IntThresh(level) | tmp
' Set interrupt threshold level, in micro-g's
'   Valid values: 0..16_000000
    tmp := $00
    readReg(core#INT1_THS, 1, @tmp)
    case level
        0..16_000000:                                       ' 0..16_000000 = 0..16M micro-g's = 0..16 g's
        OTHER:
            case AccelScale(-2)                             '
                2: tmp *= 16_000                            '
                4: tmp *= 32_000                            '
                8: tmp *= 62_000                            '
                16: tmp *= 186_000                          ' Scale threshold register's 7-bit range
            return tmp                                      '   to micro-g's

    case AccelScale(-2)                                     '
        2: tmp := 16_000                                    '
        4: tmp := 32_000                                    '
        8: tmp := 62_000                                    '
        16: tmp := 186_000                                  ' Scale micro-g's to threshold register's

    level /= tmp                                            '   7-bit range
    writeReg(core#INT1_THS, 1, @level)

PUB MagBias(x, y, z, rw)
' Dummy method

PUB MagData(x, y, z)
' Dummy method

PUB MagDataRate(hz)
' Dummy method

PUB MagDataReady
' Dummy method

PUB MagGauss(x, y, z)
' Dummy method

PUB MagOpMode(mode)
' Dummy method

PUB MagScale(scale)
' Dummy method

PRI readReg(reg_nr, nr_bytes, buff_addr) | cmd_packet
' Read nr_bytes from register 'reg_nr' to address 'buff_addr'
    case reg_nr
        $07..$0D, $0F, $1E..$27, $2E..$3F:
        $28..$2D:                                               ' If reading from accel data regs,
#ifdef LIS3DH_SPI
            reg_nr |= core#MS_SPI                                  '   set multi-byte read mode (SPI)
#elseifdef LIS3DH_I2C
            reg_nr |= core#MS_I2C                                  '   set multi-byte read mode (I2C)
#endif
        OTHER:
            return FALSE

#ifdef LIS3DH_SPI
    reg_nr |= core#R
    spi.Write(TRUE, @reg_nr, 1, FALSE)                             ' Ask for reg, but don't deselect after
    spi.Read(buff_addr, nr_bytes, TRUE)                         ' Read in the data
#elseifdef LIS3DH_I2C
    cmd_packet.byte[0] := SLAVE_WR | _sa0
    cmd_packet.byte[1] := reg_nr

    i2c.start                                                   ' S
    i2c.wr_block(@cmd_packet, 2)                                ' W [SL|W] [REG]
    i2c.start                                                   ' Rs
    i2c.write(SLAVE_RD | _sa0)                                  ' W [SL|R]
    i2c.rd_block(buff_addr, nr_bytes, TRUE)                     ' R ...
    i2c.stop                                                    ' P
#endif

PRI writeReg(reg_nr, nr_bytes, buff_addr) | cmd_packet
' Write nr_bytes to register 'reg_nr' stored at buff_addr
    case reg_nr
        $1E..$26, $2E, $30, $32..$34, $36..$38, $3A..$3F:
        OTHER:
            return FALSE
#ifdef LIS3DH_SPI
    spi.Write(TRUE, @reg_nr, 1, FALSE)                             ' Ask for reg, but don't deselect after
    spi.Write(TRUE, buff_addr, nr_bytes, TRUE)                  ' Write data - now it can be deselected
#elseifdef LIS3DH_I2C
    cmd_packet.byte[0] := SLAVE_WR | _sa0
    cmd_packet.byte[1] := reg_nr

    i2c.start
    i2c.wr_block(@cmd_packet, 2)
    i2c.wr_block(buff_addr, nr_bytes)
    i2c.stop
#endif
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
