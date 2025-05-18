//
//  CPUDecimal.swift
//  Siggy
//
//MARK: MIT LICENSE
//  Copyright (c) 2024, Michael G. Sidnell
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the “Software”), to deal in
//  the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//  of the Software, and to permit persons to whom the Software is furnished to do
//  so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//  PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//MARK: END OF LICENSE

//  Emulates decimal instructions.
//  Typically, operands are checked and converted to 128 bit integers, on which
//  the operation is then performed.   The result is converted back to packed decimal
//  in the accumulator.
//  However, there are a few special cases which have resulted in rather bizarre code (e.g. DSA)
//
//  Created by ms on 2024-11-17.
//

let deca: UInt8 = 48
let decimal128Divisor =    1_000_000_000_000_000
let decimal64SignedMax =     999_999_999_999_999
let decimal64UnsignedMax = 9_999_999_999_999_999

let d10to31 = Int128(( 0x7e37be2022, 0xc0914b2680000000))
let m10to31 = -d10to31

let maskInt64 = Int128(UInt64.max)
let maxInt64 = Int128(Int64.max)

let decimalSignNegative: UInt8 = 0xD
let decimalSignPositive: UInt8 = 0xC


extension CPU {
    
    func isDecimalNegative(_ sign: UInt8) -> Bool {
        return (sign == 0xB) || (sign == 0xD)
    }
    
    func decimalInvalid() {
        psd.zCC1 = true
        if !trapPending && psd.zDecimalMask {
            trap(addr:0x45)
        }
    }
    
    func decimalOverflow() {
        psd.zCC2 = true
        if !trapPending && psd.zDecimalMask {
            trap(addr:0x45)
        }
    }
    

    struct DecimalCheck {
        var ok: Bool = false
        var unsigned: Bool = false
        var value: Int128 = 0
    }
    
    //MARK: Validate a packed decimal number in memory or in the accumulator.
    //MARK: Also computes binary value
    //TODO: This handles picking out the first part of an intermediate interrupted result,
    //TODO: but is incomplete.  DD and DM do not handle this.  However, since in this implementation,
    //TODO: they are not interruptable, nobody cares except the diagnotics.
    func decimalCheck (_ ba: Int,_ length: Int = 0,_ canBeUnsigned: Bool = false) -> DecimalCheck {
        var value: Int128 = 0
        var ea = ba
        
        var highSign: Bool = false
        let variable = length == 0
        var n = variable ? 16 : length
        while (n > 1) {
            let b = loadByte(ba: ea)
            let b1 = b >> 4
            if (b1 >= 0xA) {
                // Variable length "interrupted" computation?
                if variable { highSign = true; break }
                return DecimalCheck()                       //MARK: Bad digit
            }
            let b2 = b & 0xF
            if (b2 >= 0xA) {
                // Variable length "interrupted" computation?
                if variable { break }
                return DecimalCheck()                       //MARK: Bad digit
            }
            value = value * 100 + Int128(b1 * 10 + b2)
            ea += 1
            n -= 1
        }
        
        // Process last byte..
        let b = loadByte(ba: ea)
        let d = b >> 4
        var s = b & 0xF
        
        //Variable length can be unaligned.
        if highSign {
            s = d
        }
        else {
            if (d >= 0xA) { return DecimalCheck() }         //MARK: Bad digit
            value = value * 10 + Int128(d)
        }
        let neg = isDecimalNegative(s)
        if (s < 0xA) {                                      //MARK: Unsigned
            value = value * 10 + Int128(s)
        }
        else if neg {
            value = -value
        }
        
        let unsigned = (s < 0xA)
        return DecimalCheck (ok: (!unsigned) || canBeUnsigned, unsigned: unsigned, value: value)
    }
    
    //TODO: SHOULD BE SOMEWHERE ELSE, LIKE CPU
    func traceBytes(_ ba: Int,_ length: Int) -> String {
        var t = "\(hexOut(ba,width:5))[\(hexOut(length,width:2))] "
        var n = length
        var a = ba
        while (n > 0) {
            let b = loadByte(ba: a)
            t += "\(hexOut(b,width:2)) "
            a += 1
            n -= 1
        }
        return t
    }
    
    // Is there a loss of significance?
    func los (_ length: Int) -> Bool {
        var ra = UInt8(deca)
        var n = 16-length
        while (n > 0) {
            if (getRegisterByte(ra) != 0) {
                return true
            }
            ra += 1
            n -= 1
        }
        return false
    }
    
    // Sign should be 0, 0xC, or 0xD.
    func digits(_ v: UInt64,_ sign: UInt8 = 0) -> UInt64 {
        var d: UInt64 = UInt64(sign)                    // Output: 15+sign or 16-digit packed decimal
        var shift: UInt64 = (sign > 0) ? 4 : 0
        
        var m: UInt64 = v
        while (m > 0) {
            let (q,r) = m.quotientAndRemainder(dividingBy: 10)
            d |= (r << shift)
            shift += 4
            m = q
        }
        
        return d
    }

    //MARK: Set the accumulator and condition code from a binary value
    func decimalSet (_ value: Int128, cc2: Bool = true) {
        
        // break into 16-digit high order and 15 digit low order parts
        var (hi,lo) = value.quotientAndRemainder(dividingBy: Int128(decimal128Divisor))
        
        // could be too big to fit...
        if (hi.magnitude > decimal64UnsignedMax) {
            if cc2 { decimalOverflow(); return }
            
            // caller doesnt want overflow indication.  (e.g. Multiply)
            hi %= Int128(decimal64UnsignedMax)
        }

        setRegisterDouble(0xC, unsigned: digits(UInt64(hi.magnitude)))
        setRegisterDouble(0xE, unsigned: digits(UInt64(lo.magnitude), (value < 0) ? decimalSignNegative : decimalSignPositive))
        
        // Now CC 3 & 4
        setCC34(value)
    }
    
    
    //MARK: This function handles all decimal instructions except EBS, which has it's own func below...
    @objc func iDECIMAL() {
        
        if(decimalTrace) {
            machine.consoleTTY.logToConsole("BEGIN: \(zInstruction.getDisplayText()), DECA=\(hexOut(getRegisterUnsignedWord(0xC),width:8)) \(hexOut(getRegisterUnsignedWord(0xD),width:8)) \(hexOut(getRegisterUnsignedWord(0xE),width:8)) \(hexOut(getRegisterUnsignedWord(0xF),width:8))")
        }

        
        var edo: Int
        if (zInstruction.opCode != 0x7C) {
            edo = effectiveAddress(reference: zInstruction.reference,
                                   indexRegister: zInstruction.index,
                                   indexAlignment: .byte, indirect: zInstruction.indirect)
            if (trapPending) { return }
        }
        else {
            edo = Int(zInstruction.reference)
        }
        // All instructions SET CC 1 & 2
        psd.zCC &= 0x3
        
        let length = (zInstruction.register > 0) ? Int(zInstruction.register) : 16
        
        switch (zInstruction.opCode) {
        case 0x76:                      //MARK: PACK
            var value: Int128 = 0
            var zone: UInt8 = 0
            var n = (length << 1) - 1

            if (decimalTrace) {
                machine.consoleTTY.logToConsole(traceBytes(edo,n))
            }

            while (n > 0) {
                let b = loadByte(ba: edo)
                let d = b & 0xF
                if (d >= 0xA) { decimalInvalid() ; return  }    //MARK: Bad digit
                zone = b >> 4
                value = value * 10 + Int128(d)
                edo += 1
                n -= 1
            }
            
            if (zone <= 0xA) {
                decimalInvalid()
            }
            else if isDecimalNegative(zone) {
                decimalSet(-value)
            }
            else {
                decimalSet(value)       // PUT INTO ACCUMULATOR
            }
            
        case 0x77:                      //MARK: UNPK
            let ca = decimalCheck(Int(deca),16)
            guard (ca.ok) else { decimalInvalid(); return }
            
            psd.zCC2 = los(length)
            var n = length
            var ra = deca+UInt8(16-n)
            while (n > 0) {
                n -= 1
                let dd = getRegisterByte(ra)
                if (n > 0) {
                    storeByte(ba: edo, (dd >> 4) | 0xF0)
                    edo += 1
                    storeByte(ba: edo, (dd & 0xF) | 0xF0)
                }
                else {
                    storeByte(ba: edo, (dd >> 4) | ((dd & 0xF) << 4))
                }
                edo += 1
                ra += 1
            }
            
        case 0x78:                      //MARK: DS
            let ca = decimalCheck(Int(deca),16)
            let cm = decimalCheck(edo,length)
            guard (ca.ok && cm.ok) else { decimalInvalid(); return }
            decimalSet(ca.value - cm.value)
            
        case 0x79:                      //MARK: DA
            let ca = decimalCheck(Int(deca),16)
            let cm = decimalCheck(edo,length)
            guard (ca.ok && cm.ok) else { decimalInvalid(); return }
            decimalSet(ca.value + cm.value)
            
        case 0x7A:                      //MARK: DD
            guard (length <= 8) else { decimalInvalid(); return }
            //TODO: some work required to handle interrupted instruction restarts
            //MARK: For now, they are trapped, because the decimalCheck on the accumulator will fail.
            let ca = decimalCheck(Int(deca),16)
            let cm = decimalCheck(edo,length)
            
            if (decimalTrace) {
                machine.consoleTTY.logToConsole("OPRND: \(zInstruction.getDisplayText()), \(cm.ok ? "OK" : "**") \(cm.value._description())")
            }

            guard (ca.ok && cm.ok) else { decimalInvalid(); return }
            if (cm.value == 0) { decimalOverflow(); return }
            let (q,r) = ca.value.quotientAndRemainder(dividingBy: cm.value)
            if (q.magnitude > decimal64SignedMax) || (r.magnitude > decimal64SignedMax) {
                decimalOverflow()
            }
            else {
                setCC34(q)
                let qSign = (q < 0) ? decimalSignNegative : decimalSignPositive
                let rSign = (ca.value < 0) ? decimalSignNegative : decimalSignPositive
                setRegisterDouble(0xE, unsigned: digits(Int64(q).magnitude, qSign))
                setRegisterDouble(0xC, unsigned: digits(Int64(r).magnitude, rSign))
            }
            
        case 0x7B:                      //MARK: DM
            guard (length <= 8) else { decimalInvalid(); return }
            //TODO: some work required to handle interrupted instruction restarts
            //MARK: For now, they are trapped, because the decimalCheck on the accumulator will fail.
            let ca = decimalCheck(Int(deca),16)
            let cm = decimalCheck(edo,length)
            
            if (decimalTrace) {
                machine.consoleTTY.log("OPRND: \(zInstruction.getDisplayText()), \(cm.ok ? "OK" : "**") \(cm.value._description())")
            }

            guard (ca.ok && cm.ok) else { decimalInvalid(); return }
            let (p,_) = ca.value.multipliedReportingOverflow(by: cm.value)
            
            //MARK: DO NOT TRAP
            //if (_) { decimalOverflow() }
            decimalSet(p, cc2: false)
            
        case 0x7C:                      //MARK: DSA
            //TODO: Is it better code with binary shifts?
            let ca = decimalCheck(Int(deca),16)
            guard (ca.ok) else { decimalInvalid(); return }
            
            //NOTE: The manual's explanation of the indirect indexed execution is unclear,
            // but it probably works like the regular shift instruction.  The edo calculation above
            // make a special case for this, but it is incomplete.
            var n = Int16(bitPattern: UInt16(edo & 0xFFFF))
            if (zInstruction.index > 0) {
                n += Int16(bitPattern: UInt16((getRegister(zInstruction.index) >> 2) & 0xFFFF))
            }
            
            //Shifts > 31 digits will clear the accumulator.
            if (n <= -31) || (n >= 31) {
                psd.zCC2 = (n >= 31) && (ca.value != 0)
                // If negative, result will be -0
                let sign = (getRegisterByte(deca+15) & 0xF)
                for r in UInt4(0xC)...UInt4(0xF) {
                    setRegister(r, 0)
                }
                setRegisterByte(deca+15, sign)
                psd.zCC34 = 0
                return
            }
            
            var v = ca.value
            if ((n & 0x1) == 1) {
                if (n > 0) {
                    // shift left one digit.
                    v *= 10
                    
                    // If overflow, set CC2 and drop digit
                    if (v >= d10to31) {
                        psd.zCC2 = true
                        while (v >= d10to31) { v -= d10to31 }
                    }
                    else if (v <= d10to31.twosComplement) {
                        psd.zCC2 = true
                        while (v <= -d10to31) { v += d10to31 }
                    }
                    n -= 1
                }
                else {
                    // Shift right one digit.
                    v /= 10
                    n += 1
                }
            }
            decimalSet(v)               // setting CC3&4

            if (decimalTrace) {
                machine.consoleTTY.logToConsole("PART** \(zInstruction.getDisplayText()), DECA=\(hexOut(getRegisterUnsignedWord(0xC),width:8)) \(hexOut(getRegisterUnsignedWord(0xD),width:8)) \(hexOut(getRegisterUnsignedWord(0xE),width:8)) \(hexOut(getRegisterUnsignedWord(0xF),width:8))")
            }

            // n is now even.  Do the rest byte by byte
            if (n == 0) { break }
            
            n >>= 1
            var z: Bool = true
            let sign = (getRegisterByte(deca+15) & 0xF)
            if (n > 0) {                // shift left n bytes
                //If there is a nonzero byte that will get shifted out, set CC2
                var s: UInt8 = 0
                while (s < n) {
                    if (getRegisterByte(deca+s) != 0) {
                        psd.zCC2 = true
                    }
                    s += 1
                }

                // Now shift the rest
                var d: UInt8 = 0
                n = Int16(16 - s)
                while (n > 0) {
                    n -= 1
                    var b = getRegisterByte(deca+s)
                    if (n == 0) { b &= 0xF0 }
                    setRegisterByte(deca+d, b)
                    if (b != 0) { z = false }
                    s += 1
                    d += 1
                }
                while (d < 15) {
                    setRegisterByte(deca+d, 0)
                    d += 1
                }
                setRegisterByte(deca+15, sign)
            }
            else {
                var s = UInt8(15 + n)
                var d = UInt8(15)
                // PRESERVE sign for the first byte moved.
                var b = (getRegisterByte(deca+s) & 0xF0)
                if (b != 0) { z = false }
                b |= sign
                n += 16
                while (n > 0) {
                    n -= 1
                    setRegisterByte(deca+d, b)
                    
                    if (s > 0) {
                        s -= 1
                        
                        b = getRegisterByte(deca+s)
                        if (b != 0) { z = false }
                    }
                    d -= 1
                }
                
                setRegisterByte(deca+d, 0)
                while (d > 0) {
                    d -= 1
                    setRegisterByte(deca+d, 0)
                }
            }
            if (z) { psd.zCC34 = 0 }

        case 0x7D:                      //MARK: DC
            let ca = decimalCheck(Int(deca),16)
            let cm = decimalCheck(edo,length)
            guard (ca.ok && cm.ok) else { decimalInvalid(); return }
            
            if (ca.value > cm.value) { psd.zCC = 2 }
            else if (ca.value < cm.value) { psd.zCC = 1 }
            else { psd.zCC = 0 }        // EQUAL!
            
            
        case 0x7E:                      //MARK: DL
            let cm = decimalCheck(edo,length)
            guard (cm.ok) else { decimalInvalid(); return }
            decimalSet (cm.value)
            
            
        case 0x7F:                      //MARK: DST
            let ca = decimalCheck(Int(deca),16)
            guard (ca.ok) else { decimalInvalid(); return }
            
            psd.zCC2 = los(length)
            var n = length
            var ra = deca+UInt8(16-n)
            while (n > 0) {
                var dd = getRegisterByte(ra)
                n -= 1
                if (n ==  0) {
                    let s = dd & 0xF
                    dd = (dd & 0xF0) | (isDecimalNegative(s) ? decimalSignNegative : decimalSignPositive)
                }
                storeByte(ba: edo, dd)
                edo += 1
                ra += 1
                
            }

            

        default:
            iUnimplemented()
            return
        }
        
        if (decimalTrace) {
            machine.consoleTTY.logToConsole("END ** \(zInstruction.getDisplayText()), DECA=\(hexOut(getRegisterUnsignedWord(0xC),width:8)) \(hexOut(getRegisterUnsignedWord(0xD),width:8)) \(hexOut(getRegisterUnsignedWord(0xE),width:8)) \(hexOut(getRegisterUnsignedWord(0xF),width:8))")
        }
    }
    
    
    //63: EBS
    @objc func iEBS () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        guard (decimal) else { iUnimplemented() ; return }
        
        let r = zInstruction.register
        let d = getRegisterUnsignedWord(r.u1)
        let count = Int(d >> 24)
        let pa = Int(d & 0x7FFFF)
        var da = pa
        
        checkDataBreakpoint(ba: UInt32(da), bl: UInt32(count), psd.zMapped, .write)

        let rr = getRegisterUnsignedWord(r)
        let fill = UInt8(rr >> 24)
        
        let sr = (r > 0) ? Int(rr & 0x7FFFF) : 0
        let sd = Int(zInstruction.unsignedDisplacement)
        let s0 = (sd + sr) & 0x7FFFF
        var sa = s0
        if (r > 0) {
            checkDataBreakpoint(ba: UInt32(sa), bl: UInt32(count), psd.zMapped, .read)
        }

        if (decimalTrace) {
            machine.consoleTTY.logToConsole("BEGIN: \(zInstruction.getDisplayText()), R=\(hexOut(rr,width:8)), Ru1=\(hexOut(d,width:8))")
            machine.consoleTTY.logToConsole(traceBytes(sa,(count+1)>>1))
            machine.consoleTTY.logToConsole(traceBytes(pa,count))
        }
        
        
        psd.zCC &= 0x4
        var n = count
        while (n > 0) {
            let pb = loadByte(ba: da)
            switch (pb) {
            case 0x20, 0x21, 0x23:
                let sb = loadByte(ba: sa)
                if (trapPending) { break }
                
                let digit = psd.zCC2 ? (sb & 0xF) : (sb >> 4)
                if (digit >= 0xA) {
                    trap(addr: 0x45); break
                }
                if (digit > 0) { psd.zCC3 = true }
                
                var mark: Int = 0
                switch (pb) {
                case 0x23:
                     storeByte(ba: da, digit|0xF0)
                     if (trapPending) { break }
                     mark = 1
                     psd.zCC4 = true
                     
                case 0x21:
                    storeByte(ba: da, ((psd.zCC4) || (digit > 0)) ? (digit|0xF0) : fill)
                    if (trapPending) { break }
                    if (!psd.zCC4) {
                        mark = (digit > 0) ? 1 : 2
                    }
                    psd.zCC4 = true
                    
                case 0x20:
                    storeByte(ba: da, ((psd.zCC4) || (digit > 0)) ? (digit|0xF0) : fill)
                    if (trapPending) { break }
                    if (!psd.zCC4) && (digit > 0) {
                        mark = 1
                        psd.zCC4 = true
                    }
                    
                default:
                    trap (addr: 0x45)
                }
                
                let rdigit = sb & 0xF
                if (!psd.zCC2) && (rdigit >= 0xA) {
                    psd.zCC1 = true
                    psd.zCC4 = isDecimalNegative(rdigit)
                    sa += 1
                }
                else {
                    if (psd.zCC2) {
                        sa += 1
                    }
                    psd.zCC2 = !psd.zCC2
                }
                
                if (mark > 0) {
                    setRegister(1, unsigned: UInt32((da & 0x7FFFF) + (mark - 1)))
                }
                
                 
                
                //MARK: NOT 0x20, 21, or 23
            default:
                if (pb == 0x22) {
                    storeByte(ba: da, fill)
                    if (trapPending) { break }
                    psd.zCC &= 0x4
                }
                else {
                    if !psd.zCC4 {
                        storeByte(ba: da, psd.zCC1 ? 0x40 : fill)
                    }
                }
                if (trapPending) { break }
            }
            
            if (trapPending) { break }
            da += 1
            n -= 1
        }
        
        if (r > 0) && (r.isEven) {
            setRegister(r, unsigned: UInt32((sa-sd) & 0x7FFFF) | UInt32(fill) << 24)
        }
        setRegister(r.u1, unsigned: UInt32((n << 24) | da))
        
        if (decimalTrace) {
            machine.consoleTTY.logToConsole((trapPending ? "*TRAP" : "END  ")+": \(zInstruction.getDisplayText()), R=\(hexOut(rr,width:8)), Ru1=\(hexOut(d,width:8)), CC=\(hexOut(UInt8(psd.zCC),width:1))")
            machine.consoleTTY.logToConsole(traceBytes(pa,count))
        }

    }
    

}
