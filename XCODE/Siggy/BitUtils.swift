//
//  BitUtils.swift
//  Siggy
//
//  Created by MS on 2023-02-21.
//

import Foundation

// Masks for sign bits.
let u64b0:      UInt64 = 0x8000000000000000
let u32b0:      UInt32 =         0x80000000
let u32b0le:    UInt32 =         0x00000080         // Little endian
let u16b0:      UInt16 =             0x8000

// Masks for Floats.
let f64Mantissa: UInt64 = 0xFFFFFFFFFFFFFF
let f64LeadBit:  UInt64 = 0x80000000000000


extension FixedWidthInteger {
    @inlinable func bitTest(mask: Self) -> Bool {
        return ((self & mask) != 0)
    }
    
    func bitIsSet(bit: Int) -> Bool {
        let mask = Self(1) << (self.bitWidth-(bit+1))
        return ((self & mask) != 0)
    }
    
    @inlinable mutating func setBit(mask: Self) {
        self |= mask
    }
    
    mutating func setBit(bit: Int) {
        let mask = Self(1) << (self.bitWidth-(bit+1))
        setBit(mask: mask)
    }
    
    @inlinable mutating func clearBit(mask: Self) {
        self &= ~mask
    }
    
    mutating func clearBit(bit: Int) {
        let mask = Self(1) << (self.bitWidth-(bit+1))
        clearBit(mask: mask)
    }
    
    // TWO'S Complement
    var twosComplementReportingCarry: (Self, Bool) { get {
        var mask = Self.max
        if self is (any SignedInteger) {
            mask = Self(-1)
        }
        return (self ^ mask).addingReportingOverflow(1)
    }}
    
    var twosComplement: Self { get {
        let (c,_) = twosComplementReportingCarry
        return c
    }}
}


class BitMap {
    let mask: [UInt8] = [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]
    var nBits: Int
    var nBytes: Int
    var map: UnsafeMutablePointer<UInt8>
    
    init (count: Int,_ with: UInt8) {
        nBits = count
        nBytes = (count+7) >> 3
        map = UnsafeMutablePointer<UInt8>.allocate(capacity: nBytes)
        map.initialize(repeating: with, count: nBytes)
    }
    
    convenience init (count: Int, from: Data? = nil) {
        self.init(count: count, 0)
        if let d = from {
            for i in 0 ... nBytes {
                map[i] = (i < d.count) ? d[i] : 0
            }
        }
    }
    
    func setBit(_ n: Int) {
        if (n >= 0) && (n < nBits) {
            let b = n >> 3
            map[b] |= mask[n & 7]
        }
    }
    
    func resetBit(_ n: Int) {
        if (n >= 0) && (n < nBits) {
            let b = n >> 3
            map[b] &= (mask[n & 7] ^ 0xFF)
        }
    }
    
    func isSet(_ n: Int) -> Bool {
        if (n >= 0) && (n < nBits) {
            let b = n >> 3
            return ((map[b] & mask[n & 7]) != 0)
        }
        return false
    }
    
    func isReset(_ n: Int) -> Bool {
        if (n >= 0) && (n < nBits) {
            let b = n >> 3
            return ((map[b] & mask[n & 7]) == 0)
        }
        return false
    }

}



public func hexIn64(_ hex: String?, ignoreLeading: [Character] = [], emptyResult: UInt64? = nil) -> UInt64? {
    guard (hex != nil) else { return emptyResult }
    
    var value: UInt64 = 0
    let s: String = hex!
    
    if (s.isEmpty) { return emptyResult }
    
    var leading: Bool = true
    for c in s {
        if (!leading) || (!ignoreLeading.contains(c)) {
            if let d = c.hexDigitValue {
                value = (value << 4) + UInt64(d)
                leading = false
            }
            else {
                return nil
            }
        }
    }
    return value
}

public func hexIn(hex: String?, emptyResult: Int? = nil) -> Int? {
    if let value = hexIn64(hex, ignoreLeading: ["-"]) {
        if (hex!.first == "-") {
            return (value <= Int.max) ? -Int(value) : emptyResult
        }
        return (value <= Int.max) ? Int(value) : emptyResult
    }
    return emptyResult
}

public func hexIn(hex: String?, defaultValue: Int) -> Int {
    if let v = hexIn(hex: hex) {
        return v
    }
    return defaultValue
}

public func hexOut64(_ value: UInt64, width: Int = 0) -> String {
    let hexit: [String] = ["0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"]
    var s = ""
    var v = value
    var w = (width > 0) ? width : 16
    while (v > 0) && (w > 0) {
        s += hexit[Int(v & 0xf)]
        v >>= 4
        w -= 1
    }
    
    if (width > 0) && (s.count < width) {
        s = s.pad(width, "0")
    }
    else if (s.count == 0) {
        s = "0"
    }
    
    return String(s.reversed())
}

public func hexOut<T: FixedWidthInteger>(_ value: T, width: Int = 0, treatAsUnsigned: Bool = false) -> String {
    if value is any UnsignedInteger {
        return hexOut64(UInt64(value), width: width)
    }
    else if (treatAsUnsigned) {
        return hexOut64(UInt64(bitPattern: Int64(value)), width: width)
    }
    
    // For signed values, display optional sign and the magnitude
    if (value == T.min) {
        return "-" + hexOut64(0, width: width)
    }
    let signedValue = Int64(value)
    if (signedValue < 0) {
        return "-" + hexOut64(UInt64(-Int(value)), width: width)
    }
    
    // signed value is positive
    return hexOut64(UInt64(signedValue), width: width)
}
