{
    --------------------------------------------
    Filename: display.oled.us2066.i2c.spin
    Author: Jesse Burt
    Description: I2C driver for US2066-based OLED
        alphanumeric displays
    Copyright (c) 2020
    Created Dec 30, 2017
    Updated Mar 3, 2020
    See end of file for terms of use.
    --------------------------------------------
}
#include "lib.terminal.spin"

CON
' I2C Defaults
    SLAVE_WR        = core#SLAVE_ADDR
    SLAVE_RD        = SLAVE_WR|1
    R               = %1

    DEF_SCL         = 28
    DEF_SDA         = 29
    DEF_HZ          = 400_000
    I2C_MAX_FREQ    = core#I2C_MAX_FREQ

' Build some basic headers for I2C transactions
    CMD_HDR         = ((core#CTRLBYTE_CMD << 8) | SLAVE_WR)
    DAT_HDR         = ((core#CTRLBYTE_DATA << 8) | SLAVE_WR)

    TRANSTYPE_CMD   = 0
    TRANSTYPE_DATA  = 1

    CMDSET_FUND     = 0
    CMDSET_EXTD     = 1
    CMDSET_EXTD_IS  = 2
    CMDSET_OLED     = 3

    LEFT            = core#DISP_LEFT
    RIGHT           = core#DISP_RIGHT

' Display visibility modes
    OFF             = 0
    NORMAL          = 1
    ON              = 1
    INVERT          = 2

' SEG Voltage reference/enable or disable internal regulator
    INTERNAL        = 0
    EXTERNAL        = 1

' Constants for compatibility with display.lcd.serial.spin object
    LCD_BKSPC       = $08                                   ' move cursor left
    LCD_RT          = $09                                   ' move cursor right
    LCD_LF          = $0A                                   ' move cursor down 1 line
    LCD_CLS         = $0C                                   ' clear LCD (follow with 5 ms delay)
    LCD_CR          = $0D                                   ' move pos 0 of next line
    LCD_BL_ON       = $11                                   ' backlight on
    LCD_BL_OFF      = $12                                   ' backlight off
    LCD_OFF         = $15                                   ' LCD off
    LCD_ON1         = $16                                   ' LCD on; cursor off, blink off
    LCD_ON2         = $17                                   ' LCD on; cursor off, blink on
    LCD_ON3         = $18                                   ' LCD on; cursor on, blink off
    LCD_ON4         = $19                                   ' LCD on; cursor on, blink on
    LCD_LINE0       = $80                                   ' move to line 1, column 0
    LCD_LINE1       = $94                                   ' move to line 2, column 0
    LCD_LINE2       = $A8                                   ' move to line 3, column 0
    LCD_LINE3       = $BC                                   ' move to line 4, column 0
' Flag top-level objects can use to tell this is the PASM version
    PASM            = TRUE

VAR

    byte _reset
    byte _sa0_addr
' Variables to hold US2066 register states
    byte _mirror_h, _mirror_v
    byte _char_predef, _char_set
    byte _fontwidth, _cursor_invert, _disp_lines_NW
    byte _frequency, _divider
    byte _disp_en, _cursor_en, _blink_en
    byte _disp_lines_N, _dblht_en
    byte _seg_remap, _seg_pincfg
    byte _ext_vsl, _gpio_state
    byte _contrast
    byte _phs1_per, _phs2_per
    byte _vcomh_des_lvl
    byte _dblht_mode
    byte _cgram_blink, _disp_invert
    byte _fadeblink

OBJ

    i2c     : "com.i2c"
    core    : "core.con.us2066"
    time    : "time"
    io      : "io"

PUB Null
' This is not a top-level object

PUB Start(resetpin): okay
' Use default I2C settings - only have to specify the OLED display's reset pin
    okay := Startx (DEF_SCL, DEF_SDA, resetpin, core#I2C_MAX_FREQ, 0)

PUB Startx(SCL_PIN, SDA_PIN, RESET_PIN, I2C_HZ, SLAVE_BIT): okay
' Start with custom settings
'  SCL         - I2C Serial Clock pin
'  SDA         - I2C Serial Data pin
'  resetpin    - OLED display's assigned reset pin
'  hz          - I2C Bus Frequency (max 400kHz)
'  slave_bit   - Flag to indicate optional alternative slave address
    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31)
        if I2C_HZ =< core#I2C_MAX_FREQ
            if okay := i2c.setupx (SCL_PIN, SDA_PIN, I2C_HZ)    'I2C Object Started?
                time.MSleep (1)
                _reset := RESET_PIN
                case ||slave_bit
                        1: _sa0_addr := 1 << 1
                        0: _sa0_addr := 0
                        OTHER:
                            i2c.terminate
                            return FALSE
                Reset
                Defaults4x20
                if DeviceID == core#DEVID_RESP
                    return okay
                else
                    return FALSE
    return FALSE                                                'If we got here, something went wrong

PUB Stop
' Turn the display visibility off and stop the I2C cog
    DisplayVisibility (OFF)
    i2c.terminate

PUB Defaults2x16
' Set some sane defaults
    _fontwidth := core#FONTWIDTH_5
    _cursor_invert := core#CURSOR_NORMAL
    _disp_lines_NW := core#NW_1_2_LINE

    _disp_lines_N := core#DISP_LINES_2_4
    _dblht_en := 0

    _disp_en := 0
    _cursor_en := 0
    _blink_en := 0

    _char_predef := core#CG_ROM_RAM_240_8
    _char_set := core#CHAR_ROM_A

    _frequency := %0111
    _divider := %0000

    _mirror_h := core#SEG0_99
    _mirror_v := core#COM0_31

    _seg_remap := core#SEG_LR_REMAP_DIS
    _seg_pincfg := core#ALT_SEGPINCFG

    _ext_vsl := core#VSL_INTERNAL
    _gpio_state := core#GPIO_OUT_LOW

    _contrast := 127

    _phs1_per := 8
    _phs2_per := 7

    _vcomh_des_lvl := 2

    _cgram_blink := core#CGRAM_BLINK_DIS
    _disp_invert := core#NORMAL_DISPLAY

    _fadeblink := 0

PUB Defaults4x20
' Set some sane defaults
    _fontwidth := core#FONTWIDTH_5
    _cursor_invert := core#CURSOR_NORMAL
    _disp_lines_NW := core#NW_3_4_LINE

    _disp_lines_N := core#DISP_LINES_2_4
    _dblht_en := 0

    _disp_en := 0
    _cursor_en := 0
    _blink_en := 0

    _char_predef := core#CG_ROM_RAM_240_8
    _char_set := core#CHAR_ROM_A

    _frequency := %0111
    _divider := %0000

    _mirror_h := core#SEG0_99
    _mirror_v := core#COM0_31

    _seg_remap := core#SEG_LR_REMAP_DIS
    _seg_pincfg := core#ALT_SEGPINCFG

    _ext_vsl := core#VSL_INTERNAL
    _gpio_state := core#GPIO_OUT_LOW

    _contrast := 127

    _phs1_per := 8
    _phs2_per := 7

    _vcomh_des_lvl := 2

    _cgram_blink := core#CGRAM_BLINK_DIS
    _disp_invert := core#NORMAL_DISPLAY

    _fadeblink := 0

PUB Busy | flag
' Flag indicating display is busy
'   Returns: TRUE (-1) if busy, FALSE (0) otherwise
    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, $00, 0)
    i2c.start
    i2c.write (SLAVE_RD | _sa0_addr)
    flag := i2c.read (TRUE)
    i2c.stop

    if (flag >> 7) & %1
        return TRUE
    else
        return FALSE

PUB Char(ch) | col, row, pos
' Display single character.
'   NOTE: Control codes are interpreted.
'       To display the glyph for these characters, use Char_Literal(), instead
    case ch
        7:                                  ' Flash the display
            DisplayVisibility (INVERT)
            time.MSleep (50)
            DisplayVisibility (NORMAL)
        BS, $7F:
            case pos := GetPos
                $00..$13:
                    if pos > $00            ' Keep backing up as long as
                        Position(pos-1, 0)  ' we're not at the left-most column
                        Char_Literal(" ")
                        Position(pos-1, 0)
                    else
                        Position (0, 0)     ' 1st display line:Stop upper-left
                        Char_Literal(" ")   ' Stop upper-left / HOME
                        Position (0, 0)
                $20..$33:
                    if pos > $20
                        col := pos-$20
                        Position(col-1, 1)
                        Char_Literal(" ")
                        Position(col-1, 1)
                    else
                        Position(19, 0)     ' Wrap to previous line
                        Char_Literal(" ")
                        Position(19, 0)
                $40..$53:
                    if pos > $40
                        col := pos-$40
                        Position(col-1, 2)
                        Char_Literal(" ")
                        Position(col-1, 2)
                    else
                        Position(19, 1)     ' Wrap to previous line
                        Char_Literal(" ")
                        Position(19, 1)
                $60..$73:
                    if pos > $60
                        col := pos-$60
                        Position (col-1, 3)
                        Char_Literal(" ")
                        Position (col-1, 3)
                    else
                        Position (19, 2)    ' Wrap to previous line
                        Char_Literal(" ")
                        Position (19, 2)
                OTHER: return
        LF:
            case pos := GetPos              ' Get current display RAM address pointer
                $00..$13:                   ' Pointer is somewhere in row 0's range, so
                    row := 1                '   line-feed to row 1
                $20..$33:
                    row := 2                ' .. 2
                    pos -= $20
                $40..$53:
                    row := 3                ' .. 3
                    pos -= $40
                $60..$73:
                    row := 3                ' Already at last row - stay there
                    pos -= $60
                OTHER: row := 0
            Position (pos, row)             ' Set new position to same column on new row
        CB:
            Clear
        CR:
            case GetPos
                $00..$13: row := 0          ' As in LF, row 0
                $20..$33: row := 1          ' .. 1
                $40..$53: row := 2          ' .. 2
                $60..$73: row := 3          ' .. 3
                OTHER: return
            Position (0, row)               ' Set new position to column 0 of same row
        OTHER:
            wrdata(ch)

PUB Char_Literal(ch)
' Display single character
'   NOTE: Control codes will not be processed, but the font glyph will be display instead
    ch &= $FF
    wrdata(ch)

PUB CharGen(count)
' Select number of pre-defined vs free user-defined character cells
'   Valid values:
'       240 (leaves 8 available user-defined characters)
'       248 (leaves 8 available user-defined characters)
'       250 (leaves 6 available user-defined characters)
'       256 (leaves 0 available user-defined characters)
    case count
        240: _char_predef := core#CG_ROM_RAM_240_8
        248: _char_predef := core#CG_ROM_RAM_248_8
        250: _char_predef := core#CG_ROM_RAM_250_6
        256: _char_predef := core#CG_ROM_RAM_256_0
        OTHER: return

    writeReg (TRANSTYPE_CMD, 2, CMDSET_EXTD, core#FUNCTION_SEL_B, _char_predef | _char_set)

PUB CharROM(char_set)
' Select ROM font / character set
'   Valid values:
'       0: ROM A
'       1: ROM B
'       2: ROM C
'   Any other value returns the current setting
    case char_set
        0: _char_set := core#CHAR_ROM_A
        1: _char_set := core#CHAR_ROM_B
        2: _char_set := core#CHAR_ROM_C
        OTHER:
            return _char_set

    writeReg (TRANSTYPE_CMD, 2, CMDSET_EXTD, core#FUNCTION_SEL_B, _char_predef | _char_set)

PUB Clear
' Clear display
    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#CLEAR_DISPLAY, 0)

PUB ClearLine(line)
' Clear specified line
'   Valid values: 0..3
'   Any other value is ignored
    if lookdown (line: 0..3)
        Position(0, line)
        repeat 20
            Char(" ")

PUB ClockFreq(freq)
' Set display internal oscillator frequency, in kHz
'   Valid values:
'       454..556 (see lookup tables below for specific values)
'   Any other value returns the current setting
    case freq := lookdown(freq: 54, 460, 467, 474, 481, 488, 494, 501, 508, 515, 522, 528, 535, 542, 549, 556)
        1..16:
            _frequency := freq << 4
        OTHER:
            result := _frequency >> 4
            result := lookupz(result: 54, 460, 467, 474, 481, 488, 494, 501, 508, 515, 522, 528, 535, 542, 549, 556)
            return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#DISP_CLKDIV_OSC, _frequency | _divider)

PUB ClockDiv(divider)
' Set clock frequency divider used by the display controller
'   Valid values: 1..16 (default: 1)
    case divider
        1..16:
            _divider := divider - 1
        OTHER:
            return _divider + 1

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#DISP_CLKDIV_OSC, _frequency | _divider)

PUB COMLogicHighLevel(level)
' Set COMmon pins high logic level, relative to Vcc
'   Valid values:
'       0_65: 0.65 * Vcc
'       0_71: 0.71 * Vcc
'      *0_77: 0.77 * Vcc
'       0_83: 0.83 * Vcc
'       1_00: 1.00 * Vcc
    case level
        0_65, 0_71, 0_77, 0_83, 1_00:
            _vcomh_des_lvl := lookdownz(level: 0_65, 0_71, 0_77, 0_83, 1_00) << 4
        OTHER:
            result := lookupz(_vcomh_des_lvl >> 4: 0_65, 0_71, 0_77, 0_83, 1_00)
            return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_VCOMH_DESEL, _vcomh_des_lvl)

PUB Contrast(level)
' Set display contrast level
'   Valid values: 0..127 (POR: 127)
'   Any other value returns the current setting
    case level
        0..255: _contrast := level
        OTHER:
            return _contrast

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_CONTRAST, _contrast)

PUB CursorBlink(enable)
' Enable cursor blinking
'   Valid values:
'      *FALSE (0): Steady cursor
'       TRUE (-1 or 1): Blinking cursor
'   Any other value returns the current setting
    case ||enable
        0: _blink_en := core#BLINK_OFF
        1: _blink_en := core#BLINK_ON
        OTHER:
            return _blink_en

    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#DISPLAY_ONOFF | _disp_en | _cursor_en | _blink_en, 0)

PUB CursorInvert(enable)
' Invert cursor
'   Valid values:
'      *FALSE (0): Normal cursor
'       TRUE (-1 or 1): Inverted cursor
'   Any other value returns the current setting
    case ||enable
        1: _cursor_invert := core#CURSOR_INVERT
        0: _cursor_invert := core#CURSOR_NORMAL
        OTHER:
            return _cursor_invert

    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#EXTENDED_FUNCSET | _fontwidth | _cursor_invert | _disp_lines_NW, 0)

PUB CursorMode(type)
' Select cursor display mode
'   Valid values:
'       0: No cursor
'       1: Block, blinking
'       2: Underscore, no blinking
'       3: Underscore, block blinking
    case type
        0:  _cursor_invert := _blink_en := _cursor_en := FALSE
        1:
            _cursor_en := core#CURSOR_OFF
            _cursor_invert := core#CURSOR_INVERT
            _blink_en := core#BLINK_ON
        2:
            _cursor_en := core#CURSOR_ON
            _cursor_invert := core#CURSOR_NORMAL
            _blink_en := core#BLINK_OFF
        3:
            _cursor_en := core#CURSOR_ON
            _cursor_invert := core#CURSOR_NORMAL
            _blink_en := core#BLINK_ON
        OTHER: return

    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#DISPLAY_ONOFF | _disp_en | _cursor_en | _blink_en, 0)
    CursorInvert (_cursor_invert >> 1)

PUB DeviceID
' Read device ID
'   Returns: $21 if successful
    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, $00, 0)

    i2c.start
    i2c.write (SLAVE_RD | _sa0_addr)
    i2c.read (FALSE)          'First read gets the address counter register - throw it away
    result := i2c.read (i2c#NAK)    'Second read gets the Part ID
    i2c.stop

PUB DisplayBlink(delay)
' Gradually fade out/in display
'   Valid values:
'       0..128, in multiples of 8
'   Any other value returns the current setting
'   NOTE: 0 effectively disables the setting
    case delay
        0: _fadeblink := core#FADE_BLINK_DIS
        8,16,24,32,40,48,56,64,72,80,88,96,104,112,120,128: _fadeblink := (core#BLINK_ENA | ((delay / 8) - 1))
        OTHER:
            return _fadeblink

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#FADEOUT_BLINK, _fadeblink)

PUB DisplayFade(delay)
' Gradually fade out display (just once)
'   Valid values:
'       0..128, in multiples of 8
'   Any other value returns the current setting
'   NOTE: 0 effectively disables the function
    case delay
        0: _fadeblink := core#FADE_BLINK_DIS
        8,16,24,32,40,48,56,64,72,80,88,96,104,112,120,128: _fadeblink := (core#FADE_OUT_ENA | ((delay / 8) - 1))
        OTHER:
            return _fadeblink

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#FADEOUT_BLINK, _fadeblink)

PUB DisplayInverted(enabled)
' Invert display colors
'   Valid values:
'       TRUE (-1 or 1), FALSE (0)
    case ||enabled
        0, 1:
            enabled := lookupz(||enabled: NORMAL, INVERT)
            DisplayVisibility(enabled)
        OTHER:
            return FALSE

PUB DisplayLines(lines)
' Set number of display lines
'   Valid values:
'       1..4
'   Any other value is ignored
    case lines
        1:
            _disp_lines_N := core#DISP_LINES_1_3
            _disp_lines_NW := core#NW_1_2_LINE
        2:
            _disp_lines_N := core#DISP_LINES_2_4
            _disp_lines_NW := core#NW_1_2_LINE
        3:
            _disp_lines_N := core#DISP_LINES_1_3
            _disp_lines_NW := core#NW_3_4_LINE
        4:
            _disp_lines_N := core#DISP_LINES_2_4
            _disp_lines_NW := core#NW_3_4_LINE

        OTHER: return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_FUND, core#FUNCTION_SET_0 | _disp_lines_N | _dblht_en, 0)
    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#EXTENDED_FUNCSET | _fontwidth | _cursor_invert | _disp_lines_NW, 0)

PUB DisplayShift(direction)
' Shift the display left or right by one character cell's width
'   Valid values:
'       LEFT (2)
'       RIGHT (3)
'   Any other value is ignored
    case direction
        LEFT:             ' As long as the value passed is valid,
        RIGHT:            '  leave it alone, and use it directly in the writeReg line.
        OTHER: return

    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#CURS_DISP_SHIFT | direction, 0)

PUB DoubleHeight(mode)
' Set double-height font style mode
'   Valid values:
'      *0: Standard height font all 4 lines / double-height disabled
'       1: Bottom two lines form one double-height line (top 2 lines standard height, effectively 3 lines)
'       2: Middle two lines form one double-height line (top and bottom lines standard height, effectively 3 lines)
'       3: Top and bottom lines each form a double-height line (effectively 2 lines)
'       4: Top two lines form one double-height line (bottom 2 lines standard height, effectively 3 lines)
'   Any other value returns the current setting
'   NOTE: Takes effect immediately - will affect current screen contents
    case mode
        0:
            _dblht_mode := 0
            _dblht_en := 0
            writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#FUNCTION_SET_0 | core#DISP_LINES_2_4 | core#DBLHT_FONT_DIS, 0)
            return
        1: _dblht_mode := core#DBLHEIGHT_BOTTOM
        2: _dblht_mode := core#DBLHEIGHT_MIDDLE
        3: _dblht_mode := core#DBLHEIGHT_BOTH
        4: _dblht_mode := core#DBLHEIGHT_TOP
        OTHER:
            return _dblht_mode

    _dblht_en := core#DBLHT_FONT_EN

    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#DBLHEIGHT | _dblht_mode, 0)

PUB DisplayVisibility(mode)
' Set display visibility
'   Valid values:
'       OFF (0): Display off
'       NORMAL (1): Normal display
'       INVERT (2): Inverted display
'   Any other value returns the current setting
'   NOTE: Takes effect immediately. Does not affect display RAM contents
'   NOTE: Display may appear dimmer, overall, when inverted
    case mode
        OFF:
            _disp_en := 0
        NORMAL:
            _disp_en := core#DISP_ON
            _disp_invert := core#NORMAL_DISPLAY
        INVERT:
            _disp_en := core#DISP_ON
            _disp_invert := core#REVERSE_DISPLAY
        OTHER:
            result := ( (_disp_en >> 2) & 1 ) | ((_disp_invert & 1) << 1)
            return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_FUND, core#DISPLAY_ONOFF | _disp_en | _cursor_en | _blink_en, 0)
    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#FUNCTION_SET_1 | _cgram_blink | _disp_invert, 0)

PUB FontWidth(dots)
' Set Font width
'   Valid values: *5 or 6
'   Any other value returns the current setting
    case dots
        5: _fontwidth := core#FONTWIDTH_5
        6: _fontwidth := core#FONTWIDTH_6
        OTHER:
            return _fontwidth

    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#EXTENDED_FUNCSET | _fontwidth | _cursor_invert | _disp_lines_NW, 0)

PUB GetPos: addr | data_in
' Get current position in DDRAM
'   Returns: Display address of current cursor position
    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, $00, 0)
    i2c.start
    i2c.write (SLAVE_RD | _sa0_addr)
    addr := i2c.read (TRUE)
    i2c.stop

PUB GPIOState(state)
' Set state of GPIO pin
'   Valid values:
'       0: GPIO pin HiZ, input disabled (always read as low)
'       1: GPIO pin HiZ, input enabled
'      *2: GPIO pin output, low
'       3: GPIO pin output, high
    case state
        0: _gpio_state := core#GPIO_HIZ_INP_DIS
        1: _gpio_state := core#GPIO_HIZ_INP_ENA
        2: _gpio_state := core#GPIO_OUT_LOW
        3: _gpio_state := core#GPIO_OUT_HIGH
        OTHER:
            return _gpio_state

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#FUNCTION_SEL_C, _ext_vsl | _gpio_state)

PUB Home
' Returns cursor to home position (0, 0)
'   NOTE: Doesn't clear the display
    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#HOME_DISPLAY, 0)

PUB MirrorH(enable)
' Mirror display, horizontally
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value returns the current setting
    case ||enable
        0: _mirror_h := core#SEG99_0
        1: _mirror_h := core#SEG0_99
        OTHER:
            return _mirror_h

    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#ENTRY_MODE_SET | _mirror_h | _mirror_v, 0)

PUB MirrorV(enable)
' Mirror display, vertically
'   Valid values: TRUE (-1 or 1), FALSE (0)
'   Any other value returns the current setting
    case ||enable
        0: _mirror_v := core#COM0_31
        1: _mirror_v := core#COM31_0
        OTHER:
            return _mirror_v

    writeReg (TRANSTYPE_CMD, 1, CMDSET_EXTD, core#ENTRY_MODE_SET | _mirror_h | _mirror_v, 0)

PUB PinCfg(cfg)
' Change mapping between display data column address and segment driver.
'   Valid values:
'       0: Sequential SEG pin cfg
'       1: Alternative (odd/even) SEG pin cfg
'   NOTE: Only affects subsequent data input. Data already displayed/in DDRAM will be unchanged.
    case cfg
        0: _seg_pincfg := core#SEQ_SEGPINCFG
        1: _seg_pincfg := core#ALT_SEGPINCFG
        OTHER: return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_SEG_PINS, _seg_remap | _seg_pincfg)

PUB Phase1Period(clocks)
' Set length of phase 1 of segment waveform of the driver
' Valid values: 0..32 clocks
    case clocks
        2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32: _phs1_per := (clocks >> 1) - 1
        OTHER: return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_PHASE_LEN, _phs2_per | _phs1_per)

PUB Phase2Period(clocks)
' Set length of phase 2 of segment waveform of the driver
'   Valid values: 1..15 clocks (POR: 7)
    case clocks
        1..15: _phs2_per := (clocks << 4)
        OTHER: return

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_PHASE_LEN, _phs2_per | _phs1_per)

PUB Position(column, row) | offset
' Set current cursor position
    case column
        0..19:
            case row
                0..3: offset := ($20 * row) + column <# ($20 * row) + $13
                OTHER: return
        OTHER: return

    writeReg (TRANSTYPE_CMD, 0, CMDSET_FUND, core#SET_DDRAM_ADDR|offset, 0)

PUB Reset
' Send reset signal to display controller
    io.Output(_reset)
    io.Low(_reset)
    time.USleep(core#TRES)
    io.High(_reset)
    time.MSleep (1)

PUB SEGVoltageRef(ref)
' Select segment voltage reference
'   Valid values:
'      *INTERNAL (0): Internal VSL
'       EXTERNAL (1): External VSL
'   Any other value returns the current setting
    case ref
        INTERNAL:
            _ext_vsl := core#VSL_INTERNAL
        EXTERNAL:
            _ext_vsl := core#VSL_EXTERNAL
        OTHER:
            return _ext_vsl

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#FUNCTION_SEL_C, _ext_vsl | _gpio_state)

PUB StrDelay(stringptr, delay)
' Display zero-terminated string with inter-character delay, in ms
    repeat strsize(stringptr)
        Char(byte[stringptr++])
        time.MSleep (delay)

PUB StrDelay_Literal(stringptr, delay)
' Display zero-terminated string with inter-character delay, in ms
'   NOTE: Control characters will not be processed, but will be displayed
    repeat strsize(stringptr)
        Char_Literal(byte[stringptr++])
        time.MSleep (delay)

PUB Str_Literal(stringptr)
' Display zero-terminated string
'   NOTE: Control characters will not be processed, but will be displayed
    repeat strsize(stringptr)
        Char_Literal(byte[stringptr++])

PUB SupplyVoltage(V)
' Set supply voltage (enable/disable internal regulator)
'   Valid values:
'      *5: Enable internal regulator (use for 5V operation)
'       3, 3_3: Disable internal regulator (3.3V/low-voltage operation)
'   Any other value is ignored
    case V
        3, 3_3:
        5:
            V := core#INT_REG_ENABLE
        OTHER: return

    writeReg (TRANSTYPE_CMD, 2, CMDSET_EXTD, core#FUNCTION_SEL_A, V)

PUB TextDirection(direction)
' Change mapping between display data column address and segment driver.
'   Valid values:
'       0: Disable SEG left/right remap
'       1: Enable SEG left/right remap
'   NOTE: Only affects subsequent data input. Data already displayed/in DDRAM will be unchanged.
    case direction
        0: _seg_remap := core#SEG_LR_REMAP_DIS
        1: _seg_remap := core#SEG_LR_REMAP_EN
        OTHER:
            return _seg_remap

    writeReg (TRANSTYPE_CMD, 1, CMDSET_OLED, core#SET_SEG_PINS, _seg_remap | _seg_pincfg)

PRI wrdata(databyte) | cmd_packet
' Write bytes with the DATA control byte set
    cmd_packet.byte[0] := SLAVE_WR | _sa0_addr
    cmd_packet.byte[1] := core#CTRLBYTE_DATA
    cmd_packet.byte[2] := databyte

    i2c.start
    i2c.wr_block (@cmd_packet, 3)
    i2c.stop

PRI readReg(reg, bytes, dest) | cmd_packet

    case reg
        0:
            i2c.start
            i2c.write (SLAVE_RD | _sa0_addr)
            result := i2c.read (TRUE)
            i2c.stop
            return

    case bytes
        1:
'            writeReg (reg, 0, 0)
'            writeReg (trans_type, nr_bytes, cmd_set, cmd, val)
        OTHER:
            return

    i2c.start
    i2c.wr_block (@cmd_packet, 2)

    i2c.start
    i2c.write (SLAVE_RD)
    i2c.rd_block (dest, bytes, TRUE)
    i2c.stop

PRI writeReg(trans_type, nr_bytes, cmd_set, cmd, val) | cmd_packet[4]

    case trans_type
        TRANSTYPE_CMD:
            cmd_packet.word[0] := CMD_HDR | _sa0_addr

            case cmd_set
                CMDSET_FUND:
                    cmd_packet.byte[2] := cmd
                    nr_bytes := 3

                CMDSET_EXTD:
                    case nr_bytes
                        1:
                            cmd_packet.byte[2] := core#CMDSET_EXTENDED | _disp_lines_N | _dblht_en
                            cmd_packet.byte[3] := core#CTRLBYTE_CMD
                            cmd_packet.byte[4] := cmd
                            cmd_packet.byte[5] := core#CTRLBYTE_CMD
                            cmd_packet.byte[6] := core#CMDSET_FUNDAMENTAL | _disp_lines_N | _dblht_en
                            nr_bytes := 7

                        2:
                            cmd_packet.byte[2] := core#CMDSET_EXTENDED | _disp_lines_N | _dblht_en
                            cmd_packet.byte[3] := core#CTRLBYTE_CMD
                            cmd_packet.byte[4] := cmd
                            cmd_packet.byte[5] := core#CTRLBYTE_DATA
                            cmd_packet.byte[6] := val
                            cmd_packet.byte[7] := core#CTRLBYTE_CMD
                            cmd_packet.byte[8] := core#CMDSET_FUNDAMENTAL | _disp_lines_N | _dblht_en
                            nr_bytes := 9

                        OTHER:
                            return

                CMDSET_EXTD_IS:
                    case nr_bytes
                        1:
                            cmd_packet.byte[2] := core#CMDSET_EXTENDED | _disp_lines_N | _dblht_en | %1{IS = 1}
                            cmd_packet.byte[3] := core#CTRLBYTE_CMD
                            cmd_packet.byte[4] := cmd
                            cmd_packet.byte[5] := core#CTRLBYTE_CMD
                            cmd_packet.byte[6] := core#CMDSET_FUNDAMENTAL | _disp_lines_N | _dblht_en
                            nr_bytes := 7

                        2:
                            cmd_packet.byte[2] := core#CMDSET_EXTENDED | _disp_lines_N | _dblht_en
                            cmd_packet.byte[3] := core#CTRLBYTE_CMD
                            cmd_packet.byte[4] := cmd
                            cmd_packet.byte[5] := core#CTRLBYTE_DATA
                            cmd_packet.byte[6] := val
                            cmd_packet.byte[7] := core#CTRLBYTE_CMD
                            cmd_packet.byte[8] := core#CMDSET_FUNDAMENTAL | _disp_lines_N | _dblht_en
                            nr_bytes := 9
                        OTHER:
                            return

                CMDSET_OLED:
                    cmd_packet.byte[2] := core#CMDSET_EXTENDED | _disp_lines_N | _dblht_en
                    cmd_packet.byte[3] := core#CTRLBYTE_CMD
                    cmd_packet.byte[4] := core#OLED_CMDSET_ENA
                    cmd_packet.byte[5] := core#CTRLBYTE_CMD
                    cmd_packet.byte[6] := cmd
                    cmd_packet.byte[7] := core#CTRLBYTE_CMD ' Yes, command - not data
                    cmd_packet.byte[8] := val
                    cmd_packet.byte[9] := core#CTRLBYTE_CMD
                    cmd_packet.byte[10] := core#OLED_CMDSET_DIS
                    cmd_packet.byte[11] := core#CTRLBYTE_CMD
                    cmd_packet.byte[12] := core#CMDSET_FUNDAMENTAL | _disp_lines_N | _dblht_en
                    nr_bytes := 13

        TRANSTYPE_DATA:
            cmd_packet.byte[0] := SLAVE_WR | _sa0_addr
            cmd_packet.byte[1] := core#CTRLBYTE_DATA
            cmd_packet.byte[2] := val
            nr_bytes := 3

    i2c.start
    i2c.wr_block (@cmd_packet, nr_bytes)
    i2c.stop

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
