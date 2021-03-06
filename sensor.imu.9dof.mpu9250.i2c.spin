{
    --------------------------------------------
    Filename: sensor.imu.9dof.mpu9250.i2c.spin
    Author: Jesse Burt
    Description: Driver for the InvenSense MPU9250
    Copyright (c) 2020
    Started Sep 2, 2019
    Updated Aug 23, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SLAVE_XLG           = core#SLAVE_ADDR
    SLAVE_XLG_WR        = core#SLAVE_ADDR
    SLAVE_XLG_RD        = core#SLAVE_ADDR|1

    SLAVE_MAG           = core#SLAVE_ADDR_MAG
    SLAVE_MAG_WR        = core#SLAVE_ADDR_MAG
    SLAVE_MAG_RD        = core#SLAVE_ADDR_MAG|1

    DEF_SCL             = 28
    DEF_SDA             = 29
    DEF_HZ              = 100_000
    I2C_MAX_FREQ        = core#I2C_MAX_FREQ

    X_AXIS              = 0
    Y_AXIS              = 1
    Z_AXIS              = 2

    R                   = 0
    W                   = 1

' Magnetometer operating modes
    POWERDOWN           = %0000
    SINGLE              = %0001
    CONT8               = %0010
    CONT100             = %0110
    EXT_TRIG            = %0100
    SELFTEST            = %1000
    FUSEACCESS          = %1111

' Interrupt active level
    HIGH                = 0
    LOW                 = 1

' Interrupt output type
    INT_PP              = 0
    INT_OD              = 1

' Clear interrupt status options
    READ_INT_FLAG       = 0
    ANY                 = 1

' Interrupt sources
    INT_WAKE_ON_MOTION  = 64
    INT_FIFO_OVERFLOW   = 16
    INT_FSYNC           = 8
    INT_SENSOR_READY    = 1

' Temperature scales
    C                   = 0
    F                   = 1

' FIFO modes
    BYPASS              = 0
    STREAM              = 1
    FIFO                = 2

' Clock sources
    INT20               = 0
    AUTO                = 1
    CLKSTOP             = 7

VAR

    long _mag_bias[3]
    word _accel_cnts_per_lsb, _gyro_cnts_per_lsb, _mag_cnts_per_lsb
    byte _mag_sens_adj[3]
    byte _temp_scale

OBJ

    i2c : "com.i2c"
    core: "core.con.mpu9250.spin"
    time: "time"

PUB Null
''This is not a top-level object

PUB Start{}: okay                                               ' Default to "standard" Propeller I2C pins and 100kHz

    okay := Startx (DEF_SCL, DEF_SDA, DEF_HZ)

PUB Startx(SCL_PIN, SDA_PIN, I2C_HZ): okay

    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.setupx (SCL_PIN, SDA_PIN, I2C_HZ)    ' I2C Object Started?
                time.usleep (core#TREGRW)
                if i2c.present (SLAVE_XLG)                      ' Response from device?
                    disablei2cmaster{}                          ' Bypass the internal I2C master so we can read the Mag from the same bus
                    if deviceid{} == core#DEVID_RESP            ' Is it really an MPU9250?
                        readmagadj{}
                        magsoftreset{}
                        return okay

    return FALSE                                                ' If we got here, something went wrong

PUB Defaults
' Factory default settings
    accelscale(2)
    gyroscale(250)
    magopmode(CONT100)
    magscale(16)
    tempscale(C)

PUB Stop{}
' Put any other housekeeping code here required/recommended by your device before shutting down
    i2c.terminate

PUB AccelAxisEnabled(xyz_mask): curr_mask
' Enable data output for Accelerometer - per axis
'   Valid values: 0 or 1, for each axis:
'       Bits    210
'               XYZ
'   Any other value polls the chip and returns the current setting
    curr_mask := 0
    readreg(core#PWR_MGMT_2, 1, @curr_mask)
    case xyz_mask
        %000..%111:                                         ' We do the XOR below because the logic in the chip is actually the reverse of the method name, i.e., a bit set to 1 _disables_ that axis
            xyz_mask := ((xyz_mask ^ core#DISABLE_INVERT) & core#BITS_DISABLE_XYZA) << core#FLD_DISABLE_XYZA
        other:
            return ((curr_mask >> core#FLD_DISABLE_XYZA) & core#BITS_DISABLE_XYZA) ^ core#DISABLE_INVERT

    xyz_mask := ((curr_mask & core#MASK_DISABLE_XYZA) | xyz_mask) & core#PWR_MGMT_2_MASK
    writereg(core#PWR_MGMT_2, 1, @xyz_mask)

PUB AccelBias(ptr_x, ptr_y, ptr_z, rw) | tmp[3], tc_bit[3]
' Read or write/manually set accelerometer calibration offset values
'   Valid values:
'       When rw == W (1, write)
'           ptr_x, ptr_y, ptr_z: -16384..16383
'       When rw == R (0, read)
'           ptr_x, ptr_y, ptr_z:
'               Pointers to variables to hold current settings for respective axes
'   NOTE: The MPU9250 accelerometer is pre-programmed with offsets, which may or may not be adequate for your application
    readreg(core#XA_OFFS_H, 2, @tmp[X_AXIS])                ' Discrete reads because the three axes
    readreg(core#YA_OFFS_H, 2, @tmp[Y_AXIS])                '   aren't contiguous register pairs
    readreg(core#ZA_OFFS_H, 2, @tmp[Z_AXIS])

    case rw
        W:
            tc_bit[X_AXIS] := tmp[X_AXIS] & 1               ' LSB of each axis' data is a temperature compensation flag
            tc_bit[Y_AXIS] := tmp[Y_AXIS] & 1
            tc_bit[Z_AXIS] := tmp[Z_AXIS] & 1

            ptr_x := (ptr_x & $FFFE) | tc_bit[X_AXIS]
            ptr_y := (ptr_y & $FFFE) | tc_bit[Y_AXIS]
            ptr_z := (ptr_z & $FFFE) | tc_bit[Z_AXIS]

            writereg(core#XA_OFFS_H, 2, @ptr_x)
            writereg(core#YA_OFFS_H, 2, @ptr_y)
            writereg(core#ZA_OFFS_H, 2, @ptr_z)

        R:
            long[ptr_x] := ~~tmp[X_AXIS]
            long[ptr_y] := ~~tmp[Y_AXIS]
            long[ptr_z] := ~~tmp[Z_AXIS]
        other:
            return

PUB AccelData(ptr_x, ptr_y, ptr_z) | tmp[2]
' Read accelerometer data   'xxx flag to choose data path? i.e., pull live data from sensor or from fifo... hub var
    tmp := $00
    readreg(core#ACCEL_XOUT_H, 6, @tmp)

    long[ptr_x] := ~~tmp.word[2]
    long[ptr_y] := ~~tmp.word[1]
    long[ptr_z] := ~~tmp.word[0]

PUB AccelDataRate(Hz): curr_setting
' Set accelerometer output data rate, in Hz
'   Valid values: 4..1000
'   Any other value polls the chip and returns the current setting
    curr_setting := xlgdatarate(Hz)

PUB AccelDataReady{}: flag
' Flag indicating new accelerometer data available
'   Returns: TRUE (-1) if new data available, FALSE (0) otherwise
    return xlgdataready{}

PUB AccelG(ptr_x, ptr_y, ptr_z) | tmpx, tmpy, tmpz
' Read accelerometer data, calculated
'   Returns: Linear acceleration in millionths of a g
    acceldata(@tmpx, @tmpy, @tmpz)
    long[ptr_x] := (tmpx * _accel_cnts_per_lsb)
    long[ptr_y] := (tmpy * _accel_cnts_per_lsb)
    long[ptr_z] := (tmpz * _accel_cnts_per_lsb)

PUB AccelLowPassFilter(cutoff_Hz): curr_setting | lpf_bypass_bit
' Set accelerometer output data low-pass filter cutoff frequency, in Hz
'   Valid values: 5, 10, 20, 42, 98, 188
'   Any other value polls the chip and returns the current setting
    curr_setting := lpf_bypass_bit := 0
    readreg(core#ACCEL_CFG2, 1, @curr_setting)
    case cutoff_Hz
        0:                                                  ' Disable/bypass the LPF
            lpf_bypass_bit := (%1 << core#ACCEL_FCHOICE_B)
        5, 10, 20, 42, 98, 188:
            cutoff_Hz := lookdown(cutoff_Hz: 188, 98, 42, 20, 10, 5)
        other:
            if (curr_setting >> core#ACCEL_FCHOICE_B) & %1  ' The LPF bypass bit is set, so
                return 0                                    '   return 0 (LPF bypassed/disabled)
            else
                return lookup(curr_setting & core#A_DLPFCFG_BITS: 188, 98, 42, 20, 10, 5)

    cutoff_Hz := (curr_setting & core#A_DLPFCFG_MASK & core#ACCEL_FCHOICE_B_MASK) | cutoff_Hz | lpf_bypass_bit
    writereg(core#ACCEL_CFG2, 1, @cutoff_Hz)

PUB AccelScale(g): curr_scl
' Set accelerometer full-scale range, in g's
'   Valid values: *2, 4, 8, 16
'   Any other value polls the chip and returns the current setting
    curr_scl := 0
    readreg(core#ACCEL_CFG, 1, @curr_scl)
    case g
        2, 4, 8, 16:
            g := lookdownz(g: 2, 4, 8, 16) << core#ACCEL_FS_SEL
            _accel_cnts_per_lsb := lookupz(g >> core#ACCEL_FS_SEL: 61, 122, 244, 488)   ' 1/16384, 1/8192, 1/4096, 1/2048 * 1_000_000
        other:
            curr_scl := (curr_scl >> core#ACCEL_FS_SEL) & core#ACCEL_FS_SEL_BITS
            return lookupz(curr_scl: 2, 4, 8, 16)

    g := ((curr_scl & core#ACCEL_FS_SEL_MASK) | g) & core#ACCEL_CFG_MASK
    writereg(core#ACCEL_CFG, 1, @g)

PUB CalibrateAccel{} | tmpx, tmpy, tmpz, tmpbiasraw[3], axis, samples, factory_bias[3], orig_scale, orig_datarate, orig_lpf
' Calibrate the accelerometer
'   NOTE: The accelerometer must be oriented with the package top facing up for this method to be successful
    longfill(@tmpx, 0, 14)                                   ' Initialize variables to 0
    orig_scale := accelscale(-2)                            ' Preserve the user's original settings
    orig_datarate := acceldatarate(-2)
    orig_lpf := accellowpassfilter(-2)

    accelscale(2)                                           ' Set accel to most sensitive scale,
    acceldatarate(1000)                                     '   fastest sample rate,
    accellowpassfilter(188)                                 '   and a low-pass filter of 188Hz

                                                            ' MPU9250 accel has factory bias offsets,
                                                            '   so read them in first
    accelbias(@factory_bias[X_AXIS], @factory_bias[Y_AXIS], @factory_bias[Z_AXIS], 0)

    samples := 40                                           ' # samples to use for averaging

    repeat samples
        repeat until acceldataready
        acceldata(@tmpx, @tmpy, @tmpz)
        tmpbiasraw[X_AXIS] += tmpx
        tmpbiasraw[Y_AXIS] += tmpy
        tmpbiasraw[Z_AXIS] += tmpz - (1_000_000 / _accel_cnts_per_lsb) ' Assumes sensor facing up!

    repeat axis from X_AXIS to Z_AXIS
        tmpbiasraw[axis] /= samples
        tmpbiasraw[axis] := (factory_bias[axis] - (tmpbiasraw[axis]/8))

    accelbias(tmpbiasraw[X_AXIS], tmpbiasraw[Y_AXIS], tmpbiasraw[Z_AXIS], W)

    accelscale(orig_scale)                                  ' Restore user settings
    acceldatarate(orig_datarate)
    accellowpassfilter(orig_lpf)

PUB CalibrateGyro{} | tmpx, tmpy, tmpz, tmpbiasraw[3], axis, samples, orig_scale, orig_datarate, orig_lpf
' Calibrate the gyroscope
    longfill(@tmpx, 0, 8)                                   ' Initialize variables to 0
    orig_scale := gyroscale(-2)                             ' Preserve the user's original settings
    orig_datarate := xlgdatarate(-2)
    orig_lpf := gyrolowpassfilter(-2)

    gyroscale(250)                                          ' Set gyro to most sensitive scale,
    gyrodatarate(1000)                                      '   fastest sample rate,
    gyrolowpassfilter(188)                                  '   and a low-pass filter of 188Hz
    gyrobias(0, 0, 0, W)                                    ' Reset gyroscope bias offsets
    samples := 40                                           ' # samples to use for average

    repeat samples                                          ' Accumulate samples to be averaged
        repeat until gyrodataready
        gyrodata(@tmpx, @tmpy, @tmpz)
        tmpbiasraw[X_AXIS] -= tmpx                          ' Bias offsets are _added_ by the chip, so
        tmpbiasraw[Y_AXIS] -= tmpy                          '   negate the samples
        tmpbiasraw[Z_AXIS] -= tmpz

                                                            ' Write offsets to sensor (scaled to expected range)
    gyrobias((tmpbiasraw[X_AXIS]/samples) / 4, (tmpbiasraw[Y_AXIS]/samples) / 4, (tmpbiasraw[Z_AXIS]/samples) / 4, W)

    gyroscale(orig_scale)                                   ' Restore user settings
    gyrodatarate(orig_datarate)
    gyrolowpassfilter(orig_lpf)

PUB CalibrateMag{} | magmin[3], magmax[3], magtmp[3], axis, samples, opmode_orig
' Calibrate the magnetometer
    longfill(@magmin, 0, 13)                                ' Initialize variables to 0
    opmode_orig := magopmode(-2)                            ' Store the user's currently set mag operating mode,
    magopmode(CONT100)                                      '   just in case it's not continuous, 100Hz
    magbias(0, 0, 0, W)                                     ' Reset magnetometer bias offsets
    samples := 10                                           ' # samples to use for mean

    magdata(@magtmp[X_AXIS], @magtmp[Y_AXIS], @magtmp[Z_AXIS])
    magmax[X_AXIS] := magmin[X_AXIS] := magtmp[X_AXIS]      ' Establish initial minimum and maximum values:
    magmax[Y_AXIS] := magmin[Y_AXIS] := magtmp[Y_AXIS]      ' Start as the same value to avoid skewing the
    magmax[Z_AXIS] := magmin[Z_AXIS] := magtmp[Z_AXIS]      '   calcs (because vars were initialized with 0)

    repeat samples
        repeat until magdataready{}
        magdata(@magtmp[X_AXIS], @magtmp[Y_AXIS], @magtmp[Z_AXIS])
        repeat axis from X_AXIS to Z_AXIS
            magmax[axis] := magtmp[axis] #> magmax[axis]    ' Find the maximum value seen during sampling
            magmin[axis] := magtmp[axis] <# magmin[axis]    '   as well as the minimum, for each axis

    magbias((magmax[X_AXIS] + magmin[X_AXIS]) / 2, (magmax[Y_AXIS] + magmin[Y_AXIS]) / 2, (magmax[Z_AXIS] + magmin[Z_AXIS]) / 2, W) ' Write the average of the samples just gathered as new bias offsets
    magopmode(opmode_orig)                                  ' Restore the user's original operating mode

PUB ClockSource(src): curr_src
' Set sensor clock source
'   Valid values:
'       INT20 (0): Internal 20MHz oscillator
'      *AUTO (1): Automatically select best choice (PLL if ready, else internal oscillator)
'       CLKSTOP (7): Stop clock and hold in reset
    curr_src := 0
    readreg(core#PWR_MGMT_1, 1, @curr_src)
    case src
        INT20, AUTO, CLKSTOP:
        other:
            return curr_src & core#CLKSEL_BITS

    src := (curr_src & core#CLKSEL_MASK) | src
    writereg(core#PWR_MGMT_1, 1, @src)

PUB DeviceID{}: id
' Read device ID
'   Returns: AK8963 ID (LSB), MPU9250 ID (MSB)
    id := 0
    readreg(core#WIA, 1, @id.byte[0])
    readreg(core#WHO_AM_I, 1, @id.byte[1])

PUB FIFOEnabled(state): curr_state
' Enable the FIFO
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: This disables the interface to the FIFO, but the chip will still write data to it, if FIFO data sources are defined with FIFOSource()
    curr_state := 0
    readreg(core#USER_CTRL, 1, @curr_state)
    case ||(state)
        0, 1:
            state := ||(state) << core#FLD_FIFO_EN
            state := ((curr_state & core#MASK_FIFO_EN) | state) & core#USER_CTRL_MASK
            writereg(core#USER_CTRL, 1, @state)
        other:
            return ((curr_state >> core#FLD_FIFO_EN) & 1) == 1

PUB FIFOFull{}: flag
' Flag indicating FIFO is full
'   Returns: TRUE (-1) if FIFO is full, FALSE (0) otherwise
'   NOTE: If this flag is set, the oldest data has already been dropped from the FIFO
    readreg(core#INT_STATUS, 1, @flag)
    return ((flag >> core#FLD_FIFO_OVERFLOW_INT) & 1) == 1

PUB FIFOMode(mode): curr_mode
' Set FIFO mode
'   Valid values:
'       BYPASS (0): FIFO disabled
'       STREAM (1): FIFO enabled; when full, new data overwrites old data
'       FIFO (2): FIFO enabled; when full, no new data will be written to FIFO
'   Any other value polls the chip and returns the current setting
'   NOTE: If no data sources are set using FIFOSource(), the current mode returned will be BYPASS (0), regardless of what the mode was previously set to
    curr_mode := 0
    readreg(core#CONFIG, 1, @curr_mode)
    case mode
        BYPASS:                                             ' If bypassing the FIFO, turn
            fifosource(%00000000)                           '   off all FIFO data collection
            return
        STREAM, FIFO:
            mode := lookdownz(mode: STREAM, FIFO) << core#FIFO_MODE
        other:
            curr_mode := (curr_mode >> core#FIFO_MODE) & 1
            if fifosource(-2)                               ' If there's a mask set with FIFOSource(), return
                return lookupz(curr_mode: STREAM, FIFO)     '   either STREAM or FIFO as the current mode
            else
                return BYPASS                               ' If not, anything besides 0 (BYPASS) doesn't really matter or make sense
    mode := (curr_mode & core#FIFO_MODE_MASK) | mode
    writereg(core#CONFIG, 1, @mode)

PUB FIFORead(nr_bytes, ptr_data)
' Read FIFO data
    readreg(core#FIFO_R_W, nr_bytes, ptr_data)

PUB FIFOReset{} | tmp
' Reset the FIFO    XXX - expand..what exactly does it do?
    tmp := 1 << core#FLD_FIFO_RST
    writereg(core#USER_CTRL, 1, @tmp)

PUB FIFOSource(mask): curr_mask
' Set FIFO source data, as a bitmask
'   Valid values:
'       Bits: 76543210
'           7: Temperature
'           6: Gyro X-axis
'           5: Gyro Y-axis
'           4: Gyro Z-axis
'           3: Accelerometer
'           2: I2C Slave #2
'           1: I2C Slave #1
'           0: I2C Slave #0
'   Any other value polls the chip and returns the current setting
'   NOTE: If any one of the Gyro axis bits or the temperature bits are set, all will be buffered, even if they're not explicitly enabled (chip limitation)
    case mask
        %00000000..%11111111:
            writereg(core#FIFO_EN, 1, @mask)
        other:
            curr_mask := 0
            readreg(core#FIFO_EN, 1, @curr_mask)
            return

PUB FIFOUnreadSamples{}: nr_samples
' Number of unread samples stored in FIFO
'   Returns: unsigned 13bit
    readreg(core#FIFO_COUNTH, 2, @nr_samples)

PUB FSYNCActiveState(state): curr_state
' Set FSYNC pin active state/logic level
'   Valid values: LOW (1), *HIGH (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#INT_BYPASS_CFG, 1, @curr_state)
    case state
        LOW, HIGH:
            state := state << core#FLD_ACTL_FSYNC
        other:
            return (curr_state >> core#FLD_ACTL_FSYNC) & %1

    state := ((curr_state & core#MASK_ACTL_FSYNC) | state) & core#INT_BYPASS_CFG_MASK
    writereg(core#INT_BYPASS_CFG, 1, @state)

PUB GyroAxisEnabled(xyz_mask): curr_mask
' Enable data output for Gyroscope - per axis
'   Valid values: 0 or 1, for each axis:
'       Bits    210
'               XYZ
'   Any other value polls the chip and returns the current setting
    curr_mask := 0
    readreg(core#PWR_MGMT_2, 1, @curr_mask)
    case xyz_mask
        %000..%111:                                         ' We do the XOR below because the logic in the chip is actually the reverse of the method name, i.e., a bit set to 1 _disables_ that axis
            xyz_mask := ((xyz_mask ^ core#DISABLE_INVERT) & core#BITS_DISABLE_XYZG) << core#FLD_DISABLE_XYZG
        other:
            return ((curr_mask >> core#FLD_DISABLE_XYZG) & core#BITS_DISABLE_XYZG) ^ core#DISABLE_INVERT

    xyz_mask := ((curr_mask & core#MASK_DISABLE_XYZG) | xyz_mask) & core#PWR_MGMT_2_MASK
    writereg(core#PWR_MGMT_2, 1, @xyz_mask)

PUB GyroBias(ptr_x, ptr_y, ptr_z, rw) | tmp[3]
' Read or write/manually set gyroscope calibration offset values
'   Valid values:
'       When rw == W (1, write)
'           ptr_x, ptr_y, ptr_z: -32768..32767
'       When rw == R (0, read)
'           ptr_x, ptr_y, ptr_z:
'               Pointers to variables to hold current settings for respective axes
    case rw
        W:
            writereg(core#XG_OFFS_USR, 2, @ptr_x)
            writereg(core#YG_OFFS_USR, 2, @ptr_y)
            writereg(core#ZG_OFFS_USR, 2, @ptr_z)

        R:
            readreg(core#XG_OFFS_USR, 2, @tmp[X_AXIS])
            readreg(core#YG_OFFS_USR, 2, @tmp[Y_AXIS])
            readreg(core#ZG_OFFS_USR, 2, @tmp[Z_AXIS])
            long[ptr_x] := ~~tmp[X_AXIS]
            long[ptr_y] := ~~tmp[Y_AXIS]
            long[ptr_z] := ~~tmp[Z_AXIS]
        other:
            return

PUB GyroData(ptr_x, ptr_y, ptr_z) | tmp[2]
' Read gyro data
    tmp := $00
    readreg(core#GYRO_XOUT_H, 6, @tmp)

    long[ptr_x] := ~~tmp.word[2]
    long[ptr_y] := ~~tmp.word[1]
    long[ptr_z] := ~~tmp.word[0]

PUB GyroDataRate(Hz): curr_setting
' Set gyroscope output data rate, in Hz
'   Valid values: 4..1000
'   Any other value polls the chip and returns the current setting
    curr_setting := xlgdatarate(Hz)

PUB GyroDataReady{}: flag
' Flag indicating new gyroscope data available
'   Returns: TRUE (-1) if new data available, FALSE (0) otherwise
    return xlgdataready{}

PUB GyroDPS(gx, gy, gz) | tmpx, tmpy, tmpz
'Read gyroscope calibrated data (micro-degrees per second)
    gyrodata(@tmpx, @tmpy, @tmpz)
    long[gx] := (tmpx * _gyro_cnts_per_lsb)
    long[gy] := (tmpy * _gyro_cnts_per_lsb)
    long[gz] := (tmpz * _gyro_cnts_per_lsb)

PUB GyroLowPassFilter(cutoff_Hz): curr_setting | lpf_bypass_bits
' Set gyroscope output data low-pass filter cutoff frequency, in Hz
'   Valid values: 5, 10, 20, 42, 98, 188
'   Any other value polls the chip and returns the current setting
    curr_setting := lpf_bypass_bits := 0
    readreg(core#CONFIG, 1, @curr_setting)
    readreg(core#GYRO_CFG, 1, @lpf_bypass_bits)
    case cutoff_Hz
        0:                                                  ' Disable/bypass the LPF
            lpf_bypass_bits.byte[1] := (%11 << core#FCHOICE_B)  ' Store the new setting into the 2nd byte of the variable
        5, 10, 20, 42, 98, 188:
            cutoff_Hz := lookdown(cutoff_Hz: 188, 98, 42, 20, 10, 5)
        other:
            if lpf_bypass_bits & core#FCHOICE_B_BITS <> %00    ' The LPF bypass bit is set, so
                return 0                                    '   return 0 (LPF bypassed/disabled)
            else
                return lookup(curr_setting & core#DLPF_CFG_BITS: 188, 98, 42, 20, 10, 5)

    lpf_bypass_bits := (lpf_bypass_bits.byte[0] & core#DLPF_CFG_MASK) | lpf_bypass_bits.byte[1]
    cutoff_Hz := (curr_setting & core#DLPF_CFG_MASK) | cutoff_Hz
    writereg(core#CONFIG, 1, @cutoff_Hz)
    writereg(core#GYRO_CFG, 1, @lpf_bypass_bits)

PUB GyroScale(dps): curr_scl
' Set gyroscope full-scale range, in degrees per second
'   Valid values: *250, 500, 1000, 2000
'   Any other value polls the chip and returns the current setting
    curr_scl := 0
    readreg(core#GYRO_CFG, 1, @curr_scl)
    case dps
        250, 500, 1000, 2000:
            dps := lookdownz(dps: 250, 500, 1000, 2000) << core#GYRO_FS_SEL
            _gyro_cnts_per_lsb := lookupz(dps >> core#GYRO_FS_SEL: 7633, 15_267, 30_487, 60_975)    ' 1/131, 1/65.5, 1/32.8, 1/16.4 * 1_000_000
        other:
            curr_scl := (curr_scl >> core#GYRO_FS_SEL) & core#GYRO_FS_SEL_BITS
            return lookupz(curr_scl: 250, 500, 1000, 2000)

    dps := ((curr_scl & core#GYRO_FS_SEL_MASK) | dps) & core#GYRO_CFG_MASK
    writereg(core#GYRO_CFG, 1, @dps)

PUB IntActiveState(state): curr_state
' Set interrupt pin active state/logic level
'   Valid values: LOW (1), *HIGH (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#INT_BYPASS_CFG, 1, @curr_state)
    case state
        LOW, HIGH:
            state := state << core#FLD_ACTL
        other:
            return (curr_state >> core#FLD_ACTL) & %1

    state := ((curr_state & core#MASK_ACTL) | state) & core#INT_BYPASS_CFG_MASK
    writereg(core#INT_BYPASS_CFG, 1, @state)

PUB IntClearedBy(method): curr_setting
' Select method by which interrupt status may be cleared
'   Valid values:
'      *READ_INT_FLAG (0): Only by reading interrupt flags
'       ANY (1): By any read operation
'   Any other value polls the chip and returns the current setting
    curr_setting := 0
    readreg(core#INT_BYPASS_CFG, 1, @curr_setting)
    case method
        ANY, READ_INT_FLAG:
            method := method << core#FLD_INT_ANYRD_2CLEAR
        other:
            return (curr_setting >> core#FLD_INT_ANYRD_2CLEAR) & %1

    method := ((curr_setting & core#MASK_INT_ANYRD_2CLEAR) | method) & core#INT_BYPASS_CFG_MASK
    writereg(core#INT_BYPASS_CFG, 1, @method)

PUB Interrupt{}: flag
' Indicates one or more interrupts have been asserted
'   Returns: non-zero result if any interrupts have been asserted:
'       INT_WAKE_ON_MOTION (64) - Wake on motion interrupt occurred
'       INT_FIFO_OVERFLOW (16) - FIFO overflowed
'       INT_FSYNC (8) - FSYNC interrupt occurred
'       INT_SENSOR_READY (1) - Sensor raw data updated
    flag := 0
    readreg(core#INT_STATUS, 1, @flag)

PUB IntLatchEnabled(enable): curr_setting
' Latch interrupt pin when interrupt asserted
'   Valid values:
'      *FALSE (0): Interrupt pin is pulsed (width = 50uS)
'       TRUE (-1): Interrupt pin is latched, and must be cleared explicitly
'   Any other value polls the chip and returns the current setting
    curr_setting := 0
    readreg(core#INT_BYPASS_CFG, 1, @curr_setting)
    case ||(enable)
        0, 1:
            enable := (||(enable) << core#FLD_LATCH_INT_EN)
        other:
            return ((curr_setting >> core#FLD_LATCH_INT_EN) & %1) == 1

    enable := ((curr_setting & core#MASK_LATCH_INT_EN) | enable) & core#INT_BYPASS_CFG_MASK
    writereg(core#INT_BYPASS_CFG, 1, @enable)

PUB IntMask(mask): curr_mask
' Allow interrupts to assert INT pin, set by mask, or by ORing together symbols shown below
'   Valid values:
'       Bits: %x6x43xx0 (bit positions marked 'x' aren't supported by the device; setting any of them to '1' will be considered invalid and will query the current setting, instead)
'               Function                                Symbol              Value
'           6: Enable interrupt for wake on motion      INT_WAKE_ON_MOTION (64)
'           4: Enable interrupt for FIFO overflow       INT_FIFO_OVERFLOW  (16)
'           3: Enable FSYNC interrupt                   INT_FSYNC           (8)
'           1: Enable raw Sensor Data Ready interrupt   INT_SENSOR_READY    (1)
'   Any other value polls the chip and returns the current setting
    case mask & (core#INT_ENABLE_MASK ^ $FF)                                    ' Check the mask param passed to us against the inverse (xor $FF) of the
        0:                                                                      ' allowed bits(INT_ENABLE_MASK). If only allowed bits are set, the result should be 0
            mask &= core#INT_ENABLE_MASK
            writereg(core#INT_ENABLE, 1, @mask)
        other:                                                                  ' and it will be considered valid.
            curr_mask := 0
            readreg(core#INT_ENABLE, 1, @curr_mask)
            return curr_mask & core#INT_ENABLE_MASK

PUB IntOutputType(pp_od): curr_setting
' Set interrupt pin output type
'   Valid values:
'      *INT_PP (0): Push-pull
'       INT_OD (1): Open-drain
'   Any other value polls the chip and returns the current setting
    curr_setting := 0
    readreg(core#INT_BYPASS_CFG, 1, @curr_setting)
    case pp_od
        INT_PP, INT_OD:
            pp_od := pp_od << core#FLD_OPEN
        other:
            return (curr_setting >> core#FLD_OPEN) & %1

    pp_od := ((curr_setting & core#MASK_OPEN) | pp_od) & core#INT_BYPASS_CFG_MASK
    writereg(core#INT_BYPASS_CFG, 1, @pp_od)

PUB MagADCRes(bits): curr_res
' Set magnetometer ADC resolution, in bits
'   Valid values: *14, 16
'   Any other value polls the chip and returns the current setting
    curr_res := 0
    readreg(core#CNTL1, 1, @curr_res)
    case bits
        14, 16:
            _mag_cnts_per_lsb := lookdownz(bits: 14, 16)                    ' Set scaling factor
            _mag_cnts_per_lsb := lookupz(_mag_cnts_per_lsb: 5_997, 1_499)   ' based on ADC res
            bits := lookdownz(bits: 14, 16) << core#FLD_BIT
        other:
            curr_res := (curr_res >> core#FLD_BIT) & %1
            return lookupz(curr_res: 14, 16)

    bits := ((curr_res & core#MASK_BIT) | bits) & core#CNTL1_MASK
    writereg(core#CNTL1, 1, @bits)

PUB MagBias(ptr_x, ptr_y, ptr_z, rw)
' Read or write/manually set magnetometer calibration offset values
'   Valid values:
'       When rw == W (1, write)
'           ptr_x, ptr_y, ptr_z: -32760..32760
'       When rw == R (0, read)
'           ptr_x, ptr_y, ptr_z:
'               Pointers to variables to hold current settings for respective axes
    case rw
        W:
            _mag_bias[X_AXIS] := ptr_x
            _mag_bias[Y_AXIS] := ptr_y
            _mag_bias[Z_AXIS] := ptr_z
        R:
            long[ptr_x] := _mag_bias[X_AXIS]
            long[ptr_y] := _mag_bias[Y_AXIS]
            long[ptr_z] := _mag_bias[Z_AXIS]
        other:
            return

PUB MagData(ptr_x, ptr_y, ptr_z) | tmp[2]
' Read Magnetometer data
    tmp := $00
    readreg(core#HXL, 7, @tmp)                              ' Read 6 magnetometer data bytes, plus an extra (required) read of the status register

    tmp.word[X_AXIS] -= _mag_bias[X_AXIS]
    tmp.word[Y_AXIS] -= _mag_bias[Y_AXIS]
    tmp.word[Z_AXIS] -= _mag_bias[Z_AXIS]
    long[ptr_x] := ~~tmp.word[X_AXIS] * _mag_sens_adj[X_AXIS]
    long[ptr_y] := ~~tmp.word[Y_AXIS] * _mag_sens_adj[Y_AXIS]
    long[ptr_z] := ~~tmp.word[Z_AXIS] * _mag_sens_adj[Z_AXIS]

PUB MagDataOverrun{}: flag
' Flag indicating magnetometer data has overrun (i.e., new data arrived before previous measurement was read)
'   Returns: TRUE (-1) if overrun occurred, FALSE (0) otherwise
    flag := 0
    readreg(core#ST1, 1, @flag)
    return ((flag >> core#FLD_DOR) & %1) == 1

PUB MagDataRate(Hz)
' Set magnetometer output data rate, in Hz
'   Valid values: 8, 100
'   Any other value polls the chip and returns the current setting
'   NOTE: This setting switches to/only affects continuous measurement mode
    case Hz
        8:
            magopmode(CONT8)
        100:
            magopmode(CONT100)
        other:
            case magopmode(-2)
                CONT8:
                    return 8
                CONT100:
                    return 100

PUB MagDataReady{}: flag
' Flag indicating new magnetometer data is ready to be read
'   Returns: TRUE (-1) if new data available, FALSE (0) otherwise
    flag := 0
    readreg(core#ST1, 1, @flag)
    return (flag & %1) == 1

PUB MagGauss(mx, my, mz) | tmpx, tmpy, tmpz ' XXX unverified
' Read magnetomer data, calculated
'   Returns: Magnetic field strength, in micro-Gauss (i.e., 1_000_000 = 1Gs)
    magdata(@tmpx, @tmpy, @tmpz)
    long[mx] := (tmpx * _mag_cnts_per_lsb)
    long[my] := (tmpy * _mag_cnts_per_lsb)
    long[mz] := (tmpz * _mag_cnts_per_lsb)

PUB MagOverflow{}: flag
' Flag indicating magnetometer measurement has overflowed
'   Returns: TRUE (-1) if overrun occurred, FALSE (0) otherwise
'   NOTE: If this flag is TRUE, measurement data should not be trusted
'   NOTE: This bit self-clears when the next measurement starts
    flag := 0
    readreg(core#ST2, 1, @flag)
    return ((flag >> core#FLD_HOFL) & %1) == 1

PUB MagScale(scale): curr_scl
' Set full-scale range of magnetometer, in Gauss
'   Valid values: 48
'   NOTE: The magnetometer has only one full-scale range. This method is provided primarily for API compatibility with other IMUs
    case magadcres(-2)
        14:
            _mag_cnts_per_lsb := 5_997
        16:
            _mag_cnts_per_lsb := 1_499

    return 48

PUB MagSelfTestEnabled(state): curr_state
' Enable magnetometer self-test mode (generates magnetic field)
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value polls the chip and returns the current setting
    curr_state := 0
    readreg(core#ASTC, 1, @curr_state)
    case ||(state)
        0, 1:
            state := (||(state) << core#FLD_SELF) & core#ASTC_MASK
        other:
            return ((curr_state >> core#FLD_SELF) & %1) == 1

    state := (curr_state & core#MASK_SELF) | state
    writereg(core#ASTC, 1, @state)

PUB MagSoftReset{} | tmp
' Perform soft-reset of magnetometer: initialize all registers
    tmp := %1 & core#CNTL2_MASK
    writereg(core#CNTL2, 1, @tmp)

PUB MagTesla(mx, my, mz) | tmpx, tmpy, tmpz ' XXX unverified
' Read magnetomer data, calculated
'   Returns: Magnetic field strength, in thousandths of a micro-Tesla/nano-Tesla (i.e., 12000 = 12uT)
    magdata(@tmpx, @tmpy, @tmpz)
    long[mx] := (tmpx * _mag_cnts_per_lsb) * 100
    long[my] := (tmpy * _mag_cnts_per_lsb) * 100
    long[mz] := (tmpz * _mag_cnts_per_lsb) * 100

PUB MagOpMode(mode): curr_mode | tmp
' Set magnetometer operating mode
'   Valid values:
'      *POWERDOWN (0): Power down
'       SINGLE (1): Single measurement mode
'       CONT8 (2): Continuous measurement mode, 8Hz updates
'       CONT100 (6): Continuous measurement mode, 100Hz updates
'       EXT_TRIG (4): External trigger measurement mode
'       SELFTEST (8): Self-test mode
'       FUSEACCESS (15): Fuse ROM access mode
'   Any other value polls the chip and returns the current setting
    curr_mode := 0
    readreg(core#CNTL1, 1, @curr_mode)
    case mode
        POWERDOWN, SINGLE, CONT8, CONT100, EXT_TRIG, SELFTEST, FUSEACCESS:
        other:
            return curr_mode & core#BITS_MODE

    mode := ((curr_mode & core#MASK_MODE) | mode) & core#CNTL1_MASK
    tmp := POWERDOWN
    writereg(core#CNTL1, 1, @tmp)                           ' Transition to power down state
    time.msleep(100)                                        '   and wait 100ms first, per AK8963 datasheet
    writereg(core#CNTL1, 1, @mode)                          ' Then, transition to the selected mode

PUB MeasureMag{}
' Perform magnetometer measurement
    magopmode(SINGLE)

PUB ReadMagAdj{}
' Read magnetometer factory sensitivity adjustment values
    magopmode(FUSEACCESS)
    readreg(core#ASAX, 3, @_mag_sens_adj)
    magopmode(CONT100)
    _mag_sens_adj[X_AXIS] := ((((((_mag_sens_adj[X_AXIS] * 1000) - 128_000) / 2) / 128) + 1_000)) / 1000
    _mag_sens_adj[Y_AXIS] := ((((((_mag_sens_adj[Y_AXIS] * 1000) - 128_000) / 2) / 128) + 1_000)) / 1000
    _mag_sens_adj[Z_AXIS] := ((((((_mag_sens_adj[Z_AXIS] * 1000) - 128_000) / 2) / 128) + 1_000)) / 1000

PUB Reset{}
' Perform soft-reset
    magsoftreset{}
    xlgsoftreset{}

PUB TempDataRate(Hz): curr_setting
' Set temperature output data rate, in Hz
'   Valid values: 4..1000
'   Any other value polls the chip and returns the current setting
    curr_setting := xlgdatarate(Hz)

PUB Temperature{}: temp
' Read temperature, in hundredths of a degree
    temp := 0
    readreg(core#TEMP_OUT_H, 2, @temp)
    case _temp_scale
        F:
        other:
            return ((temp * 1_0000) / 333_87) + 21_00 'XXX unverified

PUB TempScale(scale)
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

PUB XLGDataRate(Hz): curr_setting
' Set accelerometer/gyro/temp sensor output data rate, in Hz
'   Valid values: 4..1000
'   Any other value polls the chip and returns the current setting
    case Hz
        4..1000:
            Hz := (1000 / Hz) - 1
            writereg(core#SMPLRT_DIV, 1, @Hz)
        other:
            curr_setting := 0
            readreg(core#SMPLRT_DIV, 1, @curr_setting)
            return 1000 / (curr_setting + 1)

PUB XLGDataReady{}: flag
' Flag indicating new gyroscope/accelerometer data is ready to be read
'   Returns: TRUE (-1) if new data available, FALSE (0) otherwise
    readreg(core#INT_STATUS, 1, @flag)
    return (flag & %1) == 1

PUB XLGLowPassFilter(cutoff_Hz): curr_setting
' Set accel/gyro/temp sensor low-pass filter cutoff frequency, in Hz
'   Valid values: 5, 10, 20, 42, 98, 188
'   Any other value polls the chip and returns the current setting (accel in lower word, gyro in upper word)
    curr_setting.word[0] := accellowpassfilter(cutoff_Hz)
    curr_setting.word[1] := gyrolowpassfilter(cutoff_Hz)

PUB XLGSoftReset{} | tmp
' Perform soft-reset of accelerometer and gyro: initialize all registers
    tmp := 1 << core#H_RESET
    writereg(core#PWR_MGMT_1, 1, @tmp)

PRI disableI2CMaster{} | tmp

    tmp := 0
    readreg(core#INT_BYPASS_CFG, 1, @tmp)
    tmp &= core#MASK_BYPASS_EN
    tmp := (tmp | 1 << core#FLD_BYPASS_EN)
    writereg(core#INT_BYPASS_CFG, 1, @tmp)

PRI readReg(reg_nr, nr_bytes, buff_addr) | cmd_packet, tmp
' Read nr_bytes from the slave device buff_addr
    case reg_nr                                             ' Basic register validation (device ID is embedded in the upper byte of each register symbol
        core#SELF_TEST_X_GYRO..core#SELF_TEST_Z_GYRO, core#SELF_TEST_X_ACCEL..core#SELF_TEST_Z_ACCEL, core#SMPLRT_DIV..core#WOM_THR, core#FIFO_EN..core#INT_ENABLE, core#INT_STATUS, core#EXT_SENS_DATA_00..core#EXT_SENS_DATA_23, core#I2C_SLV0_DO..core#USER_CTRL, core#PWR_MGMT_2, core#FIFO_COUNTH..core#WHO_AM_I, core#XG_OFFS_USR, core#YG_OFFS_USR, core#ZG_OFFS_USR, core#XA_OFFS_H, core#YA_OFFS_H, core#ZA_OFFS_H, core#ACCEL_XOUT_H..core#ACCEL_ZOUT_L, core#GYRO_XOUT_H..core#GYRO_ZOUT_L, core#TEMP_OUT_H:
            cmd_packet.byte[0] := SLAVE_XLG_WR              ' Accel/Gyro regs
            cmd_packet.byte[1] := reg_nr.byte[0]
            i2c.start{}
            i2c.wr_block (@cmd_packet, 2)
            i2c.start{}
            i2c.write (SLAVE_XLG_RD)
            repeat tmp from nr_bytes-1 to 0                 ' Read MSB to LSB (* relevant only to multi-byte registers)
                byte[buff_addr][tmp] := i2c.read(tmp == 0)
            i2c.stop{}
        core#HXL, core#HYL, core#HZL, core#WIA..core#ASTC, core#I2CDIS..core#ASAZ:
            cmd_packet.byte[0] := SLAVE_MAG_WR              ' Mag regs
            cmd_packet.byte[1] := reg_nr.byte[0]
            i2c.start{}
            i2c.wr_block (@cmd_packet, 2)
            i2c.start{}
            i2c.write (SLAVE_MAG_RD)
            repeat tmp from 0 to nr_bytes-1                 ' Read LSB to MSB (* relevant only to multi-byte registers)
                byte[buff_addr][tmp] := i2c.read(tmp == nr_bytes-1)
            i2c.stop{}
        other:
            return

PRI writeReg(reg_nr, nr_bytes, buff_addr) | cmd_packet, tmp
' Write nr_bytes to the slave device from buff_addr
    case reg_nr                                             ' Basic register validation (device ID is embedded in the upper byte of each register symbol
        core#SELF_TEST_X_GYRO..core#SELF_TEST_Z_GYRO, core#SELF_TEST_X_ACCEL..core#SELF_TEST_Z_ACCEL, core#SMPLRT_DIV..core#WOM_THR, core#FIFO_EN..core#I2C_SLV4_CTRL, core#INT_BYPASS_CFG, core#INT_ENABLE, core#I2C_SLV0_DO..core#PWR_MGMT_2, core#FIFO_COUNTH..core#FIFO_R_W, core#XG_OFFS_USR, core#YG_OFFS_USR, core#ZG_OFFS_USR, core#XA_OFFS_H, core#YA_OFFS_H, core#ZA_OFFS_H:
            cmd_packet.byte[0] := SLAVE_XLG_WR              ' Accel/Gyro regs
            cmd_packet.byte[1] := reg_nr.byte[0]
            i2c.start{}
            i2c.wr_block (@cmd_packet, 2)
            repeat tmp from nr_bytes-1 to 0                 ' Write MSB to LSB (* relevant only to multi-byte registers)
                i2c.write (byte[buff_addr][tmp])
            i2c.stop{}
        core#CNTL1..core#ASTC, core#I2CDIS:
            cmd_packet.byte[0] := SLAVE_MAG_WR              ' Mag regs
            cmd_packet.byte[1] := reg_nr.byte[0]
            i2c.start{}
            i2c.wr_block(@cmd_packet, 2)
            i2c.write (byte[buff_addr][0])
            i2c.stop{}
        other:
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
