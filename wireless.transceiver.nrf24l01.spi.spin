{
    --------------------------------------------
    Filename: wireless.transceiver.nrf24l01.spi.spin
    Author: Jesse Burt
    Description: Driver for Nordic Semi. nRF24L01+
    Copyright (c) 2020
    Started Jan 6, 2019
    Updated Feb 3, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    ROLE_TX     = 0
    ROLE_RX     = 1

' RXAddr and TXAddr constants
    READ        = 0
    WRITE       = 1

' Can be used as a parameter for PayloadReady, PayloadSent, MaxRetransReached to clear interrupts
    CLEAR       = 1

VAR

    byte    _CE, _CSN, _SCK, _MOSI, _MISO
    word    _status

OBJ

    spi     : "com.spi.4w"
    core    : "core.con.nrf24l01"
    time    : "time"
    io      : "io"

PUB Null
''This is not a top-level object

PUB Startx(CE_PIN, CSN_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): okay | tmp[2], i

    if lookdown(CE_PIN: 0..31) and lookdown(CSN_PIN: 0..31) and lookdown(SCK_PIN: 0..31) and lookdown(MOSI_PIN: 0..31) and lookdown(MISO_PIN: 0..31)
        if okay := spi.start (core#CLK_DELAY, core#CPOL)
            _CE := CE_PIN
            _CSN := CSN_PIN
            _SCK := SCK_PIN
            _MOSI := MOSI_PIN
            _MISO := MISO_PIN
            time.USleep(core#TPOR)
            time.USleep(core#TPD2STBY)

            io.Low(_CE)
            io.Output(_CE)
            io.High(_CSN)
            io.Output(_CSN)

            Defaults                                            ' The nRF24L01+ has no RESET pin or function,
                                                                '   so set defaults
            RXAddr(@tmp, 0, READ)                               ' There's also no 'ID' register, so read in the
            repeat i from 0 to 4                                '   address for pipe #0.
                if tmp.byte[i] <> $E7                           ' If bytes read back are different from the default,
                    return FALSE                                '   there's either a connection problem, or
            return okay                                         '   no nRF24L01+ connected.
                                                                ' NOTE: This is only guaranteed to work after
                                                                '   setting defaults.
    return FALSE                                                ' If we got here, something went wrong

PUB Stop

    io.High(_CSN)
    io.Low(_CE)
    Sleep
    spi.Stop

PUB Defaults | tmp[2]
' The nRF24L01+ has no RESET pin or function to restore the chip to a known initial operating state,
'   so use this method to establish default settings, per the datasheet
    CRCCheckEnabled(TRUE)
    CRCLength(1)
    Sleep
    TXMode
    AutoAckEnabledPipes(%000000)
    PipesEnabled(%000011)
    AddressWidth(5)
    AutoRetransmitDelay(250)
    AutoRetransmitCount(3)
    Channel(2)
    TESTCW(FALSE)
    PLL_Lock(FALSE)
    DataRate(2000)
    TXPower(0)
    PayloadReady(CLEAR)
    PayloadSent(CLEAR)
    MaxRetransReached(CLEAR)
    tmp := string($E7, $E7, $E7, $E7, $E7)
    RXAddr(tmp, 0, WRITE)
    tmp := string($C2, $C2, $C2, $C2, $C2)
    RXAddr(tmp, 1, WRITE)
    tmp := $C3
    RXAddr(@tmp, 2, WRITE)
    tmp := $C4
    RXAddr(@tmp, 3, WRITE)
    tmp := $C5
    RXAddr(@tmp, 4, WRITE)
    tmp := $C6
    RXAddr(@tmp, 5, WRITE)
    tmp := string($E7, $E7, $E7, $E7, $E7)
    TXAddr(tmp, WRITE)
    repeat tmp from 0 to 5
        PayloadLen(0, tmp)
    DynamicPayload(%000000)
    DynPayloadEnabled(FALSE)
    EnableACK(FALSE)

PUB CE(state)
' Set state of nRF24L01+ Chip Enable pin
'   Valid values:
'       TX mode:
'           0: Enter Idle mode
'           1: Initiate transmission of queued data
'       RX mode:
'           0: Enter Idle mode
'           1: Active receive mode
    io.Set(_CE, state)
    time.USleep (core#THCE)

PUB AddressWidth(bytes) | tmp
' Set width, in bytes, of RX/TX address field
'   Valid values: 3, 4, 5
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_SETUP_AW, 1, @tmp)
    case bytes
        3, 4, 5:
            bytes := bytes-2
        OTHER:
            result := (tmp & core#BITS_AW) + 2
            return

    tmp &= core#MASK_AW
    tmp := (tmp | bytes) & core#NRF24_SETUP_AW_MASK
    writeReg (core#NRF24_SETUP_AW, 1, @tmp)

PUB AfterRX (next_state)
' Define state to transition to after packet rcvd
'   0: Remain in active RX state, ready to receive packets
'   Any other value: Change to RX state, but immediately enter a lower-power Idle/Standby state
    RXTX(ROLE_RX)
    if next_state
        Idle
    else
        CE(1)

PUB AutoAckEnabledPipes(pipe_mask) | tmp
' Enable the Auto Acknowledgement function (aka Enhanced ShockBurst - (TM) NORDIC Semi.)
'   per set data pipe mask:
'   Data Pipe:     5    0   5    0
'                  |....|   |....|
'   Valid values: %000000..%111111
'   0 disables AA for the given pipe, 1 enables
'   Example:
'       AutoAckEnabledPipes(%001010)
'           would enable AA for data pipes 1 and 3, and disable for all others
    readReg (core#NRF24_EN_AA, 1, @tmp)
    case pipe_mask
        %000000..%111111:
        OTHER:
            result := tmp & core#NRF24_EN_AA_MASK
            return

    writeReg (core#NRF24_EN_AA, 1, @pipe_mask)

PUB AutoRetransmitDelay(delay_us) | tmp
' Setup of automatic retransmission - Auto Retransmit Delay, in microseconds
' Delay defined from end of transmission to start of next transmission
'   Valid values: 250..4000
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_SETUP_RETR, 1, @tmp)
    case delay_us := lookdown(delay_us: 250, 500, 750, 1000, 1250, 1500, 1750, 2000, 2250, 2500, 2750, 3000, 3250, 3500, 3750, 4000)
        1..16:
            delay_us := (delay_us - 1) << core#FLD_ARD
        OTHER:
            tmp := ((tmp >> core#FLD_ARD) & core#BITS_ARD) + 1
            result := lookup(tmp: 250, 500, 750, 1000, 1250, 1500, 1750, 2000, 2250, 2500, 2750, 3000, 3250, 3500, 3750, 4000)
            return
    tmp &= core#MASK_ARD
    tmp := (tmp | delay_us) & core#NRF24_SETUP_RETR_MASK
    writeReg (core#NRF24_SETUP_RETR, 1, @tmp)

PUB AutoRetransmitCount(tries) | tmp
' Setup of automatic retransmission - Auto Retransmit Count
' Defines number of attempts to re-transmit on fail of Auto-Acknowledge
'   Valid values: 0..15 (0 disables re-transmit)
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_SETUP_RETR, 1, @tmp)
    case tries
        0..15:
        OTHER:
            result := (tmp & core#BITS_ARC)
            return
    tmp &= core#MASK_ARC
    tmp := (tmp | tries) & core#NRF24_SETUP_RETR_MASK
    writeReg (core#NRF24_SETUP_RETR, 1, @tmp)

PUB CarrierFreq(MHz)
' Set carrier frequency, in MHz
'   Valid values: 2400..2527
'   Any other value polls the chip and returns the current setting
    case MHz
        2400..2527:
            Channel(MHz-2400)
        OTHER:
            return 2400 + Channel(-2)

PUB Channel(number)
' Set RF channel
'   Valid values: 0..127
'   Any other value polls the chip and returns the current setting
    case number
        0..127:
            writeReg (core#NRF24_RF_CH, 1, @number)
        OTHER:
            readReg (core#NRF24_RF_CH, 1, @result)

PUB CRCCheckEnabled(enabled) | tmp
' Enable CRC
' NOTE: Forced on if any data pipe has AutoAck enabled
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_CONFIG, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_EN_CRC
        OTHER:
            result := ((tmp >> core#FLD_EN_CRC) & %1) * TRUE
            return

    tmp &= core#MASK_EN_CRC
    tmp := (tmp | enabled) & core#NRF24_CONFIG_MASK
    writeReg (core#NRF24_CONFIG, 1, @tmp)

PUB CRCLength(bytes) | tmp
' Choose CRC Encoding scheme, in bytes
'   Valid values: 1, 2
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_CONFIG, 1, @tmp)
    case bytes
        1, 2:
            bytes := (bytes-1) << core#FLD_CRCO
        OTHER:
            result := ((tmp >> core#FLD_CRCO) & %1) + 1
            return

    tmp &= core#MASK_CRCO
    tmp := (tmp | bytes) & core#NRF24_CONFIG_MASK
    writeReg (core#NRF24_CONFIG, 1, @tmp)

PUB DataRate(kbps) | tmp
' Set RF data rate in kbps
'   Valid values: 250, 1000, 2000
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_RF_SETUP, 1, @tmp)
    case kbps
        1000:
            tmp &= core#MASK_RF_DR_HIGH
            tmp &= core#MASK_RF_DR_LOW
        2000:
            tmp |= (1 << core#FLD_RF_DR_HIGH)
            tmp &= core#MASK_RF_DR_LOW
        250:
            tmp &= core#MASK_RF_DR_HIGH
            tmp |= (1 << core#FLD_RF_DR_LOW)
        OTHER:
            tmp := (tmp >> core#FLD_RF_DR_HIGH) & %101          'Only care about the RF_DR_x bits
            result := lookupz(tmp: 1000, 2000, 0, 0, 250)
            return

    writeReg (core#NRF24_RF_SETUP, 1, @tmp)

PUB DynamicACK(enabled) | tmp
' Enable selective auto-acknowledge feature
' When enabled, the receive will not auto-acknowledge packets sent to it.
' XXX expand
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_FEATURE, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_EN_DYN_ACK
        OTHER:
            result := ((tmp >> core#FLD_EN_DYN_ACK) & core#BITS_EN_DYN_ACK) * TRUE
            return

    tmp &= core#MASK_EN_DYN_ACK
    tmp := (tmp | enabled) & core#NRF24_FEATURE_MASK
    writeReg (core#NRF24_FEATURE, 1, @tmp)

PUB DynamicPayload(mask) | tmp
' Control which data pipes (0 through 5) have dynamic payload length enabled, using a 6-bit mask
'   Data pipe:     5    0   5     0
'                  |....|   |.....|
'   Valid values: %000000..%1111111
    readReg (core#NRF24_DYNPD, 1, @tmp)
    case mask
        %000000..%111111:
'           Don't actually do anything if the values are in this range,
'            since they're already actually valid. Commented line below
'            shows what *would* be done:
'            mask := (mask << core#FLD_ERX_P0)
        OTHER:
            result := tmp & core#NRF24_DYNPD_MASK
            return

    tmp &= core#MASK_DPL
    tmp := (tmp | mask) & core#NRF24_DYNPD_MASK
    writeReg (core#NRF24_DYNPD, 1, @tmp)

PUB DynPayloadEnabled(enabled) | tmp
' Enable Dynamic Payload Length
' NOTE: Must be enabled to use the DynamicPayload method.
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_FEATURE, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_EN_DPL
        OTHER:
            result := ((tmp >> core#FLD_EN_DPL) & core#BITS_EN_DPL) * TRUE
            return

    tmp &= core#MASK_EN_DPL
    tmp := (tmp | enabled) & core#NRF24_FEATURE_MASK
    writeReg (core#NRF24_FEATURE, 1, @tmp)

PUB EnableACK(enabled) | tmp
' Enable payload with ACK
' XXX Add timing notes/code from datasheet, p.63, note d
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_FEATURE, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_EN_ACK_PAY
        OTHER:
            result := ((tmp >> core#FLD_EN_ACK_PAY) & core#BITS_EN_ACK_PAY) * TRUE
            return

    tmp &= core#MASK_EN_ACK_PAY
    tmp := (tmp | enabled) & core#NRF24_FEATURE_MASK
    writeReg (core#NRF24_FEATURE, 1, @tmp)

PUB FlushRX

    writeReg (core#NRF24_FLUSH_RX, 0, 0)

PUB FlushTX

    writeReg (core#NRF24_FLUSH_TX, 0, 0)

PUB Idle

    CE(0)

PUB IntMask(mask) | tmp
' Control which events will trigger an interrupt on the IRQ pin, using a 3-bit mask
'           Bits:  210   210
'                  |||   |||
'   Valid values: %000..%111
'       Bit:    Interrupt will be asserted on IRQ pin if:
'       2       new data is ready in RX FIFO
'       1       data is transmitted
'       0       TX retransmits reach maximum
'   Set a bit to 0 to disable the specific interrupt, 1 to enable
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_CONFIG, 1, @tmp)
    case mask
        %000..%111:
            mask := !(mask << core#FLD_MASK_MAX_RT) 'Invert because the chip's internal logic is reversed, i.e.,
        OTHER:                                      ' 1 disables the interrupt, 0 enables an active-low interrupt
            result := !(tmp >> core#FLD_MASK_MAX_RT) & core#BITS_INTS
            return

    tmp &= core#MASK_INTS
    tmp := (tmp | mask) & core#NRF24_CONFIG_MASK
    writeReg (core#NRF24_CONFIG, 1, @tmp)

PUB LostPackets
' Count lost packets
'   Returns: Number of lost packets since last channel/carrier freq set
'   Max value is 15
'   NOTE: To reset, re-set the Channel or CarrierFreq
    readReg (core#NRF24_OBSERVE_TX, 1, @result)
    result := (result >> core#FLD_PLOS_CNT) & core#BITS_PLOS_CNT

PUB MaxRetransReached(clear_intr) | tmp
' Query or clear Maximum number of TX retransmits interrupt
' NOTE: If this flag is set, it must be cleared to enable further communication.
'   Valid values: TRUE (-1 or 1): Clear interrupt flag
'   Any other value returns TRUE when max number of retransmits reached, FALSE otherwise
    readReg (core#NRF24_STATUS, 1, @tmp)
    case ||clear_intr
        1:
            clear_intr := %1 << core#FLD_MAX_RT
        OTHER:
            result := ((tmp >> core#FLD_MAX_RT) & core#BITS_MAX_RT) * TRUE
            return

    tmp &= core#MASK_MAX_RT
    tmp := (tmp | clear_intr) & core#NRF24_STATUS_MASK
    writeReg (core#NRF24_STATUS, 1, @tmp)

PUB NodeAddress(addr_ptr)
' Set node address
'   NOTE: This sets the address for Receive pipe 0 as well as the Transmit address
    RXAddr(addr_ptr, 0, WRITE)
    TXAddr(addr_ptr, WRITE)

PUB PacketsRetransmitted
' Count retransmitted packets
'   Returns: Number of packets retransmitted since the start of transmission of a new packet
    readReg (core#NRF24_OBSERVE_TX, 1, @result)
    result &= core#BITS_ARC_CNT

PUB PayloadLen(width, pipe_nr) | tmp
' Set length of static payload, in bytes
'   Returns number of bytes in RX payload in data pipe, or 0 if pipe unused
'   Valid values:
'       pipe: 0..5 (default 0)
'       width: 0..32
'   Any other value for pipe is ignored
'   Any other value for width polls the chip and returns the current setting
'   NOTE: Setting a width of 0 effectively disables the pipe
    tmp := 0
    case pipe_nr
        0..5:
            readReg (core#NRF24_RX_PW_P0 + pipe_nr, 1, @tmp)
            case width
                0..32:
                    writeReg (core#NRF24_RX_PW_P0 + pipe_nr, 1, @width)
                    return width
                OTHER:
                    result := tmp & core#BITS_RX_PW_P0
                    return result

        OTHER:
            return FALSE

PUB PayloadReady(clear_intr) | tmp
' Query or clear Data Ready RX FIFO interrupt
'   Valid values: TRUE (-1 or 1): Clear interrupt flag
'   Any other value queries the chip and returns TRUE if new data in FIFO, FALSE otherwise
    readReg (core#NRF24_STATUS, 1, @tmp)
    case ||clear_intr
        1:
            clear_intr := ||clear_intr << core#FLD_RX_DR
        OTHER:
            result := ((tmp >> core#FLD_RX_DR) & core#BITS_RX_DR) * TRUE
            return

    tmp &= core#MASK_RX_DR
    tmp := (tmp | clear_intr) & core#NRF24_STATUS_MASK
    writeReg (core#NRF24_STATUS, 1, @tmp)

PUB PayloadSent(clear_intr) | tmp
' Query or clear Data Sent TX FIFO interrupt
'   Valid values: TRUE (-1 or 1): Clear interrupt flag
'   Any other value polls the chip and returns TRUE if packet transmitted, FALSE otherwise
    readReg (core#NRF24_STATUS, 1, @tmp)
    case ||clear_intr
        1:
            clear_intr := ||clear_intr << core#FLD_TX_DS
        OTHER:
            result := ((tmp >> core#FLD_TX_DS) & core#BITS_TX_DS) * TRUE
            return

    tmp &= core#MASK_TX_DS
    tmp := (tmp | clear_intr) & core#NRF24_STATUS_MASK
    writeReg (core#NRF24_STATUS, 1, @tmp)

PUB PipesEnabled(mask) | tmp
' Control which data pipes (0 through 5) are enabled, using a 6-bit mask
'   Data pipe:     5    0   5    0
'                  |....|   |....|
'   Valid values: %000000..%111111
    case mask
        %000000..%111111:
'           Don't actually do anything if the values are in this range,
'            since they're already actually valid. Commented line below
'            shows what *would* be done:
'            mask := (mask << core#FLD_ERX_P0)
        OTHER:
            result := tmp & core#NRF24_EN_RXADDR_MASK
            return

    tmp &= core#MASK_EN_RXADDR
    tmp := (tmp | mask) & core#NRF24_EN_RXADDR_MASK
    writeReg (core#NRF24_EN_RXADDR, 1, @tmp)

PUB PLL_Lock(enabled) | tmp
' Force PLL Lock signal (intended for testing only)
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_RF_SETUP, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_PLL_LOCK
        OTHER:
            result := ((tmp >> core#FLD_PLL_LOCK) & %1) * TRUE
            return

    tmp &= core#MASK_PLL_LOCK
    tmp := (tmp | enabled) & core#NRF24_RF_SETUP_MASK
    writeReg (core#NRF24_RF_SETUP, 1, @tmp)

PUB PowerUp(enabled) | tmp
' Power on or off
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_CONFIG, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_PWR_UP
        OTHER:
            result := ((tmp >> core#FLD_PWR_UP) & %1) * TRUE
            return

    tmp &= core#MASK_PWR_UP
    tmp := (tmp | enabled) & core#NRF24_CONFIG_MASK
    writeReg (core#NRF24_CONFIG, 1, @tmp)

PUB RPD
' Received Power Detector
'   Returns:
'   FALSE/0: No Carrier
'   TRUE/-1: Carrier Detected
    result := $00
    readReg (core#NRF24_RPD, 1, @result)
    result *= TRUE

PUB RSSI
' RSSI (emulated)
'   Returns:
'       -64: Carrier detected
'       -255 No carrier
    case RPD
        TRUE:
            return -64
        FALSE:
            return -255

PUB RXAddr(buff_addr, pipe, rw) | tmp[2]
' Set receive address of pipe number 'pipe' from buffer at address buff_addr
'   Valid values:
'       buff_addr:
'           Address of buffer containing nRF24L01+ address to transmit to
'           For pipes 0 and 1, must be a buffer at least 5 bytes long
'           For pipes 2..5, must be a buffer at least 1 byte long
'       pipe: 0..5
'           Any other value is ignored
'       rw:
'           0: Read current address
'           1: Write new address
'           Any other value reads current address
    bytefill(@tmp, $00, 8)
    case pipe
        0, 1:
            readReg (core#NRF24_RX_ADDR_P0 + pipe, 5, @tmp)
                case rw
                    1:
                        writeReg (core#NRF24_RX_ADDR_P0 + pipe, 5, buff_addr)
                    OTHER:
                        bytemove(buff_addr, @tmp, 5)
                        return
        2..5:                                                                   ' Pipes 2..5 are limited to
            readReg (core#NRF24_RX_ADDR_P0 + pipe, 1, @tmp)                     '  1 unique address byte
                case rw                                                         '  (hardware limitation)
                    1:
                        writeReg (core#NRF24_RX_ADDR_P0 + pipe, 1, buff_addr)
                    OTHER:
                        bytemove(buff_addr, @tmp, 1)
                        return
        OTHER:                                                                  ' Invalid pipe
            return

PUB RXFIFOEmpty
' Queries the FIFO_STATUS register for RX FIFO empty flag
'   Returns TRUE if empty, FALSE if there's data in RX FIFO
    readReg (core#NRF24_FIFO_STATUS, 1, @result)
    return (result & %1) * TRUE

PUB RXFIFOFull
' Queries the FIFO_STATUS register for RX FIFO full flag
'   Returns TRUE if full, FALSE if there're available locations in the RX FIFO
    readReg (core#NRF24_FIFO_STATUS, 1, @result)
    result >>= core#FLD_RXFIFO_FULL
    result &= %1

PUB RXMode
' Change chip state to RX (receive)
    RXTX(ROLE_RX)
    CE(1)

PUB RXPayload(nr_bytes, buff_addr) | tmp
' Receive payload stored in FIFO
'   Valid values:
'       nr_bytes: 1..32 (Any other value is ignored)
'   Any other value is ignored
    case nr_bytes
        1..32:
            readReg (core#NRF24_R_RX_PAYLOAD, nr_bytes, buff_addr)
        OTHER:
            return FALSE

PUB RXPipePending
' Returns pipe number of pending data available in FIFO
'   Returns: Pipe number 0..5, or 7 if FIFO is empty
    result := (Status >> core#FLD_RX_P_NO) & core#BITS_RX_P_NO

PUB RXTX(role) | tmp
' Set to Primary RX or TX
'   Valid values: 0: TX, 1: RX
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_CONFIG, 1, @tmp)
    case role
        0, 1:
            role := role << core#FLD_PRIM_RX
        OTHER:
            result := ((tmp >> core#FLD_PRIM_RX) & %1)
            return

    tmp &= core#MASK_PRIM_RX
    tmp := (tmp | role) & core#NRF24_CONFIG_MASK
    writeReg (core#NRF24_CONFIG, 1, @tmp)

PUB Sleep
' Power down chip
    PowerUp(FALSE)

PUB TESTCW(enabled) | tmp
' Enable continuous carrier transmit (intended for testing only)
'   Valid values: FALSE: Disable, TRUE (-1 or 1): Enable.
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_RF_SETUP, 1, @tmp)
    case ||enabled
        0, 1:
            enabled := ||enabled << core#FLD_CONT_WAVE
        OTHER:
            result := ((tmp >> core#FLD_CONT_WAVE) & %1) * TRUE
            return

    tmp &= core#MASK_CONT_WAVE
    tmp := (tmp | enabled) & core#NRF24_RF_SETUP_MASK
    writeReg (core#NRF24_RF_SETUP, 1, @tmp)

PUB TXAddr(buff_addr, rw) | tmp[2]
' Set transmit address
'   Valid values:
'       buff_addr:
'           Address of buffer containing nRF24L01+ address to transmit to
'       rw:
'           0: Read current address
'           1: Write new address
'           Any other value reads current address
' NOTE: Buffer at buff_addr must be a minimum of 5 bytes
    bytefill(@tmp, $00, 8)
    readReg (core#NRF24_TX_ADDR, 5, @tmp)

    case rw
        1:
        OTHER:
            bytemove(buff_addr, @tmp, 5)
            return

    writeReg (core#NRF24_TX_ADDR, 5, buff_addr)

PUB TXFIFOEmpty
' Queries the FIFO_STATUS register for TX FIFO empty flag
'   Returns TRUE if empty, FALSE if there's data in TX FIFO
    readReg (core#NRF24_FIFO_STATUS, 1, @result)
    result &= (1 << core#FLD_TXFIFO_EMPTY) * TRUE

PUB TXFIFOFull
' Returns TX FIFO full flag
'   Returns: TRUE if full, FALSE if locations available in TX FIFO
    result := (Status & core#FLD_TX_FULL) * TRUE

PUB TXMode
' Change chip state to TX (transmit)
    RXTX(ROLE_TX)

PUB TXPayload(nr_bytes, buff_addr, deferred) | cmd_packet, tmp
' Queue payload to be transmitted
'   Valid values:
'       nr_bytes: 1..32 (Any other value is ignored)
'       deferred:
'           FALSE(0): Transmit immediately after queuing data
'           Any other value: Queue data only, don't transmit
    case nr_bytes
        1..32:
            writeReg (core#NRF24_W_TX_PAYLOAD, nr_bytes, buff_addr)
            ifnot deferred                                          ' Transmit immediately
                CE(1)                                               '   unless deferred is nonzero
                CE(0)
        OTHER:
            return FALSE

PUB TXPower(dBm) | tmp
' Set transmit mode RF output power, in dBm
'   Valid values: -18, -12, -6, 0
'   Any other value polls the chip and returns the current setting
    readReg (core#NRF24_RF_SETUP, 1, @tmp)
    case dBm
        -18, -12, -6, 0:
            dBm := lookdownz(dBm: -18, -12, -6, 0)
            dBm := dBm << core#FLD_RF_PWR
        OTHER:
            tmp := (tmp >> core#FLD_RF_PWR) & core#BITS_RF_PWR
            result := lookupz(tmp: -18, -12, -6, 0)
            return

    tmp &= core#MASK_RF_PWR
    tmp := (tmp | dBm) & core#NRF24_RF_SETUP_MASK
    writeReg (core#NRF24_RF_SETUP, 1, @tmp)

PUB TXReuse
' Queries the FIFO_STATUS register for TX_REUSE flag
'   Returns TRUE if re-using last transmitted payload, FALSE if not
    readReg (core#NRF24_FIFO_STATUS, 1, @result)
    result &= (1 << core#FLD_TXFIFO_REUSE) * TRUE

PRI Status
' Returns status of last SPI transaction
    readReg (core#NRF24_STATUS, 1, @result)

PRI writeReg (reg, nr_bytes, buff_addr) | tmp
' Write reg to MOSI
    ifnot lookdown(reg: $00..$17, $1C..$1D, $A0, $E1..$E3)              'Validate reg - there are a few the datasheet says are for testing
        return FALSE                                                    ' only and will cause the chip to malfunction if written to.

    reg |= core#NRF24_W_REG
    case reg    'XXX clean this up a little; remove some redundancy with the lookdown table above
        core#NRF24_W_TX_PAYLOAD:
            io.Low(_CSN)
            spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)
            repeat tmp from 0 to nr_bytes-1
                spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
            io.High(_CSN)

        core#NRF24_FLUSH_TX:
            io.Low(_CSN)
            spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)
            io.High(_CSN)

        core#NRF24_FLUSH_RX:
            io.Low(_CSN)
            spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)
            io.High(_CSN)

        OTHER:
            case nr_bytes
                0:
                    io.Low(_CSN)
                    spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg) 'Simple command
                    io.High(_CSN)
                1..5:
                    io.Low(_CSN)
                    spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg) 'Command w/nr_bytes data bytes following
                    repeat tmp from 0 to nr_bytes-1
                        spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, byte[buff_addr][tmp])
                    io.High(_CSN)

                OTHER:
                    result := FALSE
                    buff_addr := 0

PRI readReg (reg, nr_bytes, buff_addr) | tmp
' Read reg from MISO
    ifnot lookdown(reg: $00..$17, $1C..$1D, $61)                        'Validate reg - there are a few the datasheet says are for testing
        return FALSE                                                    ' only and will cause the chip to malfunction if written to.

    case reg    'XXX clean this up a little; remove some redundancy with the lookdown table above
        core#NRF24_RPD:
            io.Low(_CSN)
            spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)
            byte[buff_addr][0] := spi.ShiftIn (_MISO, _SCK, core#MISO_BITORDER, 8)
            io.High(_CSN)

        core#NRF24_R_RX_PAYLOAD:
            io.Low(_CSN)
            spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg)
            repeat tmp from 0 to nr_bytes-1
                byte[buff_addr][tmp] := spi.ShiftIn (_MISO, _SCK, core#MISO_BITORDER, 8)
            io.High(_CSN)
        OTHER:

            case nr_bytes
                1..5:
                    io.Low(_CSN)
                    spi.ShiftOut (_MOSI, _SCK, core#MOSI_BITORDER, 8, reg) ' Which register to query
                    repeat tmp from 0 to nr_bytes-1
                        byte[buff_addr][tmp] := spi.ShiftIn (_MISO, _SCK, core#MISO_BITORDER, 8)
                    io.High(_CSN)
                OTHER:
                    result := FALSE
                    buff_addr := 0

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
