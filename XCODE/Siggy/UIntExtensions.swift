//
//  UInts.swift
//  Siggy
//
//  Created by ms on 2024-09-20.
//


// MARK: Arithmetic extensions for UINTs
extension UInt64 {
    // MARK: Carry is from the unsigned operation; Overflow is signed overflow
    func addReportingCarryAndOverflow (_ addend: UInt64) -> (UInt64, Bool, Bool) {
        let (r, c) = addingReportingOverflow(addend)

        let ssign = (self & u64b0)
        let asign = (addend & u64b0)
        if (ssign != asign) {
            return (r, c, false)                // Overflow not possible
        }
        let rsign = (r & u64b0)
        return (r, c, (rsign != ssign))
    }
}

extension UInt32 {
    // MARK: Carry is from the unsigned operation; Overflow is signed overflow
    func addReportingCarryAndOverflow (_ addend: UInt32) -> (UInt32, Bool, Bool) {
        let s = UInt(self) + UInt(addend)
        let r = UInt32(s & 0xFFFFFFFF)
        let c = (s > 0xFFFFFFFF)
        
        if (r == 0) {
            return (r, c, false)
        }
        
        let ssign = (self & u32b0)
        let asign = (addend & u32b0)
        if (ssign != asign) {
            return (r, c, false)                // Overflow not possible
        }
        
        let rsign = (r & u32b0)
        return (r, c, (rsign != ssign))
    }
}

extension UInt16 {
    // MARK: Carry is from the unsigned operation; Overflow is signed overflow
    func addReportingCarryAndOverflow (_ addend: UInt16) -> (UInt16, Bool, Bool) {
        let s = UInt(self) + UInt(addend)
        let r = UInt16(s & 0xFFFF)
        let c = (s > 0xFFFF)

        let ssign = (self & u16b0)
        let asign = (addend & u16b0)
        if (ssign != asign) {
            return (r, c, false)                // Overflow not possible
        }
        let rsign = (r & u16b0)
        return (r, c, (rsign != ssign))
    }
}


