//
//  MiscUtils.swift
//  Siggy
//
//  Created by MS on 2023-08-22.
//

import Foundation
import Quartz


// Useful stuff.  Where should it go?
extension String {
    mutating func addToCommaSeparatedList (_ t: String) {
        self += (self == "") ? t : (", "+t)
    }
    
    func pad(_ toLength: Int,_ padChar: Character = " ") -> String {
        if (self.count < toLength) {
            return self + Array(repeating: padChar, count: toLength-count)
        }
        return self
    }
    
    //MARK: I HATE SLICES
    func substr(_ from: Int,_ length: Int = -1) -> String {
        if self.isEmpty || (from < 0) || (from >= self.count) { return "" }
        if (length == 0) { return "" }
        
        let r = self.count - from
        let n = ((length < 0) ?  r : min(r, length)) - 1
        
        let f = self.index(self.startIndex, offsetBy: from)
        let t = self.index(f, offsetBy: n)
        let s = self[f...t]
        return String(s)
    }
    
}


@inlinable func controlState (_ b: Bool) -> NSControl.StateValue {
    return b ? .on : .off
}

@inlinable func controlBool (_ control: NSButton) -> Bool {
    return (control.state == .on)
}

@inlinable func controlYN (_ control: NSButton) -> String {
    return (control.state == .on) ? "Y" : "N"
}


func asciiBytes(_ data: Data, unprintable: String = ".", noCR: Bool = false) -> String {
    var s = ""
    for b in data {
        if (b == 0x15) {
            if !(noCR) {
                s.append("\n")
            }
        }
        else if (b == 0x08) {
            s.append("    ")
        }
        else {
            s.append(printableAsciiFromEbcdic(b, UInt8(unprintable.utf8.first!)))
        }
    }
    return s
}

func asciiBytes(_ dw: UInt64, unprintable: String = ".", textc: Bool = false) -> String {
    var vdw = dw
    var data: Data = Data(bytes: &vdw, count: 8)
    if (textc) {
        let count = Int(data[0] & 0x7)
        data = data.dropFirst()
        if (count < 7) { data = data.dropLast(7-count) }        
    }
    return asciiBytes(data, unprintable: unprintable, noCR: true)
}

//MARK: ASCII / EBCDIC TRANSLATION
let e2a: [UInt8] = [
    0x00, 0x01, 0x02, 0x03, 0x04, 0x09, 0x06, 0x07, 0x08, 0x05, 0x15, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x2E, 0x3C, 0x28, 0x2B, 0x7C,
    0x26, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0x24, 0x2A, 0x29, 0x3B, 0x7E,
    0x2D, 0x2F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5E, 0x2C, 0x25, 0x5F, 0x3E, 0x3F,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A, 0x23, 0x40, 0x27, 0x3D, 0x22,
    0x00, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x5C, 0x7B, 0x7D, 0x5B, 0x5D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x7B, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x7D, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E  ]

let a2e: [UInt8] = [
    0x00, 0x01, 0x02, 0x03, 0x04, 0x09, 0x06, 0x07, 0x08, 0x05, 0x15, 0x0B, 0x0C, 0x15, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    0x40, 0x5A, 0x7F, 0x7B, 0x5B, 0x6C, 0x50, 0x7D, 0x4D, 0x5D, 0x5C, 0x4E, 0x6B, 0x60, 0x4B, 0x61,
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0x7A, 0x5E, 0x4C, 0x7E, 0x6E, 0x6F,
    0x7C, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
    0xD7, 0xD8, 0xD9, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xB4, 0xB1, 0xB5, 0x6A, 0x6D,
    0x4A, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xB2, 0x4F, 0xB3, 0x5F, 0xFF ]



func printableAsciiFromEbcdic (_ b: UInt8,_ unprintable: UInt8) -> String {
    let c = e2a[Int(b)]
    if (c < 0x20) {
        return String(cString: [unprintable,0])
    }
    return String(cString: [c,0])
}

func dottedAsciiFromEbcdic (_ b: UInt8) -> String {
    return printableAsciiFromEbcdic(b, 0x2E);
}

func ebcdicFromAscii(_ a: UInt8) -> UInt8 {
    return (a2e[Int(a & 0x7f)])
}

func asciiFromEbcdic(_ b: UInt8) -> UInt8 {
    return (e2a[Int(b)] & 0x7f)
}


//MARK: Return an array of text lines suitable for printing.
func hexDump(_ d: Data) -> [String] {
    let bCount = d.count
    let bBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bCount)
    d.copyBytes(to: bBuffer, count: bCount)

    var result: [String] = []
    var i32: Int32 = 0
    let w32 = Int32(bCount)
    while (i32 < bCount) {
        if let s = hexDumpLineC(bBuffer, i32, w32, 0, 3, 0) {
            result.append((s))
        }
        i32 += 32
    }
    
    return result
}
