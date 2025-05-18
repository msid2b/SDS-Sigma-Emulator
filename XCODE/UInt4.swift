//
//    UInt4.swift
//    UInt4
//
//    MIT License
//
//    Copyright (c) 2018 Mark Renaud
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.
//
// MARK: Adapted to use UInt8 as the storage unit (MGS)


import Foundation

public struct UInt4 {
    internal var internalValue: UInt8 = 0 {
        willSet(newInternalValue) {
            guard newInternalValue >= 0 else { fatalError("Negative value is not representable") }
            guard newInternalValue < 16 else { fatalError("UInt4: Not enough bits to represent value \(newInternalValue)") }
        }
    }
    

    
    init(_ value: IntegerLiteralType = 0) {
        defer {
            // use defer so that willSet bounds checking on internalValue will get called from the init
            internalValue = UInt8(value)
        }
    }
    
    // MARK: Additions by MGS
    var isEven: Bool    { return ((internalValue & 1) == 0) }
    var isOdd: Bool     { return ((internalValue & 1) == 1) }
    var next: UInt4     { return UInt4((internalValue + 1) & 0xF) }
    var previous: UInt4 { return UInt4((internalValue == 0) ? 0xF : (internalValue - 1)) }
    var u1: UInt4       { return UInt4(internalValue | 1) }
    
}

extension UInt4: BinaryInteger {
    public typealias Words = [UInt]
    
    public init<T>(_ source: T) where T : BinaryInteger {
        defer {
            // use defer so that willSet bounds checking on internalValue will get called from the init
            internalValue = UInt8(source)
        }
    }
    
    public init<T>(_ source: T) where T : BinaryFloatingPoint {
        defer {
            // use defer so that willSet bounds checking on internalValue will get called from the init
            internalValue = UInt8(source)
        }
    }
    
    // while a default implementation is provided, as of Swift 4.1
    public init<T>(clamping source: T) where T : BinaryInteger {
        if source > UInt4.max.internalValue {
            internalValue = UInt4.max.internalValue
        } else if source < UInt4.min.internalValue {
            internalValue = UInt4.min.internalValue
            return
        } else {
            internalValue = UInt8(source)
        }
    }
    
    
    public var  bitWidth: Int {
        return 4
    }
    
    public var trailingZeroBitCount: Int {
        if internalValue.trailingZeroBitCount > 4 {
            return 4
        }
        return internalValue.trailingZeroBitCount
    }
    
    public var words: UInt4.Words {
        return [UInt(internalValue)]
    }
    
    public static var isSigned: Bool {
        return false
    }
    
    public static func % (lhs: UInt4, rhs: UInt4) -> UInt4 {
        return UInt4(lhs.internalValue % rhs.internalValue)
    }
    
    public static func %= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue %= rhs.internalValue
    }
    
    public static func &= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue &= rhs.internalValue
    }
    
    
    public static func / (lhs: UInt4, rhs: UInt4) -> UInt4 {
        return UInt4(lhs.internalValue / rhs.internalValue)
    }
    
    public static func /= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue /= rhs.internalValue
    }
    
    public static func ^= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue ^= rhs.internalValue
    }
    
    public static func |= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue |= rhs.internalValue
    }
    
    // MARK: - Replacing missing or buggy default implementations
    
    // Note: while bit shift default implementations
    //       should be added by default, it seems
    //       there is a current error
    //       bitshift operators needed to be added
    //       added manually to avoid error: "Inlining
    //      'transparent' functions forms circular
    //       loop"
    // See:  https://github.com/apple/swift/pull/14761
    //       https://bugs.swift.org/browse/SR-7019?attachmentViewMode=list
    
    public static func >> (lhs: UInt4, rhs: Int) -> UInt4 {
        // a -'ve >> is really a <<
        if rhs < 0 {
            return lhs << abs(rhs)
        }
        return UInt4(lhs.internalValue >> rhs)
    }
    
    public static func << (lhs: UInt4, rhs: Int) -> UInt4 {
        // a -'ve << is really a >>
        if rhs < 0 {
            return lhs >> abs(rhs)
        }
        let uValue = UInt8(lhs.internalValue) << rhs
        let bitWidthDiff = uValue.bitWidth - 4
        let newUValue = (uValue << bitWidthDiff) >> bitWidthDiff
        return UInt4(newUValue)
    }
    
    public static func >>= (lhs: inout UInt4, rhs: Int) {
        let result = lhs >> rhs
        lhs.internalValue = result.internalValue
    }
    
    public static func <<= (lhs: inout UInt4, rhs: Int) {
        let result = lhs << rhs
        lhs.internalValue = result.internalValue
    }
}


extension UInt4: Comparable {
    public static func < (lhs: UInt4, rhs: UInt4) -> Bool {
        return lhs.internalValue < rhs.internalValue
    }
}

extension UInt4: Equatable {
    public static func == (lhs: UInt4, rhs: UInt4) -> Bool {
        return lhs.internalValue == rhs.internalValue
    }
}

extension UInt4: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = UInt8
    public init(integerLiteral value: IntegerLiteralType) {
        internalValue = value
    }
}

extension UInt4: FixedWidthInteger {
    public static var bitWidth: Int {
        return 4
    }
    
    public func addingReportingOverflow(_ rhs: UInt4) -> (partialValue: UInt4, overflow: Bool) {
        let value = self.internalValue + rhs.internalValue
        let max = UInt8(UInt4.max)
        if value > max {
            return (UInt4(value - max - 1), true)
        }
        return (UInt4(value), false)
    }
    
    public func subtractingReportingOverflow(_ rhs: UInt4) -> (partialValue: UInt4, overflow: Bool) {
        let value = Int8(self.internalValue) - Int8(rhs.internalValue)
        let max = UInt8(UInt4.max)
        if value < 0 {
            return (UInt4(max - UInt8(-value) + 1), true)
        }
        return (UInt4(value), false)
    }
    
    public func multipliedReportingOverflow(by rhs: UInt4) -> (partialValue: UInt4, overflow: Bool) {
        let value = self.internalValue * rhs.internalValue
        let max = UInt8(UInt4.max)
        if value > max {
            return (UInt4(value - max - 1), true)
        }
        return (UInt4(value), false)
        
    }
    
    // NOTE: dividing by zero is not an error with this function
    //       - it will instead will report `overflow` as `true`
    //       and report the `partialValue` as the dividend
    //       (as per the function documentation)
    //       eg. `x.dividedReportingOverflow(by: 0)` is `(x, true)`
    //       HOWEVER - current implementations of UInt8, UInt16, etc
    //       cause a `Division by zero` error in Xcode.
    //       This appears to be a known bug in swift.
    //       See: https://bugs.swift.org/browse/SR-5964
    //       Our implementation will return the result as per
    //       the documentation (as there is no static Xcode
    //       checks for UInt4).
    public func dividedReportingOverflow(by rhs: UInt4) -> (partialValue: UInt4, overflow: Bool) {
        if rhs.internalValue == 0 {
            return (self, true)
        }
        return (UInt4(self.internalValue / rhs.internalValue), false)
    }
    
    public func remainderReportingOverflow(dividingBy rhs: UInt4) -> (partialValue: UInt4, overflow: Bool) {
        if rhs.internalValue == 0 {
            return (self, true)
        }
        let remainder = self.internalValue % rhs.internalValue
        return (UInt4(remainder), false)
    }
    
    public func multipliedFullWidth(by other: UInt4) -> (high: UInt4, low: UInt4) {
        let result = UInt8(self.internalValue * other.internalValue)
        let low = UInt4((result << 4) >> 4)
        let high = UInt4(result >> 4)
        return (high, low)
    }
    
    public func dividingFullWidth(_ dividend: (high: UInt4, low: UInt4)) -> (quotient: UInt4, remainder: UInt4) {
        
        if self == 0 {
            fatalError("Division by zero")
        }
        let combined: UInt8 = (UInt8(dividend.high) << 4) | UInt8(dividend.low)
        
        let quotient8 = combined / UInt8(self)
        let remainder8 = combined % UInt8(self)
        // if the quotient is GREATER than the max value of the
        // return type - then we will do as standard library does
        // and truncate rather than crash
        // see: https://github.com/apple/swift/blob/d5c904b4f7faa0dea2ea4a0d8c17a1ec2fb0e0b1/stdlib/public/core/Integers.swift.gyb#L3596
        let quotient4 = UInt4((quotient8 << 4) >> 4)
        // the remainder should fit into the return type
        let remainder4 = UInt4(remainder8)
        
        return (quotient4, remainder4)
    }
    
    public var nonzeroBitCount: Int {
        return internalValue.nonzeroBitCount
    }
    
    public var leadingZeroBitCount: Int {
        // convert to UInt8 first (to handle possiblity
        // of < 64-bit systerms), then get rid of additional leading
        // 4-bits worth of zeros
        return internalValue.leadingZeroBitCount - 4
    }
    
    public var byteSwapped: UInt4 {
        // as UInt4 is less than 8 bits, it is less than 1 byte
        // thus there is only 1 byte, and it cannot be swapped
        return self
    }
    
    public static var max: UInt4 {
        return UInt4(15)
    }
    
    public static var min: UInt4 {
        return UInt4(0)
    }
    
    // MARK: - Replacing missing or buggy default implementations
    
    // we shouldn't need to generate this init - but we do
    // and hopefully we shouldn't need by Swift 5.0
    // see: https://forums.swift.org/t/how-do-i-make-a-uint0/9516/3
    // Essentially this function chops off leading bits
    // if it can't fit into the number of bits provided by UInt4
    // see: https://github.com/apple/swift/blob/d5c904b4f7faa0dea2ea4a0d8c17a1ec2fb0e0b1/stdlib/public/core/Integers.swift.gyb#L3499
    public init<T>(_truncatingBits source: T) where T : BinaryInteger {
        // convert to Int
        let value = UInt8(source)
        // truncate by off all but trailing 4 bits of data
        internalValue = (value << (value.bitWidth - 4)) >> (value.bitWidth - 4)
    }
    
    
}

extension UInt4: Numeric {
    public init?<T>(exactly source: T) where T : BinaryInteger {
        guard let intVal = UInt8(exactly: source) else { return nil }
        if (intVal < 16) && (intVal >= 0) {
            internalValue = intVal
        } else {
            return nil
        }
    }
    
    public static func -= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue -= rhs.internalValue
    }
    
    public static func - (lhs: UInt4, rhs: UInt4) -> UInt4 {
        return UInt4(lhs.internalValue - rhs.internalValue)
    }
    
    public static func += (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue += rhs.internalValue
    }
    
    public static func + (lhs: UInt4, rhs: UInt4) -> UInt4 {
        return UInt4(lhs.internalValue + rhs.internalValue)
    }
    
    public static func * (lhs: UInt4, rhs: UInt4) -> UInt4 {
        return UInt4(lhs.internalValue * rhs.internalValue)
    }
    
    public static func *= (lhs: inout UInt4, rhs: UInt4) {
        lhs.internalValue *= rhs.internalValue
    }
    
    public typealias Magnitude = UInt4
    
    public var magnitude: UInt4 {
        return self
    }
    
}

extension UInt4: UnsignedInteger { }
