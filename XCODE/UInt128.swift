//MARK: THIS IS A FINE EXAMPLE
// of how ridudiculously complex and bureaucratic it is to do something in swift that would be for all
// intents and purposes, pretty easy in C.
// In some ways, Swift is extraordinarily bloated, arcane, and underdocumented.

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// Modified for public use in pre-Swift 6 installations as a precursor
// to using Swift 6. Modified by Michael Griebling

// MARK:  Modified for compatibility with older versions of MacOS by MGS.
// MARK:  Uses (U)Int instead of StaticBigInt for literals
// MARK:  Added UInt128.allSet constant for all bits on (Using a literal -1 causes errors).

// MARK: Memory layout

/// A 128-bit unsigned integer value type.

@frozen
public struct UInt128: Sendable, Codable {
    //  On 32-bit platforms, we don't want to use Builtin.Int128 for layout
    //  because it would be 16B aligned, which is excessive for such targets
    //  (and generally incompatible with C's `_BitInt(128)`). Instead we lay
    //  out the type as two `UInt64` fields--note that we have to be careful
    //  about endianness in this case.
#if _endian(little)
    public var _low: UInt64
    public var _high: UInt64
  #else
    public var _high: UInt64
    public var _low: UInt64
#endif
  
  /// Creates a new instance from the given tuple of high and low parts.
  ///
  /// - Parameter value: The tuple to use as the source of the new instance's
  ///   high and low parts.
    public init(_ value: (high: UInt64, low: UInt64)) {
        self._low = value.low
        self._high = value.high
    }

    @_transparent
    public init(_low: UInt64, _high: UInt64) {
        self._low = _low
        self._high = _high
    }

    public var _value: Int128 {
        @_transparent get {
            unsafeBitCast(self, to: Int128.self)
        }
        
        @_transparent set {
            self = Self(newValue)
        }
    }

    @_transparent
    public init(_ _value: Int128) {
        self = unsafeBitCast(_value, to: Self.self)
    }

  /// Creates a new instance with the same memory representation as the given
  /// value.
  ///
  /// This initializer does not perform any range or overflow checking. The
  /// resulting instance may not have the same numeric value as
  /// `bitPattern`---it is only guaranteed to use the same pattern of bits in
  /// its binary representation.
  ///
  /// - Parameter bitPattern: A value to use as the source of the new instance's
  ///   binary representation.
  
    @_transparent
    public init(bitPattern: Int128) {
        self.init(bitPattern._value)
    }
     
}

extension UInt128 {
  public var components: (high: UInt64, low: UInt64) {
    @inline(__always) get { (_high, _low) }
    @inline(__always) set { (self._high, self._low) = (newValue.high, newValue.low) }
  }
}

// MARK: - Constants

extension UInt128 {
    @_transparent
    public static var zero: Self {
        Self(_low: 0, _high: 0)
    }

    @_transparent
    public static var min: Self {
        zero
    }

    @_transparent
    public static var max: Self {
        Self(_low: .max, _high: .max)
    }
      
    public static var allSet: Self {
        max
    }
}


extension UInt128: ExpressibleByIntegerLiteral {
    
    public typealias IntegerLiteralType = UInt
    
    public init(integerLiteral value: IntegerLiteralType) {
        precondition(UInt64.bitWidth == 64, "Expecting 64-bit UInt")
        precondition(value.signum() >= 0, "UInt128 literal cannot be negative")
        precondition(value.bitWidth <= Self.bitWidth+1,
                     "\(value.bitWidth)-bit literal too large for UInt128")
        self.init(_low: UInt64(value), _high: 0)
    }


    @inlinable
    public init?<T>(exactly source: T) where T: BinaryInteger {
        guard let high = UInt64(exactly: source >> 64) else { return nil }
        let low = UInt64(truncatingIfNeeded: source)
        self.init(_low: low, _high: high)
    }

    @inlinable
    public init<T>(_ source: T) where T: BinaryInteger {
        guard let value = Self(exactly: source) else {
            fatalError("value cannot be converted to UInt128 because it is outside the representable range")
        }
        self = value
    }

    @inlinable
    public init<T>(clamping source: T) where T: BinaryInteger {
        guard let value = Self(exactly: source) else {
            self = source < .zero ? .zero : .max
            return
        }
        self = value
    }

    @inlinable
    public init<T>(truncatingIfNeeded source: T) where T: BinaryInteger {
        let high = UInt64(truncatingIfNeeded: source >> 64)
        let low = UInt64(truncatingIfNeeded: source)
        self.init(_low: low, _high: high)
    }

    @_transparent
    public init(_truncatingBits source: UInt) {
        self.init(_low: UInt64(source), _high: .zero)
    }
}

// MARK: - Conversions from Binary floating-point

extension UInt128 {
  
  @inlinable
  public init?<T>(exactly source: T) where T: BinaryFloatingPoint {
    let highAsFloat = (source * 0x1.0p-64).rounded(.towardZero)
    guard let high = UInt64(exactly: highAsFloat) else { return nil }
    guard let low = UInt64(
      exactly: high == 0 ? source : source - 0x1.0p64*highAsFloat
    ) else { return nil }
    self.init(_low: low, _high: high)
  }

  @inlinable
  public init<T>(_ source: T) where T: BinaryFloatingPoint {
    guard let value = Self(exactly: source.rounded(.towardZero)) else {
      fatalError("value cannot be converted to UInt128 because it is outside the representable range")
    }
    self = value
  }
}

// MARK: - Non-arithmetic utility conformances
extension UInt128: Equatable {
  @_transparent
  public static func ==(a: Self, b: Self) -> Bool {
    (a._high, a._low) == (b._high, b._low)
  }
}

extension UInt128: Comparable {
  @_transparent
  public static func <(a: Self, b: Self) -> Bool {
    (a._high, a._low) < (b._high, b._low)
  }
}


extension UInt128: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_low)
    hasher.combine(_high)
  }
}

extension UInt128 {
  
  public func dividingFullWidth(
    _ dividend: (high: Self, low: Self.Magnitude)
  ) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide42(
      (dividend.high.components, dividend.low.components),
      by: self.components)
    return (Self(q), Self(r))
  }
  
  public func quotientAndRemainder(
    dividingBy other: Self
  ) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide22(
      self.magnitude.components, by: other.magnitude.components)
    let quotient = Self.Magnitude(q)
    let remainder = Self.Magnitude(r)
    return (quotient, remainder)
  }
  
  /// Maximum power of the `radix` for an unsigned 64-bit UInt for base
  /// indices of 2...36
  static let _maxPowers : [Int] = [
    63, 40, 31, 27, 24, 22, 21, 20, 19, 18, 17, 17, 16, 16, 15, 15, 15, 15,
    14, 14, 14, 14, 13, 13, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12, 12, 12, 12
  ]
  
  /// Divides `x` by rⁿ where r is the `radix`. Returns the quotient,
  /// remainder, and digits
  static func _div(x:UInt128, radix:Int) -> (q:UInt128, r:UInt64, digits:Int) {
    var digits = _maxPowers[radix-2]
    let maxDivisor: UInt64
    let r: (quotient:UInt128.Magnitude, remainder:UInt128.Magnitude)
    
    // set the maximum radix power for the divisor
    switch radix {
      case  2: maxDivisor = 0x8000_0000_0000_0000
      case  4: maxDivisor = 0x4000_0000_0000_0000
      case  8: maxDivisor = 0x8000_0000_0000_0000
      case 10: maxDivisor = 10_000_000_000_000_000_000
      case 16: maxDivisor = 0x1000_0000_0000_0000
      case 32: maxDivisor = 0x1000_0000_0000_0000
      default:
        // Compute the maximum divisor for a worst-case radix of 36
        // Max radix = 36 so 36¹² = 4_738_381_338_321_616_896 < UInt64.max
        var power = radix * radix       // squared
        power *= power                  // 4th power
        power = power * power * power   // 12th power
        maxDivisor = UInt64(power)
        digits = 12
    }
    r = x.quotientAndRemainder(dividingBy: UInt128((high: 0, low: maxDivisor)))
    return (r.quotient, r.remainder._low, digits)
  }
  
  /// Converts the UInt128 `self` into a string with a given `radix`.  The
  /// radix string can use uppercase characters if `uppercase` is true.
  ///
  /// Why convert numbers in chunks?  This approach reduces the number of
  /// calls to division and modulo functions so is more efficient than a naïve
  /// digit-based approach.  Ideally this code should be in the String module.
  /// Further optimizations may be possible by using unchecked string buffers.
  internal func _description(radix:Int=10, uppercase:Bool=false) -> String {
    guard 2...36 ~= radix else { return "0" }
    if self == Self.zero { return "0" }
    var result = (q:self.magnitude, r:UInt64(0), digits:0)
    var str = ""
    while result.q != Self.zero {
      result = Self._div(x: result.q, radix: radix)
      var temp = String(result.r, radix: radix, uppercase: uppercase)
      if result.q != Self.zero {
        temp = String(repeating: "0", count: result.digits-temp.count) + temp
      }
      str = temp + str
    }
    return str
  }
}

extension UInt128 : CustomStringConvertible {
  public var description: String {
    _description(radix: 10)
  }
}

extension UInt128: CustomDebugStringConvertible {
  public var debugDescription: String {
    description
  }
}

// MARK: - Overflow-reporting arithmetic

extension UInt128 {
  public func addingReportingOverflow(_ other: Self) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideAddReportingOverflow22(self.components, other.components)
    return (Self(r), o)
  }

  public func subtractingReportingOverflow(_ other: Self) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideSubtractReportingOverflow22(self.components, other.components)
    return (Self(r), o)
  }

  @_transparent
  public func multipliedReportingOverflow(by other: Self) -> (partialValue: Self, overflow: Bool) {
    let h1 = self._high.multipliedReportingOverflow(by: other._low)
    let h2 = self._low.multipliedReportingOverflow(by: other._high)
    let h3 = h1.partialValue.addingReportingOverflow(h2.partialValue)
    let (h, l) = self._low.multipliedFullWidth(by: other._low)
    let high = h3.partialValue.addingReportingOverflow(h)
    let overflow = (
      (self._high != 0 && other._high != 0)
      || h1.overflow || h2.overflow || h3.overflow || high.overflow)
    return (Self(_low: l, _high: high.partialValue), overflow)
  }

  @_transparent
  public func dividedReportingOverflow(by other: Self) -> (partialValue: Self, overflow: Bool) {
      if other == Self.zero {
          return (self, true)
      }
    
      if Self.isSigned && other == .allSet && self == .min {
          return (self, true)
      }
      
      // Unsigned divide never overflows.
      return (quotientAndRemainder(dividingBy: other).quotient, false)
  }

  @_transparent
  public func remainderReportingOverflow(dividingBy other: Self) -> (partialValue: Self, overflow: Bool) {
      if other == Self.zero {
          return (self, true)
      }
      
      if Self.isSigned && other == .allSet && self == .min {
          return (0, true)
      }
      
      return (quotientAndRemainder(dividingBy: other).remainder, false)
  }
}

// MARK: - AdditiveArithmetic conformance

extension UInt128: AdditiveArithmetic {
  @_transparent
  public static func +(a: Self, b: Self) -> Self {
    let (result, overflow) = a.addingReportingOverflow(b)
    assert(!overflow, "arithmetic overflow")
    return result
  }

  @_transparent
  public static func -(a: Self, b: Self) -> Self {
    let (result, overflow) = a.subtractingReportingOverflow(b)
    assert(!overflow, "arithmetic overflow")
    return result
  }
}

// MARK: - Multiplication and division

extension UInt128 {
  @_transparent
  public static func *(a: Self, b: Self) -> Self {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    assert(!overflow, "arithmetic overflow")
    return result
  }

  @_transparent
  public static func *=(a: inout Self, b: Self) {
    a = a * b
  }

  @_transparent
  public static func /(a: Self, b: Self) -> Self {
    a.dividedReportingOverflow(by: b).partialValue
  }

  @_transparent
  public static func /=(a: inout Self, b: Self) {
    a = a / b
  }

  @_transparent
  public static func %(a: Self, b: Self) -> Self {
    a.remainderReportingOverflow(dividingBy: b).partialValue
  }

  @_transparent
  public static func %=(a: inout Self, b: Self) {
    a = a % b
  }
}

// MARK: - Numeric conformance
extension UInt128: Numeric {
  public typealias Magnitude = Self

  @_transparent
  public var magnitude: Self {
    self
  }
}

// MARK: - BinaryInteger conformance

extension UInt128: BinaryInteger {
  
  @frozen
  public struct Words {
    @usableFromInline
    let _value: UInt128

    @_transparent
    public init(_value: UInt128) {
      self._value = _value
    }
  }
  
  @_transparent
  public var words: Words {
    Words(_value: self)
  }

  @_transparent
  public static func &=(a: inout Self, b: Self) {
    a._low &= b._low
    a._high &= b._high
  }

  @_transparent
  public static func |=(a: inout Self, b: Self) {
    a._low |= b._low
    a._high |= b._high
  }

  @_transparent
  public static func ^=(a: inout Self, b: Self) {
    a._low ^= b._low
    a._high ^= b._high
  }

  public static func &>>=(a: inout Self, b: Self) {
    a = Self(_wideMaskedShiftRight(a.components, b._low))
  }

  public static func &<<=(a: inout Self, b: Self) {
    _wideMaskedShiftLeft(&a.components, b._low)
  }

  @_transparent
  public var trailingZeroBitCount: Int {
    _low == 0 ? 64 + _high.trailingZeroBitCount : _low.trailingZeroBitCount
  }

  @_transparent
  public var _lowWord: UInt {
    UInt(_low)
  }
}

extension UInt128.Words: RandomAccessCollection {
  
  public typealias Element = UInt
  public typealias Index = Int
  public typealias SubSequence = Slice<Self>
  public typealias Indices = Range<Int>

  @_transparent
  public var count: Int {
    128 / UInt.bitWidth
  }

  @_transparent
  public var startIndex: Int {
    0
  }

  @_transparent
  public var endIndex: Int {
    count
  }

  @_transparent
  public var indices: Indices {
    startIndex ..< endIndex
  }

  @_transparent
  public func index(after i: Int) -> Int {
    i + 1
  }

  @_transparent
  public func index(before i: Int) -> Int {
    i - 1
  }

  public subscript(position: Int) -> UInt {
    @inlinable
    get {
      precondition(position >= 0 && position < count, "Index out of bounds")
      var value = _value
#if _endian(little)
      let index = position
#else
      let index = count - 1 - position
#endif
      return _withUnprotectedUnsafePointer(to: &value) {
        $0.withMemoryRebound(to: UInt.self, capacity: count) { $0[index] }
      }
    }
  }
}

// MARK: - FixedWidthInteger conformance
extension UInt128: FixedWidthInteger, UnsignedInteger {
  @_transparent
  public static var bitWidth: Int { 128 }

  @_transparent
  public var nonzeroBitCount: Int {
    _high.nonzeroBitCount &+ _low.nonzeroBitCount
  }

  @_transparent
  public var leadingZeroBitCount: Int {
    _high == 0 ? 64 + _low.leadingZeroBitCount : _high.leadingZeroBitCount
  }

  @_transparent
  public var byteSwapped: Self {
    return Self(_low: _high.byteSwapped, _high: _low.byteSwapped)
  }
}

// MARK: - Integer comparison type inference

extension UInt128 {
    // IMPORTANT: The following four apparently unnecessary overloads of
    // comparison operations are necessary for literal comparands to be
    // inferred as the desired type.
    @_transparent @_alwaysEmitIntoClient
    public static func != (lhs: Self, rhs: Self) -> Bool {
        return !(lhs == rhs)
    }

    @_transparent @_alwaysEmitIntoClient
    public static func <= (lhs: Self, rhs: Self) -> Bool {
        return !(rhs < lhs)
    }

    @_transparent @_alwaysEmitIntoClient
    public static func >= (lhs: Self, rhs: Self) -> Bool {
        return !(lhs < rhs)
    }

    @_transparent @_alwaysEmitIntoClient
    public static func > (lhs: Self, rhs: Self) -> Bool {
        return rhs < lhs
    }
}

// MARK: - BinaryFloatingPoint Interoperability
extension BinaryFloatingPoint {
    public init(_ value: UInt128) {
        precondition(value._high == 0,
                     "Value is too large to fit into a BinaryFloatingPoint.")
        self.init(value._low)
    }

    public init?(exactly value: UInt128) {
        if value._high > 0 {
            return nil
        }
        self = Self(value._low)
    }
}

//MARK: Signed Int128
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// Modified for public use in pre-Swift 6 installations as a precursor
// to using Swift 6. Modified by Michael Griebling

// MARK: Memory layout

/// A 128-bit signed integer value type.
@frozen
public struct Int128: Sendable, Codable {
#if _endian(little)
    public var _low: UInt64
    public var _high: Int64
  #else
    public var _high: Int64
    public var _low: UInt64
#endif

    @_transparent
    public init(_low: UInt64, _high: Int64) {
        self._low = _low
        self._high = _high
    }
  
    public init(_ value: (high: Int64, low: UInt64)) {
        self._low = value.low
        self._high = value.high
    }

    public var _value: Int128 {
        @_transparent get { self }
        @_transparent set { self = Self(newValue) }
    }

    @_transparent
    public init(_ _value: Int128) {
        self = _value
    }
  

  /// Creates a new instance with the same memory representation as the given
  /// value.
  ///
  /// This initializer does not perform any range or overflow checking. The
  /// resulting instance may not have the same numeric value as
  /// `bitPattern`---it is only guaranteed to use the same pattern of bits in
  /// its binary representation.
  ///
  /// - Parameter bitPattern: A value to use as the source of the new instance's
  ///   binary representation.
  @_transparent
  public init(bitPattern: UInt128) {
    self.init(bitPattern._value)
  }
}

extension Int128 {
  public var components: (high: Int64, low: UInt64) {
    @inline(__always) get { (_high, _low) }
    @inline(__always) set { (self._high, self._low) = (newValue.high, newValue.low) }
  }
}


// MARK: - Constants

extension Int128 {
  
  @_transparent
  public static var zero: Self {
    Self(_low: 0, _high: 0)
  }

  
  @_transparent
  public static var min: Self {
    Self(_low: .zero, _high: .min)
  }

  
  @_transparent
  public static var max: Self {
    Self(_low: .max, _high: .max)
  }
}

// MARK: - Conversions from other integers

extension Int128: ExpressibleByIntegerLiteral {
  
  public typealias IntegerLiteralType = Int
  
  public init(integerLiteral value: IntegerLiteralType) {
    precondition(UInt64.bitWidth == 64, "Expecting 64-bit UInt")
    precondition(value.bitWidth <= Self.bitWidth,
                 "\(value.bitWidth)-bit literal too large for Int128")
      self.init(_low: UInt64(bitPattern: Int64(value)), _high: Int64((value < 0) ? -1 : 0))
  }

  @inlinable
  public init?<T>(exactly source: T) where T: BinaryInteger {
    guard let high = Int64(exactly: source >> 64) else { return nil }
    let low = UInt64(truncatingIfNeeded: source)
    self.init(_low: low, _high: high)
  }

  @inlinable
  public init<T>(_ source: T) where T: BinaryInteger {
    guard let value = Self(exactly: source) else {
      fatalError("value cannot be converted to Int128 because it is outside the representable range")
    }
    self = value
  }

  @inlinable
  public init<T>(clamping source: T) where T: BinaryInteger {
    guard let value = Self(exactly: source) else {
      self = source < .zero ? .min : .max
      return
    }
    self = value
  }

  @inlinable
  public init<T>(truncatingIfNeeded source: T) where T: BinaryInteger {
    let high = Int64(truncatingIfNeeded: source >> 64)
    let low = UInt64(truncatingIfNeeded: source)
    self.init(_low: low, _high: high)
  }

  @_transparent
  public init(_truncatingBits source: UInt) {
    self.init(_low: UInt64(source), _high: .zero)
  }
}

// MARK: - Conversions from Binary floating-point

extension Int128 {
  
  @inlinable
  public init?<T>(exactly source: T) where T: BinaryFloatingPoint {
    if source.magnitude < 0x1.0p64 {
      guard let magnitude = UInt64(exactly: source.magnitude) else {
        return nil
      }
      self = Int128(_low: magnitude, _high: 0)
      if source < 0 { self = -self }
    } else {
      let highAsFloat = (source * 0x1.0p-64).rounded(.down)
      guard let high = Int64(exactly: highAsFloat) else { return nil }
      // Because we already ruled out |source| < 0x1.0p64, we know that
      // high contains at least one value bit, and so Sterbenz' lemma
      // allows us to compute an exact residual:
      guard let low = UInt64(exactly: source - 0x1.0p64*highAsFloat) else {
        return nil
      }
      self.init(_low: low, _high: high)
    }
  }

  @inlinable
  public init<T>(_ source: T) where T: BinaryFloatingPoint {
    guard let value = Self(exactly: source.rounded(.towardZero)) else {
      fatalError("value cannot be converted to Int128 because it is outside the representable range")
    }
    self = value
  }
}

// MARK: - Non-arithmetic utility conformances

extension Int128: Equatable {
  @_transparent
  public static func ==(a: Self, b: Self) -> Bool {
    (a._high, a._low) == (b._high, b._low)
  }
}

extension Int128: Comparable {
  @_transparent
  public static func <(a: Self, b: Self) -> Bool {
    (a._high, a._low) < (b._high, b._low)
  }
}

extension Int128: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_low)
    hasher.combine(_high)
  }
}

extension Int128 {
  /// Converts the Int128 `self` into a string with a given `radix`.  The
  /// radix string can use uppercase characters if `uppercase` is true.
  ///
  /// Why convert numbers in chunks?  This approach reduces the number of
  /// calls to division and modulo functions so is more efficient than a naïve
  /// digit-based approach.  Ideally this code should be in the String module.
  /// Further optimizations may be possible by using unchecked string buffers.
  func _description(radix:Int=10, uppercase:Bool=false) -> String {
    let str = self.magnitude._description(radix:radix, uppercase: uppercase)
    if self < 0 {
      return "-" + str
    }
    return str
  }
}

extension Int128 : CustomStringConvertible {
  public var description: String {
    _description(radix: 10)
  }
}

extension Int128: CustomDebugStringConvertible {
  public var debugDescription: String {
    description
  }
}

// MARK: - Overflow-reporting arithmetic

extension Int128 {
  
  public func addingReportingOverflow(_ other: Self) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideAddReportingOverflow22(self.components, other.components)
    return (Self(r), o)
  }

  public func subtractingReportingOverflow(_ other: Self) -> (partialValue: Self, overflow: Bool) {
    let (r, o) = _wideSubtractReportingOverflow22(self.components, other.components)
    return (Self(r), o)
  }

  @_transparent
  public func multipliedReportingOverflow(by other: Self) -> (partialValue: Self, overflow: Bool) {
    let a = self.magnitude
    let b = other.magnitude
    let (magnitude, overflow) = a.multipliedReportingOverflow(by: b)
    if (self < 0) != (other < 0) {
      let partialValue = Self(bitPattern: 0 &- magnitude)
      return (partialValue, overflow || partialValue > 0)
    } else {
      let partialValue = Self(bitPattern: magnitude)
      return (partialValue, overflow || partialValue < 0)
    }
  }
  
  public func dividingFullWidth(
    _ dividend: (high: Self, low: Self.Magnitude)
  ) -> (quotient: Self, remainder: Self) {
    let m = _wideMagnitude22(dividend)
    let (quotient, remainder) = self.magnitude.dividingFullWidth(m)

    let isNegative = (self._high < 0) != (dividend.high._high < 0)
    let quotient_ = (isNegative
      ? (quotient == Self.min.magnitude ? Self.min : 0 - Self(quotient))
      : Self(quotient))
    let remainder_ = (dividend.high._high < 0
      ? 0 - Self(remainder)
      : Self(remainder))
    return (quotient_, remainder_)
  }
  
  // Need to use this because the runtime routine doesn't exist
  public func quotientAndRemainder( dividingBy other: Self) -> (quotient: Self, remainder: Self) {
    let (q, r) = _wideDivide22(
      self.magnitude.components, by: other.magnitude.components)
    let quotient = Self.Magnitude(q)
    let remainder = Self.Magnitude(r)
    let isNegative = (self._high < 0) != (other._high < 0)
    let quotient_ = (isNegative
      ? quotient == Self.min.magnitude ? Self.min : 0 - Self(quotient)
      : Self(quotient))
    let remainder_ = (self._high < 0)
      ? 0 - Self(remainder)
      : Self(remainder)
    return (quotient_, remainder_)
  }

  @_transparent
  public func dividedReportingOverflow(by other: Self) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (self, true)
    }
    return (quotientAndRemainder(dividingBy: other).quotient, false)
  }

  @_transparent
  public func remainderReportingOverflow(
    dividingBy other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    if other == Self.zero {
      return (self, true)
    }
    if Self.isSigned && other == -1 && self == .min {
      return (0, true)
    }
    return (quotientAndRemainder(dividingBy: other).remainder, false)
  }
}

// MARK: - AdditiveArithmetic conformance

extension Int128: AdditiveArithmetic {
  
  @_transparent
  public static func +(a: Self, b: Self) -> Self {
    let (result, overflow) = a.addingReportingOverflow(b)
    assert(!overflow, "arithmetic overflow")
    return result
  }

  @_transparent
  public static func -(a: Self, b: Self) -> Self {
    let (result, overflow) = a.subtractingReportingOverflow(b)
    assert(!overflow, "arithmetic overflow")
    return result
  }
}

// MARK: - Multiplication and division

extension Int128 {
  
  @_transparent
  public static func *(a: Self, b: Self) -> Self {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    assert(!overflow, "arithmetic overflow")
    return result
  }

  @_transparent
  public static func *=(a: inout Self, b: Self) {
    a = a * b
  }

  @_transparent
  public static func /(a: Self, b: Self) -> Self {
    a.dividedReportingOverflow(by: b).partialValue
  }

  @_transparent
  public static func /=(a: inout Self, b: Self) {
    a = a / b
  }

  @_transparent
  public static func %(a: Self, b: Self) -> Self {
    a.remainderReportingOverflow(dividingBy: b).partialValue
  }

  @_transparent
  public static func %=(a: inout Self, b: Self) {
    a = a % b
  }
}

// MARK: - Numeric conformance

extension Int128: SignedNumeric {
  
  public typealias Magnitude = UInt128

  @_transparent
  public var magnitude: Magnitude {
    let unsignedSelf = UInt128(_value)
    return self < 0 ? 0 &- unsignedSelf : unsignedSelf
  }
}

// MARK: - BinaryInteger conformance

extension Int128: BinaryInteger {
  
  public var words: UInt128.Words {
    Words(_value: UInt128(_value))
  }

  @_transparent
  public static func &=(a: inout Self, b: Self) {
    a._low &= b._low
    a._high &= b._high
  }

  
  @_transparent
  public static func |=(a: inout Self, b: Self) {
    a._low |= b._low
    a._high |= b._high
  }

  
  @_transparent
  public static func ^=(a: inout Self, b: Self) {
    a._low ^= b._low
    a._high ^= b._high
  }

  public static func &>>=(a: inout Self, b: Self) {
    _wideMaskedShiftRight(&a.components, b._low)
  }

  public static func &<<=(a: inout Self, b: Self) {
    _wideMaskedShiftLeft(&a.components, b._low)
  }

  @_transparent
  public var trailingZeroBitCount: Int {
    _low == 0 ? 64 + _high.trailingZeroBitCount : _low.trailingZeroBitCount
  }

  @_transparent
  public var _lowWord: UInt {
    UInt(_low)
  }
}

// MARK: - FixedWidthInteger conformance

extension Int128: FixedWidthInteger, SignedInteger {
  
  @_transparent
  public static var bitWidth: Int { 128 }

  @_transparent
  public var nonzeroBitCount: Int {
    _high.nonzeroBitCount &+ _low.nonzeroBitCount
  }

  @_transparent
  public var leadingZeroBitCount: Int {
    _high == 0 ? 64 + _low.leadingZeroBitCount : _high.leadingZeroBitCount
  }

  @_transparent
  public var byteSwapped: Self {
    return Self(_low: UInt64(bitPattern: _high.byteSwapped),
                _high: Int64(bitPattern: _low.byteSwapped))
  }

//  @_transparent
//  public static func &*(lhs: Self, rhs: Self) -> Self {
//    // The default &* on FixedWidthInteger calls multipliedReportingOverflow,
//    // which we want to avoid here, since the overflow check is expensive
//    // enough that we wouldn't want to inline it into most callers.
//    // Self(Builtin.mul_Int128(lhs._value, rhs._value))
//    let (high: h, low: l) = lhs.multipliedFullWidth(by: rhs)
//    return Self(_low:l, _high: h)
//  }
}

// MARK: - Integer comparison type inference

extension Int128 {
  // IMPORTANT: The following four apparently unnecessary overloads of
  // comparison operations are necessary for literal comparands to be
  // inferred as the desired type.
  @_transparent @_alwaysEmitIntoClient
  public static func != (lhs: Self, rhs: Self) -> Bool {
    return !(lhs == rhs)
  }

  @_transparent @_alwaysEmitIntoClient
  public static func <= (lhs: Self, rhs: Self) -> Bool {
    return !(rhs < lhs)
  }

  @_transparent @_alwaysEmitIntoClient
  public static func >= (lhs: Self, rhs: Self) -> Bool {
    return !(lhs < rhs)
  }

  @_transparent @_alwaysEmitIntoClient
  public static func > (lhs: Self, rhs: Self) -> Bool {
    return rhs < lhs
  }
}

// MARK: - BinaryFloatingPoint Interoperability
extension BinaryFloatingPoint {
    public init(_ value: Int128) {
        precondition(value._high == 0,
                     "Value is too large to fit into a BinaryFloatingPoint.")
        self.init(value._low)
    }

    public init?(exactly value: Int128) {
        if value._high > 0 {
            return nil
        }
        self = Self(value._low)
    }
}


//
//  Common.swift
//  UInt128
//
//  Created by Mike Griebling on 13.10.2024.
//

typealias _Wide2<F: FixedWidthInteger> =
  (high: F, low: F.Magnitude)

typealias _Wide3<F: FixedWidthInteger> =
  (high: F, mid: F.Magnitude, low: F.Magnitude)

typealias _Wide4<F: FixedWidthInteger> =
  (high: _Wide2<F>, low: (high: F.Magnitude, low: F.Magnitude))

func _wideMagnitude22<F: FixedWidthInteger>(_ v: _Wide2<F>) -> _Wide2<F.Magnitude> {
  var result = (high: F.Magnitude(truncatingIfNeeded: v.high), low: v.low)
  guard F.isSigned && v.high < 0 else { return result }
  result.high = ~result.high
  result.low = ~result.low
  return _wideAddReportingOverflow22(result, (high: 0, low: 1)).partialValue
}

func _wideAddReportingOverflow22<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: _Wide2<F>
) -> (partialValue: _Wide2<F>, overflow: Bool) {
  let (low, lowOverflow) = lhs.low.addingReportingOverflow(rhs.low)
  let (high, highOverflow) = lhs.high.addingReportingOverflow(rhs.high)
  let overflow = highOverflow || high == F.max && lowOverflow
  let result = (high: high &+ (lowOverflow ? 1 : 0), low: low)
  return (partialValue: result, overflow: overflow)
}

private func _wideAdd22<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: _Wide2<F>
) {
  let (result, overflow) = _wideAddReportingOverflow22(lhs, rhs)
  precondition(!overflow, "Overflow in +")
  lhs = result
}

func _wideAddReportingOverflow33<F: FixedWidthInteger>(
  _ lhs: _Wide3<F>, _ rhs: _Wide3<F>
) -> (
  partialValue: _Wide3<F>,
  overflow: Bool
) {
  let (low, lowOverflow) =
    _wideAddReportingOverflow22((lhs.mid, lhs.low), (rhs.mid, rhs.low))
  let (high, highOverflow) = lhs.high.addingReportingOverflow(rhs.high)
  let result = (high: high &+ (lowOverflow ? 1 : 0), mid: low.high, low: low.low)
  let overflow = highOverflow || (high == F.max && lowOverflow)
  return (partialValue: result, overflow: overflow)
}

func _wideSubtractReportingOverflow22<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: _Wide2<F>
) -> (partialValue: (high: F, low: F.Magnitude), overflow: Bool) {
  let (low, lowOverflow) = lhs.low.subtractingReportingOverflow(rhs.low)
  let (high, highOverflow) = lhs.high.subtractingReportingOverflow(rhs.high)
  let result = (high: high &- (lowOverflow ? 1 : 0), low: low)
  let overflow = highOverflow || high == F.min && lowOverflow
  return (partialValue: result, overflow: overflow)
}

private func _wideSubtract22<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: _Wide2<F>
) {
  let (result, overflow) = _wideSubtractReportingOverflow22(lhs, rhs)
  precondition(!overflow, "Overflow in -")
  lhs = result
}

private func _wideSubtractReportingOverflow33<F: FixedWidthInteger>(
  _ lhs: _Wide3<F>, _ rhs: _Wide3<F>
) -> (
  partialValue: _Wide3<F>,
  overflow: Bool
) {
  let (low, lowOverflow) =
    _wideSubtractReportingOverflow22((lhs.mid, lhs.low), (rhs.mid, rhs.low))
  let (high, highOverflow) = lhs.high.subtractingReportingOverflow(rhs.high)
  let result = (high: high &- (lowOverflow ? 1 : 0), mid: low.high, low: low.low)
  let overflow = highOverflow || (high == F.min && lowOverflow)
  return (partialValue: result, overflow: overflow)
}

func _wideMaskedShiftLeft<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: F.Magnitude
) -> _Wide2<F> {
  let bitWidth = F.bitWidth + F.Magnitude.bitWidth
  precondition(bitWidth.nonzeroBitCount == 1)

  // Mask rhs by the bit width of the wide value.
  let rhs = rhs & F.Magnitude(bitWidth &- 1)

  guard rhs < F.Magnitude.bitWidth else {
    let s = rhs &- F.Magnitude(F.Magnitude.bitWidth)
    return (high: F(truncatingIfNeeded: lhs.low &<< s), low: 0)
  }

  guard rhs != F.Magnitude.zero else { return lhs }
  var high = lhs.high &<< F(rhs)
  let rollover = F.Magnitude(F.bitWidth) &- rhs
  high |= F(truncatingIfNeeded: lhs.low &>> rollover)
  let low = lhs.low &<< rhs
  return (high, low)
}

func _wideMaskedShiftLeft<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: F.Magnitude
) {
  lhs = _wideMaskedShiftLeft(lhs, rhs)
}

func _wideMaskedShiftRight<F: FixedWidthInteger>(
  _ lhs: _Wide2<F>, _ rhs: F.Magnitude
) -> _Wide2<F> {
  let bitWidth = F.bitWidth + F.Magnitude.bitWidth
  precondition(bitWidth.nonzeroBitCount == 1)

  // Mask rhs by the bit width of the wide value.
  let rhs = rhs & F.Magnitude(bitWidth &- 1)

  guard rhs < F.bitWidth else {
    let s = F(rhs &- F.Magnitude(F.bitWidth))
    return (
      high: lhs.high < 0 ? ~0 : 0,
      low: F.Magnitude(truncatingIfNeeded: lhs.high &>> s))
  }

  guard rhs != F.zero else { return lhs }
  var low = lhs.low &>> rhs
  let rollover = F(F.bitWidth) &- F(rhs)
  low |= F.Magnitude(truncatingIfNeeded: lhs.high &<< rollover)
  let high = lhs.high &>> rhs
  return (high, low)
}

func _wideMaskedShiftRight<F: FixedWidthInteger>(
  _ lhs: inout _Wide2<F>, _ rhs: F.Magnitude
) {
  lhs = _wideMaskedShiftRight(lhs, rhs)
}

/// Returns the quotient and remainder after dividing a triple-width magnitude
/// `lhs` by a double-width magnitude `rhs`.
///
/// This operation is conceptually that described by Burnikel and Ziegler
/// (1998).
private func _wideDivide32<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide3<F>, by rhs: _Wide2<F>
) -> (quotient: F, remainder: _Wide2<F>) {
  // The following invariants are guaranteed to hold by dividingFullWidth or
  // quotientAndRemainder before this function is invoked:
  precondition(lhs.high != F.zero)
  precondition(rhs.high.leadingZeroBitCount == 0)
  precondition((high: lhs.high, low: lhs.mid) < rhs)

  // Estimate the quotient with a 2/1 division using just the top digits.
  var quotient = (lhs.high == rhs.high
    ? F.max
    : rhs.high.dividingFullWidth((high: lhs.high, low: lhs.mid)).quotient)

  // Compute quotient * rhs.
  // TODO: This could be performed more efficiently.
  let p1 = quotient.multipliedFullWidth(by: F(rhs.low))
  let p2 = quotient.multipliedFullWidth(by: rhs.high)
  let product = _wideAddReportingOverflow33(
    (high: F.zero, mid: F.Magnitude(p1.high), low: p1.low),
    (high: p2.high, mid: p2.low, low: .zero)).partialValue

  // Compute the remainder after decrementing quotient as necessary.
  var remainder = lhs

  while remainder < product {
    quotient = quotient &- 1
    remainder = _wideAddReportingOverflow33(
      remainder,
      (high: F.zero, mid: F.Magnitude(rhs.high), low: rhs.low)).partialValue
  }
  remainder = _wideSubtractReportingOverflow33(remainder, product).partialValue
  precondition(remainder.high == 0)
  return (quotient, (high: F(remainder.mid), low: remainder.low))
}

/// Returns the quotient and remainder after dividing a double-width
/// magnitude `lhs` by a double-width magnitude `rhs`.
func _wideDivide22<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide2<F>, by rhs: _Wide2<F>
) -> (quotient: _Wide2<F>, remainder: _Wide2<F>) {
  guard _fastPath(rhs > (F.zero, F.Magnitude.zero)) else {
    fatalError("Division by zero")
  }
  guard rhs < lhs else {
    if _fastPath(rhs > lhs) { return (quotient: (0, 0), remainder: lhs) }
    return (quotient: (0, 1), remainder: (0, 0))
  }

  if lhs.high == F.zero {
    let (quotient, remainder) =
      lhs.low.quotientAndRemainder(dividingBy: rhs.low)
    return ((0, quotient), (0, remainder))
  }

  if rhs.high == F.zero {
    let (x, a) = lhs.high.quotientAndRemainder(dividingBy: F(rhs.low))
    let (y, b) = (a == F.zero
      ? lhs.low.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((F.Magnitude(a), lhs.low)))
    return (quotient: (high: x, low: y), remainder: (high: 0, low: b))
  }

  // Left shift both rhs and lhs, then divide and right shift the remainder.
  let shift = F.Magnitude(rhs.high.leadingZeroBitCount)
  let rollover = F.Magnitude(F.bitWidth + F.Magnitude.bitWidth) &- shift
  let rhs = _wideMaskedShiftLeft(rhs, shift)
  let high = _wideMaskedShiftRight(lhs, rollover).low
  let lhs = _wideMaskedShiftLeft(lhs, shift)
  let (quotient, remainder) = _wideDivide32(
    (F(high), F.Magnitude(lhs.high), lhs.low), by: rhs)
  return (
    quotient: (high: 0, low: F.Magnitude(quotient)),
    remainder: _wideMaskedShiftRight(remainder, shift))
}

/// Returns the quotient and remainder after dividing a quadruple-width
/// magnitude `lhs` by a double-width magnitude `rhs`.
func _wideDivide42<F: FixedWidthInteger & UnsignedInteger>(
  _ lhs: _Wide4<F>, by rhs: _Wide2<F>
) -> (quotient: _Wide2<F>, remainder: _Wide2<F>) {
  guard _fastPath(rhs > (F.zero, F.Magnitude.zero)) else {
    fatalError("Division by zero")
  }
  guard _fastPath(rhs >= lhs.high) else {
    fatalError("Division results in an overflow")
  }

  if lhs.high == (F.zero, F.Magnitude.zero) {
    return _wideDivide22((high: F(lhs.low.high), low: lhs.low.low), by: rhs)
  }

  if rhs.high == F.zero {
    let a = F.Magnitude(lhs.high.high) % rhs.low
    let b = (a == F.Magnitude.zero
      ? lhs.high.low % rhs.low
      : rhs.low.dividingFullWidth((a, lhs.high.low)).remainder)
    let (x, c) = (b == F.Magnitude.zero
      ? lhs.low.high.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((b, lhs.low.high)))
    let (y, d) = (c == F.Magnitude.zero
      ? lhs.low.low.quotientAndRemainder(dividingBy: rhs.low)
      : rhs.low.dividingFullWidth((c, lhs.low.low)))
    return (quotient: (high: F(x), low: y), remainder: (high: 0, low: d))
  }

  // Left shift both rhs and lhs, then divide and right shift the remainder.
  let shift = F.Magnitude(rhs.high.leadingZeroBitCount)
  let rollover = F.Magnitude(F.bitWidth + F.Magnitude.bitWidth) &- shift
  let rhs = _wideMaskedShiftLeft(rhs, shift)

  let lh1 = _wideMaskedShiftLeft(lhs.high, shift)
  let lh2 = _wideMaskedShiftRight(lhs.low, rollover)
  let lhs = (
    high: (high: lh1.high | F(lh2.high), low: lh1.low | lh2.low),
    low: _wideMaskedShiftLeft(lhs.low, shift))

  if
    lhs.high.high == F.Magnitude.zero,
    (high: F(lhs.high.low), low: lhs.low.high) < rhs
  {
    let (quotient, remainder) = _wideDivide32(
      (F(lhs.high.low), lhs.low.high, lhs.low.low),
      by: rhs)
    return (
      quotient: (high: 0, low: F.Magnitude(quotient)),
      remainder: _wideMaskedShiftRight(remainder, shift))
  }
  let (x, a) = _wideDivide32(
    (lhs.high.high, lhs.high.low, lhs.low.high), by: rhs)
  let (y, b) = _wideDivide32((a.high, a.low, lhs.low.low), by: rhs)
  return (
    quotient: (high: x, low: F.Magnitude(y)),
    remainder: _wideMaskedShiftRight(b, shift))
}
