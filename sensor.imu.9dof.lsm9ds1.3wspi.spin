{
    --------------------------------------------
    Filename: sensor.imu.9dof.lsm9ds1.3wspi.spin
    Author: Jesse Burt
    Description: Driver for the ST LSM9DS1 9DoF/3-axis IMU
    Copyright (c) 2020
    Started Aug 12, 2017
    Updated Aug 23, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

' Indicate to user apps how many Degrees of Freedom each sub-sensor has
'   (also imply whether or not it has a particular sensor)
    ACCEL_DOF               = 3
    GYRO_DOF                = 3
    MAG_DOF                 = 3
    BARO_DOF                = 0
    DOF                     = ACCEL_DOF + GYRO_DOF + MAG_DOF + BARO_DOF

' Constants used in low-level SPI read/write
    READ                    = 1 << 7
    WRITE                   = 0
    MS                      = 1 << 6

' Bias adjustment (AccelBias(), GyroBias(), MagBias()) read or write
    R                       = 0
    W                       = 1

' Axis-specific constants
    X_AXIS                  = 0
    Y_AXIS                  = 1
    Z_AXIS                  = 2
    ALL_AXIS                = 3

' Temperature scale constants
    CELSIUS                 = 0
    FAHRENHEIT              = 1
    KELVIN                  = 2

' Endian constants
    LITTLE                  = 0
    BIG                     = 1

' Interrupt active states (applies to both XLG and Mag)
    ACTIVE_HIGH             = 0
    ACTIVE_LOW              = 1

' FIFO settings
    FIFO_OFF                = core#FIFO_OFF
    FIFO_THS                = core#FIFO_THS
    FIFO_CONT_TRIG          = core#FIFO_CONT_TRIG
    FIFO_OFF_TRIG           = core#FIFO_OFF_TRIG
    FIFO_CONT               = core#FIFO_CONT

' Sensor-specific constants
    XLG                     = 0
    MAG                     = 1
    BOTH                    = 2

' Magnetometer operation modes
    MAG_OPMODE_CONT         = %00
    MAG_OPMODE_SINGLE       = %01
    MAG_OPMODE_POWERDOWN    = %10

' Magnetometer performance setting
    MAG_PERF_LOW            = %00
    MAG_PERF_MED            = %01
    MAG_PERF_HIGH           = %10
    MAG_PERF_ULTRA          = %11

' Operating modes (dummy)
    STANDBY                 = 0
    MEASURE                 = 1

' Gyroscope operating modes (dummy)
    #0, POWERDOWN, SLEEP, NORMAL

OBJ

    spi     : "com.spi.4w"
    core    : "core.con.lsm9ds1"
    io      : "io"
    time    : "time"

VAR

    long _autoCalc
    long _gres, _gbiasraw[3]
    long _ares, _abiasraw[3]
    long _mres, _mbiasraw[3]
    long _SCL, _SDIO, _CS_AG, _CS_M

PUB Null
'This is not a top-level object  

PUB Start(SCL_PIN, SDIO_PIN, CS_AG_PIN, CS_M_PIN): okay | tmp

    if lookdown(SCL_PIN: 0..31) and lookdown(SDIO_PIN: 0..31) and lookdown(CS_AG_PIN: 0..31) and lookdown(CS_M_PIN: 0..31)
        okay := spi.start (core#CLK_DELAY, core#CPOL)
        _SCL := SCL_PIN
        _SDIO := SDIO_PIN
        _CS_AG := CS_AG_PIN
        _CS_M := CS_M_PIN

        io.High (_CS_AG)
        io.High (_CS_M)
        io.Output (_CS_AG)
        io.Output (_CS_M)

        time.MSleep (110)
' Initialize the IMU

        XLGSoftreset
        MagSoftreset

' Set both the Accel/Gyro and Mag to 3-wire SPI mode
        setSPI3WireMode
        addressAutoInc(TRUE)
        MagI2C (FALSE)      'Disable the Magnetometer I2C interface

' Once everything is initialized, check the WHO_AM_I registers
        if DeviceID == core#WHOAMI_BOTH_RESP
            Defaults
            return okay
    Stop
    return FALSE

PUB Stop

    spi.stop

PUB Defaults | tmp
'Init Gyro
    GyroDataRate (952)
    GyroIntSelect (%00)
    GyroHighPass(0)
    GyroAxisEnabled (%111)

'Init Accel
    AccelAxisEnabled (%111)

    tmp := $C0                                  '\
    writeReg(XLG, core#CTRL_REG6_XL, 1, @tmp)   ' } Rewrite high-level
    tmp := $00                                  ' |
    writeReg(XLG, core#CTRL_REG7_XL, 1, @tmp)   '/

'Init Mag
    'CTRL_REG1_M
    TempCompensation (FALSE)
    MagPerf (MAG_PERF_HIGH)
    MagDataRate (10_000) 'after 1st cold start, odr looks good. resetting the prop after this, it then looks much faster?
    MagSelfTest (FALSE)

    'CTRL_REG2_M
    MagScale (16)

    'CTRL_REG3_M
    MagI2C (FALSE)
    MagLowPower (FALSE)
    MagOpMode (MAG_OPMODE_CONT)

    'CTRL_REG4_M
    MagEndian (LITTLE)

    'CTRL_REG5_M
    MagFastRead (FALSE)
    MagBlockUpdate (TRUE)

    'INT_CFG_M
    MagIntsEnabled (%000)
    MagIntLevel (ACTIVE_LOW)
    MagIntsLatched (TRUE)

    'INT_THS_L, _H
    MagIntThresh ($0000)

'Set Scales
    GyroScale(245)
    AccelScale(2)
    MagScale(4)

PUB AccelAxisEnabled(xyz_mask): curr_mask
' Enable data output for Accelerometer - per axis
'   Valid values: FALSE (0) or TRUE (1 or -1), for each axis
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#CTRL_REG5_XL, 1, @curr_mask)
    case xyz_mask
        %000..%111:
            xyz_mask <<= core#FLD_XEN_XL
        OTHER:
            return (curr_mask >> core#FLD_XEN_XL) & core#BITS_EN_XL

    curr_mask &= core#MASK_EN_XL
    curr_mask := (curr_mask | xyz_mask) & core#CTRL_REG5_XL_MASK
    writeReg(XLG, core#CTRL_REG5_XL, 1, @curr_mask)

PUB AccelBias(axbias, aybias, azbias, rw)
' Read or write/manually set accelerometer calibration offset values
'   Valid values:
'       rw:
'           R (0), W (1)
'       axbias, aybias, azbias:
'           -32768..32767
'   NOTE: When rw is set to READ, axbias, aybias and azbias must be addresses of respective variables to hold the returned
'       calibration offset values.
    case rw
        R:
            long[axbias] := _abiasraw[X_AXIS]
            long[aybias] := _abiasraw[Y_AXIS]
            long[azbias] := _abiasraw[Z_AXIS]

        W:
            case axbias
                -32768..32767:
                    _abiasraw[X_AXIS] := axbias
                OTHER:

            case aybias
                -32768..32767:
                    _abiasraw[Y_AXIS] := aybias
                OTHER:

            case azbias
                -32768..32767:
                    _abiasraw[Z_AXIS] := azbias
                OTHER:

PUB AccelClearInt | tmp, reg
' Clears out any interrupts set up on the Accelerometer
'   and resets all Accelerometer interrupt registers to their default values.
    tmp := $00
    repeat reg from core#INT_GEN_CFG_XL to core#INT_GEN_DUR_XL
        writeReg(XLG, reg, 1, @tmp)
    readReg(XLG, core#INT1_CTRL, 1, @tmp)
    tmp &= core#MASK_INT1_IG_XL
    writeReg(XLG, core#INT1_CTRL, 1, @tmp)

PUB AccelData(ax, ay, az) | tmp[2]
' Reads the Accelerometer output registers
    readReg(XLG, core#OUT_X_L_XL, 6, @tmp)

    long[ax] := ~~tmp.word[X_AXIS] - _abiasraw[X_AXIS]
    long[ay] := ~~tmp.word[Y_AXIS] - _abiasraw[Y_AXIS]
    long[az] := ~~tmp.word[Z_AXIS] - _abiasraw[Z_AXIS]

PUB AccelDataOverrun: flag
' Dummy method

PUB AccelDataRate(Hz): curr_hz

    return XLGDataRate(hz)

PUB AccelDataReady | tmp
' Accelerometer sensor new data available
'   Returns TRUE or FALSE
    readReg(XLG, core#STATUS_REG, 1, @tmp)
    result := ((tmp >> core#FLD_XLDA) & %1) * TRUE

PUB AccelG(ax, ay, az) | tmpx, tmpy, tmpz
' Reads the Accelerometer output registers and scales the outputs to micro-g's (1_000_000 = 1.000000 g = 9.8 m/s/s)
    AccelData(@tmpx, @tmpy, @tmpz)
    long[ax] := tmpx * _ares
    long[ay] := tmpy * _ares
    long[az] := tmpz * _ares

PUB AccelHighRes(enabled) | tmp
' Enable high resolution mode for accelerometer
'   Valid values: FALSE (0) or TRUE (1 or -1)
'   Any other value polls the chip and returns the current setting
    result := booleanChoice(XLG, core#CTRL_REG7_XL, core#FLD_HR, core#MASK_HR, core#CTRL_REG7_XL_MASK, enabled, 1)

PUB AccelInt | tmp
' Flag indicating accelerometer interrupt asserted
'   Returns TRUE if interrupt asserted, FALSE if not
    readReg(XLG, core#STATUS_REG, 1, @tmp)
    result := ((tmp >> core#FLD_IG_XL) & %1) * TRUE

PUB AccelScale(g): curr_scale
' Sets the full-scale range of the Accelerometer, in g's
'   Valid values: 2, 4, 8, 16
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#CTRL_REG6_XL, 1, @curr_scale)
    case g
        2, 4, 8, 16:
            g := lookdownz(g: 2, 16, 4, 8)
            _ares := lookupz(g: 0_000061, 0_000732, 0_000122, 0_000244)
            g <<= core#FLD_FS_XL
        OTHER:
            curr_scale := ((curr_scale >> core#FLD_FS_XL) & core#BITS_FS_XL) + 1
            return lookup(curr_scale: 2, 16, 4, 8)

    curr_scale &= core#MASK_FS_XL
    curr_scale := (curr_scale | g) & core#CTRL_REG6_XL_MASK
    writeReg(XLG, core#CTRL_REG6_XL, 1, @curr_scale)

PUB CalibrateMag{} | magmin[3], magmax[3], magtmp[3], axis, samples, opmode_orig, odr_orig
' Calibrate the magnetometer
    longfill(@magmin, 0, 11)                                ' Initialize variables to 0
    opmode_orig := magopmode(-2)                            ' Store the user-set operating mode
    odr_orig := magdatarate(-2)                             '   and data rate

    magopmode(MAG_OPMODE_CONT)                              ' Change to continuous measurement mode
    magdatarate(80_000)                                     '   and fastest data rate
    magbias(0, 0, 0, W)                                     ' Start with offsets cleared

    magdata(@magtmp[X_AXIS], @magtmp[Y_AXIS], @magtmp[Z_AXIS])
    magmax[X_AXIS] := magmin[X_AXIS] := magtmp[X_AXIS]      ' Establish initial minimum and maximum values:
    magmax[Y_AXIS] := magmin[Y_AXIS] := magtmp[Y_AXIS]      ' Start both with the same value to avoid skewing the
    magmax[Z_AXIS] := magmin[Z_AXIS] := magtmp[Z_AXIS]      '   calcs (because vars were initialized with 0)

    samples := 100                                          ' XXX arbitrary
    repeat samples
        repeat until magdataready{}
        magdata(@magtmp[X_AXIS], @magtmp[Y_AXIS], @magtmp[Z_AXIS])
        repeat axis from X_AXIS to Z_AXIS
            magmin[axis] := magtmp[axis] <# magmin[axis]
            magmax[axis] := magtmp[axis] #> magmax[axis]

    magbias((magmax[X_AXIS] + magmin[X_AXIS]) / 2, (magmax[Y_AXIS] + magmin[Y_AXIS]) / 2, (magmax[Z_AXIS] + magmin[Z_AXIS]) / 2, W)

    magopmode(opmode_orig)                                  ' Restore the user settings
    magdatarate(odr_orig)                                   '

PUB CalibrateXLG | abiasrawtmp[3], gbiasrawtmp[3], axis, ax, ay, az, gx, gy, gz, samples
' Calibrates the Accelerometer and Gyroscope
' Turn on FIFO and set threshold to 32 samples
    FIFOEnabled(TRUE)
    FIFOMode(FIFO_THS)
    FIFOThreshold (31)
    samples := FIFOThreshold(-2)
    repeat until FIFOFull
    repeat axis from 0 to 2
        gbiasrawtmp[axis] := 0
        abiasrawtmp[axis] := 0

    gyrobias(0, 0, 0, W)                                    ' Clear out existing bias offsets
    accelbias(0, 0, 0, W)                                   '
    repeat samples
' Read the gyro and accel data stored in the FIFO
        GyroData(@gx, @gy, @gz)
        gbiasrawtmp[X_AXIS] += gx
        gbiasrawtmp[Y_AXIS] += gy
        gbiasrawtmp[Z_AXIS] += gz

        AccelData(@ax, @ay, @az)
        abiasrawtmp[X_AXIS] += ax
        abiasrawtmp[Y_AXIS] += ay
        abiasrawtmp[Z_AXIS] += az - (1_000_000 / _ares)     ' Assumes sensor facing up!

    gyrobias(gbiasrawtmp[X_AXIS]/samples, gbiasrawtmp[Y_AXIS]/samples, gbiasrawtmp[Z_AXIS]/samples, W)
    accelbias(abiasrawtmp[X_AXIS]/samples, abiasrawtmp[Y_AXIS]/samples, abiasrawtmp[Z_AXIS]/samples, W)

    FIFOEnabled(FALSE)
    FIFOMode (FIFO_OFF)

PUB DeviceID: id
' Read device identification
'   Returns: $683D
    id := 0
    readReg(XLG, core#WHO_AM_I_XG, 1, @id.byte[1])
    readReg(MAG, core#WHO_AM_I_M, 1, @id.byte[0])

PUB Endian(endianness): curr_order
' Choose byte order of acclerometer/gyroscope data
'   Valid values: LITTLE (0) or BIG (1)
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#CTRL_REG8, 1, @curr_order)
    case endianness
        LITTLE, BIG:
            endianness := endianness << core#FLD_BLE
        OTHER:
            return (curr_order >> core#FLD_BLE) & %1

    curr_order &= core#MASK_BLE
    curr_order := (curr_order | endianness) & core#CTRL_REG8_MASK
    writeReg(XLG, core#CTRL_REG8, 1, @curr_order)

PUB FIFOEnabled(enabled): curr_setting
' Enable FIFO memory
'   Valid values: FALSE (0), TRUE(1 or -1)
'   Any other value polls the chip and returns the current setting
    return booleanChoice(XLG, core#CTRL_REG9, core#FLD_FIFO_EN, core#MASK_FIFO_EN, core#CTRL_REG9_MASK, enabled, 1)

PUB FIFOFull: flag
' FIFO Threshold status
'   Returns: FALSE (0): lower than threshold level, TRUE(-1): at or higher than threshold level
    readReg(XLG, core#FIFO_SRC, 1, @flag)
    return ((flag >> core#FLD_FTH_STAT) & %1) == 1

PUB FIFOMode(mode): curr_mode
' Set FIFO behavior
'   Valid values:
'       FIFO_OFF        (%000) - Bypass mode - FIFO off
'       FIFO_THS        (%001) - Stop collecting data when FIFO full
'       FIFO_CONT_TRIG  (%011) - Continuous mode until trigger is deasserted, then FIFO mode
'       FIFO_OFF_TRIG   (%100) - FIFO off until trigger is deasserted, then continuous mode
'       FIFO_CONT       (%110) - Continuous mode. If FIFO full, new sample overwrites older sample
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#FIFO_CTRL, 1, @curr_mode)
    case mode
        FIFO_OFF, FIFO_THS, FIFO_CONT_TRIG, FIFO_OFF_TRIG, FIFO_CONT:
            mode <<= core#FLD_FMODE
        OTHER:
            return (curr_mode >> core#FLD_FMODE) & core#BITS_FMODE

    curr_mode &= core#MASK_FMODE
    curr_mode := (curr_mode | mode) & core#FIFO_CTRL_MASK
    writeReg(XLG, core#FIFO_CTRL, 1, @curr_mode)

PUB FIFOThreshold(level): curr_lvl
' Set FIFO threshold level
'   Valid values: 0..31
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#FIFO_CTRL, 1, @curr_lvl)
    case level
        0..31:
        OTHER:
            return curr_lvl & core#BITS_FTH

    curr_lvl &= core#MASK_FTH
    curr_lvl := (curr_lvl | level) & core#FIFO_CTRL_MASK
    writeReg(XLG, core#FIFO_CTRL, 1, @curr_lvl)

PUB FIFOUnreadSamples: nr_samples
' Number of unread samples stored in FIFO
'   Returns: 0 (empty) .. 32
    readReg(XLG, core#FIFO_SRC, 1, @nr_samples)
    return nr_samples & core#BITS_FSS

PUB GyroAxisEnabled(xyz_mask): curr_mask
' Enable data output for Gyroscope - per axis
'   Valid values: FALSE (0) or TRUE (1 or -1), for each axis
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#CTRL_REG4, 1, @curr_mask)
    case xyz_mask
        %000..%111:
            xyz_mask <<= core#FLD_XEN_G
        OTHER:
            return (curr_mask >> core#FLD_XEN_G) & core#BITS_EN_G

    curr_mask &= core#MASK_EN_G
    curr_mask := (curr_mask | xyz_mask) & core#CTRL_REG4_MASK
    writeReg(XLG, core#CTRL_REG4, 1, @curr_mask)

PUB GyroBias(gxbias, gybias, gzbias, rw)
' Read or write/manually set Gyroscope calibration offset values
'   Valid values:
'       rw:
'           R (0), W (1)
'       gxbias, gybias, gzbias:
'           -32768..32767
'   NOTE: When rw is set to READ, gxbias, gybias and gzbias must be addresses of respective variables to hold the returned calibration offset values.
    case rw
        R:
            long[gxbias] := _gbiasraw[X_AXIS]
            long[gybias] := _gbiasraw[Y_AXIS]
            long[gzbias] := _gbiasraw[Z_AXIS]

        W:
            case gxbias
                -32768..32767:
                    _gbiasraw[X_AXIS] := gxbias
                OTHER:

            case gybias
                -32768..32767:
                    _gbiasraw[Y_AXIS] := gybias
                OTHER:

            case gzbias
                -32768..32767:
                    _gbiasraw[Z_AXIS] := gzbias
                OTHER:

PUB GyroClearInt | tmp, reg_nr
' Clears out any interrupts set up on the Gyroscope and resets all Gyroscope interrupt registers to their default values.
    tmp := $00
    repeat reg_nr from core#INT_GEN_CFG_G to core#INT_GEN_DUR_G
        writeReg(XLG, reg_nr, 1, @tmp)
    readReg(XLG, core#INT1_CTRL, 1, @tmp)
    tmp &= core#MASK_INT1_IG_G
    writeReg(XLG, core#INT1_CTRL, 1, @tmp)

PUB GyroData(gx, gy, gz) | tmp[2]
' Reads the Gyroscope output registers
    readReg(XLG, core#OUT_X_G_L, 6, @tmp)
    long[gx] := ~~tmp.word[X_AXIS] - _gbiasraw[X_AXIS]
    long[gy] := ~~tmp.word[Y_AXIS] - _gbiasraw[Y_AXIS]
    long[gz] := ~~tmp.word[Z_AXIS] - _gbiasraw[Z_AXIS]

PUB GyroDataRate(Hz): curr_rate
' Set Gyroscope Output Data Rate, in Hz
'   Valid values: 0, 15, 60, 119, 238, 476, 952
'   Any other value polls the chip and returns the current setting
'   NOTE: 0 powers down the Gyroscope
'   NOTE: 15 and 60 are rounded up from the datasheet specifications of 14.9 and 59.5, respectively
    readReg(XLG, core#CTRL_REG1_G, 1, @curr_rate)
    case Hz
        0, 15, 60, 119, 238, 476, 952:
            Hz := lookdownz(Hz: 0, 15, 60, 119, 238, 476, 952) << core#FLD_ODR
        OTHER:
            curr_rate := ((curr_rate >> core#FLD_ODR) & core#BITS_ODR)
            return lookupz(curr_rate: 0, 15, 60, 119, 238, 476, 952)

    curr_rate &= core#MASK_ODR
    curr_rate := (curr_rate | Hz)
    writeReg(XLG, core#CTRL_REG1_G, 1, @curr_rate)

PUB GyroDataReady: flag
' Gyroscope sensor new data available
'   Returns TRUE or FALSE
    readReg(XLG, core#STATUS_REG, 1, @flag)
    return ((flag >> core#FLD_GDA) & %1) == 1

PUB GyroDPS(gx, gy, gz) | tmp[3]
' Read the Gyroscope output registers and scale the outputs to micro-degrees of rotation per second (1_000_000 = 1.000000 deg/sec)
    GyroData(@tmp[X_AXIS], @tmp[Y_AXIS], @tmp[Z_AXIS])
    long[gx] := tmp[X_AXIS] * _gres
    long[gy] := tmp[Y_AXIS] * _gres
    long[gz] := tmp[Z_AXIS] * _gres

PUB GyroHighPass(cutoff): curr_freq
' Set Gyroscope high-pass filter cutoff frequency
'   Valid values: 0..9
'   Any other value polls the chip and returns the current setting
    readReg(XLG, core#CTRL_REG3_G, 1, @curr_freq)
    case cutoff
        0..9:
            cutoff := cutoff << core#FLD_HPCF_G
        OTHER:
            return (curr_freq >> core#FLD_HPCF_G) & core#BITS_HPCF_G

    curr_freq &= core#MASK_HPCF_G
    curr_freq := (curr_freq | cutoff) & core#CTRL_REG3_G_MASK
    writeReg(XLG, core#CTRL_REG3_G, 1, @curr_freq)

PUB GyroInactiveDur(duration): curr_dur
' Set gyroscope inactivity timer (use GyroInactiveSleep to define behavior on inactivity)
'   Valid values: 0..255 (0 effectively disables the feature)
'   Any other value polls the chip and returns the current setting
    curr_dur := $00
    readReg(XLG, core#ACT_DUR, 1, @curr_dur)
    case duration
        0..255:
        OTHER:
            return curr_dur

    writeReg(XLG, core#ACT_DUR, 1, @duration)

PUB GyroInactiveThr(threshold): curr_thr
' Set gyroscope inactivity threshold (use GyroInactiveSleep to define behavior on inactivity)
'   Valid values: 0..127 (0 effectively disables the feature)
'   Any other value polls the chip and returns the current setting
    curr_thr := $00
    readReg(XLG, core#ACT_THS, 1, @curr_thr)
    case threshold
        0..127:
        OTHER:
            return curr_thr & core#BITS_ACT_THS

    curr_thr &= core#MASK_ACT_THS
    curr_thr := (curr_thr | threshold) & core#ACT_THS_MASK
    writeReg(XLG, core#ACT_THS, 1, @curr_thr)

PUB GyroInactiveSleep(enabled): curr_setting
' Enable gyroscope sleep mode when inactive (see GyroActivityThr)
'   Valid values: FALSE (0): Gyroscope powers down, TRUE (1 or -1) Gyroscope enters sleep mode
'   Any other value polls the chip and returns the current setting
    return booleanChoice(XLG, core#ACT_THS, core#FLD_SLEEP_ON_INACT, core#MASK_SLEEP_ON_INACT, core#ACT_THS_MASK, enabled, 1)

PUB GyroInt: flag
' Flag indicating gyroscope interrupt asserted
'   Returns TRUE if interrupt asserted, FALSE if not
    readReg(XLG, core#STATUS_REG, 1, @flag)
    return ((flag >> core#FLD_IG_G) & %1) == 1

PUB GyroIntSelect(mode): curr_mode' XXX expand
' Set gyroscope interrupt generator selection
'   Valid values:
'       *%00..%11
'   Any other value polls the chip and returns the current setting
    curr_mode := $00
    readReg(XLG, core#CTRL_REG2_G, 1, @curr_mode)
    case mode
        %00..%11:
            mode := mode << core#FLD_INT_SEL
        OTHER:
            return (curr_mode >> core#FLD_INT_SEL) & core#BITS_INT_SEL

    curr_mode &= core#MASK_INT_SEL
    curr_mode := (curr_mode | mode) & core#CTRL_REG2_G_MASK
    writeReg(XLG, core#CTRL_REG2_G, 1, @curr_mode)

PUB GyroLowPower(enabled): curr_setting
' Enable low-power mode
'   Valid values: FALSE (0), TRUE (1 or -1)
'   Any other value polls the chip and returns the current setting
    return booleanChoice(XLG, core#CTRL_REG3_G, core#FLD_LP_MODE, core#MASK_LP_MODE, core#CTRL_REG3_G_MASK, enabled, 1)

PUB GyroScale(scale): curr_scale
' Set full scale of gyroscope output, in degrees per second (dps)
'   Valid values: 245, 500, 2000
'   Any other value polls the chip and returns the current setting
    curr_scale := $00
    readReg(XLG, core#CTRL_REG1_G, 1, @curr_scale)
    case scale
        245, 500, 2000:
            scale := lookdownz(scale: 245, 500, 0, 2000)
            _gres := lookupz(scale: 0_008750, 0_017500, 0, 0_070000)
            scale <<= core#FLD_FS
        OTHER:
            curr_scale := ((curr_scale >> core#FLD_FS) & core#BITS_FS) + 1
            return lookup(curr_scale: 245, 500, 0, 2000)

    curr_scale &= core#MASK_FS
    curr_scale := (curr_scale | scale) & core#CTRL_REG1_G_MASK
    writeReg(XLG, core#CTRL_REG1_G, 1, @curr_scale)

PUB GyroSleep(enabled): curr_setting
' Enable gyroscope sleep mode
'   Valid values: FALSE (0), TRUE (1 or -1)
'   Any other value polls the chip and returns the current setting
'   NOTE: If enabled, the gyro output will contain the last measured values
    return booleanChoice(XLG, core#CTRL_REG9, core#FLD_SLEEP_G, core#MASK_SLEEP_G, core#CTRL_REG9_MASK, enabled, 1)

PUB Interrupt: flag
' Flag indicating one or more interrupts asserted
'   Returns TRUE if one or more interrupts asserted, FALSE if not
    readReg(XLG, core#INT_GEN_SRC_XL, 1, @flag)
    return ((flag >> core#FLD_IA_XL) & %1) == 1

PUB IntInactivity: flag
' Flag indicating inactivity interrupt asserted
'   Returns TRUE if interrupt asserted, FALSE if not
    readReg(XLG, core#STATUS_REG, 1, @flag)
    return ((flag >> core#FLD_INACT) & %1) == 1

PUB MagBlockUpdate(enabled): curr_setting
' Enable block update for magnetometer data
'   Valid values:
'       TRUE(-1 or 1): Output registers not updated until MSB and LSB have been read
'       FALSE(0): Continuous update
'   Any other value polls the chip and returns the current setting
    return booleanChoice (MAG, core#CTRL_REG5_M, core#FLD_BDU_M, core#MASK_BDU_M, core#CTRL_REG5_M_MASK, enabled, 1)

PUB MagBias(mxbias, mybias, mzbias, rw) | axis, msb, lsb
' Read or write/manually set Magnetometer calibration offset values
'   Valid values:
'       rw:
'           R (0), W (1)
'       mxbias, mybias, mzbias:
'           -32768..32767
'   NOTE: When rw is set to READ, mxbias, mybias and mzbias must be addresses of respective variables to hold the returned
'       calibration offset values.

    case rw
        R:
            long[mxbias] := _mbiasraw[X_AXIS]
            long[mybias] := _mbiasraw[Y_AXIS]
            long[mzbias] := _mbiasraw[Z_AXIS]

        W:
            case mxbias
                -32768..32767:
                    _mbiasraw[X_AXIS] := mxbias
                OTHER:

            case mybias
                -32768..32767:
                    _mbiasraw[Y_AXIS] := mybias
                OTHER:

            case mzbias
                -32768..32767:
                    _mbiasraw[Z_AXIS] := mzbias
                OTHER:

            repeat axis from X_AXIS to Z_AXIS
                msb := (_mbiasraw[axis] & $FF00) >> 8
                lsb := _mbiasraw[axis] & $00FF

                writeReg(MAG, core#OFFSET_X_REG_L_M + (2 * axis), 1, @lsb)
                writeReg(MAG, core#OFFSET_X_REG_H_M + (2 * axis), 1, @msb)

PUB MagClearInt | tmp
' Clears out any interrupts set up on the Magnetometer and
'   resets all Magnetometer interrupt registers to their default values
    tmp := $00
    writeReg(MAG, core#INT_SRC_M, 1, @tmp)

PUB MagData(mx, my, mz) | tmp[2]
' Read the Magnetometer output registers
    readReg(MAG, core#OUT_X_L_M, 6, @tmp)
    long[mx] := ~~tmp.word[0]                               ' Note no offset correction performed here
    long[my] := ~~tmp.word[1]                               '   because the LSM9DS1's Mag has
    long[mz] := ~~tmp.word[2]                               '   offset regs built-in

PUB MagDataOverrun: status
' Magnetometer data overrun
'   Returns: Overrun status as bitfield
'       MSB   LSB
'       |     |
'       3 2 1 0
'       3: All axes data overrun
'       2: Z-axis data overrun
'       1: Y-axis data overrun
'       0: X-axis dta overrun
'   Example:
'       %1111: Indicates data has overrun on all axes
'       %0010: Indicates Y-axis data has overrun
'   NOTE: Overrun status indicates new data for axis has overwritten the previous data.
    readReg(MAG, core#STATUS_REG_M, 1, @status)
    return (status >> core#FLD_OR) & core#BITS_OR

PUB MagDataRate(mHz): curr_rate
' Set Magnetometer Output Data Rate, in milli-Hz
'   Valid values: 625, 1250, 2500, 5000, *10_000, 20_000, 40_000, 80_000
'   Any other value polls the chip and returns the current setting
    curr_rate := $00
    readReg(MAG, core#CTRL_REG1_M, 1, @curr_rate)
    case mHz
        625, 1250, 2500, 5000, 10_000, 20_000, 40_000, 80_000:
            mHz := lookdownz(mHz: 625, 1250, 2500, 5000, 10_000, 20_000, 40_000, 80_000) << core#FLD_DO
        OTHER:
            curr_rate := ((curr_rate >> core#FLD_DO) & core#BITS_DO)
            return lookupz(curr_rate: 625, 1250, 2500, 5000, 10_000, 20_000, 40_000, 80_000)

    curr_rate &= core#MASK_DO
    curr_rate := (curr_rate | mHz) & core#CTRL_REG1_M_MASK
    writeReg(MAG, core#CTRL_REG1_M, 1, @curr_rate)

PUB MagDataReady: flag
' Polls the Magnetometer status register to check if new data is available.
'   Returns TRUE if data available, FALSE if not
    readReg(MAG, core#STATUS_REG_M, 1, @flag)
    return (flag & core#BITS_DA) > 0

PUB MagEndian(endianness): curr_order
' Choose byte order of magnetometer data
'   Valid values: LITTLE (0) or BIG (1)
'   Any other value polls the chip and returns the current setting
    curr_order := $00
    readReg(MAG, core#CTRL_REG4_M, 1, @curr_order)
    case endianness
        LITTLE, BIG:
            endianness := endianness << core#FLD_BLE_M
        OTHER:
            return (curr_order >> core#FLD_BLE_M) & %1

    curr_order &= core#MASK_BLE_M
    curr_order := (curr_order | endianness) & core#CTRL_REG4_M_MASK
    writeReg(MAG, core#CTRL_REG4_M, 1, @curr_order)

PUB MagFastRead(enabled): curr_setting
' Enable reading of only the MSB of data to increase reading efficiency, at the cost of precision and accuracy
'   Valid values: TRUE(-1 or 1), FALSE(0)
'   Any other value polls the chip and returns the current setting
    return booleanChoice (MAG, core#CTRL_REG5_M, core#FLD_FAST_READ, core#MASK_FAST_READ, core#CTRL_REG5_M_MASK, enabled, 1)

PUB MagGauss(mx, my, mz) | tmp[3]
' Read the Magnetometer output registers and scale the outputs to micro-Gauss (1_000_000 = 1.000000 Gs)
    MagData(@tmp[X_AXIS], @tmp[Y_AXIS], @tmp[Z_AXIS])
    long[mx] := tmp[X_AXIS] * _mres
    long[my] := tmp[Y_AXIS] * _mres
    long[mz] := tmp[Z_AXIS] * _mres

PUB MagInt: intsrc
' Magnetometer interrupt source(s)
'   Returns: Interrupts that are currently asserted, as a bitmask
'   MSB    LSB
'   |      |
'   76543210
'   7: X-axis exceeds threshold, positive side
'   6: Y-axis exceeds threshold, positive side
'   5: Z-axis exceeds threshold, positive side
'   4: X-axis exceeds threshold, negative side
'   3: Y-axis exceeds threshold, negative side
'   2: Z-axis exceeds threshold, negative side
'   1: A measurement exceeded the internal magnetometer measurement range (overflow)
'   0: Interrupt asserted
    readReg(MAG, core#INT_SRC_M, 1, @intsrc)

PUB MagIntLevel(active_state): curr_state
' Set active state of INT_MAG pin when magnetometer interrupt asserted
'   Valid values: ACTIVE_LOW (0), ACTIVE_HIGH (1)
'   Any other value polls the chip and returns the current setting
    curr_state := $00
    readReg(MAG, core#INT_CFG_M, 1, @curr_state)
    case active_state
        ACTIVE_LOW, ACTIVE_HIGH:
            active_state ^= 1               ' This bit's polarity is opposite that of the XLG
            active_state <<= core#FLD_IEA
        OTHER:
            return (curr_state >> core#FLD_IEA) & %1

    curr_state &= core#MASK_IEA
    curr_state := (curr_state | active_state) & core#INT_CFG_M_MASK
    writeReg(MAG, core#INT_CFG_M, 1, @curr_state)

PUB MagIntsEnabled(enable_mask): curr_mask
' Enable magnetometer interrupts, as a bitmask
'   Valid values: %000..%111
'     MSB   LSB
'       |   |
'       2 1 0
'       2: X-axis data overrun
'       1: Y-axis data overrun
'       0: Z-axis dta overrun
'   Example:
'       %111: Enable interrupts for all three axes
'       %010: Enable interrupts for Y axis only

'   Any other value polls the chip and returns the current setting
    curr_mask := $00
    readReg(MAG, core#INT_CFG_M, 1, @curr_mask)
    case enable_mask
        %000..%111:
            enable_mask <<= core#FLD_XYZIEN
        OTHER:
            return (curr_mask>> core#FLD_XYZIEN) & core#BITS_XYZIEN

    curr_mask &= core#MASK_XYZIEN
    curr_mask := (curr_mask | enable_mask) & core#INT_CFG_M_MASK
    writeReg(MAG, core#INT_CFG_M, 1, @curr_mask)

PUB MagIntsLatched(enabled): curr_setting
' Latch interrupts asserted by the magnetometer
'   Valid values: TRUE (-1 or 1) or FALSE
'   Any other value polls the chip and returns the current setting
'   NOTE: If enabled, interrupts must be explicitly cleared using MagClearInt XXX verify
    return booleanChoice (MAG, core#INT_CFG_M, core#FLD_IEL, core#MASK_IEL, core#INT_CFG_M, enabled, -1)

PUB MagIntThresh(level): curr_thr 'XXX rewrite to take gauss as a param
' Set magnetometer interrupt threshold
'   Valid values: 0..32767
'   Any other value polls the chip and returns the current setting
'   NOTE: The set level is an absolute value and is compared to positive and negative measurements alike
    curr_thr := $00
    readReg(MAG, core#INT_THS_L_M, 2, @curr_thr)
    case level
        0..32767:
            swap(@level)
        OTHER:
            swap(@curr_thr)
            return curr_thr

    curr_thr := level & $7FFF
    writeReg(MAG, core#INT_THS_L_M, 2, @curr_thr)

PUB MagLowPower(enabled): curr_setting
' Enable magnetometer low-power mode
'   Valid values: TRUE (-1 or 1) or FALSE
'   Any other value polls the chip and returns the current setting
    return booleanChoice (MAG, core#CTRL_REG3_M, core#FLD_LP, core#MASK_LP, core#CTRL_REG3_M_MASK, enabled, 1)

PUB MagOpMode(mode): curr_mode
' Set magnetometer operating mode
'   Valid values:
'       MAG_OPMODE_CONT (0): Continuous conversion
'       MAG_OPMODE_SINGLE (1): Single conversion
'       MAG_OPMODE_POWERDOWN (2): Power down
    curr_mode := $00
    readReg(MAG, core#CTRL_REG3_M, 1, @curr_mode)
    case mode
        MAG_OPMODE_CONT, MAG_OPMODE_SINGLE, MAG_OPMODE_POWERDOWN:
        OTHER:
            return (curr_mode & core#BITS_MD)
            return
    curr_mode &= core#MASK_MD
    curr_mode := (curr_mode | mode) & core#CTRL_REG3_M_MASK
    writeReg(MAG, core#CTRL_REG3_M, 1, @curr_mode)

PUB MagOverflow: flag
' Magnetometer measurement range overflow
'   Returns: TRUE (-1) if measurement overflows sensor's internal range, FALSE otherwise
    return ((MagInt >> core#FLD_MROI) & %1) == 1

PUB MagPerf(mode): curr_mode
' Set magnetometer performance mode
'   Valid values:
'       MAG_PERF_LOW (0)
'       MAG_PERF_MED (1)
'       MAG_PERF_HIGH (2)
'       MAG_PERF_ULTRA (3)
'   Any other value polls the chip and returns the current setting
    readReg(MAG, core#CTRL_REG1_M, 1, @curr_mode.byte[0])
    readReg(MAG, core#CTRL_REG4_M, 1, @curr_mode.byte[1])

    case mode
        MAG_PERF_LOW, MAG_PERF_MED, MAG_PERF_HIGH, MAG_PERF_ULTRA:
        OTHER:
            return (curr_mode.byte[0] >> core#FLD_OM) & core#BITS_OM

    curr_mode.byte[0] &= core#MASK_OM
    curr_mode.byte[0] := (curr_mode.byte[0] | (mode << core#FLD_OM))
    curr_mode.byte[1] &= core#MASK_OMZ
    curr_mode.byte[1] := (curr_mode.byte[1] | (mode << core#FLD_OMZ))

    writeReg(MAG, core#CTRL_REG1_M, 1, @curr_mode.byte[0])
    writeReg(MAG, core#CTRL_REG4_M, 1, @curr_mode.byte[1])

PUB MagScale(scale): curr_scl
' Set full scale of Magnetometer, in Gauss
'   Valid values: 4, 8, 12, 16
'   Any other value polls the chip and returns the current setting
    curr_scl := $00
    readReg(MAG, core#CTRL_REG2_M, 1, @curr_scl)
    case(scale)
        4, 8, 12, 16:
            scale := lookdownz(scale: 4, 8, 12, 16)
            _mres := lookupz(scale: 0_000140, 0_000290, 0_000430, 0_000580)
            scale <<= core#FLD_FS_M
        OTHER:
            curr_scl := (curr_scl >> core#FLD_FS_M) & core#BITS_FS_M
            return lookupz(curr_scl: 4, 8, 12, 16)

    curr_scl := scale & (core#BITS_FS_M << core#FLD_FS_M)   'Mask off ALL other bits, because the only other
    writeReg(MAG, core#CTRL_REG2_M, 1, @curr_scl)           'fields in this reg are for performing soft-reset/reboot

PUB MagSelfTest(enabled): curr_setting
' Enable on-chip magnetometer self-test
'   Valid values: TRUE (-1 or 1) or FALSE
'   Any other value polls the chip and returns the current setting
    return booleanChoice (MAG, core#CTRL_REG1_M, core#FLD_ST, core#MASK_ST, core#CTRL_REG1_M_MASK, enabled, 1)

PUB MagSoftreset | tmp
' Perform soft-test of magnetometer
    tmp := $00
    tmp := (1 << core#FLD_REBOOT) | (1 << core#FLD_SOFT_RST)
    tmp &= core#CTRL_REG2_M_MASK
    writeReg(MAG, core#CTRL_REG2_M, 1, @tmp)
    time.MSleep (10)

    tmp := $00                                  'Mag doesn't seem to come out of reset unless
    writeReg(MAG, core#CTRL_REG2_M, 1, @tmp)  ' clearing the reset bit manually - Why would this behave
    setSPI3WireMode                             ' differently than the XL/G reset?

PUB Temperature: temp
' Get temperature from chip
'   Returns: Temperature in hundredths of a degree Celsius (1000 = 10.00 deg C)
    readReg(XLG, core#OUT_TEMP_L, 2, @temp)
    return (((temp.byte[0] << 8 | temp.byte[1]) >> 8) * 10) + 250

PUB TempCompensation(enable): curr_setting
' Enable on-chip temperature compensation for magnetometer readings
'   Valid values: TRUE (-1 or 1) or FALSE
'   Any other value polls the chip and returns the current setting
    return booleanChoice (MAG, core#CTRL_REG1_M, core#FLD_TEMP_COMP, core#MASK_TEMP_COMP, core#CTRL_REG1_M, enable, 1)

PUB TempDataReady: flag
' Temperature sensor new data available
'   Returns TRUE or FALSE
    readReg(XLG, core#STATUS_REG, 1, @flag)
    return ((flag >> core#FLD_TDA) & %1) == 1

PRI XLGDataBlockUpdate(enabled): curr_setting
' Wait until both MSB and LSB of output registers are read before updating
'   Valid values: FALSE (0): Continuous update, TRUE (1 or -1): Do not update until both MSB and LSB are read
'   Any other value polls the chip and returns the current setting
    return booleanChoice(XLG, core#CTRL_REG8, core#FLD_BDU, core#MASK_BDU, core#CTRL_REG8_MASK, enabled, 1)

PUB XLGDataRate(Hz): curr_rate
' Set output data rate, in Hz, of accelerometer and gyroscope
'   Valid values: 0 (power down), 14, 59, 119, 238, 476, 952
'   Any other value polls the chip and returns the current setting
    curr_rate := $00
    readReg(XLG, core#CTRL_REG1_G, 1, @curr_rate)
    case Hz := lookdown(Hz: 0, 14{.9}, 59{.5}, 119, 238, 476, 952)
        1..7:
            Hz := (Hz - 1) << core#FLD_ODR
        OTHER:
            curr_rate := ((curr_rate >> core#FLD_ODR) & core#BITS_ODR) + 1
            return lookup(curr_rate: 0, 14{.9}, 59{.5}, 119, 238, 476, 952)

    curr_rate &= core#MASK_ODR
    curr_rate := (curr_rate | Hz) & core#CTRL_REG1_G_MASK
    writeReg(XLG, core#CTRL_REG1_G, 1, @curr_rate)

PUB XLGIntLevel(active_state): curr_state
' Set active state for interrupts from Accelerometer and Gyroscope
'   Valid values: ACTIVE_HIGH (0) - active high, ACTIVE_LOW (1) - active low
'   Any other value polls the chip and returns the current setting
    curr_state := $00
    readReg(XLG, core#CTRL_REG8, 1, @curr_state)
    case active_state
        ACTIVE_HIGH, ACTIVE_LOW:
            active_state := active_state << core#FLD_H_LACTIVE
        OTHER:
            return (curr_state >> core#FLD_H_LACTIVE) & %1

    curr_state &= core#MASK_H_LACTIVE
    curr_state := (curr_state | active_state) & core#CTRL_REG8_MASK
    writeReg(XLG, core#CTRL_REG8, 1, @curr_state)

PUB XLGSoftreset | tmp
' Perform soft-reset of accelerometer/gyroscope
    tmp := %1
    writeReg(XLG, core#CTRL_REG8, 1, @tmp)
    time.MSleep (10)

PUB setAccelInterrupt(axis, threshold, duration, overunder, andOr) | tmpregvalue, accelths, accelthsh, tmpths
'Configures the Accelerometer interrupt output to the INT_A/G pin.
'XXX LEGACY METHOD
    overunder &= $01
    andOr &= $01
    tmpregvalue := 0
    readReg(XLG, core#CTRL_REG4, 1, @tmpregvalue)
    tmpregvalue &= $FD
    writeReg(XLG, core#CTRL_REG4, 1, @tmpregvalue)
    readReg(XLG, core#INT_GEN_CFG_XL, 1, @tmpregvalue)
    if andOr
        tmpregvalue |= $80
    else
        tmpregvalue &= $7F
    if (threshold < 0)
        threshold := -1 * threshold
    accelths := 0
    tmpths := 0
    tmpths := (_ares * threshold) >> 7
    accelths := tmpths & $FF

    case(axis)
        X_AXIS:
            tmpregvalue |= (1 <<(0 + overunder))
            writeReg(XLG, core#INT_GEN_THS_X_XL, 1, @accelths)
        Y_AXIS:
            tmpregvalue |= (1 <<(2 + overunder))
            writeReg(XLG, core#INT_GEN_THS_Y_XL, 1, @accelths)
        Z_AXIS:
            tmpregvalue |= (1 <<(4 + overunder))
            writeReg(XLG, core#INT_GEN_THS_Z_XL, 1, @accelths)
        OTHER:
            writeReg(XLG, core#INT_GEN_THS_X_XL, 1, @accelths)
            writeReg(XLG, core#INT_GEN_THS_Y_XL, 1, @accelths)
            writeReg(XLG, core#INT_GEN_THS_Z_XL, 1, @accelths)
            tmpregvalue |= (%00010101 << overunder)
    writeReg(XLG, core#INT_GEN_CFG_XL, 1, @tmpregvalue)
    if (duration > 0)
        duration := $80 | (duration & $7F)
    else
        duration := $00
    writeReg(XLG, core#INT_GEN_DUR_XL, 1, @duration)
    readReg(XLG, core#INT1_CTRL, 1, @tmpregvalue)
    tmpregvalue |= $40
    writeReg(XLG, core#INT1_CTRL, 1, @tmpregvalue)

PUB setGyroInterrupt(axis, threshold, duration, overunder, andOr) | tmpregvalue, gyroths, gyrothsh, gyrothsl
' Configures the Gyroscope interrupt output to the INT_A/G pin.
' XXX LEGACY METHOD
    overunder &= $01
    tmpregvalue := 0
    readReg(XLG, core#CTRL_REG4, 1, @tmpregvalue)
    tmpregvalue &= $FD
    writeReg(XLG, core#CTRL_REG4, 1, @tmpregvalue)
    writeReg(XLG, core#CTRL_REG4, 1, @tmpregvalue)
    readReg(XLG, core#INT_GEN_CFG_G, 1, @tmpregvalue)
    if andOr
        tmpregvalue |= $80
    else
        tmpregvalue &= $7F
    gyroths := 0
    gyrothsh := 0
    gyrothsl := 0
    gyroths := _gres * threshold 'TODO: REVIEW (use limit min/max operators and eliminate conditionals below?)

    if gyroths > 16383
        gyroths := 16383
    if gyroths < -16384
        gyroths := -16384
    gyrothsl := (gyroths & $FF)
    gyrothsh := (gyroths >> 8) & $7F

    case(axis)
        X_AXIS :
            tmpregvalue |= (1 <<(0 + overunder))
            writeReg(XLG, core#INT_GEN_THS_XH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_XL_G, 1, @gyrothsl)
        Y_AXIS :
            tmpregvalue |= (1 <<(2 + overunder))
            writeReg(XLG, core#INT_GEN_THS_YH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_YL_G, 1, @gyrothsl)
        Z_AXIS :
            tmpregvalue |= (1 <<(4 + overunder))
            writeReg(XLG, core#INT_GEN_THS_ZH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_ZL_G, 1, @gyrothsl)
        OTHER :
            writeReg(XLG, core#INT_GEN_THS_XH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_XL_G, 1, @gyrothsl)
            writeReg(XLG, core#INT_GEN_THS_YH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_YL_G, 1, @gyrothsl)
            writeReg(XLG, core#INT_GEN_THS_ZH_G, 1, @gyrothsh)
            writeReg(XLG, core#INT_GEN_THS_ZL_G, 1, @gyrothsl)
            tmpregvalue |= (%00010101 << overunder)
    writeReg(XLG, core#INT_GEN_CFG_G, 1, @tmpregvalue)
    if (duration > 0)
        duration := $80 | (duration & $7F)
    else
        duration := $00
    writeReg(XLG, core#INT_GEN_DUR_G, 1, @duration)
    readReg(XLG, core#INT1_CTRL, 1, @tmpregvalue)
    tmpregvalue |= $80
    writeReg(XLG, core#INT1_CTRL, 1, @tmpregvalue)

PUB setMagInterrupt(axis, threshold, lowhigh) | tmpcfgvalue, tmpsrcvalue, magths, magthsl, magthsh 'PARTIAL
' XXX LEGACY METHOD
    lowhigh &= $01
    tmpcfgvalue := $00
    tmpcfgvalue |= (lowhigh << 2)
    tmpcfgvalue |= $03
    tmpsrcvalue := $00
    magths := 0
    magthsl := 0
    magthsh := 0
    magths := _mres * threshold

    if (magths < 0)
        magths := -1 * magths
    if (magths > 32767)
        magths := 32767
    magthsl := magths & $FF
    magthsh := (magths >> 8) & $7F
    writeReg(MAG, core#INT_THS_L_M, 1, @magthsl)
    writeReg(MAG, core#INT_THS_H_M, 1, @magthsh)
    case axis
        X_AXIS :
            tmpcfgvalue |= ((1 << 7) | 2)
        Y_AXIS :
            tmpcfgvalue |= ((1 << 6) | 2)
        Z_AXIS :
            tmpcfgvalue |= ((1 << 5) | 2)
        OTHER :
            tmpcfgvalue |= (%11100010)
    writeReg(MAG, core#INT_CFG_M, 1, @tmpcfgvalue)

PRI addressAutoInc(enabled): curr_mode
' Enable automatic address increment, for multibyte transfers (SPI and I2C)
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_mode := $00
    readReg(XLG, core#CTRL_REG8, 1, @curr_mode)
    case ||enabled
        0, 1:
            enabled := (||enabled) << core#FLD_IF_ADD_INC
        OTHER:
            return ((curr_mode >> core#FLD_IF_ADD_INC) & %1) * TRUE

    curr_mode &= core#MASK_IF_ADD_INC
    curr_mode := (curr_mode | enabled) & core#CTRL_REG8_MASK
    writeReg(XLG, core#CTRL_REG8, 1, @curr_mode)

PRI MagI2C(enabled): curr_setting
' Enable Magnetometer I2C interface
'   Valid values: *TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
    return booleanChoice(MAG, core#CTRL_REG3_M, core#FLD_M_I2C_DISABLE, core#MASK_M_I2C_DISABLE, core#CTRL_REG3_M_MASK, enabled, -1)

PRI setSPI3WireMode | tmp

    tmp := (1 << core#FLD_SIM)
    writeReg(XLG, core#CTRL_REG8, 1, @tmp)
    tmp := (1 << core#FLD_M_SIM)
    writeReg(MAG, core#CTRL_REG3_M, 1, @tmp)

PRI swap(word_addr)

    byte[word_addr][3] := byte[word_addr][0]
    byte[word_addr][0] := byte[word_addr][1]
    byte[word_addr][1] := byte[word_addr][3]
    byte[word_addr][3] := 0

PRI booleanChoice(device, reg_nr, field, fieldmask, regmask, choice, invertchoice): bool
' Reusable method for writing a field that is of a boolean or on-off type
'   device: AG or MAG
'   reg: register
'   field: field within register to modify
'   fieldmask: bitmask that clears the bits in the field being modified
'   regmask: bitmask to ensure only valid bits within the register can be modified
'   choice: the choice (TRUE/FALSE, 1/0)
'   invertchoice: whether to invert the boolean logic (1 for normal, -1 for inverted)
    bool := $00
    readReg (device, reg_nr, 1, @bool)
    case ||choice
        0, 1:
            choice := ||(choice * invertchoice) << field
        OTHER:
            return (((bool >> field) & %1) * TRUE) * invertchoice

    bool &= fieldmask
    bool := (bool | choice) & regmask
    writeReg (device, reg_nr, 1, @bool)

PRI readReg(device, reg_nr, nr_bytes, buff_addr) | tmp
' Read from device
' Validate register - allow only registers that are
'   not 'reserved' (ST states reading should only be performed on registers listed in
'   their datasheet to guarantee proper behavior of the device)
    case device
        XLG:
            case reg_nr
                $04..$0D, $0F..$24, $26..$37:
                    io.Low(_CS_AG)
                    spi.shiftout(_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr | READ)
                    repeat tmp from 0 to nr_bytes-1
                        byte[buff_addr][tmp] := spi.shiftin(_SDIO, _SCL, core#MISO_BITORDER, 8)
                    io.High(_CS_AG)
                OTHER:
                    return
        MAG:
            case reg_nr
                $05..$0A, $0F, $20..$24, $27..$2D, $30..$33:
                    reg_nr |= READ
                    reg_nr |= MS
                    io.Low(_CS_M)
                    spi.shiftout(_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr)
                    repeat tmp from 0 to nr_bytes-1
                        byte[buff_addr][tmp] := spi.shiftin(_SDIO, _SCL, core#MISO_BITORDER, 8)
                    io.High(_CS_M)
                OTHER:
                    return

        OTHER:
            return

PRI writeReg(device, reg_nr, nr_bytes, buff_addr) | tmp
' Write byte to device
'   Validate register - allow only registers that are
'       writeable, and not 'reserved' (ST claims writing to these can
'       permanently damage the device)
    case device
        XLG:
            case reg_nr
                $04..$0D, $10..$13, $1E..$21, $23, $24, $2E, $30..$37:
                    io.Low (_CS_AG)
                    spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr)
                    repeat tmp from 0 to nr_bytes-1
                        spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
                    io.High (_CS_AG)
                core#CTRL_REG8:
                    io.Low (_CS_AG)
                    spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr)
                    byte[buff_addr][0] := byte[buff_addr][0] | (1 << core#FLD_SIM)   'Enforce 3-wire SPI mode
                     repeat tmp from 0 to nr_bytes-1
                        spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
                    io.High (_CS_AG)

                OTHER:
                    return

        MAG:
            case reg_nr
                $05..$0A, $0F, $20, $21, $23, $24, $27..$2D, $30..$33:
                    reg_nr |= WRITE
                    reg_nr |= MS
                    io.Low (_CS_M)
                    spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr)
                    repeat tmp from 0 to nr_bytes-1
                        spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
                    io.High (_CS_M)
                core#CTRL_REG3_M:   'Ensure any writes to this register also keep the 3-wire SPI mode bit set
                    reg_nr |= WRITE
                    io.Low (_CS_M)
                    spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, reg_nr)
                    byte[buff_addr][0] := byte[buff_addr][0] | (1 << core#FLD_M_SIM)    'Enforce 3-wire SPI mode
                    repeat tmp from 0 to nr_bytes-1
                        spi.SHIFTOUT (_SDIO, _SCL, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
                    io.High (_CS_M)
                OTHER:
                    return
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
