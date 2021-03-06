{
    --------------------------------------------
    Filename: lib.termwidgets.spin
    Author: Jesse Burt
    Description: Library of terminal widgets
    Copyright (c) 2020
    Started Dec 14, 2019
    Updated Jun 29, 2020
    See end of file for terms of use.
    --------------------------------------------
}

'   Must be included using the preprocessor #include directive
'   Requires:
'       An object with string.integer declared as a child object, defined with symbol name int
'       An object that has the following standard terminal methods:
'           Dec (param)
'           Char (param)
'           Str (param)
'           Hex (param, digits)
'           Position (x, y)

PUB Frac(scaled, divisor) | whole[4], part[4], places, tmp
' Display a scaled up number in its natural form - scale it back down by divisor
    whole := scaled / divisor
    tmp := divisor
    places := 0

    repeat
        tmp /= 10
        places++
    until tmp == 1
    part := int.DecZeroed(||(scaled // divisor), places)

    Dec (whole)
    Char (".")
    Str (part)

PUB HexDump(buff_addr, base_addr, nr_bytes, columns, x, y) | maxcol, maxrow, digits, hexoffset, ascoffset, offset, hexcol, asccol, row, col, currbyte
' Display a hexdump of a region of memory
'   buff_addr: Start address of memory
'   base_addr: Address used to display as base address in hex dump (affects display only)
'   nr_bytes: Total number of bytes to display
'   columns: Number of bytes to display on each line
'   x, y: Terminal position to display start of hex dump
    maxcol := columns-1
    maxrow := nr_bytes / columns
    digits := 5                                                 ' Number of digits used to display offset
    hexoffset := digits + 2
    ascoffset := hexoffset + (columns * 3)
    offset := 0

    repeat row from y to y+maxrow
        Position (x, row)
        Hex (base_addr+offset, digits)                          ' Show offset address of row in 'digits'
        Str (string(": "))
        repeat col from x to maxcol
            currbyte := byte[buff_addr][offset++]
            hexcol := (col * 3) + hexoffset                 ' Compute the terminal X position of the hex byte
            asccol := col + ascoffset                       ' and the ASCII character

            Position (hexcol, row)                              ' Show the ASCII value in hex
            Hex (currbyte, 2)                                   '   of the current byte

            Position (asccol, row)                              ' Show the ASCII character
            case currbyte                                       '   of the current byte
                32..127:                                        '   IF it's a printable character
                    Char (currbyte)
                OTHER:                                          '   Otherwise, just show a period
                    Char (".")
            if offset > nr_bytes-1
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

