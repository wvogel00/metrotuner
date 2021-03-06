i{
    --------------------------------------------
    Filename: CC1101-TXDemo.spin
    Author: Jesse Burt
    Description: Simple transmit demo of the cc1101 driver
    Copyright (c) 2020
    Started Nov 23, 2019
    Updated Apr 14, 2020
    See end of file for terms of use.
    --------------------------------------------
}
CON

    _clkmode        = cfg#_clkmode
    _xinfreq        = cfg#_xinfreq

    LED             = cfg#LED1
    SER_RX          = 31
    SER_TX          = 30
    SER_BAUD        = 115_200


    CS_PIN          = 0                             ' Change to your module's connections
    SCK_PIN         = 3
    MOSI_PIN        = 2
    MISO_PIN        = 1

    NODE_ADDRESS    = $02

OBJ

    ser         : "com.serial.terminal.ansi"
    cfg         : "core.con.boardcfg.flip"
    io          : "io"
    time        : "time"
    int         : "string.integer"
    cc1101      : "wireless.transceiver.cc1101.spi"

VAR

    long _ser_cog, _cc1101_cog
    long _fifo[16]
    byte _pktlen

PUB Main | choice

    Setup

    cc1101.GPIO0 (cc1101#IO_HI_Z)                   ' Set CC1101 GPIO0 to Hi-Z mode
    cc1101.AutoCal(cc1101#IDLE_RXTX)                ' Perform auto-calibration when transitioning from Idle to TX
    cc1101.Idle
    
    ser.str(string("Waiting for radio idle status..."))
    repeat until cc1101.State == 1
    ser.str(string("done", ser#CR, ser#LF))

    cc1101.CarrierFreq(433_900_000)                 ' Set carrier frequency

    ser.str(string("Waiting for PLL lock..."))
    repeat until cc1101.PLLLocked == TRUE           ' Don't proceed until PLL is locked
    ser.str(string("done", ser#CR, ser#LF))

    cc1101.TXPowerIndex(0)
    cc1101.TXPower(0)                               ' -30, -20, -15, -10, 0, 5, 7, 10 dBm
    ser.str(string("TXPower: "))
    ser.dec(cc1101.TXPower(-255))
    ser.str(string("dBm", ser#CR, ser#LF))

    ser.str(string("Press any key to begin transmitting", ser#CR, ser#LF))
    ser.CharIn

    Transmit

    FlashLED(LED, 100)     ' Signal execution finished

PUB Transmit | count, tmp, to_node

    _pktlen := 10
    cc1101.NodeAddress(NODE_ADDRESS)                ' Set this node's address
    cc1101.PayloadLenCfg (cc1101#PKTLEN_FIXED)      ' Fixed payload length
    cc1101.PayloadLen (_pktlen)                     ' Set payload length to _pktlen
    cc1101.CRCCheckEnabled (TRUE)                   ' Enable CRC checks on received payloads
    cc1101.SyncMode (cc1101#SYNCMODE_3032_CS)       ' Accept payload as valid only if:
    cc1101.AppendStatus (FALSE)                     '   At least 30 of 32 syncword bits match
                                                    '   Carrier sense is above set threshold
    to_node := $01

    ser.Clear
    ser.Position(0, 0)
    ser.str(string("Transmit mode - "))
    ser.Dec(cc1101.CarrierFreq(-2))
    ser.str(string("Hz", ser#CR, ser#LF))
    ser.str(string("Transmitting to node $"))
    ser.Hex(to_node, 2)

    _fifo.byte[0] := to_node                        ' Address of node we're sending to
    _fifo.byte[1] := NODE_ADDRESS                   ' This node's address
    _fifo.byte[2] := "T"                            ' Start of payload
    _fifo.byte[3] := "E"
    _fifo.byte[4] := "S"
    _fifo.byte[5] := "T"

    count := 0
    cc1101.AfterTX (cc1101#TXOFF_IDLE)              ' What state to change the radio to after transmission
    repeat
        tmp := int.DecZeroed(count++, 4)            ' Tack a counter onto the
        bytemove(@_fifo.byte[6], tmp, 4)            '   end of the payload
        ser.position(0, 10)
        ser.str(string("Sending "))
        ser.str(@_fifo)
        cc1101.Idle
        cc1101.FlushTX
        cc1101.FSTX
        cc1101.TXMode
        cc1101.TXPayload (_pktlen, @_fifo)
        time.Sleep (5)                              ' Try not to abuse the airwaves - wait between transmissions

PUB Setup

    repeat until _ser_cog := ser.StartRXTX (SER_RX, SER_TX, 0, SER_BAUD)
    time.MSleep(100)
    ser.Clear
    ser.str(string("Serial terminal started", ser#CR, ser#LF))
    if _cc1101_cog := cc1101.Start (CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
        ser.str(string("CC1101 driver started", ser#CR, ser#LF))
    else
        ser.str(string("CC1101 driver failed to start - halting", ser#CR, ser#LF))
        FlashLED (LED, 500)

DAT
' Radio states
MARC_STATE  byte    "SLEEP           ", 0 {0}
            byte    "IDLE            ", 0 {1}
            byte    "XOFF            ", 0 {2}
            byte    "VCOON_MC        ", 0 {3}
            byte    "REGON_MC        ", 0 {4}
            byte    "MANCAL          ", 0 {5}
            byte    "VCOON           ", 0 {6}
            byte    "REGON           ", 0 {7}
            byte    "STARTCAL        ", 0 {8}
            byte    "BWBOOST         ", 0 {9}
            byte    "FS_LOCK         ", 0 {10}
            byte    "IFADCON         ", 0 {11}
            byte    "ENDCAL          ", 0 {12}
            byte    "RX              ", 0 {13}
            byte    "RX_END          ", 0 {14}
            byte    "RX_RST          ", 0 {15}
            byte    "TXRX_SWITCH     ", 0 {16}
            byte    "RXFIFO_OVERFLOW ", 0 {17}
            byte    "FSTXON          ", 0 {18}
            byte    "TX              ", 0 {19}
            byte    "TX_END          ", 0 {20}
            byte    "RXRX_SWITCH     ", 0 {21}

#include "lib.utility.spin"

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

