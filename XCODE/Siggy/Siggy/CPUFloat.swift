//
//  CPUFloat.swift
//  Siggy
//
//MARK: MIT LICENSE
//  Copyright (c) 2023, Michael G. Sidnell
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

//  Created by ms on 2024-11-17.
//


//MARK: FLOATING POINT CONVERSIONS
//MARK: Convert double precision Sigma float (Little Endian) to IEEE
func ie3Float (_ d: UInt64) -> Double {
    guard (d != 0) else { return (0) }
    
    let neg = (d & u64b0)
    let a = (neg == 0) ? d : d.twosComplement
    
    var exp = Int((a >> 56) & 0x7F) - 0x40
    var f = a & f64Mantissa
    
    guard (f != 0) else { return 0 }        // DIRTY ZERO - Clean it up
                
    // Convert exponent from 16^x to 2^x
    exp <<=  2
    
    // Account for implicit 1. in IEEE mantissa
    exp -= 1
    
    // Adjust fraction
    while ((f & f64LeadBit) == 0) {
        exp -= 1
        f <<= 1
    }
    
    if (exp <= -1022) {
        // Align - No assumed leading bit
        f >>= 4
    }
    else {
        // Remove leading bit
        f ^= f64LeadBit
        
        // Align for 52 (+1 assumed) bits of mantissa
        f >>= 3
    }
    
    
    // Construct IEEE 64-bit float (N.B. Bias is 3FF, not 400)
    return Double(bitPattern: neg | (UInt64(exp + 0x3FF) << 52) | f)
}

//Convert single precision Sigma float to IEEE
//TODO: Is extending the low order bit better?
func ie3Float (_ w: UInt32) -> Double {
    return ie3Float(UInt64(w) << 32)
}

//MARK: Convert IEEE to double precision Sigma float (Little Endian) ; trap indicator, and CC
//MARK: The PSD FS setting is ignored - the IEEE va;lue has already normalized the result.
func sigmaDouble (_ d: Double,_ mode: CPU.PSD.FloatMode) -> (UInt64, Bool, UInt4) {
    if (d.isNaN) || (d.isSignalingNaN) { return (.max, true, 0) }
    if (d.isZero) { return (0, false, 0) }
    
    let neg = (d.sign == .minus)
    var exp = d.exponent
    
    var f: UInt64
    if (exp <= -1022) {
        f = (d.significandBitPattern << 4)
    }
    else {
        f = (d.significandBitPattern << 3) | f64LeadBit
    }

    
    // Adjust Fraction
    let ebits = exp & 0x3
    f >>= (3-ebits)
    
    // Account for implicit 1. in IEEE mantissa
    exp += 4
    
    // Convert exponent from 2^x to 16^x
    exp >>= 2
    
    let cc = UInt4(neg ? 1 : 2)
    if (exp > 0x3f) {
        //MARK: OVERFLOW
        return (.max, true, 0x4 | cc )
    }

    // TRY to resuscitate an almost underflow
    while (exp < -0x40) && (f != 0) {
        exp += 1
        f >>= 4
    }
    
    if (exp < -0x40) {
        //MARK: UNDERFLOW
        if mode.normalize { return (0, false, cc) }
        return (0, mode.zero, 0xC | cc)
    }
    
    // Get absolute value
    let a = (UInt64(exp + 0x40) << 56) | f
    if (neg) { return (a.twosComplement, false, cc) }
    
    // +ve
    return (a, false, cc)
}

extension CPU {
    
    // Floating point instruction emulator.
    // This routine handles all floating point operations.
    // The operands are converted to IEEE 64-bit floats, and the operation is done nativeley.
    // The result is converted back to sigma float and put into the result register(s)
    @objc func iFP() {
        guard (floatingPoint) else { iUnimplemented() ; return }

        var om: Double = 0
        var or: Double = 0
        let r = zInstruction.register

        if ((zInstruction.opCode & 0x20) != 0) {
            let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
            if (trapPending) { return }
            
            om = ie3Float(loadUnsignedWord(wa: wa))
            if (trapPending) { return }
            
            or = ie3Float(getRegisterUnsignedWord(r))
        }
        else {
            let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
            if (trapPending) { return }
            
            om = ie3Float(loadUnsignedDoubleWord(da: da))
            if (trapPending) { return }
            
            or = ie3Float(getRegisterUnsignedDouble(r))
        }
        
        var v: UInt64   = 0
        var t: Bool     = false
        var cc: UInt4   = 0
        var result: Double = 0
        
        switch (zInstruction.opCode) {
        case 0x1C, 0x3C:                // FSL, FSS
            result = or - om
        case 0x1D, 0x3D:                // FAL, FAS
            result = or + om
        case 0x1E, 0x3E:                // FDL, FDS
            if (om == 0) {
                v = .min; t = true; cc = 0xD  //MARK: Negative Inf
                MSLog("Zerodivide!")
                return
            }
            else {
                result = or / om
            }
        case 0x1F, 0x3F:                // FML, FML
            result = or * om

            
        default:
            iUnimplemented()
            return
        }
        
        (v,t,cc) = sigmaDouble(result, psd.zFloat)
        
        if (t) {
            psd.zCC = 0x4 | cc
        }
        else {
            if ((zInstruction.opCode & 0x20) != 0) {
                let w =  UInt32(v >> 32)
                setRegister(r, unsigned: w)
            }
            else {
                setRegisterDouble(r, unsigned: v)
            }
            psd.zCC = cc
        }
        
        if (floatTrace) {
            machine.consoleTTY.log ("FP: \(zInstruction.getDisplayText()), R=\(or), M=\(om), result=\(result) .\(hexOut(v,width:16))")
        }
    }
    

}
