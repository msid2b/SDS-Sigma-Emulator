//
//  MSDate.swift  UPDATED: 2024-06-29
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
//

import Foundation
import CoreMedia

// Integer based immutable date object.
// The claendar is implicitly JULIAN. A date is an integer value representing the number of "ticks" since January 1, 0001AD
// A tick is one tenth of a microsecond and so the value 631,139,652,000,000,000 is midnight, January 1, 2001
// The largest possible date is: Julian day 10,675,199 = September 14, 29227
// Dates later than December 31, 9999 may not function correctly when represented in ISO8601
// Any date less than January 1, 0001 is not supported.  The year 0 is not valid.
// BC dates could be supported with negative values, but will require work

struct MSDateComponents {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int
    var tick: Int
    //    var tz: NSTimeZone
}

func formatGMTOffset (secondsFromGMT: Int) -> String {
    var m: Int = secondsFromGMT/60
    var sign: String = "+"
    if (m < 0) {
        sign = "-"
        m = -m
    }
    let h = m/60
    m = m - (h*60)
    return sign + String(format: "%02d:%02d", h, m)
}

func interpretGMTOffset (s: String) -> Int? {
    let signs = CharacterSet(charactersIn: "+-")
    let separators = CharacterSet(charactersIn: ": ")
    
    var tzhour: Int = 0
    var tzminute: Int = 0
    
    let scanner = Scanner(string: s)
    scanner.charactersToBeSkipped = CharacterSet.controlCharacters
    if let sign = scanner.scanCharacters(from: signs) {
        if scanner.scanInt(&tzhour) {
            if (tzhour > 100) {
                // This format has not HHMM separator...
                let hhmm = tzhour
                tzhour = hhmm / 100
                tzminute = hhmm - (tzhour*100)
            }
            else if !scanner.isAtEnd {
                if (scanner.scanCharacters(from: separators) == nil) { return nil }
                if !scanner.scanInt(&tzminute) { return nil }
            }
            if !scanner.isAtEnd { return nil }
            
            var offsetSeconds = ((tzhour * 60) + tzminute) * 60
            if (sign == "-") { offsetSeconds = -offsetSeconds }
            return offsetSeconds
        }
    }
    return nil
}


typealias MSTimestamp = Int64

class MSInterval: Comparable {
    // Coding required to make this different from the corresponding MSDate value
    let ticksPerSecond = MSDate.ticksPerSecond
    
    var ticks: Int64 = 0
    var days: Int { get { return Int(ticks / Int64(ticksPerSecond*86400)) }}
    var hours: Int { get { return Int(ticks / Int64(ticksPerSecond*3600)) }}
    var minutes: Int { get { return Int(ticks / Int64(ticksPerSecond*60)) }}
    var seconds: Int { get { return Int(ticks / Int64(ticksPerSecond)) }}
    
    init (_ ticks: Int64) {
        self.ticks = ticks
    }
    
    init (_ ticks: Int) {
        self.ticks = Int64(ticks)
    }
    
    init (negative: Bool = false, days: UInt = 0, hours: UInt = 0, minutes: UInt = 0, seconds: UInt = 0, ticks: UInt = 0) {
        let ts = Int64(((days*24 + hours)*60 + minutes)*60 + seconds)*Int64(ticksPerSecond) + Int64(ticks)
        self.ticks = negative ? -ts : ts
    }
    
    static func < (lhs: MSInterval, rhs: MSInterval) -> Bool {
        return (lhs.ticks < rhs.ticks)
    }
    
    static func == (lhs: MSInterval, rhs: MSInterval) -> Bool {
        return (lhs.ticks == rhs.ticks)
    }
    
    static func > (lhs: MSInterval, rhs: MSInterval) -> Bool {
        return (lhs.ticks > rhs.ticks)
    }
}


// MAC-OS has a raw  nanosecond clock (that is zeroed at boot-time?, maybe never)
// Swift has it's own Date/Time class which is a FLOAT, and therefore pretty useless.
// However, MAC-OS has obtained the date and time from some NTP server and so we can use this
// to syncronize to the raw nanosecond timer.
class MSClock {
    static let shared = MSClock()
    var systemClock: CMClock
    
    var nanoScale: Int64 = 1
    var gmt_Scale: Int64 = 100
    
    var syncClockTime: Int64 = 0
    var syncTimestamp: Int64 = 0
    var syncCount: Int = 0
    
    init () {
        systemClock = CMClockGetHostTimeClock()
        sync()
    }
    
    func sync() {
        syncCount += 1
        
        let systemTime = systemClock.time
        
        let timeScale = MSDate.ticksPerSecond64
        gmt_Scale = Int64(systemTime.timescale) / timeScale
        nanoScale = Int64(systemTime.timescale) / 1000000000
        syncClockTime = systemTime.value
        
        // Use the Date object to get the current MSDate timestamp, then calculate an offset to the syncClockTime.
        let dateNow = Date()
        let gmtReference = dateNow.timeIntervalSinceReferenceDate           // UTC, so it says.
        let gmtTimestamp = MSDate.NSDateReference*MSDate.ticksPerSecond64 + Int64(gmtReference * Double(MSDate.ticksPerSecond))  // GMT timestamp for now.
        syncTimestamp = gmtTimestamp
        
        MSLog (level: .info, "Clock syncronized (\(syncCount)): GMT: \(gmtTimestamp), DateReference: \(gmtReference), GMTscale: \(gmt_Scale), NanoScale: \(nanoScale)")
    }
    
    //MARK: Get current time.  If the timer has rolled over, re-synchronize.
    func gmtTimestamp() -> Int64 {
        let systemTime = systemClock.time
        let clockTime = systemTime.value
        if (clockTime < syncClockTime) {
            sync()
        }
        return (clockTime - syncClockTime) / gmt_Scale + syncTimestamp
    }
    
    //MARK: Raw nanoseconds can be used for timing, but watch the roll.
    func nanoSeconds(noSync: Bool = false) -> Int64 {
        let systemTime = systemClock.time
        let clockTime = systemTime.value
        return clockTime
    }
    
}

// This it the MSDate class. A 64 bit integer GMT based timstamp with 1/10 microsecond resolution.

class MSDate: NSDate, Comparable, @unchecked Sendable {
    struct YearMonthDay {
        var year: Int
        var month: Int
        var day: Int
    }
    
    enum DisplayOption {
        case subseconds
        case noTimeZone
        case gmtOffset
    }
    
    static let secondsPerDay = 86400
    static let ticksPerMicrosecond = 10
    static let ticksPerMicrosecond64: Int64 = 10
    
    static let ticksPerMillisecond = 10000
    static let ticksPerMillisecond64: Int64 = 10000
    
    static let ticksPerSecond = 10000000
    static let ticksPerSecond64: Int64 = 10000000
    
    static let ticksPerDay = secondsPerDay*ticksPerSecond
    
    static let daysPerQuadyear = 1461               // 365 * 3 + 366
    static let daysPerLeapCentury = 36525           // 1461 * 25
    static let daysPerCentury = daysPerLeapCentury-1
    static let daysPerQuadcentury = 146097          // 36524 * 3 + 36525
    
    static let daysInMonth: [Int] = [31,28,31,30,31,30,31,31,30,31,30,31]
    
    static let julianDay0 = 0
    static let julianDayMax = 10675199
    static let julianDayMin = julianDay0            // *** Change to implemnt BC dates
    
    static let GMT = TimeZone(abbreviation: "GMT")!
    static let localTimeZone = NSTimeZone.system
    
    class func isLeapYear (_ year: Int) -> Bool {
        guard ((year & 3) == 0) else { return false }
        guard year.isMultiple(of: 100) else { return true }
        guard year.isMultiple(of: 400) else { return false }
        return true
    }
    
    class func dayOfYear (_ month: Int,_ day: Int, isLeap: Bool = false) -> Int {
        // Result is 1-366.
        
        var doy = day
        var m = 1
        while (m < month) {
            doy += daysInMonth[m-1]
            if (m == 2) && (isLeap) {
                doy += 1
            }
            m += 1
        }
        
        return doy
    }
    
    class func interpretJulianDay (_ jd: Int) -> YearMonthDay {
        guard (jd >= 0) else { return (YearMonthDay(year: 0,month: 0,day: 0)) }
        
        let qc = jd / daysPerQuadcentury
        var remainingDays = jd - (qc * daysPerQuadcentury)
        
        let century = remainingDays / daysPerCentury
        remainingDays -= (century * daysPerCentury)
        
        // the preceding century calculation is 4 only for the last day of a quad century, (eg. 1600, 2000), these centuries have an extra day.
        if (century > 3) {
            return (YearMonthDay(year: (qc+1)*400, month: 12, day: 31))
        }
        
        let qy = remainingDays / daysPerQuadyear
        remainingDays -= (qy * daysPerQuadyear)
        
        let yearOfQuad = remainingDays / 365                // Last one is a leap year unless it is a non-leap century
        remainingDays -= (yearOfQuad * 365)
        
        let year = 1 + qc*400 + century*100 + qy*4 + yearOfQuad
        let (m, d) = monthAndDay(remainingDays+1, isLeap: isLeapYear(year))
        return (YearMonthDay(year: year, month: m, day: d))
    }
    
    class func calculateJulianDay (_ year: Int,_ month: Int,_ day: Int) -> Int {
        guard (year > 0) else { return 0 }
        guard (month > 0) && (month <= 12) else { return 0 }
        guard (day > 0) && (day <= 31) else { return 0 }
        
        // adjust for year 1 base
        let year0 = year - 1
        
        let quadcentury = year0 / 400
        var remainingYears = year0 - (quadcentury * 400)
        let century = remainingYears / 100
        remainingYears -= (century * 100)
        
        let quadyear = remainingYears / 4
        remainingYears -= (quadyear * 4)
        
        var jd = MSDate.dayOfYear(month, day, isLeap: MSDate.isLeapYear(year))-1
        jd += remainingYears * 365
        jd += quadyear * daysPerQuadyear
        jd += century * daysPerCentury
        jd += quadcentury * daysPerQuadcentury
        
        return jd
        
    }
    
    class func monthAndDay(_ dayOfYear: Int, isLeap: Bool) -> (month: Int,day: Int) {
        // DayOfYear is 1-366.
        var d = dayOfYear
        var m = 1
        for x in daysInMonth {
            if (d <= x) { break }
            if (m == 2) && (isLeap) {
                if (d == 29) { break }
                d -= 1
            }
            d -= x
            m += 1
        }
        return (month: m, day: d)
    }
    
    // The number of seconds between our reference (i.e. zero) time (0001-01-01) and Swift's (Jan 1, 2001)
    static let NSDateReference: Int64 = (730485 * 86400)
    
    class func secondsSinceNSDateReference(_ ts: Int64) -> Double {
        let gmtSeconds = ts / MSDate.ticksPerSecond64
        let gmtTicks = ts - (gmtSeconds * MSDate.ticksPerSecond64)
        let reference = gmtSeconds - NSDateReference
        return Double(reference) + Double(gmtTicks)/Double(MSDate.ticksPerSecond)
    }
    
    
    static func < (lhs: MSDate, rhs: MSDate) -> Bool {
        return (lhs.gmtTimestamp < rhs.gmtTimestamp)
    }
    
    static func == (lhs: MSDate, rhs: MSDate) -> Bool {
        return (lhs.gmtTimestamp == rhs.gmtTimestamp)
    }
    
    static func > (lhs: MSDate, rhs: MSDate) -> Bool {
        return (lhs.gmtTimestamp > rhs.gmtTimestamp)
    }
    
    func compare(_ other: MSDate) -> ComparisonResult {
        if (gmtTimestamp < other.gmtTimestamp) {
            return (.orderedAscending)
        }
        else if (gmtTimestamp > other.gmtTimestamp) {
            return .orderedDescending
        }
        return .orderedSame
    }
    
    private(set) var gmtTimestamp: Int64 = MSTimestamp.min
    private(set) var displayTimeZone: TimeZone
    
    var gmtSecond: Int64 { get { return gmtTimestamp / MSDate.ticksPerSecond64 }}
    var subseconds: Int { get { return Int(gmtTimestamp - (gmtSecond * MSDate.ticksPerSecond64)) }}
    var gmtJulianDay: Int { get { return calculateJulianDay(timeZone: MSDate.GMT) }}
    var julianDay: Int { get { return calculateJulianDay() }}
    var dateValue: Date { get { return convertToNSDate() as Date }}
    //var secondsSinceReference: Double { get { return convertToNSDate().timeIntervalSinceReferenceDate }}
    
    // Vars for implicitly local timezone values
    var dayOfWeek: Int { get { return calculateDayOfWeek() }}
    var dayOfYear: Int { get { return calculateDayOfYear() }}
    var year: Int { get { return components().year }}
    var midnight: MSDate { get { return settingTimeTo (hour:0, minute: 0, second: 0, subsecond: 0) }}
    var endOfDay: MSDate { get { return settingTimeTo (hour:23, minute: 59, second: 59, subsecond: MSDate.ticksPerSecond-1) }}
    var roundedToMinute: MSDate { get { return roundTo(MSDate.ticksPerSecond64*60) }}
    
    // Display strings (local time)
    var EXIFFormat: String { get { return formatEXIF() }}
    var TIFFFormat: String { get { return formatEXIF() }}
    var IPTCDateFormat: String { get { return formatIPTCDate() }}
    var IPTCTimeFormat: String { get { return formatIPTCTime() }}
    var localDisplayString: String { get { return formatForDisplay(timeZone: TimeZone.current) }}
    var displayString: String { get { return formatForDisplay(timeZone: displayTimeZone) }}
    
    // For making filenames (GMT)
    var filenameString: String { get { return formatFilenameComponent() }}
    
    
    override init() {
        displayTimeZone = MSDate.localTimeZone
        gmtTimestamp = MSClock.shared.gmtTimestamp()
        super.init()                                                            // Current LOCAL Date and Time
    }
    
    init (gmtTimestamp ts: Int64, timeZone: TimeZone = MSDate.localTimeZone) {
        displayTimeZone = timeZone
        gmtTimestamp = ts
        super.init()
    }
    
    required init?(coder: NSCoder) {
        displayTimeZone = MSDate.GMT
        super.init(coder: coder)
    }
    
    init? (julianDay: Int, timeZone: TimeZone = MSDate.localTimeZone) {
        displayTimeZone = timeZone
        guard (julianDay > MSDate.julianDayMin) && (julianDay <= MSDate.julianDayMax) else { return nil }
        gmtTimestamp = Int64(julianDay * MSDate.ticksPerDay)
        super.init()
    }
    
    init? (components c: MSDateComponents, tz: TimeZone! = MSDate.localTimeZone) {
        guard (c.year > 0) && (c.year < 200000)  else { return nil }
        guard (c.month > 0) && (c.month <= 12) else { return nil }
        guard (c.day > 0) else { return nil }
        if (c.month == 2) && (MSDate.isLeapYear(c.year)) {
            guard (c.day <= 29) else { return nil }
        }
        else {
            guard (c.day <= MSDate.daysInMonth[c.month-1]) else { return nil }
        }
        guard (c.hour >= 0) && (c.hour < 24) else { return nil }
        guard (c.minute >= 0) && (c.minute < 60) else { return nil }
        guard (c.second >= 0) && (c.second < 60) else { return nil }
        guard (c.tick >= 0) && (c.tick < MSDate.ticksPerSecond) else { return nil }
        
        let jd = MSDate.calculateJulianDay (c.year, c.month, c.day)
        var ts = Int64(jd * MSDate.ticksPerDay)
        ts += Int64((c.hour * 60 + c.minute) * 60 + c.second) * MSDate.ticksPerSecond64 + Int64(c.tick)
        
        ts -= Int64(tz.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: MSDate.secondsSinceNSDateReference(ts))) * MSDate.ticksPerSecond)
        gmtTimestamp =  ts
        displayTimeZone = tz
        super.init()
    }
    
    convenience init? (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0, tick: Int = 0, timeZone: TimeZone! = MSDate.localTimeZone) {
        let components = MSDateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second, tick: tick)
        self.init(components: components, tz: timeZone)
    }
    
    
    init (date: NSDate, timeZone: NSTimeZone! = MSDate.localTimeZone as NSTimeZone) {
        let tz = timeZone as TimeZone
        let reference = date.timeIntervalSinceReferenceDate + Double(MSDate.NSDateReference)
        let referenceSeconds = reference.rounded(.towardZero)
        let seconds = Int64(referenceSeconds)
        let ticks = Int64((reference - referenceSeconds) * Double(MSDate.ticksPerSecond))
        let ts = seconds * MSDate.ticksPerSecond64 + ticks
        
        //MARK:  ts is already GMT
        
        gmtTimestamp = ts
        displayTimeZone = tz
        super.init()
    }
    
    convenience init? (date: Date?, timeZone: TimeZone! = MSDate.localTimeZone) {
        guard (date != nil) else { return nil }
        self.init (date: date! as NSDate, timeZone: timeZone as NSTimeZone)
    }
    
    
    // MARK: This will probably handle all ISO8601 inputs
    init? (_ s: String) {
        // Handle yyyy-MM-ddXHH:mm:ss.fffffff+hh:mm or,
        //        yyyy-MM-ddXHH:mm:ss.fffffffZ
        // Colons and dashes are interchangeable.  X can be nothing, whitespace, T, comma, colon or dash
        displayTimeZone = MSDate.localTimeZone
        
        var year: Int = 0
        var month: Int = 0
        var day: Int = 0
        var hour: Int = 0
        var minute: Int = 0
        var second: Int = 0
        var fractionalSecond: Double = 0
        let separators = CharacterSet.init(charactersIn: ":-")
        let dateTimeSeparators = separators.union(CharacterSet.init(charactersIn: " ,T"))
        
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = CharacterSet.controlCharacters
        if scanner.scanInt(&year),
           scanner.scanCharacters(from: separators) != nil,
           scanner.scanInt(&month),
           scanner.scanCharacters(from: separators) != nil,
           scanner.scanInt(&day) {
            // Have the date, so validate before proceding
            guard (year > 0) && (year < 29227) else { return nil }
            guard (month > 0) && (month <= 12) else { return nil }
            guard (day > 0) else { return nil }
            if (month == 2) && (MSDate.isLeapYear(year)) {
                guard (day <= 29) else { return nil }
            }
            else {
                guard (day <= MSDate.daysInMonth[month-1]) else { return nil }
            }
            
            if scanner.scanCharacters(from: dateTimeSeparators) != nil {
                if scanner.scanInt(&hour),
                   scanner.scanCharacters(from: separators) != nil,
                   scanner.scanInt(&minute) {
                    guard (hour >= 0) && (hour < 24) else { return nil }
                    guard (minute >= 0) && (minute < 60) else { return nil }
                    
                    if scanner.scanCharacters(from: separators) != nil,
                       scanner.scanInt(&second) {
                        guard (second >= 0) && (second < 60) else { return nil }
                        
                        if scanner.scanCharacters(from: CharacterSet.init(charactersIn: ".")) != nil {
                            if let subsecond = scanner.scanCharacters(from: CharacterSet.decimalDigits) {
                                // Figure out the fraction
                                let divisor = Double(powf(10.0,Float(subsecond.count)))
                                if let fraction = Double(subsecond) {
                                    fractionalSecond = fraction / divisor
                                }
                                guard (fractionalSecond >= 0) && (fractionalSecond < 1) else { return nil }
                            }
                            else { return nil }
                        }
                    }
                    
                    // Looking for timezone information
                    // Allow whitespace here (ISO8601 doesn't)
                    _ = scanner.scanCharacters(from: .whitespaces)
                    if let remainder = scanner.scanCharacters(from: CharacterSet.alphanumerics.union(CharacterSet.init(charactersIn: "+-: []"))) {
                        if !scanner.isAtEnd { return nil }
                        
                        if (remainder == "Z") {
                            displayTimeZone = MSDate.GMT
                        }
                        else if let offset = interpretGMTOffset(s: remainder),
                                let tz = TimeZone(secondsFromGMT: offset) {
                            displayTimeZone = tz
                        }
                        else if let tz = TimeZone(abbreviation: remainder) {
                            displayTimeZone = tz
                        }
                    }
                }
                else { return nil }
            }
            else if !scanner.isAtEnd { return nil }
        }
        else { return nil }
        
        let jd = MSDate.calculateJulianDay (year, month, day)
        var ts = Int64(jd * MSDate.ticksPerDay)
        ts += Int64((hour * 60 + minute) * 60 + second) * MSDate.ticksPerSecond64 + Int64(fractionalSecond*Double(MSDate.ticksPerSecond))
        
        ts -= Int64(displayTimeZone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: MSDate.secondsSinceNSDateReference(ts))) * MSDate.ticksPerSecond)
        gmtTimestamp = ts
        super.init()
    }
    
    override init(timeIntervalSinceReferenceDate: TimeInterval) {
        displayTimeZone = MSDate.GMT
        let reference = timeIntervalSinceReferenceDate + Double(MSDate.NSDateReference)
        let gmtSeconds = Int64(reference.rounded(.towardZero))
        let gmtTicks = Int64(reference.remainder(dividingBy: 1.0) * Double(MSDate.ticksPerSecond))
        gmtTimestamp = gmtSeconds * MSDate.ticksPerSecond64 + gmtTicks
        super.init()
    }
    
    override var timeIntervalSinceReferenceDate: TimeInterval { get { return TimeInterval(MSDate.secondsSinceNSDateReference(gmtTimestamp)) }}
    
    
    private func convertToNSDate() -> NSDate {
        let interval = MSDate.secondsSinceNSDateReference(gmtTimestamp)
        return NSDate(timeIntervalSinceReferenceDate: interval)  // .addingTimeInterval(-Double(displayTimeZone.secondsFromGMT()))
    }
    
    private func roundTo (_ ticks: Int64) -> MSDate {
        var (q,r) = gmtTimestamp.quotientAndRemainder(dividingBy: ticks)
        if ((r + r) > ticks) { q += 1 }
        return MSDate(gmtTimestamp: q * ticks)
    }
    
    // Return the components of the date and time.
    // If a timezone is specified, use that to return the localized components
    // Otherwise, use the original time zone from when the MSDate object was created.
    // NOTE that this means if you want unconverted GMT values, or if you want LOCAL values, you must specify the desired timezone.
    func components (timeZone: TimeZone? = nil) -> MSDateComponents {
        let tz: TimeZone = (timeZone != nil) ? timeZone! : displayTimeZone
        let tso = Int64(tz.secondsFromGMT(for: dateValue))*MSDate.ticksPerSecond64
        let ts = gmtTimestamp + tso
        
        let julianDay = Int(ts/Int64(MSDate.ticksPerDay))
        let ticks = Int(ts - Int64(julianDay * MSDate.ticksPerDay))
        
        let ymd = MSDate.interpretJulianDay(julianDay)
        
        let seconds = ticks / MSDate.ticksPerSecond
        let t = ticks - (seconds * MSDate.ticksPerSecond)
        let minutes = seconds / 60
        let s = seconds - (minutes * 60)
        let h = minutes / 60
        let min = minutes - (h * 60)
        return (MSDateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: h, minute: min, second: s, tick: t))
    }
    
    func milliseconds() -> Int {
        let c = components()
        return (c.tick / (MSDate.ticksPerMicrosecond*1000))
    }
    
    func ISO8601Format (timeZone: TimeZone? = nil) -> String {
        let tz = timeZone != nil ? timeZone! : displayTimeZone
        let c = components(timeZone: tz)
        
        // 2022-08-23T18:22:43.123Z or, 2022-08-23T18:22:43.123+00:00
        let baseResult = String(format:"%04d-%02d-%02dT%02d:%02d:%02d.%06d",
                                c.year,c.month,c.day,c.hour,c.minute,c.second,c.tick/MSDate.ticksPerMicrosecond)
        
        let offsetSeconds = Int(tz.secondsFromGMT(for: dateValue))
        if (offsetSeconds != 0) {
            let offsetMinutes = abs(offsetSeconds) / 60
            let offsetHours = offsetMinutes / 60
            let offsetMins = offsetMinutes - (offsetHours * 60)
            let sign = (offsetSeconds < 0) ? "-" : "+"
            let offset = sign + String(format:"%02d:%02d", offsetHours, offsetMins)
            return baseResult+offset
        }
        
        return baseResult+"Z"
    }
    
    func basicDateString(_ separator: String, timeZone: TimeZone? = nil) -> String {
        let c = components(timeZone: timeZone)
        return String(format: "%04d\(separator)%02d\(separator)%02d", c.year, c.month, c.day)
    }
    
    func basicDatetimeString(_ dateSeparator: String,_ timeSeparator: String, timeZone: TimeZone? = nil) -> String {
        let c = components(timeZone: timeZone)
        return String(format: "%04d\(dateSeparator)%02d\(dateSeparator)%02d, %02d\(timeSeparator)%02d\(timeSeparator)%02d", c.year, c.month, c.day, c.hour, c.minute, c.second)
    }
    
    func msDatetimeString (_ dateSeparator: String,_ timeSeparator: String, timeZone: TimeZone? = nil) -> String {
        return basicDatetimeString (dateSeparator, timeSeparator, timeZone: timeZone) + "." + String(milliseconds())
    }
    
    func formatForDisplay (timeZone: TimeZone? = nil, options: [MSDate.DisplayOption] = []) -> String {
        let tz = timeZone != nil ? timeZone! : TimeZone.current
        let c = components(timeZone: tz)
        
        var result =  String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year, c.month, c.day, c.hour, c.minute, c.second)
        if options.contains(.subseconds) {
            result = result + String(format:".%07d", c.tick)
        }
        if !options.contains(.noTimeZone) {
            if (options.contains(.gmtOffset)) {
                result += formatGMTOffset(secondsFromGMT: tz.secondsFromGMT(for: self.dateValue))
            }
            else if let abb = tz.abbreviation(for: self.dateValue) {
                result += " " + abb
            }
            else {
                result += " " + tz.identifier
            }
        }
        return result
    }
    
    private func formatFilenameComponent() -> String {
        let c = components(timeZone: MSDate.GMT)
        return String(format: "%04d%02d%02d%02d%02d%02d", c.year, c.month, c.day, c.hour, c.minute, c.second)
    }
    
    private func formatEXIF(timeZone: TimeZone? = nil) -> String {
        let c = components(timeZone: timeZone)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year, c.month, c.day, c.hour, c.minute, c.second)
    }
    
    private func formatIPTCDate (timeZone: TimeZone? = nil) -> String {
        let c = components(timeZone: timeZone)
        return String(format: "%04d%02d%02d", c.year, c.month, c.day)
    }
    
    private func formatIPTCTime (timeZone: TimeZone? = nil) -> String {
        let c = components(timeZone: timeZone)
        return String(format: "%02d%02d%02d", c.hour, c.minute, c.second)
    }
    
    
    func calculateJulianDay(timeZone: TimeZone = MSDate.localTimeZone) -> Int {
        var ts = gmtTimestamp
        let offsetSeconds = timeZone.secondsFromGMT(for: self.dateValue)
        ts += Int64(offsetSeconds) * MSDate.ticksPerSecond64
        return Int(ts/Int64(MSDate.ticksPerDay))
    }
    
    func calculateDayOfWeek(timeZone: TimeZone! = MSDate.localTimeZone) -> Int {
        // 0: Sunday
        let julianDay = calculateJulianDay(timeZone: timeZone)
        return (julianDay-1).quotientAndRemainder(dividingBy: 7).remainder
    }
    
    func calculateDayOfYear(timeZone: TimeZone! = MSDate.localTimeZone) -> Int {
        // 1: January 1
        let c = components(timeZone: timeZone)
        return MSDate.dayOfYear(c.month, c.day, isLeap: MSDate.isLeapYear(c.year))
    }
    
    func settingTimeTo (hour: Int, minute: Int, second: Int = 0, subsecond: Int = 0, timeZone: TimeZone! = MSDate.localTimeZone) -> MSDate {
        var h = hour
        var m = minute
        var s = second
        var t = subsecond
        
        if (h < 0) || (h >= 24) { h = 0 }
        if (m < 0) || (m >= 60) { m = 0 }
        if (s < 0) || (s >= 60) { s = 0 }
        if (t < 0) || (t >= MSDate.ticksPerSecond) { t = 0 }
        
        let c = components(timeZone: timeZone)
        return MSDate(year: c.year, month: c.month, day: c.day, hour: h, minute: m, second: s, tick: t)!
    }
    
    func intervalSince (_ date: MSDate) -> MSInterval {
        return MSInterval(self.gmtTimestamp - date.gmtTimestamp)
    }
    
    func intervalUntil (_ date: MSDate) -> MSInterval {
        return MSInterval(date.gmtTimestamp - self.gmtTimestamp)
    }
    
    func addingInterval (_ interval: MSInterval) -> MSDate {
        return MSDate(gmtTimestamp: self.gmtTimestamp + interval.ticks, timeZone: displayTimeZone)
    }
    
    func adding (years: UInt = 0, months: UInt = 0) -> MSDate? {
        var c = components()
        c.month += Int(months)
        while (c.month > 12) {
            c.month -= 12
            c.year += 1
        }
        c.year += Int(years)
        return MSDate(components: c)
    }
    
    func subtracting (years: UInt = 0, months: UInt = 0) -> MSDate? {
        var c = components()
        c.month -= Int(months)
        while (c.month < 1) {
            c.month += 12
            c.year -= 1
        }
        c.year -= Int(years)
        return MSDate(components: c)
    }
    
    func adding (days: UInt = 0, hours: UInt = 0, minutes: UInt = 0, seconds: UInt = 0, ticks: UInt = 0) -> MSDate {
        let ti = Int64(((days*24 + hours)*60 + minutes)*60 + seconds)*MSDate.ticksPerSecond64 + Int64(ticks)
        return MSDate(gmtTimestamp: self.gmtTimestamp + ti, timeZone: displayTimeZone)
    }
    
    func subtracting (days: UInt = 0, hours: UInt = 0, minutes: UInt = 0, seconds: UInt = 0, ticks: UInt = 0) -> MSDate {
        let ti = Int64(((days*24 + hours)*60 + minutes)*60 + seconds)*MSDate.ticksPerSecond64 + Int64(ticks)
        return MSDate(gmtTimestamp: self.gmtTimestamp - ti, timeZone: displayTimeZone)
    }
    
}

// These tests can be invoked in debugging mode to validate basic operation.
func validateMSDate() {
    MSLog (level: .always, "Beginning MSDate Validations:" + MSDate().displayString)
    
    if let dt = MSDate (year: 2001, month: 1, day: 1, hour: 0, minute: 0) {
        MSLog (level: .info, "Reference Date \(dt.displayString): GMTTS: \(dt.gmtTimestamp), SECONDS: \(dt.gmtTimestamp/MSDate.ticksPerSecond64) GMTJD: \(dt.gmtJulianDay), JD: \(dt.julianDay)")
    }
    let dateValue = NSDate(timeIntervalSinceReferenceDate: 0)
    let dt = MSDate(date: dateValue)
    MSLog (level: .info, "Reference NSDate \(dt.displayString): GMTTS: \(dt.gmtTimestamp), SECONDS: \(dt.gmtTimestamp/MSDate.ticksPerSecond64) GMTJD: \(dt.gmtJulianDay), JD: \(dt.julianDay)")
    
    MSLog (level: .info, "Check Date 0001-01-01: " + (MSDate(year: 1, month: 1, day: 1, hour: 12, minute: 0)?.displayString ?? "nil!") )
    MSLog (level: .info, "Check Date 0400-12-31: " + (MSDate(year: 400, month: 12, day: 31, hour: 12, minute: 0)?.displayString ?? "nil!") )
    MSLog (level: .info, "Check Date 1200-02-29: " + (MSDate(year: 1200, month: 2, day: 29, hour: 12, minute: 0)?.displayString ?? "nil!") )
    MSLog (level: .info, "Check Date 1900-02-29: " + (MSDate(year: 1900, month: 2, day: 29, hour: 12, minute: 0)?.displayString ?? "nil!") )
    MSLog (level: .info, "Check Date 2000-02-29: " + (MSDate(year: 2000, month: 2, day: 29, hour: 12, minute: 0)?.displayString ?? "nil!") )
    
    
    for x in [MSDate(year: 1900, month: 12, day: 31, hour: 12, minute: 0), MSDate(year: 2000, month: 12, day: 31, hour: 12, minute: 0), MSDate(year: 2001, month: 1, day: 1, hour: 12, minute: 0)] {
        if let dt = x {
            let dc = dt.components()
            let dateValue = dt.dateValue
            MSLog (level: .info, "For: \(dt.displayString): GMTTS: \(dt.gmtTimestamp), GMTJD: \(dt.gmtJulianDay), JD: \(dt.julianDay)")
            
            let cy = Calendar.current.component(.year, from: dateValue)
            let cm = Calendar.current.component(.month, from: dateValue)
            let cd = Calendar.current.component(.day, from: dateValue)
            if (dc.year != cy) ||
                (dc.month != cm) ||
                (dc.day != cd) {
                if #available(macOS 12.0, *) {
                    MSLog (level: .always,
                           String(format: "Conversion validation for \(dt.displayString) failed: \(dateValue.formatted())"))
                } else {
                    // Fallback on earlier versions
                    MSLog (level: .always,
                           String(format: "Conversion validation for \(dt.displayString) failed: \(dateValue)"))
                    
                }
                
            }
        }
    }
    MSLog (level: .always, "Conversion validation completed")
    
    
    
    for y in 1...2050 {
        for m in 1...12 {
            let year: Int = y
            let month: Int = m
            let dt = MSDate(year: year, month: month, day: 1, hour: 1, minute: 1)
            let dc = dt!.components()
            if (dc.year != y) || (dc.month != m) || (dc.day != 1) {
                MSLog (level: .always,
                       String(format: "In/out validation for %04d-%02d failed: %04d-%02d-%02d %02d:%02d:%02d.%07d",
                              year, month, dc.year, dc.month, dc.day, dc.hour, dc.minute, dc.second, dc.tick))
            }
        }
    }
    MSLog (level: .always, "Year/Month validation completed")
    
    
    // -1 Day to accomodate being in far eastern time zones.
    MSLog (level: .always, "Maximum day: " + MSDate(julianDay: 10675198)!.displayString)
    
    let now = MSDate()
    MSLog (level: .always, "Today: " + now.displayString + ", day of week: \(now.dayOfWeek), day of year: \(now.dayOfYear)")
    
    let v = NSDate(timeIntervalSinceReferenceDate: 0)
    let w = MSDate(timeIntervalSinceReferenceDate: 0)
    MSLog (level: .always, "Comparison should be zero: \(w.compare(v as Date).rawValue)")
    
    MSLog (level: .always, "Testing input strings: ")
    let testStrings = ["2022-08-29T08:33","2022-08-29,08:33:01.1234567","2022-08-29 08:33:01.1234567-05:00", "2021-09-01 8:22:01-800", "2021-09-01 8:22 MST", "1988-01-01 12:00:00GMT"]
    for s in testStrings {
        if let d = MSDate(s) {
            MSLog (level: .always, s + ": " + d.displayString)
        }
        else {
            MSLog (level: .always, s + ": FAILED initializer")
        }
    }
    
    var syncDate = MSDate()
    MSLog (level: .always, "\(MSClock.shared.syncCount)>> Sync: " + syncDate.formatForDisplay(options: [.subseconds]) + " - " + syncDate.formatForDisplay(timeZone: MSDate.GMT))
    
    Thread.sleep(forTimeInterval: 1.0)
    syncDate = MSDate()
    MSLog (level: .always, "\(MSClock.shared.syncCount)>> 1 Second: " + syncDate.formatForDisplay(options: [.subseconds]))
    
    let systemClock = CMClockGetHostTimeClock()
    let bs = systemClock.time.value
    Thread.sleep(forTimeInterval: 0)
    let st = systemClock.time.value - bs
    MSLog (level: .always, "Thread.sleep(0) took \(st) ns.")
    
    
    //  MSLog (level: .always, "Avaiable time zones:")
    //  for (a,n) in TimeZone.abbreviationDictionary {
    //      MSLog (level: .always, a as String + " - " + n as String)
    //  }
    //    Thread.sleep(forTimeInterval: 10.0)
    //    MSLog (level: .always, "\(MSClock.shared.syncCount)>> 10 Seconds: " + MSDate().formatForDisplay(options: [.subseconds]))
    //    Thread.sleep(forTimeInterval: 30.0)
    //    MSLog (level: .always, "\(MSClock.shared.syncCount)>> 30 Seconds: " + MSDate().formatForDisplay(options: [.subseconds]))
    
}
