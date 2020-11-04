CON
' FLiP Propeller Module
' Parallax #32123
' Clock Settings
    _CLKMODE        = RCFAST
'    _CLKMODE        = XTAL1 + PLL16X
'    _XINFREQ        = 5_000_000

' Pin definitions
    LED_L1          = 0
    LED_L2          = 1
    LED_L3          = 2
    LED_L4          = 3
    LED_R1          = 24
    LED_R2          = 25
    LED_R3          = 26
    LED_R4          = 27

    BUZZER          = 12
    MICIN           = 13

    ROT_A           = 14
    ROT_B           = 15

    SCL             = 16                                    ' I2C
    SDA             = 17

    SER_RX_DEF      = 31                                    ' Serial
    SER_TX_DEF      = 30
    SER_BAUD_DEF    = 115_200

    METRONOME_MODE  = %0100
    TUNER_MODE      = %0101

    NONE            = %1100
    CW              = %1101
    CCW             = %1110
    PUSH            = %1111

PUB Null
' This is not a top-level object
