{
    --------------------------------------------
    Filename: NRF24L01-TXDemo.spin
    Author: Jesse Burt
    Description: nRF24L01+ Transmit demo (no ShockBurst/Auto Acknowledgement)
    Copyright (c) 2020
    Started Nov 23, 2019
    Updated Feb 3, 2020
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

    CE_PIN          = 5
    CSN_PIN         = 4
    SCK_PIN         = 1
    MOSI_PIN        = 2
    MISO_PIN        = 0

    CLEAR           = 1
    CHANNEL         = 2

OBJ

    ser         : "com.serial.terminal.ansi"
    cfg         : "core.con.boardcfg.flip"
    io          : "io"
    time        : "time"
    int         : "string.integer"
    nrf24       : "wireless.transceiver.nrf24l01.spi"

VAR

    long _ser_cog, _nrf24_cog
    long _fifo[8]
    byte _payloadlen

PUB Main

    Setup

    ser.str(string("Press any key to begin transmitting", ser#CR, ser#LF))
    ser.CharIn

    Transmit

PUB Transmit | addr[2], count, i, tmp

    _payloadlen := 8                                        ' Payload length. MUST match the RX side for
    nrf24.PayloadLen (_payloadlen, 0)                       '   successful transmission

    nrf24.TXMode                                            ' Set to Transmit mode
    nrf24.PowerUp (TRUE)
    nrf24.TXPower (-18)                                     ' Set transmit power: -18, -12, -6, 0 (dBm)
    nrf24.Channel (2)                                       ' Set transmit channel. MUST match the RX side for
                                                            '   successful transmission

    nrf24.AutoAckEnabledPipes(%000000)                      ' Disable Enh. ShockBurst/Auto Acknowledgement
    nrf24.PayloadSent(CLEAR)                                ' Clear Payload Sent interrupt
    nrf24.MaxRetransReached(CLEAR)                          ' Clear Max. Retransmit Reached interrupt

    addr := string($E7, $E7, $E7, $E7, $E7)                 ' Set address to transmit to
    nrf24.TXAddr (addr, nrf24#WRITE)                        '   MUST match one pipe on the RX side

    ser.Clear
    ser.Position(0, 0)
    ser.str(string("Transmit mode: Channel "))              ' Show the currently set channel
    ser.dec(nrf24.Channel(-2))
    ser.newline
    ser.str(string("Transmitting to node $"))

    nrf24.TXAddr (@addr, nrf24#READ)                        ' Read back transmit-to address
    repeat i from 4 to 0                                    ' ...
        ser.Hex(addr.byte[i], 2)                            '   and show it

    _fifo.byte[0] := "T"                                    ' Start of payload
    _fifo.byte[1] := "E"                                    '   (first four bytes of _payloadlen)
    _fifo.byte[2] := "S"
    _fifo.byte[3] := "T"

    count := 0
    repeat
        tmp := int.DecZeroed(count, 4)                      ' Tack a counter onto the end of the payload
        bytemove(@_fifo.byte[4], tmp, 4)                    '   (last four bytes of _payloadlen)
        ser.position(0, 8)
        ser.str(string("Sending"))

        nrf24.TXPayload (_payloadlen, @_fifo, FALSE)        ' Transmit payload. deferred: FALSE
        count++                                             '   (i.e., immediately)

        ser.Hexdump(@_fifo, 0, _payloadlen, _payloadlen, 0, 9)

        nrf24.PayloadSent(CLEAR)                            ' Clear interrupt
        nrf24.FlushTX                                       '   and flush FIFO. Ready for the next packet
        time.MSleep(1000)                                   ' Don't abuse the airwaves - wait between packets

PUB Setup

    repeat until _ser_cog := ser.StartRXTX (SER_RX, SER_TX, 0, SER_BAUD)
    time.MSleep(30)
    ser.Clear
    ser.str(string("Serial terminal started", ser#CR, ser#LF))
    if _nrf24_cog := nrf24.Startx (CE_PIN, CSN_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
        ser.str(string("NRF24L01+ driver started", ser#CR, ser#LF))
    else
        ser.str(string("NRF24L01+ driver failed to start - halting", ser#CR, ser#LF))
        FlashLED (LED, 500)

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
