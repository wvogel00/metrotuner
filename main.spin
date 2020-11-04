CON
    _clkmode = RCFAST
    
    MyLED = 0       ' pin connected to a LED via a resistor
    SCL = 14        ' OLED SCL
    SDA = 15        ''OLED SDA

VAR
    long addr       'device address
    long mode       'active flag
    long Stack[9]
    
' external object file
OBJ
    Serial : "Parallax Serial Terminal"
    i2c     : "i2c"
    'Oled : "SSD1306"
    
PUB Main
    Serial.Start(115200)
    cognew(OLED_Test, @Stack)
    dira[MyLed] := 1                 'set direction
    repeat                           'forever
        outa[MyLed] := 1               'set it high
        waitcnt(clkfreq + cnt)         'one second
        outa[MyLed] := 0               'low
        waitcnt(clkfreq/2 + cnt)       'one-half second
        Serial.Str (String("hello",13))

PUB OLED_Test
    'Oled.init(SCL, SDA, false)