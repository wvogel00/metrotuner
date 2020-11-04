CON
'' Parral Labs Dev Board
'' Clock Settings
  _CLKMODE      = XTAL1 + PLL16X
  _XINFREQ      = 5_000_000

'' Pin definitions
  BUTTON1       = 14  '' Onboard push-button switches
  BUTTON2       = 15

  LED1          = 16  '' Onboard blue and
  LED2          = 17  ''  green LEDs

  SCL           = 28  '' I2C
  SDA           = 29

PUB Null
'' This is not a top-level object
