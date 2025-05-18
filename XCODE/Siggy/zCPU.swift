//
//  CPU.swift
//  Siggy
//
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

//  This module implements a Σ-7 CPU.
//  It should be possible to extend this to multiple Σ-9 CPUs sharing 1024KW of memory.
//

import Foundation
import CoreMedia

let pageWordMask = 0x1ff
let pageWordMaskU = UInt(0x1ff)
let pageWordSize = pageWordMask+1
let pageByteSize = pageWordSize*4

let registerBlocks = 16
let registerBlockSize = registerBlocks*16
let registerMask = 0xFFFFFFFF

let  instructionName: [String] =
["N/E",           "N/E",            "LCFI",           "N/E",            "CAL1",           "CAL2",           "CAL3",           "CAL4",           //00-07
 "PLW",           "PSW",            "PLM",            "PSM",            "N/E",            "N/E",            "LPSD",           "XPSD",           //08-0F
 "AD",            "CD",             "LD",             "MSP",            "N/E",            "STD",            "N/E",            "N/E",            //10-17
 "SD",            "CLM",            "LCD",            "LAD",            "FSL",            "FAL",            "FDL",            "FML",            //18-1F
 "AI",            "CI",             "LI",             "MI",             "SF",             "S",              "N/E",            "N/E",            //20-27
 "CVS",           "CVA",            "LM",             "STM",            "N/E",            "N/E",            "WAIT",           "LRP",            //28-2F
 "AW",            "CW",             "LW",             "MTW",            "N/E",            "STW",            "DW",             "MW",             //30-37
 "SW",            "CLR",            "LCW",            "LAW",            "FSS",            "FAS",            "FDS",            "FMS",            //38-3F
 "TTBS",          "TBS",            "N/E",            "N/E",            "ANLZ",           "CS",             "XW",             "STS",            //40-47
 "EOR",           "OR",             "LS",             "AND",            "SIO",            "TIO",            "TDV",            "HIO",            //48-4F
 "AH",            "CH",             "LH",             "MTH",            "N/E",            "STH",            "DH",             "MH",             //50-57
 "SH",            "N/E",            "LCH",            "LAH",            "N/E",            "N/E",            "N/E",            "N/E",            //58-5F
 "CBS",           "MBS",            "N/E",            "EBS",            "BDR",            "BIR",            "AWM",            "EXU",            //60-67
 "BCR",           "BCS",            "BAL",            "INT",            "RD",             "WD",             "AIO",            "MMC",            //68-6F
 "LCF",           "CB",             "LB",             "MTB",            "STCF",           "STB",            "PACK",           "UNPK",           //70-77
 "DS",            "DA",             "DD",             "DM",             "DSA",            "DC",             "DL",             "DST"]            //78-7F


// *********************************************** Instruction Class ****************************************************
// It might be interesting to do instruction execution in this class with a heirarchy of objects, howeverf this is not
// what this does.  This class is used really to provide easy access to the various parts of an instruction word for the
// CPU.
// It also supplies a method to create printable disassembled instruction text
class Instruction: Any {
    var value: UInt32
    var indirect: Bool { get { return (value & 0x80000000) != 0 }}
    var opCode: Int { get { return Int((value & 0x7f000000) >> 24) } set { replaceOpCode(newValue)}}
    var register: UInt4 { get { return UInt4((value & 0x00f00000) >> 20) }}
    var delta: Int8 { get { return Int8(bitPattern: UInt8((value & 0x00f00000) >> 16)) >> 4 }}
    var index: UInt4 { get { return UInt4((value & 0x000e0000) >> 17) }}
    var reference: Int { get { return Int(value & 0x0001ffff) }}
    var signedDisplacement: Int32 { get { return getSignedDisplacement() }}
    var unsignedDisplacement: UInt32 { get { return getUnsignedDisplacement() }}
    var extendedDisplacement: UInt32 { get { return getExtendedDisplacement() }}

    func getSignedDisplacement() -> Int32 {
        let value = self.value & 0xfffff
        if (value & 0x80000) == 0 {
            return Int32(value)
        }
        return (-Int32((value ^ 0xfffff)+1))
    }
    
    func getUnsignedDisplacement() -> UInt32 {
        return UInt32(self.value & 0xfffff)
    }
    
    func getExtendedDisplacement() -> UInt32 {
        let value = self.value & 0xfffff
        if (value & 0x80000) == 0 {
            return UInt32(value)
        }
        return (UInt32 (value | 0xfff00000)) // EXTEND SIGN
    }
    
    var isImmediate: Bool { get { return (opCode < 0x4) || ((opCode >= 0x20) && (opCode <= 0x23)) || ((opCode >= 0x40) && (opCode <= 0x43)) || ((opCode >= 0x60) && (opCode <= 0x63)) }}
    var isModifyAndTest: Bool { get { return [0x33, 0x53, 0x73].contains(opCode) }}
    var isShift: Bool { get { return opCode == 0x25 }}
    
    func getDisplayText(blankZero: Bool = false, pad: Bool = true) -> String {
        // Modifiers for BCR (68)
        func bcrText (_ r: UInt4) -> String {
            var mod = ""
            switch (r) {
            case 0: break
            case 1: mod = "GEz"
            case 2: mod = "LEz"
            case 3: mod = "Ez"
            case 4: mod = "AZ"
            default:
                mod = "CR,\(r)"
            }
            return mod
        }
        
        // Modifiers for BCS (69)
        func bcsText (_ r: UInt4) -> String {
            var mod = ""
            switch (r) {
            case 0: mod = "NEVER"
            case 1: mod = "Lz"
            case 2: mod = "Gz"
            case 3: mod = "NEz"
            case 4: mod = "ANZ"
            default:
                mod = "CS,\(r)"
            }
            return mod
        }
        
        
        if (instructionName[opCode] != "N/E") {
            if isImmediate {
                let iName = instructionName[opCode] + ",\(register)  "
                let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                return iName + iTab + "." + String(format:"%X", signedDisplacement) +  (indirect ? "*??" : "")
            }
            else if (isShift) {
                let shiftType = (reference & 0x700) >> 8
                let shiftMask = (reference & 0x7F)
                let shiftCount = (shiftMask > 0x3F) ? -Int(0x80 - shiftMask) : Int(shiftMask)
                var iName = "S"
                if (!indirect) {
                    switch (shiftType) {
                    case 0: // Logical, single register.
                        iName = "SLS,\(register)  "
                        break
                        
                    case 1: // Logical, double register.
                        iName = "SLD,\(register)  "
                        break
                        
                    case 2: // Circular, single
                        iName = "SCS,\(register)  "
                        break;
                        
                    case 3: // Circular, double
                        iName = "SCD,\(register)  "
                        break;
                        
                    case 4: // Arithmetic, single
                        iName = "SAS,\(register)  "
                        break;
                        
                    case 5: // Arithmetic, double
                        iName = "SAD,\(register)  "
                        break
                        
                    default:
                        iName += ":"+hexOut(shiftType,width: 2)
                        break
                    }
                    
                    let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                    return iName + iTab + "." + String(format:"%X", shiftCount) + ((index > 0) ? ",\(index)" : "")
                }
                else {
                    let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                    return iName + iTab + "*" + String(format:"%X", reference) + ((index > 0) ? ",\(index)" : "")
                }
            }
            else if (opCode == 0x68) {
                let iName = "B"+bcrText(register)
                let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                return iName + iTab + (indirect ? "*" : ".") + String(format:"%X", reference) + ((index > 0) ? ",\(index)" : "")
            }
            else if (opCode == 0x69) {
                let iName = "B"+bcsText(register)
                let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                return iName + iTab + (indirect ? "*" : ".") + String(format:"%X", reference) + ((index > 0) ? ",\(index)" : "")
            }
            else {
                let rOrDelta = isModifyAndTest ? delta : Int8(register)
                let iName = instructionName[opCode] + ",\(rOrDelta)"
                let iTab = pad ? String(repeating: " ", count: 10-min(iName.count,10)) : " "
                return iName + iTab + (indirect ? "*" : ".") + String(format:"%X", reference) + ((index > 0) ? ",\(index)" : "")
            }
        }
        
        if (opCode == 0) && (blankZero) {
            return ""
        }
        
        return "DATA      ."+String(format:"%08X",value)
    }
    
    func replaceOpCode(_ opCode: Int) {
        value = UInt32((opCode & 0xFF) << 24) | (value & 0x00FFFFFF)
    }
    
    
    init (_ rawValue: UInt32) {
        self.value = rawValue
    }
    
    init? (_ text: String) {
        if let v = hexIn(hex: text) {
            self.value = UInt32(v & 0xFFFFFFFF)
            return
        }
        
        // PARSE an instruction.  Works for most.
        // TODO: Deal with Shifts 
        var op = ""
        var r = 0
        var x = 0
        var i = false
        var ad = ""
        var ps = 0
        for c in text {
            switch (ps) {
            case 0:
                if (c.isLetter) || (c.isNumber) { op += String(c) }
                else if (c == ",") { ps = 1 }
                else if (c.isWhitespace) {
                    ps = 2
                    switch(op.uppercased()) {
                    case "B":       op = "BCR"
                    case "BGE":     op = "BCR"; r = 1
                    case "BL":      op = "BCS"; r = 1
                    case "BLE":     op = "BCR"; r = 2
                    case "BG":      op = "BCS"; r = 2
                    case "BE":      op = "BCR"; r = 3
                    case "BNE":     op = "BCS"; r = 3
                    case "BAZ":     op = "BCR"; r = 4
                    case "BANZ":    op = "BCS"; r = 4
                    default: break
                    }
                }
                else { return nil }
                
            case 1:
                if (c.isNumber), let a = c.asciiValue { r = r * 10 + Int(a-0x30) }
                else if (c.isWhitespace) { ps = 2 }
                else { return nil }
                
            case 2:
                if (c == "*") { i = true }
                else if (c == ",") { ps = 3 }
                else if (c.isHexDigit) { ad += String(c) }
                
            case 3:
                if (c.isNumber), let a = c.asciiValue { x = x * 10 + Int(a-0x30) }
                else if (c.isWhitespace) { ps = 4 }
                else { return nil }
                
            case 4:
                if (!c.isWhitespace) { return nil }
                
            default: break
            }
        }
        
        
        if let opCode = instructionName.firstIndex(of: op.uppercased()),
           let a = hexIn(hex: ad, emptyResult: 0),
           (r <= 15),
           (x <= 7) {
            
            let v = (i ? 0x80000000 : 0) | (Int(opCode) << 24) | (r << 20) | (x << 17) | a
            self.value = UInt32(v & 0xFFFFFFFF)
            return
        }
        return nil
    }
}

// *********************************************** Memory Class ****************************************************
// Implements the real memory. Each page is protected by a semaphore mutex so that IO and CPU threads 
// can work as independently as possible.
// This class handles the write-lock mechanism

class Memory: Any {
    // Emulated "Real" i.e. non-virtual memory page
    struct Page {
        var access: SimpleMutex
        var writeLock: UInt8
        var bytes: UnsafeMutableRawPointer
    }
    
    // Access is controlled at a page level.  This allows the CPU and IO devices to be modifying different pages concurrently.
    private var realPages: [Page?] = []
    private var maxPages: Int
    private var realPageMask: Int
    let pageOffsetMask = 0x7FF
    var maxRealPages: Int { get { return maxPages }}
    
    func writeLock(forAddress: Int) -> UInt8 {
        let px = Int(forAddress >> 11) & realPageMask
        
        if let page = realPages[px] {
            //MARK: Writelocks are only applicable to the lower 128KW
            return (px <= 0x0ff) ? page.writeLock : 0
        }
        return 0xff
    }
    
    @inlinable public func load<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
        let px = Int(offset >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        let result = page.bytes.load(fromByteOffset: (offset & pageOffsetMask), as: type)
        page.access.release()
        return result
    }
    
    @inlinable public func storeBytes<T>(of value: T, toByteOffset offset: Int = 0, as type: T.Type) {
        let px = Int(offset >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        page.bytes.storeBytes (of: value, toByteOffset: (offset & pageOffsetMask), as: type)
        page.access.release()
    }
    
    // Atomic Exchange
    public func exchangeRawWord (ba: Int,_ w: UInt32) -> UInt32 {
        let pbo = ba & pageOffsetMask
        let px = Int(ba >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        
        let v = page.bytes.load(fromByteOffset: pbo, as: UInt32.self)
        page.bytes.storeBytes (of: w, toByteOffset: pbo, as: UInt32.self)
        
        page.access.release()
        return v
    }
    

    // Slow, but atomic, modify operations: return (result, overflow, carry)
    public func atomicModifyByte(by delta: UInt8, atByteOffset offset: Int = 0) -> (UInt8, Bool, Bool) {
        let pbo = offset & pageOffsetMask
        let px = Int(offset >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        
        let v = page.bytes.load(fromByteOffset: pbo, as: UInt8.self)
        let (sv, carry) = v.addingReportingOverflow(delta)
        
        page.bytes.storeBytes (of: sv, toByteOffset: pbo, as: UInt8.self)
        page.access.release()
        return (sv, false, carry)
    }
    
    public func atomicModifyHalf(by value: Int8, atByteOffset offset: Int = 0) -> (Int16, Bool, Bool) {
        let pbo = offset & pageOffsetMask
        let px = Int(offset >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        
        let mv = (value >= 0) ? UInt16(value) : (value > Int16.min) ? (UInt16(-value).twosComplement) : 0x8000
        let v = page.bytes.load(fromByteOffset: pbo, as: UInt16.self).bigEndian
        let (sv, carry) = v.addingReportingOverflow(mv)
        page.bytes.storeBytes (of: sv.bigEndian, toByteOffset: pbo, as: UInt16.self)
        
        page.access.release()
        let op = (value > 0) && (v <= 0x7FFF) && ((sv & 0x8000) != 0)
        let on = (value < 0) && (v > 0x7FFF) && ((sv & 0x8000) == 0)
        
        return (Int16(bitPattern: sv), op || on , carry)
    }
    
    public func atomicModifyWord(by value: Int32, atByteOffset offset: Int = 0) -> (Int32, Bool, Bool) {
        let pbo = offset & pageOffsetMask
        let px = Int(offset >> 11) & realPageMask
        let page = realPages[px]!
        page.access.acquire()
        
        let mv = (value >= 0) ? UInt32(value) : (value > Int32.min) ? (UInt32(-value).twosComplement) : 0x80000000
        let v = page.bytes.load(fromByteOffset: pbo, as: UInt32.self).bigEndian
        let (sv, carry) = v.addingReportingOverflow(mv)
        page.bytes.storeBytes (of: sv.bigEndian, toByteOffset: pbo, as: UInt32.self)
        
        page.access.release()
        let op = (value > 0) && (v <= 0x7FFFFFFF) && ((sv & 0x80000000) != 0)
        let on = (value < 0) && (v > 0x7FFFFFFF) && ((sv & 0x80000000) == 0)
        
        return (Int32(bitPattern: sv), op || on , carry)
    }
    
    
    init (pages: Int) {
        maxPages = pages
        realPageMask = maxPages-1
        
        realPages = Array(repeating: nil, count: maxPages)
        for i in 0 ... maxPages-1 {
            realPages[i] = Page(access: SimpleMutex(), writeLock: 0, bytes: UnsafeMutableRawPointer.allocate(byteCount: pageByteSize, alignment: 8))
        }
    }
    
    func clear() {
        for p in realPages {
            p?.bytes.initializeMemory(as: UInt64.self, repeating: 0, count: pageByteSize >> 3)
        }
    }
    
    // Load a word full of write locks (16 per word)
    func setWriteLocks (word: UInt32, startPage: UInt) {
        var w = word
        var c = UInt(16)
        var p = Int(startPage + c) & pageWordMask
        
        //machine.log(level: .debug, "Setting Locks Word:"+hexOut(word)+",SP="+hexOut(startPage)+",C="+hexOut(c))
        while (c > 0) {
            c -= 1
            p = (p == 0) ? pageWordMask : (p - 1)
            realPages[p]?.writeLock = UInt8(w & 0x3)
            
            //machine.log(level: .debug, "Page "+hexOut(p)+": Lock "+hexOut(zWriteLock[p]))
            w >>= 2
        }
    }
    
    
    func loadByte (_ address: Int) -> UInt8 {
        return load(fromByteOffset: address, as: UInt8.self)
    }
    
    func loadHalf (_ address: Int) -> Int16 {
        return load(fromByteOffset: address, as: Int16.self).bigEndian
    }
    
    func loadWord (_ address: Int) -> Int32 {
        return load(fromByteOffset: address, as: Int32.self).bigEndian
    }
    
    func loadWord (word: Int) -> Int32 {
        return load(fromByteOffset: word << 2, as: Int32.self).bigEndian
    }
    
    func loadUnsignedWord (word: Int) -> UInt32 {
        return load(fromByteOffset: word << 2, as: UInt32.self).bigEndian
    }
    
    func loadRawWord (word: Int) -> UInt32 {
        return load(fromByteOffset: word << 2, as: UInt32.self)
    }
    
    func loadRawWord (_ address: Int) -> UInt32 {
        return load(fromByteOffset: address, as: UInt32.self)
    }
    
    func loadDoubleWord (_ address: Int) -> Int64 {
        return load(fromByteOffset: address, as: Int64.self).bigEndian
    }
    
    func loadUnsignedDoubleWord (_ address: Int) -> UInt64 {
        return load(fromByteOffset: address, as: UInt64.self).bigEndian
    }
    
    func loadUnsignedRawDoubleWord (_ address: Int) -> UInt64 {
        return load(fromByteOffset: address, as: UInt64.self)
    }
    
    
    func storeByte (_ address: Int,_ value: UInt8) {
        storeBytes(of: value, toByteOffset: address, as: UInt8.self)
    }
    
    func storeHalf (_ address: Int,_ value:  Int16) {
        storeBytes(of: value.bigEndian, toByteOffset: address, as: Int16.self)
    }
    
    func storeWord (_ address: Int,_ value:  Int32) {
        storeBytes(of: value.bigEndian, toByteOffset: address, as: Int32.self)
    }
    
    func storeWord (word: Int,_ value:  Int32) {
        storeBytes(of: value.bigEndian, toByteOffset: word << 2, as: Int32.self)
    }
    
    func storeRawWord (word: Int,unsigned:  UInt32) {
        storeBytes(of: unsigned, toByteOffset: word << 2, as: UInt32.self)
    }
    
    func storeRawWord (_ address: Int,unsigned: UInt32) {
        storeBytes(of: unsigned, toByteOffset: address, as: UInt32.self)
    }
    
    func storeWord (word: Int,unsigned: UInt32) {
        storeBytes(of: unsigned.bigEndian, toByteOffset: word << 2, as: UInt32.self)
    }
    
    func storeDoubleWord (_ address: Int,_ value: Int64) {
        storeBytes(of: value.bigEndian, toByteOffset: address, as: Int64.self)
    }
    
    func storeDoubleWord (word: Int,_ unsigned: UInt64) {
        storeBytes(of: unsigned.bigEndian, toByteOffset: word << 2, as: UInt64.self)
    }
    
    func copyWord (fromWordAddress: Int, toWordAddress: Int) {
        let a = fromWordAddress << 2
        let w = load(fromByteOffset: a, as: UInt32.self)
        let d = toWordAddress << 2
        storeBytes(of: w, toByteOffset: d, as: UInt32.self)
    }
    
    // MARK: moveData is used by devices to do input operations.
    func moveData (from data: Data, to address: Int, maximum length: Int = 0) {
        var count = (length > 0) ? min(data.count, length) : data.count
        let d = data as NSData
        var dx = 0
        
        var px = address >> 11
        var offset = address & 0x7FF
        
        while (count > 0) {
            let page = realPages[px]!
            page.access.acquire()
            
            var n = min(count, pageByteSize - offset)
            count -= n
            
            if (offset > 0) {
                // TODO: There must be an easier way
                // Move n bytes to page[offset] from data[dx]
                while (n > 0) {
                    page.bytes.storeBytes (of: d[dx], toByteOffset: offset, as: UInt8.self)
                    dx += 1
                    offset += 1
                    n -= 1
                }
            }
            else {
                // Faster when starting at beginning of page.
                page.bytes.copyMemory(from: d.bytes+dx, byteCount: n)
                dx += n
            }
            
            page.access.release()
            
            // Set up for next pagefull
            px += 1
            offset = 0
        }
        
    }
    
    // MARK: getData is used by devices for output operations.
    func getData (from address: Int, count: Int) -> Data {
        var px = address >> 11
        var offset = address & 0x7FF
        
        var remaining = count
        let data = NSMutableData()
        
        while (remaining > 0) {
            let page = realPages[px]!
            page.access.acquire()
            let n = min(remaining, pageByteSize - offset)
            let chunk = Data(bytes: page.bytes.advanced(by: offset), count: n)
            data.append(chunk)
            page.access.release()
            
            // Set up for next pagefull
            remaining -= n
            px += 1
            offset = 0
        }
        
        return (data as Data)
    }
    
    
}


// *********************************************** VirtualMemory Class ****************************************************
// Each CPU uses a virtual memory object to allow for it's own map.
// Every Virtual memory object refers to the common real memory object
class VirtualMemory {
    enum AccessMode: Int {
        case none = 3
        case read = 2
        case execute = 1
        case write = 0
    }
    
    private var cpu: CPU!
    
    private var realMemory: Memory!
    private var maxRealPages: Int
    private var validAddressMask: UInt32
    private var invalidAddressMask: UInt32
    var realPages: Int { get { return maxRealPages }}
    
    private var maxVirtualPages: Int
    var virtualPages: Int { get { return maxVirtualPages }}
    
    private var zMemoryMap: UnsafeMutablePointer<UInt16>
    private var zAccessControl: UnsafeMutablePointer<UInt8>
    
    func map (virtualPage: Int) -> UInt16 {
        return zMemoryMap[virtualPage]
    }
    
    func access (virtualPage: Int) -> UInt8 {
        return zAccessControl[virtualPage]
    }
    
    
    init (realMemory: Memory, maxVirtualPages: Int, cpu: CPU!) {
        self.cpu = cpu
        self.realMemory = realMemory
        self.maxRealPages = realMemory.maxRealPages
        self.validAddressMask = UInt32((maxRealPages << 11) - 1)
        self.invalidAddressMask = self.validAddressMask ^ 0xFFFFFFFF
        self.maxVirtualPages = maxVirtualPages
        
        // Virtual and real memory sizes cna be different
        zMemoryMap = UnsafeMutablePointer<UInt16>.allocate(capacity: maxVirtualPages)
        zMemoryMap.initialize(repeating: 0, count: maxVirtualPages)
        
        // Set up map
        zAccessControl = UnsafeMutablePointer<UInt8>.allocate(capacity: maxVirtualPages)
        zAccessControl.initialize(repeating: 0, count: maxVirtualPages)
    }
    
    func clear() {
        realMemory.clear()
    }
    
    
    // load a word full of page maps (4 per word)
    func setMap (word: UInt32, startPage: UInt) {
        var w = word
        var c = UInt(4)
        var p = Int(startPage + c) & pageWordMask
        
        //machine.log(level: .debug, "Setting Map Word:"+hexOut(word)+",SP="+hexOut(startPage)+",C="+hexOut(c))
        while (c > 0) {
            c -= 1
            p = (p == 0) ? pageWordMask : (p - 1)
            zMemoryMap[p] = UInt16(w & 0xFF)
            
            //machine.log(level: .debug, "Virtual page "+hexOut(p)+": real "+hexOut(zMemoryMap[p]))
            
            w >>= 8
        }
    }
    
    // load a word full of wide page maps (2 per word)
    func setMapWide (word: UInt32, startPage: UInt) {
        var w = word
        var c = UInt(2)
        var p = Int(startPage + c) & pageWordMask
        
        //machine.log(level: .debug, "Setting Map Wide:"+hexOut(word)+",SP="+hexOut(startPage)+",C="+hexOut(c))
        while (c > 0) {
            c -= 1
            p = (p == 0) ? pageWordMask : (p - 1)
            zMemoryMap[p] = UInt16(w & 0x1FFF)
            
            //machine.log(level: .debug, "Virtual page "+hexOut(p)+": real "+hexOut(zMemoryMap[p]))
            w >>= 16
        }
    }
    
    // load a word full of access controls (16 per word)
    func setAccess (word: UInt32, startPage: UInt) {
        var w = word
        var c = UInt(16)
        var p = Int(startPage + c) & pageWordMask
        
        //machine.log(level: .debug, "Setting Access Word:"+hexOut(word)+",SP="+hexOut(startPage)+",C="+hexOut(c))
        while (c > 0) {
            c -= 1
            p = (p == 0) ? pageWordMask : (p - 1)
            zAccessControl[p] = UInt8(w & 0x3)
            
            //machine.log(level: .debug, "Page "+hexOut(p)+": access "+hexOut(zAccessControl[p]))
            
            w >>= 2
        }
    }
    
    
    func mapWord (_ virtualAddress: UInt32,_ accessMode: AccessMode,_ master: Bool) -> (Bool, UInt32) {
        guard (virtualAddress > 0xf) else { return (false, virtualAddress) }
        
        let virtualPage = Int((virtualAddress & 0x1fe00) >> 9)
        
        // If not master, check acccess
        if (!master) {
            let ac = zAccessControl[virtualPage] & 0x3
            if (accessMode.rawValue < ac) {
                return (true, virtualAddress)
            }
        }
        
        let realPage = Int(zMemoryMap[virtualPage])
        let realAddress = (UInt32(realPage) << 9) | (virtualAddress & 0x1ff)
        
        return (false, realAddress)
    }
    
    // Used by LRA
    func mapDoubleWordAddress (_ virtualAddress: Int) -> (Int, Bool, UInt8, UInt8) {
        let virtualPage = (virtualAddress >> 8) & 0xFF
        let ac = zAccessControl[virtualPage] & 0x3
        
        let realPage = Int(zMemoryMap[virtualPage])
        let realAddress = (realPage << 8) | (virtualAddress & 0xFF)
        
        return (realAddress, (realPage < realMemory.maxRealPages), realMemory.writeLock(forAddress: realAddress), ac)
    }
    
    // This returns a real byte address, suitable for accessing the appropriate real page directly.
    // It handles real extended addressing mode for the S9
    // No alignment check is made
    func realAddress (ba: Int,_ accessMode: AccessMode) -> (Bool, Int) {
        var isCPU = false
        if (Thread.current == cpu) {
            isCPU = true
        }
        
        
        var a = UInt32(ba)
        if (cpu.psd.zMapped) {
            let wa = (a >> 2) & 0x1FFFF
            if isCPU {
                cpu.checkDataBreakpoint(wa, true, accessMode)
            }
            let (t, w) = mapWord(wa, accessMode, cpu.psd.zMaster)
            if isCPU, t {
                cpu.trap(addr: 0x40, ccMask: 1)         // SET CC4
                return (true, 0)
            }
            
            a = (w << 2) | (a & 0x3)
        }
        else if (cpu.psd.zMA) {
            if ((a & 0x40000) != 0) {
                a = (a & 0x3FFFF) | (UInt32(cpu.psd.zExtension) << 18)
            }
        }
                
        // MARK: Did we just run off the end of memory?
        if isCPU, ((a & invalidAddressMask) != 0) {
            cpu.trap(addr: 0x40, ccMask: 1)             // SET CC4
            return (true, 0)
        }
        
        
        if isCPU {
            // MARK: CHECK FOR UNMAPPED DATA BREAK
            cpu.checkDataBreakpoint(a >> 2, false, accessMode)
            
            if (accessMode == .write) {
                let writeLock = realMemory.writeLock(forAddress: Int(a))
                let writeKey = cpu.psd.zWriteKey
                if (writeLock != 0) && (writeKey != 0) && (writeLock != writeKey) {
                    cpu.trap(addr: 0x40, ccMask: 1)         // SET CC4
                    return (true, 0)
                }
            }
        }
        return (false, Int(a))
    }
    
    
    func loadByte (ba: Int) -> UInt8 {
        let (t, a) = realAddress(ba: ba, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: UInt8.self)
    }
    
    func loadHalf (ha: Int) -> Int16 {
        let (t, a) = realAddress(ba: ha << 1, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: Int16.self).bigEndian
    }
    
    func loadWord (wa: Int) -> Int32 {
        let (t, a) = realAddress(ba: wa << 2, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: Int32.self).bigEndian
    }
    
    func loadUnsignedWord (wa: Int) -> UInt32 {
        let (t, a) = realAddress(ba: wa << 2, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: UInt32.self).bigEndian
    }
    
    func loadRawWord (wa: Int) -> UInt32 {
        let (t, a) = realAddress(ba: wa << 2, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: UInt32.self)
    }
    
    func loadAndSetRawWord (wa: Int) -> UInt32 {
        let (t, a) = realAddress(ba: wa << 2, .read)
        if (t) { return 0 }
        let r = realMemory.load(fromByteOffset: a, as: UInt32.self)
        realMemory.storeByte(a, UInt8(r & 0x7F) | 0x80)
        return r
    }
    
    func loadDoubleWord (da: Int) -> Int64 {
        let (t, a) = realAddress(ba: da << 3, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: Int64.self).bigEndian
    }
    
    func loadUnsignedDoubleWord (da: Int) -> UInt64 {
        let (t, a) = realAddress(ba: da << 3, .read)
        if (t) { return 0 }
        return realMemory.load(fromByteOffset: a, as: UInt64.self).bigEndian
    }
    
    
    func storeByte (ba: Int,_ value: UInt8) {
        let (t, a) = realAddress(ba: ba, .write)
        if (!t) {
            realMemory.storeBytes(of: value, toByteOffset: a, as: UInt8.self)
        }
    }
    
    func storeHalf (ha: Int,_ value: Int16) {
        let (t, a) = realAddress(ba: ha << 1, .write)
        if (!t) {
            realMemory.storeBytes(of: value.bigEndian, toByteOffset: a, as: Int16.self)
        }
    }
    
    func storeHalf (ha: Int,unsigned: UInt16) {
        let (t, a) = realAddress(ba: ha << 1, .write)
        if (!t) {
            realMemory.storeBytes(of: unsigned.bigEndian, toByteOffset: a, as: UInt16.self)
        }
    }
    
    func storeRawWord (wa: Int,unsigned: UInt32) {
        let (t, a) = realAddress(ba: wa << 2, .write)
        if (!t) {
            realMemory.storeBytes(of: unsigned, toByteOffset: a, as: UInt32.self)
        }
    }
    
    func storeWord (wa: Int,_ value: Int32) {
        let (t, a) = realAddress(ba: wa << 2, .write)
        if (!t) {
            realMemory.storeBytes(of: value.bigEndian, toByteOffset: a, as: Int32.self)
        }
    }
    
    func storeWord (wa: Int,unsigned: UInt32) {
        let (t, a) = realAddress(ba: wa << 2, .write)
        if (!t) {
            realMemory.storeBytes(of: unsigned.bigEndian, toByteOffset: a, as: UInt32.self)
        }
    }
    
    func storeDoubleWord (da: Int,_ value: Int64) {
        let (t, a) = realAddress(ba: da << 3, .write)
        if (!t) {
            realMemory.storeBytes(of: value.bigEndian, toByteOffset: a, as: Int64.self)
        }
    }
    
    func storeDoubleWord (da: Int,unsigned: UInt64) {
        let (t, a) = realAddress(ba: da << 3, .write)
        if (!t) {
            realMemory.storeBytes(of: unsigned.bigEndian, toByteOffset: a, as: UInt64.self)
        }
    }
    
    
    func copyWord (fromWA: Int, toWA: Int) {
        let (t,a) = realAddress(ba: fromWA << 2, .read)
        if (!t) {
            let w = realMemory.load(fromByteOffset: a, as: UInt32.self)
            let (t, a) = realAddress(ba: toWA << 2, .write)
            if (!t) {
                realMemory.storeBytes(of: w, toByteOffset: a, as: UInt32.self)
            }
        }
    }
    
    func exchangeRawWord (wa: Int, unsigned: UInt32) -> UInt32 {
        let (t,a) = realAddress(ba: wa << 2, .write)
        if (!t) {
            return realMemory.exchangeRawWord(ba: a, unsigned)
        }
        return 0
    }
    
    
    // modify operations: return (result, overflow, carry)
    func atomicModifyByte(ba: Int, by delta: UInt8) -> (UInt8, Bool, Bool) {
        let mode: AccessMode = (delta == 0) ? .read : .write
        let (t,a) = realAddress(ba: ba, mode)
        if (!t) {
            return realMemory.atomicModifyByte(by: delta, atByteOffset: a)
        }
        return (0, false, false)
    }
    
    func atomicModifyHalf(ha: Int, by value: Int8) -> (Int16, Bool, Bool) {
        let mode: AccessMode = (value == 0) ? .read : .write
        let (t,a) = realAddress(ba: ha << 1, mode)
        if (!t) {
            return realMemory.atomicModifyHalf(by: value, atByteOffset: a)
        }
        return (0, false, false)
    }
    
    func atomicModifyWord(wa: Int, by value: Int32, atByteOffset offset: Int = 0) -> (Int32, Bool, Bool) {
        let mode: AccessMode = (value == 0) ? .read : .write
        let (t,a) = realAddress(ba: wa << 2, mode)
        if (!t) {
            return realMemory.atomicModifyWord(by: value, atByteOffset: a)
        }
        return (0, false, false)
    }
}


// INTERRUPTS
// are managed by an "InterruptSubsystem" thread that manages the clock interrupts.   It also receives external events from I/O devices.
// This model handles group 0 and group 2 interrupts only: (override, counter, IO), which use locations X'50'-X'5F'; and COC's which use X'60'-X'6F'
//
let numberInterrupts        = 32                    // GROUPS 0 and 2
let interruptLevelStateNames: [String] = ["DISARMED","ARMED","ACTIVE","WAITING"]

class InterruptSubsystem: Thread {
    
    class InterruptData {
        var timestamp: Int64
        var level: Int = 0
        var priority: UInt4 = 0                     // priority within the level.
        var location: UInt8 = 0
        var deviceAddr: UInt16 = 0
        var device: Device?
        var line: UInt8 = 0xFF
        var char: UInt8 = 0x00
        
        init (deviceAddress: UInt16, interruptLevel: Int, interruptPriority: UInt4, device: Device?, line: UInt8 = 0xFF, char: UInt8 = 0x00) {
            timestamp = MSClock.shared.gmtTimestamp()
            priority = interruptPriority
            deviceAddr = deviceAddress
            level = interruptLevel
            location = 0x50 + UInt8(interruptLevel)
            self.device = device
            self.line = line
            self.char = char
        }
        
        func qPriority() -> Int64 {
            return Int64(level << 4) | Int64(priority)
        }
    }
    
    
    enum InterruptLevelState: UInt8 {
        case disarmed = 0
        case armed = 1
        case active = 2
        case waiting = 3
        
        func name() -> String { return interruptLevelStateNames[Int(rawValue)] }
    }
    
    
    var cpu: CPU!
    var access = SimpleMutex()
    //var event = DispatchSemaphore(0)
    
    // (Group 0) Interrupt Levels
    let levelPowerOn        = 0         // Not implemented
    let levelPowerOff       = 1         // Not implemented
    
    let levelCounter1Pulse  = 2         // N.I.
    let levelCounter2Pulse  = 3         // N.I.
    let levelCounter3Pulse  = 4         // 500Hz WD bit 18
    let levelCounter4Pulse  = 5         // 500Hz WD bit 19
    
    let levelMemoryParity   = 6         // N.I.
    
    let levelCounter1Zero   = 8
    let levelCounter2Zero   = 9
    let levelCounter3Zero   = 0x0A
    let levelCounter4Zero   = 0x0B
    
    let levelIO             = 0x0C
    let levelControlPanel   = 0x0D
    
    let levelReserved1      = 0x0E
    let levelReserved2      = 0x0F
    
    // COCs use 60,61,62,63,64,65 (2 per)
    
    // Interrupt Level Information
    private(set) var count: UnsafeMutablePointer<UInt64>
    private(set) var state: UnsafeMutablePointer<InterruptLevelState>
    private(set) var enabledBitmap: UInt32 = 0
    func enabled(_ level: Int) -> Bool { return enabledBitmap.bitIsSet(bit: level) }

    private(set) var activeInterruptData: [InterruptData?] = Array(repeating: nil, count: numberInterrupts)
    
    private(set) var interruptTrace: EventTrace?
    
    // Interrupts that cannot yet go active
    var waiting: Queue!
    
    // Counters 1 and 2 are optional and not implemented
    // Clock pulses are triggered by checking wall time.
    let pulse3Interval = 2 * MSDate.ticksPerMillisecond64
    private var pulse3Time: Int64 = 0
    private var clock3Post: Int64 = 0
    
    var clock3UMBA: Int = 0                         // Target of C3 pulse MTW (UNMAPPED Byte Address)
    func setClock3Target(_ umba: Int) {
        access.acquire()
        clock3UMBA = umba
        access.release()
    }
    
    let pulse4Interval = 2 * MSDate.ticksPerMillisecond64
    private var pulse4Time: Int64 = 0
    
    var clock4IMWA: Int = 0                         // Target of C4 pulse Indirect MTW (MAPPED Word Address)
    func setClock4Target(_ imwa: Int) {
        access.acquire()
        clock4IMWA = imwa
        access.release()
    }
    
    var timersEnabled: Bool = true
    func timersOff() {
        timersEnabled = false
    }
    
    init(cpu: CPU) {
        count = UnsafeMutablePointer<UInt64>.allocate(capacity: numberInterrupts)
        count.initialize(repeating: 0, count: numberInterrupts)
        state = UnsafeMutablePointer<InterruptLevelState>.allocate(capacity: numberInterrupts)
        state.initialize(repeating: .disarmed, count: numberInterrupts)
//        activeInterruptData = UnsafeMutablePointer<InterruptData?>.allocate(capacity: numberInterrupts)
//        activeInterruptData.initialize(repeating: nil, count: numberInterrupts)

        super.init()
        
        self.cpu = cpu
        self.access = SimpleMutex()
        self.waiting = Queue(name: "Waiting Interrupts")
        
        interruptTrace = EventTrace("INTERRUPTS", capacity: 0x40, cpu.machine)
    }
    
    func currentActiveInterrupt() -> InterruptData? {
        var x: Int = 0
        while (x < numberInterrupts) {
            if (activeInterruptData[x] != nil) {
                return activeInterruptData[x]
            }
            x += 1
        }
        return nil
    }
    
    func clearActive(_ level:Int, instruction: UInt32,_ deviceAddress: UInt16 = 0) {
        activeInterruptData[level] = nil
        interruptTrace?.addEvent(type: .interruptCleared, psd: cpu.psd.value, ins: instruction, address: UInt32(deviceAddress), level: UInt8(level))
    }
    
    func enable(_ level: Int) {
        access.acquire()
        enabledBitmap.setBit(bit: level)
        access.release()
    }
    
    func disable(_ level: Int) {
        access.acquire()
        enabledBitmap.clearBit(bit: level)
        access.release()
    }
    
    //FIXME: TEMPORARY -- REMOVE THIS
    func checkState(_ level: Int,_ detail: String) {
        switch state[level] {
            //        case .active:
            //            cpu.machine.log("Active interrupt level \(hexOut(level,width:2)) needs clearing. (\(detail))")
        case .waiting:
            cpu.machine.log("Waiting interrupt level \(hexOut(level,width:2)) needs clearing. (\(detail))")
        default:
            break
        }
    }
    
    func arm(_ level: Int, clear: Bool = false,  instruction: UInt32,_ deviceAddress: UInt16 = 0) {
        access.acquire()
        if (clear) {
            clearActive(level, instruction: instruction)
        }
        else {
            checkState(level, "(A)")
        }
        state[level] = .armed
        interruptTrace?.addEvent(type: .ioStateArmed, psd: cpu.psd.value, ins: instruction, address: UInt32(deviceAddress), level: UInt8(level))
        access.release()
    }
    
    func disarm(_ level: Int, clear: Bool = false, instruction: UInt32,_ deviceAddress: UInt16 = 0) {
        access.acquire()
        if (clear) {
            clearActive(level, instruction: instruction)
        }
        else {
            checkState(level, "(D)")
        }
        state[level] = .disarmed
        interruptTrace?.addEvent(type: .ioStateDisarmed, psd: cpu.psd.value, ins: instruction, address: UInt32(deviceAddress), level: UInt8(level))
        access.release()
    }
    
    
    func armEnable(_ level: Int, clear: Bool = false, instruction: UInt32,_ deviceAddress: UInt16 = 0) {
        access.acquire()
        if (clear) {
            clearActive(level, instruction: instruction)
        }
        else {
            checkState(level, "(AE)")
        }
        state[level] =  .armed
        interruptTrace?.addEvent(type: .ioStateArmed, psd: cpu.psd.value, ins: instruction, address: UInt32(deviceAddress), level: UInt8(level))
        enabledBitmap.setBit(bit: level)
        access.release()
    }
    
    func armDisable(_ level: Int, clear: Bool = false, instruction: UInt32,_ deviceAddress: UInt16 = 0) {
        access.acquire()
        if (clear) {
            clearActive(level, instruction: instruction)
        }
        else {
            checkState(level, "(AD)")
        }
        state[level] =  .armed
        interruptTrace?.addEvent(type: .ioStateArmed, psd: cpu.psd.value, ins: instruction, address: UInt32(deviceAddress), level: UInt8(level))
        enabledBitmap.clearBit(bit: level)
        access.release()
    }
    
    
    // Determine if an interrupt level is inhibited
    private func inhibited(_ level: Int) -> Bool {
        guard (level >= levelCounter1Zero) else { return false }
        guard (level < numberInterrupts) else { return false }
        
        switch (level) {
        case levelCounter1Zero, levelCounter2Zero, levelCounter3Zero, levelCounter4Zero:
            return (cpu.psd.zInhibitCI)
            
        case levelIO, levelControlPanel:
            return (cpu.psd.zInhibitIO)
            
        default:
            return (cpu.psd.zInhibitEI)
        }
    }
    
    override func main() {
        Thread.setThreadPriority(kInterruptPriority)
        Thread.current.name = (cpu.name ?? "") + ":Interrupts"
        pulse3Time = MSClock.shared.gmtTimestamp()
        while true {
            let ts = MSClock.shared.gmtTimestamp()
            
            if (timersEnabled)  {
                // Check for CLOCK3 or CLOCK4
                // Is it time for a counter pulse? Or maybe two?
                if ((ts - pulse3Time) > pulse3Interval) {
                    clock3Pulse(ts)
                    pulse3Time += pulse3Interval
                }
                
                // Clock4 is trickier.
                access.acquire()
                let c4Enabled = enabled(levelCounter4Pulse)
                if (c4Enabled) && ((ts - pulse4Time) > pulse4Interval)  {
                    access.release()
                    if (clock4IMWA > 0x10) {
                        cpu.clock4Pulse(clock4IMWA)
                    }
                    else {
                        _ = post (levelCounter4Pulse, priority: 0)
                    }
                    access.acquire()
                    pulse4Time = ts
                }
                access.release()
            }
            
            Thread.sleep(forTimeInterval: kInterruptCycleTime)
        }
    }
    
    func clock3Pulse(_ ts: Int64) {
        guard (state[levelCounter3Pulse] != .disarmed) else { return }
        
        if (enabled(levelCounter3Pulse))  && (cpu.isRunning) {
            if (clock3UMBA > 0) {
                // MARK: EMULATE MTW,-1 (clock3)
                
                if let m = cpu.unmappedMemory {
                    let (c, _, _) = m.atomicModifyWord(by: -1, atByteOffset: clock3UMBA)
                    let inhibit = cpu?.psd?.zInhibitCI ?? true
                    if (c <= 0) && (!inhibit) && (enabled(levelCounter3Zero)) && (state[levelCounter3Zero] == .armed) {
                        //let elapsed = (ts-clock3Post) / MSDate.ticksPerMillisecond64
                        clock3Post = ts
                        _ = post(levelCounter3Zero, priority: 0)
                    }
                }
                cpu.clearWait()
            }
            else {
                _ = post (levelCounter3Pulse, priority: 0)
            }
        }
        
    }
    
    
    
    // Post an Interrupt, (or ignore it if disarmed).
    func post (_ level: Int, priority: UInt4, deviceAddr: UInt16 = 0, device: Device? = nil, line: UInt8 = 0xFF, char: UInt8 = 0) -> InterruptLevelState {
        access.acquire()
        var _state = state[level]
        if (_state != .disarmed) {
            let d = InterruptData(deviceAddress: deviceAddr,
                                  interruptLevel: level,
                                  interruptPriority: priority,
                                  device: device,
                                  line: line,
                                  char: char)
            switch (_state) {
            case .armed:
                waiting.enqueue(object: d, priority: d.qPriority())
                state[level] = .waiting
                interruptTrace?.addEvent(type: .ioStateWaiting, psd: cpu.psd.value, address: UInt32(deviceAddr), level: UInt8(level))
                break
                
            case .waiting, .active:
                if (level < levelIO) || (level == levelControlPanel) {
                    //MARK: Blow this off, we don't want to stack timer or panel interrupts
                    interruptTrace?.addEvent(type: .interruptIgnored, psd: cpu.psd.value, address: UInt32(deviceAddr), level: UInt8(level))
                    access.release()
                    return _state
                }
                //MARK: Queue this interrupt.
                else {
                    waiting.enqueue(object: d, priority: d.qPriority())
                    if (state[level] != .active) {
                        state[level] = .waiting
                        interruptTrace?.addEvent(type: .ioStateWaiting, psd: cpu.psd.value, address: UInt32(deviceAddr), level: UInt8(level))
                    }
                }
                break
                
            default:
                cpu.machine.log(level: .error, "Interrupt level is disabled but was processed:" + String(format:"%X",deviceAddr))
                break
            }
        }
        else {
            //let name = device?.name ?? "NULL"
            //cpu.machine.log(level: .debug, "*** \(name) INTERRUPT IGNORED (DISABLED)")
        }
        
        // Return new stste
        _state = state[level]
        access.release()
        if (_state == .waiting) {
            cpu.clearWait()
        }
        return _state
    }
    
    
    //MARK: Called by CPU to see if there is a new active interrupt.
    func newActive () -> InterruptData? {
        // Find a wainting interrupt that is enabled and not inhibited
        func couldGoActive() -> InterruptData? {
            let currentlyDisabled = Queue(name: "Temporary")
            
            var ww = waiting.dequeue() as? InterruptData
            while (ww != nil) && ((!enabled(ww!.level)) || inhibited(ww!.level)) {
                currentlyDisabled.enqueue(object: ww!, priority: 0)
                ww = waiting.dequeue() as? InterruptData
            }
            
            // Put any disabled interrupts back for later.
            var wd = currentlyDisabled.dequeue() as? InterruptData
            while (wd != nil) {
                waiting.enqueue(object: wd!, priority: wd!.qPriority())
                wd = currentlyDisabled.dequeue() as? InterruptData
            }
            
            return ww
        }
        
        access.acquire()
        var canGoActive: InterruptData?
        
        if let ca = currentActiveInterrupt() {
            if let w = waiting.firstObject() as? InterruptData, (ca.level <= w.level) {
                access.release()
                return nil
            }
            
            // Do a more detailed check
            if let wa = couldGoActive() {
                if (wa.level < ca.level) {
                    canGoActive = wa
                }
            }
        }
        else {
            canGoActive = couldGoActive()
        }
        
        if let cga = canGoActive {
            activeInterruptData[cga.level] = cga
            state[cga.level] = .active
            interruptTrace?.addEvent(type: .interrupt, psd: cpu.psd.value, address: UInt32(cga.deviceAddr), level: UInt8(cga.level))
        }
        
        access.release()
        return canGoActive
    }
}



// MARK: CPU
class CPU: Thread {
    enum CPUModel {
        case s7                         // SIGMA 5/6/7
        case s9                         // SIGMA 8/9
    }
    var model: CPUModel = .s7
    
    var machine: VirtualMachine!
    let stepNotification = Notification.Name("CPUStepComplete")
    
    enum PSDMapMode: Int {
        case none = 0
        case indirect = 1
        case full = 2
    }
    
    enum IndexAlignment: Int {          //MARK: LRA depends on these raw values
        case byte = 0
        case half = 1
        case word = 2
        case double = 3
    }
    
    enum StepMode: Int {
        case none = 0
        case simple = 1
        case count = 2
        case branched = 3
        case branchFailed = 4
    }
    
    enum BreakMode: Int {
        case start = 0
        case none = 1
        case access = 2
        case execution = 3
        case operation = 4
        case register = 5
        case trap = 6
        case screech = 7
    }
    
    struct MonitorInfo {
        // This structure contains CPV information and symbol definitions for debugging and displays.
        // It is determined once, at the time that the first mapped instrcution is executed
        var version: UInt16 = 0         // CPV Version
        
        // Current user & processor name table: determined dynamically the first time the map is enabled.
        var currentUserAddress: Int = 0
        var pnameAddress: Int = 0
        var dct1: Int = 0
        var ubovAddress: Int = 0
        var maxovly: Int = 0
        var ovlyName: [String] = []
        
        // Other symbols get added where possible.
        var symbols = NSMutableDictionary()
        
        init (_ unmappedMemory: Memory!) {
            //MARK: 1. Find the LAW,0 J:JIT instruction at SSE1
            //MARK: 2. 3 instructions later is a LW,4 S:CUN
            var a = 0x7FFF
            while (a > 0) {
                let w = unmappedMemory.loadRawWord(word: a)
                if (w == 0x008C003B) {
                    let lw = unmappedMemory.loadUnsignedWord(word: a+3)
                    if ((lw >> 16) == 0x3240) {
                        currentUserAddress = Int(lw & 0x7FFF)
                    }
                }
                
                //MARK: Looking for TEXTC 'UMOV" TO IDENTIFY THE P:NAME TABLE.
                else if (w == 0x404040E5) {
                    if (unmappedMemory.loadRawWord(word: a-1) == 0xD6D4E404) {
                        let pna = a - 3
                        
                        //MARK: USING PNAME, WE FIND THE CD,2 PNAME,4 INSTRUCTION AT OV1 in T:OV.
                        //MARK: THE PREVIOUS INSTRUCTION IS A LI,4 MAXOVLY
                        //MARK: THE NEXT INSTRUCTION BRANCHES TO T:OV2, WHICH CONTAINS LI,15 UB:OV
                        let cdi = UInt32(0x11280000 | pna)
                        var cda = 0x7FFF
                        while (cda > 0x1000) && (ubovAddress <= 0) {
                            if (cdi == unmappedMemory.loadUnsignedWord(word: cda)) {
                                let li = unmappedMemory.loadUnsignedWord(word: cda-1)
                                if ((li >> 20) == 0x224) {
                                    pnameAddress = pna
                                    maxovly = Int(li & 0x3f)
                                    ovlyName = []
                                    for i in 1 ... maxovly {
                                        let name = unmappedMemory.loadUnsignedRawDoubleWord((pna+2*Int(i)) << 2)
                                        ovlyName.append(asciiBytes(name, textc: true))
                                    }
                                }
                                
                                let br = unmappedMemory.loadUnsignedWord(word: cda+1)
                                if ((br >> 20) == 0x683) {
                                    let lia = Int(br & 0x7FFF)
                                    let ovi = unmappedMemory.loadUnsignedWord(word: lia)
                                    if ((ovi >> 20) == 0x22f) {
                                        ubovAddress = Int(ovi & 0x7FFF)
                                    }
                                }
                            }
                            cda -= 1
                        }
                    }
                }
                
                a -= 1
            }
            
            //MARK: IF XDLT IS HERE, COPY ITS SYMBOLS.  OTHERWISE WE AR GOING TO HAVE TO READ THEM FROM DISC.
            // This was useful when dubugging initialization and start up, before we could get to ANLZ.
            // Now it is not really necessary, except for the various report windows, which need to be rethought
            /**
            let xd1 = unmappedMemory.loadUnsignedWord(word: 0xEA00)
            if ((xd1 >> 24) == 0x68) {
                let xdb = xd1 & 0x1FFFF
                if (xdb > 0xEA03) && (xdb < 0xFFFF) {
                    // It is here, get the end of the symbol table
                    var xd2 = Int(unmappedMemory.loadUnsignedWord(word: 0xEA02))
                    if (xd2 > 0xF000) && (xd2 < 0xFFFF) {
                        var done = false
                        while !done {
                            xd2 -= 3
                            let address = unmappedMemory.loadUnsignedWord(word: xd2)
                            var a = (xd2 + 1) << 2
                            let b = unmappedMemory.loadByte(a)
                            if (b > 0) {
                                let c = Character(Unicode.Scalar(asciiFromEbcdic(b)))
                                var name = String(c)
                                for _ in 0...6 {
                                    a += 1
                                    let b = unmappedMemory.loadByte(a)
                                    if (b > 0x40) {
                                        let c = Character(Unicode.Scalar(asciiFromEbcdic(b)))
                                        name = name + String(c)
                                    }
                                }
                                symbols.setValue(address, forKey: name)
                            }
                            else { done = true }
                        }
                    }
                }
            }
            else {
                //MARK: APPARENTLY NOT NECESSARY.
                //MARK: GO Find "RACXI" on the swapper.  This will be in the middle of XDLT image.   We can grab the symbols values from there.
            }
            
            //MARK: copy for faster access
            if let a = symbols["DCT1"] as? Int {
                dct1 = a
            }
            */
        }
    }
    
    
    struct PSD {
        //TODO: Model other internal groups (like CC) on the FloatMode, i.e. Use a substruct
        
        // PSD related data
        var zCC: UInt4 = 0          // Condition code
        var zCC1: Bool                  { get { return (zCC & 0x8) != 0 } set { if newValue { zCC |= 0x8} else {zCC &= 0x7 }}}
        var zCC2: Bool                  { get { return (zCC & 0x4) != 0 } set { if newValue { zCC |= 0x4} else {zCC &= 0xB }}}
        var zCC3: Bool                  { get { return (zCC & 0x2) != 0 } set { if newValue { zCC |= 0x2} else {zCC &= 0xD }}}
        var zCC4: Bool                  { get { return (zCC & 0x1) != 0 } set { if newValue { zCC |= 0x1} else {zCC &= 0xE }}}
        
        var zCC12: UInt4                { get { return zCC >> 2 } set { zCC = (zCC & 0x3) | (newValue << 2) }}
        var zCC34: UInt4                { get { return zCC & 3  } set { zCC = (zCC & 0xC) | newValue }}
        
        struct FloatMode {
            var rawValue: UInt4

            var significance: Bool { get { return (rawValue & 0x4) != 0 } set { if newValue { rawValue |= 0x4} else {rawValue &= 0xB }}}
            var zero: Bool         { get { return (rawValue & 0x2) != 0 } set { if newValue { rawValue |= 0x2} else {rawValue &= 0xD }}}
            var normalize: Bool    { get { return (rawValue & 0x1) != 0 } set { if newValue { rawValue |= 0x1} else {rawValue &= 0xE }}}
        }
        var zFloat:FloatMode        // PSD Bits 4-7
        
        var zMode: UInt4 = 0        // Current PSD Bit 8 (0=Master), Bit 9 (Mapped), 10 (Decimal traps), 11 (Arithmetic traps)
        var zMaster: Bool               { get { return (zMode & 0x8) == 0 }}
        var zMapped: Bool               { get { return (zMode & 0x4) != 0 }}
        var zDecimalMask: Bool          { get { return (zMode & 0x2) != 0 }}
        var zArithmeticMask: Bool       { get { return (zMode & 0x1) != 0 }}
        
        
        var zInstructionAddress: UInt32 = 0
        
        var zWriteKey: UInt4 = 0
        var zInhibit: UInt4 = 0     // Interrupt Inhibit for Counter, IO, and External
        var zInhibitCI: Bool            { get { return (zInhibit & 0x4) != 0 }}
        var zInhibitIO: Bool            { get { return (zInhibit & 0x2) != 0 }}
        var zInhibitEI: Bool            { get { return (zInhibit & 0x1) != 0 }}
        
        //MARK: SIGMA 9 & BIG 6/7
        var zMAX: UInt8 = 0         // First bit is MODE ALTERED
        
        var zMA: Bool                   { get { return (zMAX & 0x80) != 0 } set { setMA(newValue)}}
        private mutating func setMA(_ newValue: Bool) {
            if (newValue) { zMAX |= 0x80 } else { zMAX &= 0x3F }
        }
        
        var zExtension: UInt8           { get { return (zMAX & 0x3F) } set { zMAX = (newValue & 0x3F) | (zMAX & 0x80) }}
        
        var zTrappedStatus: UInt8       // MARK: overlaps base S7 RP by 1 bit. Reduces register blocks to 16.
        
        var zRegisterPointer: Int = 0   // N.B. Pre-shifted so is index to register block.
        
        var value: UInt64 {
            return ((UInt64(zCC&0xf) << 60) | (UInt64(zFloat.rawValue&0x7) << 56) | (UInt64(zMode&0xf) << 52) | (UInt64(zInstructionAddress&0x1ffff) << 32) | (UInt64(zWriteKey&0x3) << 28) | (UInt64(zInhibit&0x7) << 24) | (UInt64(zMAX) << 16) | UInt64(zRegisterPointer&0x0f0) )
        }
        
        init(_ rawValue: UInt64) {
            var v = rawValue
            zRegisterPointer = Int(v & 0xF0)
            v >>= 8
            
            zTrappedStatus = UInt8(v & 0xFF)
            v >>= 8
            
            zMAX = UInt8(v & 0xFF)
            v >>= 8
            
            zInhibit = UInt4(v & 0xF)
            v >>= 4
            
            zWriteKey = UInt4(v & 0xF)
            v >>= 4
            
            zInstructionAddress = UInt32(v & 0x1FFFF)
            v >>= 20
            
            zMode = UInt4(v & 0xF)
            v >>= 4
            
            zFloat = FloatMode(rawValue: UInt4(v & 0xF))
            v >>= 4
            
            zCC = UInt4(v)
        }
    }
    
    struct CPUStatus {
        var timestamp: MSTimestamp = 0
        
        var psd: PSD!
        var instruction = Instruction(0)
        var instructionCount: Int
        var waitCount: Int
        var waitTime: Int64
        var interruptCount: Int
        
        var cun: UInt8 = 0              // Current user from S:CUN
        var name: UInt64 = 0            // System overlay name for current user
        
        var watchDog: Bool = false      // WatchDog is true if WD timer ran out.
        var trapLocation: UInt8 = 0     // Latest trap in last 15 seconds
        var intLocation: UInt8 = 0
        
        var breakMode: BreakMode = .none
        var breakIndex: Int
        
        var alarm: Bool = false
        var fault: Bool = false
        var faultMessage: String = ""
        var screechData: UInt32 = 0
        
        
        init(timestamp: MSTimestamp,_ instruction: Instruction,_ instructionCount: Int,
             _ psd: PSD,_ waitCount: Int,_ waitTime: Int64,_ interruptCount: Int,
             _ cun: UInt8,_ name: UInt64,
             wDog: Bool = false, alarm: Bool = false, trapLocation: UInt8 = 0, interruptLocation: UInt8 = 0,
             breakMode: BreakMode = .none, breakIndex: Int = -1,
             fault: Bool = false, faultMessage: String = "", screechData: UInt32 = 0)
        {
            self.psd = psd
            self.timestamp = timestamp
            self.instruction = instruction
            self.instructionCount = instructionCount
            self.waitCount = waitCount
            self.waitTime = waitTime
            self.interruptCount = interruptCount
            self.cun = cun
            self.name = name
            
            self.watchDog = wDog
            self.alarm = alarm
            self.trapLocation = trapLocation
            self.intLocation = interruptLocation
            self.breakMode = breakMode
            self.breakIndex = breakIndex
            self.fault = fault
            self.faultMessage = faultMessage
            self.screechData = screechData
        }
    }
    
    struct SPD {
        var pointer:        Int
        var trapAvailable:  Bool                // trap on avail space limits
        var availableCount: Int16               // "space" count
        var trapUsed:       Bool                // trap on used space limits
        var usedCount:      Int16               // "word" count
        
        init (dw: UInt64) {
            pointer = Int(dw >> 32) & 0x1FFFF
            trapAvailable = ((dw & 0x80000000) == 0)
            availableCount = Int16((dw >> 16) & 0x7FFF)
            trapUsed = ((dw & 0x8000) == 0)
            usedCount = Int16(dw & 0x7FFF)
        }
        
        func checkModify(delta: Int) -> (Bool, Bool) {
            let nac = Int(availableCount) - delta
            let nuc = Int(usedCount) + delta
            let overAvailable = ((nac < 0) || (nac > 0x7FFF))
            let overUsed = ((nuc < 0) || (nuc > 0x7FFF))
            if (overAvailable) || (overUsed) {
                return (overAvailable, overUsed)
            }
            return (false, false)
        }
        
        var value: UInt64 { get { return (UInt64(pointer) << 32) | (UInt64 (availableCount) << 16) | UInt64 (usedCount) | (trapAvailable ? 0 : 0x80000000) | (trapUsed ? 0 : 0x8000) }}
    }
    
    // CPV related data
    var monitorInfo: MonitorInfo!
    var currentUser: Int { get { return (monitorInfo == nil) ? 0 : Int(unmappedMemory.loadUnsignedWord(word: monitorInfo.currentUserAddress))  }}
    
    // control of threaded access to CPU variables:
    var control = SimpleMutex()
    
    private var fault: Bool = false
    private var faultMessage: String = ""
    
    // Current instruction information
    private(set) var zInstruction = Instruction(0)
    private var zAlarm: Bool = false
    private var zAlarmOutput: Bool = false
    
    var psd: PSD!
    private(set) var lastInstructionAddress: UInt32 = 0     // Used for "transition" breakpoints
    
    
    // Interrupts
    private(set) var interrupts: InterruptSubsystem!
    private(set) var interruptSuppress: Int = 0
    private(set) var interruptCount: Int = 0
    
    //  TRAPS
    struct TrapData {
        var ts: MSTimestamp
        var address: UInt8 = 0
        
        var trapCC: UInt4 = 0
        var instructionFetch: Bool = false
        
        init (location: UInt8, cc: UInt4 = 0, fetch: Bool = false) {
            ts = MSClock.shared.gmtTimestamp()
            address = location
            trapCC = cc
            instructionFetch = fetch
        }
    }
    
    var pendingTrap: TrapData!
    var lastTrap: TrapData!
    var trapPending: Bool { get { return (pendingTrap != nil) }}
    var trapCount: [Int64] = Array(repeating: 0, count: 16)
    
    // For status
    private var screechData: UInt32 = 0
    
    //Statistics:
    var instructionCount: Int { get { return opTotal }}
    var opCount: [Int] = Array(repeating: 0, count: 128)
    var opTime: [Int64] = Array(repeating: 0, count: 128)
    private var opTotal: Int = 0
    
    private var waitCount: Int = 0
    private var waitTime: Int64 = 0
    
    
    
    // BREAKPOINT DATA
    struct Breakpoint {
        var count: Int = 0
        var address: UInt32 = 0
        var mapped: Bool = false
        var unmapped: Bool = true
        
        var logAndGo: Bool = false
        
        var execute: Bool = true
        var read: Bool = false
        var write: Bool = false
        var transition: Bool = false
        var register: Bool = false
        
        var user: UInt8 = 0
        var overlay: UInt8 = 0
    }
    
    let breakpointMax = 5
    private var breakpoints: [Breakpoint?] = [nil, nil, nil, nil, nil]
    
    // Similar to breakpoints; but not address specific and only one instance.
    private var stopOnInstruction: UInt32 = 0                           // 0 = Off
    private var stopOnInstructionMask: UInt32 = 0
    func setInstructionStop (_ instruction: UInt32,_ mask: UInt32) {
        stopOnInstruction = instruction
        stopOnInstructionMask = mask
    }
        
    var stopOnTrap: UInt8 = 0                                   // 0 = Off, 0xFF = any (except CAL1), other = specific trap address
    func isTrapStop(_ a: UInt8) -> Bool {
        return (stopOnTrap == a)
    }
    
    // Single register breakpoint stops when register content = value.
    private var breakOnRegister: Bool = false
    private var breakOnRegisterNumber: UInt4 = 0
    private var breakOnRegisterValue: UInt32 = 0
    private var breakOnRegisterMask: UInt32 = 0xFFFFFFFF
    func setRegisterBreak(_ on: Bool, r: UInt4, value: UInt32, mask: UInt32) {
        breakOnRegister = on
        breakOnRegisterNumber = r
        breakOnRegisterValue = value
        breakOnRegisterMask = (mask == 0) ? 0xFFFFFFFF : mask
    }
    
    // Memory, and n sets of registers
    private var unmapped: Memory!
    private var memory: VirtualMemory!
    
    private(set) var zRegisters: UnsafeMutablePointer<Int32>
    // registerBytes and registerSetBA used to optimize access to registers..
    // It's almost nothing.
    private var registerBytes: UnsafeMutableRawPointer!             // Points at zRegisters as byte array
    private var registerSetBA: Int = 0                              // Byte offset to start of current register set.
    
    var virtualMemory: VirtualMemory! { get { return memory }}
    var unmappedMemory: Memory! { get { return unmapped }}
    
    //MARK: TRACES
    var branchTrace: EventTrace?
    var userBranchTrace: EventTrace?
    var calTrace: EventTrace?
    var ioTrace: EventTrace?
    var otherTrace: EventTrace?
    
    //MARK: REGISTER ACCESS
    func getRegister(_ r: UInt4) -> Int32 {
        return (zRegisters[psd.zRegisterPointer+Int(r)].bigEndian)
    }
    
    func getRegisterRawWord(_ r: UInt4) -> UInt32 {
        return registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self)
    }
    
    func getRegisterUnsignedWord(_ r: UInt4) -> UInt32 {
        return registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self).bigEndian
    }
    
    func getRegisterDouble(_ r: UInt4) -> Int64 {
        if (r.isOdd) {
            let v = Int64(registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: Int32.self).bigEndian)
            return ((v << 32) | v)
        }
        return registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: Int64.self).bigEndian
    }
    
    func getRegisterUnsignedDouble(_ r: UInt4) -> UInt64 {
        if (r.isOdd) {
            let v = UInt64(registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self).bigEndian)
            return ((v << 32) | v)
        }
        return registerBytes.load(fromByteOffset: registerSetBA + (Int(r) << 2), as: UInt64.self).bigEndian
    }
    
    func getRegisterHalf(_ ha: UInt8) -> Int16 {
        return registerBytes.load(fromByteOffset: registerSetBA + Int(ha << 1), as: Int16.self).bigEndian
    }
    
    func getRegisterUnsignedHalf(_ ha: UInt8) -> UInt16 {
        return registerBytes.load(fromByteOffset: registerSetBA + Int(ha << 1), as: UInt16.self).bigEndian
    }
    
    func getRegisterByte(_ ba: UInt8) -> UInt8 {
        return registerBytes.load(fromByteOffset: registerSetBA + Int(ba), as: UInt8.self)
    }
    
    func setRegisterRawWord (_ r: UInt4,unsigned: UInt32) {
        registerBytes.storeBytes(of: unsigned, toByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self)
    }
    
    func setRegister (_ r: UInt4,_ value: Int32) {
        zRegisters[psd.zRegisterPointer + Int(r)] = value.bigEndian
    }
    
    func setRegister (_ r: UInt4,unsigned: UInt32) {
        registerBytes.storeBytes(of: unsigned.bigEndian, toByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self)
    }
    
    func setRegisterDouble (_ r: UInt4,_ value: Int64) {
        if (r.isOdd) {
            registerBytes.storeBytes(of: Int32(value >> 32).bigEndian, toByteOffset: registerSetBA + (Int(r) << 2), as: Int32.self)
        }
        else {
            registerBytes.storeBytes(of: value.bigEndian, toByteOffset: registerSetBA + (Int(r) << 2), as: Int64.self)
        }
    }
    
    func setRegisterDouble (_ r: UInt4,unsigned: UInt64) {
        if (r.isOdd) {
            registerBytes.storeBytes(of: UInt32(unsigned >> 32).bigEndian, toByteOffset: registerSetBA + (Int(r) << 2), as: UInt32.self)
        }
        else {
            registerBytes.storeBytes(of: unsigned.bigEndian, toByteOffset: registerSetBA + (Int(r) << 2), as: UInt64.self)
        }
    }
    
    func setRegisterHalf(_ ha: UInt8,_ value: Int16) {
        registerBytes.storeBytes(of: value.bigEndian, toByteOffset: registerSetBA + Int(ha << 1), as: Int16.self)
    }
    
    func setRegisterHalf(_ ha: UInt8,unsigned: UInt16) {
        registerBytes.storeBytes(of: unsigned.bigEndian, toByteOffset: registerSetBA + Int(ha << 1), as: UInt16.self)
    }
    
    func setRegisterByte(_ ba: UInt8,_ value: UInt8) {
        registerBytes.storeBytes(of: value, toByteOffset: registerSetBA + Int(ba), as: UInt8.self)
    }
    
    
    // Generalized memory acccess.
    func loadByte (ba: Int) -> UInt8 {
        guard (ba > 0x3F) else { return getRegisterByte(UInt8(ba)) }
        return memory.loadByte(ba: ba)
    }
    
    func loadHalf (ha: Int) -> Int16 {
        guard (ha > 0x1F) else { return getRegisterHalf(UInt8(ha)) }
        return memory.loadHalf(ha: ha)
    }
    
    func loadUnsignedHalf (ha: Int) -> UInt16 {
        guard (ha > 0x1F) else { return UInt16(bitPattern: getRegisterHalf(UInt8(ha))) }
        return UInt16(bitPattern: memory.loadHalf(ha: ha))
    }
    
    func loadWord (wa: Int) -> Int32 {
        guard (wa > 0xF) else { return getRegister(UInt4(wa)) }
        return memory.loadWord(wa: wa)
    }
    
    func loadUnsignedWord (wa: Int) -> UInt32 {
        guard (wa > 0xF) else { return getRegisterUnsignedWord(UInt4(wa)) }
        return memory.loadUnsignedWord(wa: wa)
    }
    
    func loadRawWord (wa: Int) -> UInt32 {
        guard (wa > 0xF) else { return getRegisterRawWord(UInt4(wa)) }
        return memory.loadRawWord(wa: wa)
    }
    
    func loadDoubleWord (da: Int) -> Int64 {
        guard (da > 0x7) else { let r = UInt4(da << 1); return (Int64(getRegister(r)) << 32) | Int64(getRegisterUnsignedWord(r.next)) }
        return memory.loadDoubleWord(da: da)
    }
    
    func loadUnsignedDoubleWord (da: Int) -> UInt64 {
        guard (da > 0x7) else { let r = UInt4(da << 1); return (UInt64(getRegisterUnsignedWord(r)) << 32) + UInt64(getRegisterUnsignedWord(r.next)) }
        return memory.loadUnsignedDoubleWord(da: da)
    }
    
    
    func storeByte (ba: Int,_ value: UInt8) {
        guard (ba > 0x3F) else { setRegisterByte(UInt8(ba), value); return }
        memory.storeByte(ba: ba, value)
    }
    
    func storeHalf (ha: Int,_ value: Int16) {
        guard (ha > 0x1F) else { setRegisterHalf(UInt8(ha), value); return }
        memory.storeHalf(ha: ha, value)
    }
    
    func storeHalf (ha: Int,unsigned: UInt16) {
        guard (ha > 0x1F) else { setRegisterHalf(UInt8(ha), unsigned: unsigned); return }
        memory.storeHalf(ha: ha, unsigned: unsigned)
    }
    
    func storeRawWord (wa: Int,unsigned: UInt32) {
        guard (wa > 0xF) else { setRegisterRawWord(UInt4(wa), unsigned: unsigned); return }
        memory.storeRawWord(wa: wa, unsigned: unsigned)
    }
    
    func storeWord (wa: Int,_ value: Int32) {
        guard (wa > 0x1F) else { setRegister(UInt4(wa), value); return }
        memory.storeWord(wa: wa, value)
    }
    
    func storeWord (wa: Int,unsigned: UInt32) {
        guard (wa > 0xF) else { setRegister(UInt4(wa), unsigned: unsigned); return }
        memory.storeWord(wa: wa, unsigned: unsigned)
    }
    
    func storeDoubleWord (da: Int,_ value: Int64) {
        guard (da > 0x7) else { let r = UInt4(da << 1); setRegisterDouble(r, value); return }
        memory.storeDoubleWord(da: da, value)
    }
    
    func storeDoubleWord (da: Int,unsigned: UInt64) {
        guard (da > 0x7) else { let r = UInt4(da << 1); setRegisterDouble(r, unsigned: unsigned); return }
        memory.storeDoubleWord(da: da, unsigned: unsigned)
    }
    
    init (_ machine: VirtualMachine!, realMemory: Memory!, maxVirtualPages: Int) {
        self.machine = machine
        
        // Create and initialize the register block
        zRegisters = UnsafeMutablePointer<Int32>.allocate(capacity: registerBlockSize)
        zRegisters.initialize(repeating: 0, count: registerBlockSize )
        registerBytes = UnsafeMutableRawPointer(zRegisters)
        
        // Set up Event Traces
        branchTrace = EventTrace ("BRANCHES", capacity: 0x80, countRepeats: true, machine)
        userBranchTrace = EventTrace ("MAPPEDBRANCHES", capacity: 0x40, countRepeats: true, machine)
        calTrace = EventTrace("CALS", capacity: 0x40, machine)
        ioTrace = EventTrace("IO-OPERATIONS", capacity: 0x40, machine)
        otherTrace = EventTrace("OTHER", capacity: 0x100, machine)
        super.init()
        
        interrupts = InterruptSubsystem(cpu: self)
        unmapped = realMemory
        memory = VirtualMemory (realMemory: realMemory, maxVirtualPages: maxVirtualPages, cpu: self)
        psd = PSD(0)
    }
    
    
    func getStatus () -> CPUStatus {
        // Wait till current intruction completes
        let cun = currentUser
        var ov: UInt8 = 0
        var name: UInt64 = 0
        if (monitorInfo != nil) {
            ov = UInt8(unmappedMemory.loadByte((monitorInfo.ubovAddress << 2) + cun))
            name = (ov < 15) ? unmappedMemory.loadUnsignedRawDoubleWord((monitorInfo.pnameAddress+2*Int(ov)) << 2) : 0
        }
        if control.acquire(waitFor: MSDate.ticksPerSecond) {
            let lta = ((lastTrap != nil) && ((MSClock.shared.gmtTimestamp()-lastTrap.ts) < 2000)) ? lastTrap.address : ((pendingTrap != nil) ? pendingTrap.address : 0)
            var ail = 0
            if let active = interrupts.currentActiveInterrupt() {
                ail = active.level + 0x50
            }
            let status = CPUStatus(timestamp: MSClock.shared.gmtTimestamp(), zInstruction, instructionCount,
                                   psd, waitCount, waitTime, interruptCount,  UInt8(cun & 0xff), name,
                                   wDog: false, alarm: zAlarm, trapLocation: lta, interruptLocation: UInt8(ail),
                                   breakMode: breakMode, breakIndex: breakIndex,
                                   fault: fault, faultMessage: faultMessage, screechData: screechData)
            control.release()
            return status
        }
        
        // MARK: Unprotected access may produce inaccurate values.
        let status = CPUStatus(timestamp: MSClock.shared.gmtTimestamp(), zInstruction, instructionCount,
                               psd, waitCount, waitTime, interruptCount, UInt8(cun), name,
                               wDog: true, alarm: zAlarm, trapLocation: 0,
                               breakMode: breakMode, breakIndex: breakIndex,
                               fault: fault, faultMessage: faultMessage, screechData: screechData)
        return status
    }
    
    // MARK: Force to single step mode - can be invoked from debugger
    func setStep(count: Int = 0) {
        stepCount = count
        stepMode = .simple
    }
    
    func timersOff() {
        interrupts.timersOff()
    }
    
    func setFault (message: String) {
        fault = true
        faultMessage = message
    }
    
    func resetCPU () {
        if control.acquire(waitFor: 1000) {
            psd.zCC = 0
            psd.zFloat.rawValue = 0
            psd.zMode = 0
            psd.zInstructionAddress = 0
            psd.zWriteKey = 0
            psd.zInhibit = 0
            psd.zRegisterPointer = 0
            fault = false
            control.release()
        }
    }
    
    func resetSystem () {
        if control.acquire(waitFor: 1000) {
            unmapped.clear()
            resetCPU()
            control.release()
        }
    }
    
    
    func load(_ boot: Int) {
        if control.acquire(waitFor: 1000) {
            var i: Int = 0x20
            unmapped.storeWord(word: i, unsigned: 0)
            i += 1
            unmapped.storeWord(word: i, unsigned: 0)
            i += 1
            unmapped.storeWord(word: i, unsigned: 0x020000A8)           //22: Read, into ba(x'A8') = X'2A'
            i += 1
            unmapped.storeWord(word: i, unsigned: 0x0E000058)           //23: 88 bytes, ie 22 words.
            i += 1
            unmapped.storeWord(word: i, unsigned: 0x11)                 //24: DW address of first IO command (X'22')
            i += 1
            unmapped.storeWord(word: i, unsigned: UInt32(boot & 0xfff)) //25: { boot device address }
            i += 1
            unmapped.storeWord(word: i, unsigned: 0x32000024)           //26: LW,0 X'24'    Sets IO command DW @X'22'
            i += 1
            unmapped.storeWord(word: i, unsigned: 0xCC000025)           //27: SIO,0 *X'25'  Read boot device, byte address X'A8' (=2A), 22 words (X'58' bytes) Flags [HTE, IUE, SIL]
            i += 1
            unmapped.storeWord(word: i, unsigned: 0xCD000025)           //28: TIO,0 *X'25'  See if done
            i += 1
            unmapped.storeWord(word: i, unsigned: 0x69C00028)           //29: BCS,12 X'28'  Not done, check again.
            
            psd.zInstructionAddress = 0x26
            control.release()
        }
    }
    
    //MARK: Set new instruction address and update trace.
    func setInstructionAddress (to: UInt32) {
        branchTrace?.addEvent(type: .branch, user: UInt32(currentUser), psd: psd.value, ins: zInstruction.value, address: to)
        if (psd.zMapped) && (to >= 0xA000) {
            userBranchTrace?.addEvent(type: .branch, user: UInt32(currentUser), psd: psd.value, ins: zInstruction.value, address: to)
        }
        psd.zInstructionAddress = (to & 0x1FFFF)
        branchCompleted = true
    }
    
    func addCalTrace () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        calTrace?.addEvent(type: .cal, user: UInt32(currentUser), psd: psd.value, ins: UInt32(zInstruction.value), address: UInt32(wa))
    }
    
    func addIOTrace (_ instruction: UInt32,_ deviceAddr: UInt16,_ deviceStatus: UInt16,_ cc: UInt4) {
        ioTrace?.addEvent(type: .ioInstruction, user: UInt32(currentUser), psd: psd.value, ins: zInstruction.value, address: UInt32(deviceAddr), cc: cc, deviceInfo: deviceStatus)
    }
    
    // Calculate the virtual effective address for instruction componets.
    // For IndexAlignment byte, this produces a 19 bit byte address
    // For IndexAlignment half, this produces an 18 bit halfword address
    // For IndexAlignments word, this produces a 17 bit word address
    // For IndexAlignment double, this produces a 16 bit doubleword address.
    func effectiveAddress (reference: Int, indexRegister: UInt4, indexAlignment: IndexAlignment, indirect: Bool, noMap: Bool = false) -> Int {
        var ea = reference
        
        if (indirect) {
            if (ea <= 0xf) {
                ea = Int(getRegisterUnsignedWord(UInt4(ea)))
            }
            else if (noMap) {
                ea = Int(unmapped.loadUnsignedWord(word: ea))
            }
            else {
                ea = Int(memory.loadUnsignedWord(wa: ea))
                if trapPending { return 0 }
            }
        }
        
        switch (indexAlignment) {
        case .byte:
            ea <<= 2
            if (indexRegister > 0) {
                ea += Int(getRegister(indexRegister))
            }
            ea &= 0x7ffff
            break
            
        case .half:
            ea <<= 1
            if (indexRegister > 0) {
                ea += Int(getRegister(indexRegister))
            }
            ea &= 0x3ffff
            break
            
        case .word:
            if (indexRegister > 0) {
                ea += Int(getRegister(indexRegister))
            }
            ea &= 0x1ffff
            break
            
        case .double:
            ea >>= 1
            if (indexRegister > 0) {
                ea += (Int(getRegister(indexRegister) & 0xffff))
            }
            ea &= 0xffff
            break
            
        }
        return ea
    }
    
    //MARK:  STANDARD BREAKPOINT CHECKERS
    func clearBreakpoint (n: Int) {
        if (n > 0) && (n <= breakpointMax) {
            breakpoints[n-1] = nil
        }
    }
    
    func getBreakpoint (n: Int) -> Breakpoint? {
        if (n > 0) && (n <= breakpointMax) {
            return breakpoints[n-1]
        }
        return nil
    }
    
    func setBreakpoint (_ bp: Breakpoint, n: Int) {
        if (n > 0) && (n <= breakpointMax) {
            breakpoints[n-1] = bp
        }
    }
    
    func hitBreakPoint(_ x: Int,_ mode: BreakMode) {
        
        if (breakpoints[x] != nil) {
            if breakpoints[x]!.logAndGo {
                breakpoints[x]!.count += 1
                machine.log("BREAKPOINT: \(x), \(hexOut(breakpoints[x]!.address,width:5)), Count: \(breakpoints[x]!.count)")
                
                var rText = ""
                for r in 0 ... 15 {
                    rText += "\(hexOut(getRegisterUnsignedWord(UInt4(r)),width:8)),"
                }
                machine.log(rText)
            }
            else if (breakpoints[x]!.count > 0) {
                breakpoints[x]!.count -= 1
            }
            else {
                breakIndex = x
                breakMode = mode
            }
        }
    }
    
    func checkExecutionBreakpoint(_ ia: UInt32,_ isMapped: Bool) {
        guard (breakMode == .none) && (breakIndex < 0) else { return }
        
        for x in 0...breakpointMax-1 {
            if let bb = breakpoints[x] {
                if (bb.unmapped && !isMapped) || (bb.mapped && isMapped) {
                    let cun = currentUser
                    if (bb.user > 0), (bb.user != cun) { continue }
                    
                    let ov = (monitorInfo == nil) ? 0 : UInt8(unmappedMemory.loadByte((monitorInfo.ubovAddress << 2) + cun))
                    if (bb.overlay > 0), (bb.overlay != ov) { continue }
                    
                    if (bb.execute), (bb.address == ia) {
                        hitBreakPoint(x, .execution)
                        return
                    }
                    
                    // Break if this user is transitioning into an address >= the base.
                    if (bb.transition), (ia >= bb.address) && (lastInstructionAddress < bb.address) {
                        hitBreakPoint(x, .execution)
                        return
                    }
                }
            }
        }
    }
    
    
    func checkDataBreakpoint(_ ea: UInt32,_ mapped: Bool,_ mode: VirtualMemory.AccessMode) {
        guard (breakMode == .none) && (breakIndex < 0) else { return }
        
        for x in 0...breakpointMax-1 {
            if let bb = breakpoints[x] {
                if (bb.address == ea) {
                    if (bb.user > 0) && (bb.user != currentUser) { continue }
                    if (bb.mapped && mapped) || (bb.unmapped && !mapped) {
                        if ((bb.read) && (mode == .read)) || ((bb.write) && (mode == .write)) {
                            hitBreakPoint(x, .access)
                            return
                        }
                    }
                }
            }
        }
    }
    
    //MARK: Special case for STRING instructions which read/ write large blocks of data.
    func checkDataBreakpoint(ba: UInt32, bl: UInt32, _ mapped: Bool,_ mode: VirtualMemory.AccessMode) {
        guard (breakMode == .none) && (breakIndex < 0) else { return }
        
        for x in 0...breakpointMax-1 {
            if let bb = breakpoints[x] {
                let bba = bb.address << 2
                if (ba <= bba) && (bba < (ba + bl)) {
                    if (bb.user > 0) && (bb.user != currentUser) { continue }
                    if (bb.mapped && mapped) || (bb.unmapped && !mapped) {
                        if ((bb.read) && (mode == .read)) || ((bb.write) && (mode == .write)) {
                            hitBreakPoint(x, .access)
                            return
                        }
                    }
                }
            }
        }
    }
    
    
    
    //MARK: CLOCK4.   This implementation will cause synchronization to an instruction boundary.
    //MARK: It should be possible to do it inside the unmapped memory manager, except the state of the map is possibly volatile.
    //MARK: Think about this...
    func clock4Pulse(_ clock4IMWA: Int) {
        if (isRunning) {
            var c: Int32 = 1
            
            control.acquire()
            
            // MARK: INSTEAD EMULATE MTW,+1 *(clock4IMWA)
            if  let um = unmappedMemory {
                var wa = um.loadUnsignedWord(word: clock4IMWA)
                
                //FIXME: FOR DEBUGGING.
                //if ((wa < 0x8C07) || (wa > 0x8C0F)) && ((wa < 0x100) || (wa > 0xFFF)) {
                //    setFault (message: "PULSE4 Not a MON or JIT Clock "+hexOut(wa,width: 5))
                //}
                
                if psd.zMapped {
                    (_, wa) = virtualMemory.mapWord(wa, .read, true)
                }
                //TODO: REAL EXTENDED?
                
                (c, _, _) = um.atomicModifyWord(by: 1, atByteOffset: Int(wa) << 2)
                
                if (c == 0) && (!psd.zInhibitCI) {
                    //MARK: Under what circumstances does this happen. and is it important?
                    _ = interrupts.post(interrupts.levelCounter4Zero, priority: 0)
                }
                clearWait()
            }
            control.release()
        }
        
    }
    
    //****************************************** MAIN  **********************************************
    
    // CPU flags: [USE Atomic TestandSet]  Bit 0: RUN, Bit 1: WAIT
    private var cpuFlags: UInt64 = 0
    
    private var runSemaphore =  DispatchSemaphore(value:0)
    func clearRun() { _ = OSAtomicTestAndClear(0,&cpuFlags) }
    func setRun(stepMode m: StepMode,_ count: Int = 0) { if !OSAtomicTestAndSet(0,&cpuFlags) { stepMode = m; stepCount = count; runSemaphore.signal() }}
    var isRunning: Bool { get { return ((cpuFlags & 0x80) != 0) }}
    
    private var waitSemaphore = DispatchSemaphore(value:0)
    func setWait() { _ = OSAtomicTestAndSet(1,&cpuFlags) }
    func clearWait() {
        if OSAtomicTestAndClear(1,&cpuFlags) {
            waitSemaphore.signal()
        }
    }
    var isWaiting: Bool { get { return ((cpuFlags & 0x40) != 0) }}
    
    private(set) var decimal: Bool = true
    private(set) var decimalTrace: Bool = false
    private(set) var floatingPoint: Bool = true
    private(set) var floatTrace: Bool = false
    
    private var breakMode: BreakMode = .none
    private var breakIndex: Int = 0
    private var stepMode: StepMode = .none
    private var stepCount: Int = 0
    
    // Used to detect EXU loops
    var exuCount: Int = 0
    
    // Used to simulate a hard wait
    private var hardWaitInterval: Double = 0

    // Bracnch information
    var branchInstruction: Bool = false
    var branchCompleted: Bool = false
    
    
    override func main() {
        Thread.setThreadPriority(kCPUPriority)
        Thread.current.name = machine.name+":CPU"
        
        decimal = machine.getSetting(VirtualMachine.kDecimalInstructions) != "N"
        decimalTrace = machine.getSetting(VirtualMachine.kDecimalTrace) == "Y"
        floatingPoint = machine.getSetting(VirtualMachine.kFloatingPoint) != "N"
        floatTrace = machine.getSetting(VirtualMachine.kFloatTrace) == "Y"
        
        interrupts.start()
        
        var runAfterWait: Bool = false
        while (!fault) {
            if !isRunning {
                // MARK: Not running.  Wait until we are.
                runSemaphore.wait()
                runAfterWait = true                         // Execute at least 1 instruction
            }
            
            if isWaiting {                                  // isWaiting is set by the WAIT instruction
                //MARK: While we are waiting, things can be awoken by an I/O interrupt, in which case the IO thread will
                //MARK: signal the wait semaphore and the CPU will continue.
                //MARK: Clock4 interrupts are not checked until the beginning of an instruction cycle.
                
                let waitStart = MSClock.shared.gmtTimestamp()
                //machine.log(level: .debug, "WAIT START: \(waitStart)")
                let timeout = DispatchTime.now().advanced(by: .milliseconds(1))
                machine.waitStart()
                if (waitSemaphore.wait(timeout: timeout) == .timedOut) {
                    clearWait()
                }
                let waitLength = MSClock.shared.gmtTimestamp() - waitStart
                //machine.log(level: .debug, "WAITED: \(waitLength)")
                waitTime += waitLength
                waitCount += 1
            }
            
            control.acquire()                               // *MUTEX* access to CPU properties
            
            // Reset breakpoint indicators
            if (runAfterWait) {
                breakMode = .start
                if (interruptSuppress <= 0) {
                    interruptSuppress = 1
                }
                runAfterWait = false
            }
            else {
                breakMode = .none
            }
            breakIndex = -1
            
            // Fetch the next instruction...
            // MARK: Check for traps from previous cycle
            if (trapPending) {
                lastTrap = pendingTrap
                pendingTrap = nil
                processTrap(td: lastTrap)
            }
            
            // MARK: Check for active interrupts..
            else if (interruptSuppress > 0) {
                interruptSuppress -= 1
            }
            // FIXME: THIS ISN'T QUITE RIGHT...CLOCK PULSES CAN'T BE INHIBITED.
            else if (psd.zInhibit != 0x7) && (stepMode != .simple) {
                checkForInterrupt()
            }
            
            //MARK: Begin instruction execution cycle.
            // AT THIS POINT, the PSD is pointing at the instruction about to be executed.
            // FETCH NEXT INSTRUCTION
            var ia = psd.zInstructionAddress
            var t = false
            
            if (ia < 0x10) {
                // MARK: THE PROCESS INTIALIZATION CODE AT ONE POINT EXECUTES A CAL1,9 [1] INSTRUCTION FROM REGISTER 15...
                zInstruction.value = getRegisterUnsignedWord(UInt4(ia))
            }
            else {
                if (psd.zMapped) {
                    checkExecutionBreakpoint(ia, true)
                    (t, ia) = memory.mapWord(ia, .execute, psd.zMaster)
                }
                else {
                    if (psd.zMA) && ((ia & 0x10000) != 0) {
                        ia = (ia & 0xFFFF) | (UInt32(psd.zExtension) << 16)
                    }
                    checkExecutionBreakpoint(ia, false)
                }
                
                if (!t) {
                    // Fetch next instruction
                    zInstruction.value = unmapped.loadUnsignedWord(word: Int(ia))
                    lastInstructionAddress = ia
                    
                    if (breakMode == .start) {
                        breakMode = .none
                    }
                    else {
                        // Operation (i.e. instruction code) breakpoint?
                        if (breakMode == .none) {
                            if (stopOnInstruction > 0) {
                                if ((zInstruction.value & stopOnInstructionMask) == stopOnInstruction) {
                                    // Better to have register condyiond for each execution breakpoont,
                                    // and/or to have a switch that binds instruction and register but for now,
                                    // if instruction and register are both specified, they must both be true.
                                    if breakOnRegister {
                                        let v = getRegisterUnsignedWord(breakOnRegisterNumber)
                                        if ((v & breakOnRegisterMask) == breakOnRegisterValue) {
                                            breakMode = .operation
                                        }
                                    }
                                    else {
                                        breakMode = .operation
                                    }
                                }
                            }
                            else if breakOnRegister {
                                // No instruction stop specified
                                let v = getRegisterUnsignedWord(breakOnRegisterNumber)
                                if ((v & breakOnRegisterMask) == breakOnRegisterValue) {
                                    breakMode = .register
                                }
                            }
                        }
                        
                        if (breakMode != .none) {
                            stepMode = .simple
                        }
                    }
                }
                else {
                    pendingTrap = TrapData(location: 0x40, cc: 1, fetch: true)
                }
            }
            
            
            //MARK: If there is no breakpoint and no trap at this point, we can execute the instruction.
            if (pendingTrap == nil) && (breakMode == .none) {
                psd.zInstructionAddress += 1                                        // Point at the next instruction
                
                branchInstruction = false
                branchCompleted = false
                exuCount = 0
                
                let instructionStart = MSClock.shared.nanoSeconds()
                
                let opCode = zInstruction.opCode
                perform(instructionExecute[opCode])
                
                let instructionLength = MSClock.shared.nanoSeconds() - instructionStart
                if (instructionLength >= 0) {
                    opCount[opCode] += 1
                    opTime[opCode] += instructionLength
                    opTotal += 1
                }
                
                // Any breakpoints during instruction execution?
                if (breakMode != .none) {
                    stepMode = .simple
                }
            }
            
            // As a result of the intruction fetch and/or execution, there may now be a trap condition
            // In addition, we might have a "stopOnTrap" breakpoint set.  StopOnTrap does not apply to CAL1 traps
            if let td = pendingTrap {
                if (stopOnTrap == td.address) || ((stopOnTrap == 0xFF) && (td.address != 0x48)) {
                    stepMode = .simple
                    breakMode = .trap
                }
            }
            
            // Determine if this is the end of STEP sequence.
            var stepComplete = false
            switch (stepMode) {
            case .none:
                break
                
            case .simple:
                stepComplete = true
                break
                
            case .count:
                if (stepCount > 0) {
                    stepCount -= 1
                }
                stepComplete = (stepCount <= 0)
                break
                
            case .branched:
                stepComplete = branchInstruction && branchCompleted
                break
                
            case .branchFailed:
                stepComplete = branchInstruction && !branchCompleted
            }
            
            control.release()
            if stepComplete {
                // Let UI thread know it can update visual elements.
                NotificationCenter.default.post(name: stepNotification, object: machine)
                
                // return to the top of the loop and wait for permission to run.
                clearRun()
            }
            
            // Handle simulation of a hard BDR loop.
            if (hardWaitInterval > 0) {
                if (hardWaitInterval > 5) {
                    machine.log(level: .detail, "Hard Wait for "+String(format: "%.3f", hardWaitInterval)+" seconds!")
                }
                
                Thread.sleep (forTimeInterval: min(hardWaitInterval, 5.0))
                hardWaitInterval = 0
            }
            else {
                // Wait every 8192 instructions to allow thread rescheduling ?
                if (kCPURelease > 0) && ((opTotal & 0x1FFF) == 0) {
                    Thread.sleep(forTimeInterval: kCPURelease)
                }
            }
        }
        
        // CPU Fault - Wait until cleared, then exit
        while (fault) {
            Thread.sleep(forTimeInterval: kCPUFault)
        }
    }
    
    
    
    // MARK: INTERRUPT PROCESSING:
    @inlinable func checkForInterrupt() {
        if let id = interrupts.newActive() {
            let zInstruction = Instruction(unmapped.loadUnsignedWord(word: Int(id.location)))
            let level = id.level
            
            switch (zInstruction.opCode) {
            case 0x0F:
                // The instruction address in the PSD points at the next instruction to be executed.
                commonXPSD (zInstruction, isTrap: false)
                
            case 0x33:
                //MARK: CLOCK3 and CLOCK4 pulse interrupts get processed here the first time they happen.
                let delta = Int32(zInstruction.delta)
                
                // level 5 (i.e. counter 4 pulse) is executed mapped.
                let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: 0, indexAlignment: .word, indirect: zInstruction.indirect, noMap: (level != 5))
                if (wa > 0xF) {
                    let (v,_,_) = memory.atomicModifyWord(wa: wa, by: delta)
                    if (level <= 5) && (v == 0) {
                        _ = interrupts.post(level+6, priority: 1)
                    }
                    interrupts.arm(Int(level), clear: true, instruction: zInstruction.value)
                    
                    //MARK: For counter 3/4 pulse, remember target, so future pulses can be optimized in interrupt subsystem
                    if (machine.optimizeClocks) && ((level & 0xE) == 4) {
                        switch (level) {
                        case 4: interrupts.setClock3Target(wa << 2)
                        case 5: interrupts.setClock4Target(zInstruction.reference)
                        default: setFault (message: "Clocked Up")
                        }
                    }
                }
                
            case 0x53:
                //MARK: NEVER USED.
                let delta = zInstruction.delta
                let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: 0, indexAlignment: .half, indirect: zInstruction.indirect, noMap: (level != 5))
                if (ha > 0x1F) {
                    let (h, _, _) = memory.atomicModifyHalf(ha: ha, by: delta)
                    if (level <= 5) && (h == 0) && !(psd.zInhibitCI) {
                        _ = interrupts.post(level+6, priority: 1)
                    }
                    interrupts.arm(Int(level), clear: true, instruction: zInstruction.value)
                }
                
            case 0x73:
                //MARK: NEVER USED.
                let delta = zInstruction.delta
                let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: 0, indexAlignment: .byte, indirect: zInstruction.indirect, noMap: (level != 5))
                if (ba > 0x3F) {
                    let (b, _, _) = memory.atomicModifyByte(ba: ba, by: UInt8(bitPattern: delta))
                    if (level <= 5) && (b == 0) && !(psd.zInhibitCI) {
                        _ = interrupts.post(level+6, priority: 1)
                    }
                    interrupts.arm(Int(level), clear: true, instruction: zInstruction.value)
                }
                
            default:
                // If the interrupt location did not contain one of the above, it is invalid and that's it.
                setFault(message: "INVALID INTERRUPT LOCATION INSTRCTION: @"+String(format:"%X", id.location)+":"+zInstruction.getDisplayText())
            }
            interruptCount += 1
        }
    }
    
    // MARK: TRAP PROCESSING.
    @inlinable func processTrap(td: TrapData) {
        // Count it.
        trapCount[Int(td.address & 0xF)] += 1
        
        // Unless trap happened doing an instruction fetch, decrement instruction address to point at trapping instruction
        if !td.instructionFetch {
            psd.zInstructionAddress -= 1
        }
        
        // Execute the instruction (which should be XPSD) that is at the (mapped!) trap location
        var trapInstruction = Instruction(memory.loadUnsignedWord(wa: Int(td.address)))
        var trapCC = td.trapCC
        
        if (MSLogManager.shared.logDebug) {
            machine.log("TRAP @"+String(format:"%X", td.address)+":"+trapInstruction.getDisplayText()+", CUN="+hexOut(currentUser))
        }
        
        
        if (trapInstruction.opCode != 0x0F) {
            switch (model) {
            case .s7:
                //MARK: 7 pretends the opcode is 0F?
                trapInstruction.opCode = 0x0F                        // MARK: SKIP THE TRAPPING INSTRUCTION.
                
            case .s9:
                //MARK: 9 traps to X'4D' with CC set to 1100
                trapInstruction = Instruction(memory.loadUnsignedWord(wa: Int(0x4D)))
                trapCC = 0xC
            }
        }
        if (trapInstruction.opCode == 0x0F) {
            // Maybe just load the XPSD into the zInsruction buffer and proceed.
            // Needs an add/or in variable for CC.  For now leave it
            
            commonXPSD (trapInstruction, isTrap: true)
            if trapPending {
                // THE XPSD TRAPPED.
                // Let's not handle this...
                setFault(message: "TRAPPING XPSD TRAPPED")
            }
            
            if (trapCC > 0) {
                psd.zCC |= trapCC
                if trapInstruction.value.bitIsSet(bit: 9) {
                    psd.zInstructionAddress += UInt32(trapCC)
                }
            }
        }
        else {
            setFault(message: "INVALID TRAP LOCATION INSTRUCTION: @"+String(format:"%X", td.address)+":"+trapInstruction.getDisplayText())
        }
    }
    
    
    
    func commonXPSD (_ instruction: Instruction, isTrap: Bool) {
        // Gather old PSD
        let oldPSD = psd.value
        
        // Fetch word following XPSD, in case of SC
        //let nextWord = memory.loadUnsignedWord(wa: Int(psd.zInstructionAddress))
        
        // If trapping, slave mode needs to be reset now,
        // if not, it must already be reset
        psd.zMode &= 0x7
        
        
        var reference = instruction.reference
        
        // XPSD has a special hybrid mapping mode, where the indirection is mapped, but the rest isn't.
        // This all depends on bit 10 of the XPSD instruction.
        let bit10off = (instruction.value & 0x200000) == 0
        
        if (instruction.indirect) {
            if (isTrap && bit10off) {
                // Turn off map.
                psd.zMode &= 0xb
            }
            reference = Int(loadUnsignedWord(wa: reference))            // MARK: CAN BE A REGISTER!
        }
        
        // From this point, only use the map if currently mapped and bit 10 is set.
        if (psd.zMapped) && bit10off {
            // Turn off map.
            psd.zMode &= 0xb
        }
        
        var address = effectiveAddress (reference: reference,
                                        indexRegister: instruction.index,
                                        indexAlignment: .double,
                                        indirect: false)
        
        //MARK: Store old PSD, potentially in registers
        storeDoubleWord(da: Int(address), unsigned: oldPSD)
        // If there was an addressing trap, quit.  (Can't this cause an endless trap loop?)
        if (trapPending) { return }
        
        // Get new PSD
        address = (address + 1) << 1            // Use word address
        let newPSD1 = loadUnsignedWord(wa: Int(address))
        address += 1
        let newPSD2 = loadUnsignedWord(wa: Int(address))
        
        // Build new CPU state
        psd.zCC = UInt4((newPSD1 & 0xf0000000) >> 28)
        psd.zFloat.rawValue = UInt4((newPSD1 & 0x07000000) >> 24)
        psd.zMode = UInt4((newPSD1 & 0xf00000) >> 20)
        setInstructionAddress(to: UInt32(newPSD1 & 0x1ffff))
        psd.zWriteKey = UInt4((newPSD2 >> 28) & 0x3)
        psd.zInhibit |= UInt4((newPSD2 >> 24) & 0x7)

        psd.zMAX = UInt8((newPSD2 >> 16) & 0xFF)
        if ((newPSD2 & 0x800000) != 0) {
            machine.log(level: .debug, "Exchange PSD: MA set.  EA="+hexOut((newPSD2 >> 16) & 0x3F))
        }

        if instruction.value.bitIsSet(bit: 8) {
            let rNew = Int(newPSD2 & 0xf0)
            psd.zRegisterPointer = rNew
            registerSetBA = rNew << 2
        }
        
    }
    
    // Trap sequences
    // SET TRAP INFO FOR BEGINNING OF NEXT INSTRUCTION CYCLE
    func trap (addr: UInt8, ccMask: UInt4 = 0) {
        if (Thread.current != machine.cpu) {
            machine.log(level: .error, "********** NON-CPU THREAD TRAPPED TO \(hexOut(addr,width:2)) ************")
            return
        }
        if (pendingTrap != nil) {
            machine.log(level: .error, "********** ATTEMPT TO TRAP TO "+String(format:"%X",addr)+" WITH PENDING TRAP "+String(format:"%X", pendingTrap.address)+" ************")
        }
        else if (addr != 0x48) {
            machine.log(level: .debug, "********** USER \(hexOut(currentUser,width:2)) TRAP \(hexOut(addr,width:2)) ************")
        }
        pendingTrap = TrapData(location: addr, cc: ccMask)
    }
    
    @objc func iNonexistent()  {
        if psd.zMaster {
            trap(addr: 0x40, ccMask: 0x8)
            return
        }
        
        switch (zInstruction.opCode) {
        case 0x0C, 0x0D, 0x2C, 0x2D:            // These are privileged as well as non-existent
            trap(addr: 0x40, ccMask: 0xA)
        default:
            trap(addr: 0x40, ccMask: 0x8)
        }
    }
    
    @objc func iUnimplemented()  {
        trap(addr: 0x41, ccMask: 0x0)
    }
    
    // Set CC1 based on unsigned carry.  Addition and subtraction are somewhat ambiguous.
    // They report the unsigned carry bit in CC1 but also the signed overflow state in CC2
    // So... we do the arithmetic unsigned (detecting the carry), then compute the signed overflow state
    // based on the first bit of the operands and result.
    func setCC1(_ carry: Bool) {
        psd.zCC1 = carry
    }
    
    // Set CC2 based on known overflow state
    func setCC2(_ v: Bool) {
        psd.zCC2 = v
        if (v) && (psd.zArithmeticMask) {
            trap(addr: 0x43, ccMask: 0)
        }
    }
    
    // Sets CC3 and 4 based on sign of value
    // All values except single bytes are considered to be signed.
    func setCC34<T: FixedWidthInteger>(_ value: T) {
        psd.zCC = (psd.zCC & 0xC)
        if !(value is UInt8), ((value.leadingZeroBitCount) == 0) {
            psd.zCC4 = true
            return
        }
        
        if (value != T(0)) {
            psd.zCC3 = true
        }
    }

    func setCC34<T: FixedWidthInteger>(rawValue: T) {
        psd.zCC &= 0xC
        if !(rawValue is UInt8), ((rawValue & T(UInt8(0x80))) != 0) {
            psd.zCC4 = true
            return
        }
        
        if (rawValue != T(0)) {
            psd.zCC3 = true
        }
    }

    // MARK: Common code for PLW, PLM
    func pullValid (_ spd: SPD!,_ n: Int = 1) -> Bool {
        let (a,u) = spd.checkModify(delta: -n)
        if (spd.trapAvailable  && a) || (spd.trapUsed && u) {
            trap (addr: 0x42)
            return false
        }
        psd.zCC1 = a
        psd.zCC3 = u
        return !(a || u)
    }
    
    
    func pullCommon (count: UInt32) {
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        var spd = SPD(dw: loadUnsignedDoubleWord(da: ea))
        if (trapPending) { return }
        
        var n = Int(count)
        if pullValid(spd, n) {
            var r = UInt4((Int(zInstruction.register) + n - 1) & 0xF)
            
            // Are we crossing a page boundary?
            if ((spd.pointer & 0x1FF) < n) {
                // Yes, do it slowly.
                while (n > 0) {
                    let w = loadRawWord(wa: spd.pointer)
                    if (trapPending) { return }
                    setRegisterRawWord(r, unsigned: w)
                    
                    // Update SPD
                    spd.pointer -= 1
                    spd.availableCount += 1
                    spd.usedCount -= 1
                    storeDoubleWord(da: ea, unsigned: spd.value)
                    if (trapPending) { return }
                    
                    n -= 1
                    r = r.previous
                }
            }
            else {
                var (t,ra) = memory.realAddress(ba: (spd.pointer) << 2, .write)
                if (t) { return }
                
                while (n > 0) {
                    let w = unmapped.loadRawWord(ra)
                    setRegisterRawWord(r, unsigned: w)
                    
                    r = r.previous
                    ra -= 4
                    n -= 1
                }
                
                // Update SPD
                spd.pointer -= Int(count)
                spd.availableCount += Int16(count)
                spd.usedCount -= Int16(count)
                storeDoubleWord(da: ea, unsigned: spd.value)
                if (trapPending) { return }
            }
        }
        
        //MARK: CC1 and CC3 will be set unless trapping to X'42'
        if (trapPending) { return }
        
        // CC2 and CC4 are set according to the new counts.
        psd.zCC2 = (spd.availableCount == 0)
        psd.zCC4 = (spd.usedCount == 0)
    }
    
    // MARK: Common code for PLW, PLM
    func pushValid (_ spd: SPD!,_ n: Int = 1) -> Bool {
        let (a,u) = spd.checkModify(delta: n)
        if (spd.trapAvailable  && a) || (spd.trapUsed && u) {
            trap (addr: 0x42)
            return false
        }
        psd.zCC1 = a
        psd.zCC3 = u
        return !(a || u)
    }
    
    func pushCommon(count: UInt32) {
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        var spd = SPD(dw: loadUnsignedDoubleWord(da: ea))
        if (trapPending) { return }
        
        var n = Int(count)
        if pushValid(spd, n) {
            var r = zInstruction.register
            
            // Are we crossing a page boundary?
            if (((spd.pointer & 0x1FF) + n) > 0x1FF) {
                // Yes, do it slowly.
                while (n > 0) {
                    spd.pointer += 1
                    let w = getRegisterRawWord(r)
                    storeRawWord(wa: Int(spd.pointer), unsigned: w)
                    if (trapPending) { return }
                    
                    // Update SPD
                    spd.availableCount -= 1
                    spd.usedCount += 1
                    storeDoubleWord(da: ea, unsigned: spd.value)
                    if (trapPending) { return }
                    
                    n -= 1
                    r = r.next
                }
            }
            else {
                var (t,ra) = memory.realAddress(ba: (spd.pointer+1) << 2, .write)
                if (t) { return }
                
                while (n > 0) {
                    let w = getRegisterRawWord(r)
                    unmapped.storeRawWord(ra, unsigned: w)
                    
                    r = r.next
                    ra += 4
                    n -= 1
                }
                
                // Update SPD
                
                spd.pointer += Int(count)
                spd.availableCount -= Int16(count)
                spd.usedCount += Int16(count)
                storeDoubleWord(da: ea, unsigned: spd.value)
                if (trapPending) { return }
            }
        }

        //MARK: CC1 and CC3 will be set unless trapping to X'42'
        if (trapPending) { return }
        
        // CC2 and CC4 are set according to the new counts.
        psd.zCC2 = (spd.availableCount == 0)
        psd.zCC4 = (spd.usedCount == 0)
    }
    
    //MARK: Common IO Instruction Code
    func commonIO (ioType: IORequest.IOType, command: Int ) {
        var ioStatus: UInt16 = 0
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect) & 0x7FF
        
        if (command != 0) {
            let order = unmapped.loadByte(Int(command) << 3)
            if (order == 0) {
                var ioTypeName = ""
                switch (ioType) {
                case .SIO: ioTypeName = "SIO"
                case .HIO: ioTypeName = "HIO"
                case .TIO: ioTypeName = "TIO"
                case .TDV: ioTypeName = "TDV"
                    //default: ioTypeName = "OTHER"
                }
                machine.log ("CommonIO detected Zero order. \(ioTypeName) Command @"+hexOut(command, width:16)+" Address: "+hexOut(ea,width:3))
            }
        }
        
        let n = ea >> 8
        if (n < machine.iopTable.count), let iop = machine.iopTable[n] {
            var req = IORequest(ioType: ioType, unitAddr: (ea & 0xFF), command: command, cpu:self, psd: psd.value)
            let cc12 = iop.request(rq: &req)
            
            if (cc12 <= 1) {
                let r = zInstruction.register
                if (r > 0) {
                    setRegister(r.u1, unsigned: (UInt32(req.status) << 16) | UInt32(req.byteCount))
                    if (r.isEven) {
                        setRegister(r, unsigned: UInt32(req.command))
                    }
                }
            }
            psd.zCC12 = cc12
            ioStatus = req.status
        }
        else {
            psd.zCC |= 0xC                      // NOT RECOGNIZED
        }
        addIOTrace (zInstruction.value, UInt16(ea), ioStatus, psd.zCC)
    }
    
    
    //MARK: INSTRUCTION DISPATCH: Used by EXU as weel as main()
    let instructionExecute: [Selector] =
    [#selector(iNonexistent),   #selector(iNonexistent),    #selector(iLCFI),           #selector(iNonexistent),
     #selector(iCAL1),          #selector(iCAL2),           #selector(iCAL3),           #selector(iCAL4),           //00-07
     #selector(iPLW),           #selector(iPSW),            #selector(iPLM),            #selector(iPSM),
     #selector(iNonexistent),   #selector(iNonexistent),    #selector(iLPSD),           #selector(iXPSD),           //08-0F
     #selector(iAD),            #selector(iCD),             #selector(iLD),             #selector(iMSP),
     #selector(iNonexistent),   #selector(iSTD),            #selector(iNonexistent),    #selector(iNonexistent),    //10-17
     #selector(iSD),            #selector(iCLM),            #selector(iLCD),            #selector(iLAD),
     #selector(iFP),            #selector(iFP),             #selector(iFP),             #selector(iFP),             //18-1F
     #selector(iAI),            #selector(iCI),             #selector(iLI),             #selector(iMI),
     #selector(iSF),            #selector(iS1),             #selector(iLAS),            #selector(iNonexistent),    //20-27
     #selector(iCVS),           #selector(iCVA),            #selector(iLM),             #selector(iSTM),
     #selector(iLRA),           #selector(iLMS),            #selector(iWAIT),           #selector(iLRP),            //28-2F
     #selector(iAW),            #selector(iCW),             #selector(iLW),             #selector(iMTW),
     #selector(iNonexistent),   #selector(iSTW),            #selector(iDW),             #selector(iMW),             //30-37
     #selector(iSW),            #selector(iCLR),            #selector(iLCW),            #selector(iLAW),
     #selector(iFP),            #selector(iFP),             #selector(iFP),             #selector(iFP),             //38-3F
     #selector(iTTBS),          #selector(iTBS),            #selector(iNonexistent),    #selector(iNonexistent),
     #selector(iANLZ),          #selector(iCS),             #selector(iXW),             #selector(iSTS),            //40-47
     #selector(iEOR),           #selector(iOR),             #selector(iLS),             #selector(iAND),
     #selector(iSIO),           #selector(iTIO),            #selector(iTDV),            #selector(iHIO),            //48-4F
     #selector(iAH),            #selector(iCH),             #selector(iLH),             #selector(iMTH),
     #selector(iNonexistent),   #selector(iSTH),            #selector(iDH),             #selector(iMH),             //50-57
     #selector(iSH),            #selector(iNonexistent),    #selector(iLCH),            #selector(iLAH),
     #selector(iNonexistent),   #selector(iNonexistent),    #selector(iNonexistent),    #selector(iNonexistent),    //58-5F
     #selector(iCBS),           #selector(iMBS),            #selector(iNonexistent),    #selector(iEBS),
     #selector(iBDR),           #selector(iBIR),            #selector(iAWM),            #selector(iEXU),            //60-67
     #selector(iBCR),           #selector(iBCS),            #selector(iBAL),            #selector(iINT),
     #selector(iRD),            #selector(iWD),             #selector(iAIO),            #selector(iMMC),            //68-6F
     #selector(iLCF),           #selector(iCB),             #selector(iLB),             #selector(iMTB),
     #selector(iSTCF),          #selector(iSTB),            #selector(iDECIMAL),        #selector(iDECIMAL),        //70-77
     #selector(iDECIMAL),       #selector(iDECIMAL),        #selector(iDECIMAL),        #selector(iDECIMAL),
     #selector(iDECIMAL),       #selector(iDECIMAL),        #selector(iDECIMAL),        #selector(iDECIMAL)]        //78-7F
    
    

    //MARK: INSTRUCTION ROUTINES
    // For optional instructions, check CPUFloat.swift, and CPUDecimal.swift
    
    //02: LCFI
    @objc func iLCFI() {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let instruction = zInstruction.value
        if ((instruction & 0x200000) != 0) {
            psd.zCC = UInt4((instruction & 0xf0) >> 4)
        }
        if ((instruction & 0x100000) != 0) {
            psd.zFloat.rawValue = UInt4(instruction & 0x0f)
        }
    }
    
    //04: CAL1
    @objc func iCAL1() {
        if (MSLogManager.shared.logLevel == .debug) {
            let detail = cal1Decode (i: zInstruction, ea: 0, cpu: self)
            machine.log(zInstruction.getDisplayText() + detail)
        }
        addCalTrace()
        trap(addr: 0x48, ccMask: zInstruction.register)
    }
    
    //05: CAL2
    @objc func iCAL2() {
        addCalTrace()
        trap(addr: 0x49, ccMask: zInstruction.register)
        //setStep()
    }
    
    //06: CAL3
    @objc func iCAL3() {
        addCalTrace()
        trap(addr: 0x4A, ccMask: zInstruction.register)
    }
    
    //07: CAL4
    @objc func iCAL4() {
        addCalTrace()
        trap(addr: 0x4B, ccMask: zInstruction.register)
    }
    
    //08: PLW
    @objc func iPLW() {
        pullCommon(count: 1)
    }
    
    //09: PSW
    @objc func iPSW() {
        pushCommon(count: 1)
    }
    
    //0A: PLM
    @objc func iPLM() {
        let n = (psd.zCC == 0) ? 16 : UInt32(psd.zCC)
        pullCommon(count: n)
    }
    
    //0B: PSM
    @objc func iPSM() {
        let n = (psd.zCC == 0) ? 16 : UInt32(psd.zCC)
        pushCommon(count: n)
    }
    
    //0E: LPSD
    @objc func iLPSD() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect) << 1
        if (trapPending) { return }
        
        let newPSD1 = loadUnsignedWord(wa: Int(ea))
        let newPSD2 = loadUnsignedWord(wa: Int(ea+1))
        if (trapPending) { return }
        
        if zInstruction.value.bitIsSet(bit: 8) {
            let rNew = Int(newPSD2 & 0xf0)
            // machine.log(level: .debug, "EA: "+hexOut(ea-1)+" RP=\(psd.zRegisterPointer)")
            psd.zRegisterPointer = rNew
            registerSetBA = rNew << 2
        }
        
        
        // Build new CPU state
        psd.zCC =    UInt4((newPSD1 & 0xf0000000) >> 28)
        psd.zFloat.rawValue = UInt4((newPSD1 & 0x07000000) >> 24)
        psd.zMode =  UInt4((newPSD1 & 0x00f00000) >> 20)
        setInstructionAddress(to: UInt32(newPSD1 & 0x1ffff))
        psd.zWriteKey = UInt4((newPSD2 >> 28) & 0x3)
        psd.zInhibit = UInt4((newPSD2 >> 24) & 0x7)
        
        //MARK: MA and Extension are not changed by LPSD.
        //psd.zMAX = UInt8((newPSD2 >> 16) & 0xFF)
        
        if zInstruction.value.bitIsSet(bit: 10) {
            if let ca = interrupts.currentActiveInterrupt() {
                let level = ca.level
                if zInstruction.value.bitIsSet(bit: 11) {
                    interrupts.arm(level, clear: true, instruction: zInstruction.value)
                }
                else {
                    interrupts.disarm(level, clear: true, instruction: zInstruction.value)
                }
            }
        }
        
        if (psd.zMapped) {
            //MARK: FIRST MAPPED INSTRUCTION:  THE MONITOR HAS BEEN LOADED.  THIS IS OUR CHANCE TO DYNAMICALLY DETERMINE SOME USEFUL MONITOR SYMBOLS...
            // If this is the first time, currentUserAddress (i.e. S:CUN)  will be zero (i.e. unknown).
            // If so, we are going to find its address.  Also, we will find P:NAME.
            // The value of each of these items is displayed in the debug window.
            if (monitorInfo == nil) {
                monitorInfo = MonitorInfo(unmappedMemory)
                machine.log("Detected S_CUN = \(hexOut(monitorInfo.currentUserAddress)), P_NAME = \(hexOut(monitorInfo.pnameAddress))")
                machine.log("\(monitorInfo.symbols.count) other symbols loaded.")
            }
        }
    }
    
    //0F: XPSD
    @objc func iXPSD() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        commonXPSD(zInstruction, isTrap: false)
    }
    
    //10: AD
    @objc func iAD () {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let md = loadUnsignedDoubleWord(da: da)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rd = (UInt64(getRegisterUnsignedWord(r)) << 32) | UInt64(getRegisterUnsignedWord(r.u1))
        let (v, carry, overflow) = rd.addReportingCarryAndOverflow(md)
        
        setRegister(r, unsigned: UInt32(v >> 32))
        setRegister(r.u1, unsigned: UInt32(v & 0xFFFFFFFF))
        
        setCC1(carry)
        setCC2(overflow)
        setCC34(v)
    }
    
    //11: CD
    @objc func iCD () {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let md = loadDoubleWord(da: da)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rd = (Int64(getRegister(r)) << 32) | Int64(getRegisterUnsignedWord(r.u1))
        
        psd.zCC &= 0xC                                  // Clear CC3,4
        if (rd > md) {
            psd.zCC3 = true
            return
        }
        if (rd < md) {
            psd.zCC4 = true
            return
        }
    }
    
    
    //12: LD
    @objc func iLD() {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let d = loadDoubleWord(da: da)
        if (trapPending) { return }
        
        setRegister(r, Int32(d >> 32))
        if (r.isEven) {
            setRegister(r.u1, unsigned: UInt32(d & 0xFFFFFFFF))
        }
        
        psd.zCC &= 0xC                                  // Clear CC3,4
        if (d > 0) {
            psd.zCC3 = true
            return
        }
        if (d < 0) {
            psd.zCC4 = true
            return
        }
    }
    
    //13: MSP
    @objc func iMSP() {
        psd.zCC = 0
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        var spd = SPD(dw: loadUnsignedDoubleWord(da: ea))
        if (trapPending) { return }
        
        let delta = Int(getRegisterHalf((UInt8(zInstruction.register) << 1) + 1))
        let (a, u) = spd.checkModify(delta: delta)
        if (spd.trapAvailable && a) || (spd.trapUsed && u) {
            trap(addr: 0x42)
            return
        }
        
        if !(a || u) {
            // Update SPD
            spd.pointer += delta
            spd.usedCount += Int16(delta)
            spd.availableCount -= Int16(delta)
            storeDoubleWord(da: ea, unsigned: spd.value)
        }
        else {
            psd.zCC1 = a
            psd.zCC3 = u
        }
        // CC2 and CC4 are set according to the new counts.
        psd.zCC2 = (spd.availableCount == 0)
        psd.zCC4 = (spd.usedCount == 0)
    }
    
    
    //15: STD
    @objc func iSTD() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect) << 1
        if (trapPending) { return }
        
        let r = zInstruction.register
        storeRawWord(wa: wa, unsigned: getRegisterRawWord(r))
        if (trapPending) { return }
        
        storeRawWord(wa: wa+1, unsigned: getRegisterRawWord(r.u1))
    }
    
    //18: SD
    @objc func iSD() {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let ud = loadUnsignedDoubleWord(da: da)
        if (trapPending) { return }
        let (cd, cc) = ud.twosComplementReportingCarry
        
        let r = zInstruction.register
        let rd = (UInt64(getRegisterUnsignedWord(r)) << 32) | UInt64(getRegisterUnsignedWord(r.u1))
        let (v, carry, overflow) = rd.addReportingCarryAndOverflow(cd)
        
        setRegister(r, unsigned: UInt32(v >> 32))
        setRegister(r.u1, unsigned: UInt32(v & 0xFFFFFFFF))
        
        setCC1(carry || cc)
        setCC2(overflow)
        setCC34(v)
    }
    
    //19: CLM
    @objc func iCLM() {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let md = loadDoubleWord(da: da)
        if (trapPending) { return }
        
        let r = getRegister(zInstruction.register)
        let mh = Int32(md >> 32)
        let ml = Int32(bitPattern:UInt32(md & 0xFFFFFFFF))
        
        psd.zCC = 0
        psd.zCC1 = (r > ml)
        psd.zCC2 = (r < ml)
        psd.zCC3 = (r > mh)
        psd.zCC4 = (r < mh)
    }
    
    //1A: LCD
    @objc func iLCD () {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        var d = loadDoubleWord(da: da)
        if (trapPending) { return }
        
        let overflow = (d == Int64.min)
        if (!overflow) { d = -d }
        
        setRegister(r, Int32(d >> 32))
        if r.isEven {
            setRegister(r.u1, unsigned: UInt32(d & 0xFFFFFFFF))
        }
        setCC34(d)
        setCC2(overflow)
    }
    
    //1B: LAD
    @objc func iLAD () {
        let da = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .double, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        var d = loadDoubleWord(da: da)
        if (trapPending) { return }
        
        let overflow = (d == Int64.min)
        if (!overflow) && (d < 0) { d = -d }
        setRegister(r, Int32(d >> 32))
        if r.isEven {
            setRegister(r.u1, unsigned: UInt32(d & 0xFFFFFFFF))
        }
        setCC34(d)
        setCC2(overflow)
    }
    

    //20: AI
    @objc func iAI () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        let rv = getRegisterUnsignedWord(r)
        let iv = zInstruction.extendedDisplacement
        let (ur, carry, overflow) = rv.addReportingCarryAndOverflow(iv)

        setRegister(r, unsigned: ur)
        setCC34(ur)
        setCC2(overflow)
        setCC1(carry)
    }
    
    //21: CI
    @objc func iCI () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        let rv = getRegister(r)
        let iv = zInstruction.signedDisplacement
        
        psd.zCC &= 0xC
        psd.zCC3 = (rv > iv)
        psd.zCC4 = (rv < iv)
        
        // MARK: WAS MISCODED CHECK ONLY LOW 20 BITS
        psd.zCC2 = ((rv & iv)  != 0)
    }
    
    //22: LI
    @objc func iLI() {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let value = zInstruction.signedDisplacement
        setRegister(zInstruction.register, Int32(value))
        setCC34(value)
    }
    
    //23: MI
    @objc func iMI() {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        let rv = getRegister(r.u1)
        let iv = zInstruction.signedDisplacement
        let mr = Int64(rv) * Int64(iv)
        let highWord = Int32(mr >> 32)
        let lowWord = UInt32(mr & 0xffffffff)
        setRegister(r, highWord)
        setRegister(r.u1, unsigned: lowWord)
        setCC34(mr)
        
        // CC2 says 64 bits required for result...
        if ((lowWord & u32b0) == 0) {
            psd.zCC2 = (highWord != 0)
        }
        else {
            psd.zCC2 = (highWord != -1)
        }
    }
    
    //24: SF - Floating point shift
    @objc func iSF() {
        let r = zInstruction.register
        var iw = zInstruction.value
        if (zInstruction.indirect) {
            // Calculate unindexed effective address using indirection.  This will be used as the shift type, length, etc
            iw = UInt32(effectiveAddress(reference: zInstruction.reference, indexRegister: 0, indexAlignment: .word, indirect: true))
            if (trapPending) { return }
        }
        
        var shift = iw & 0x7F
        var xv: UInt32 = 0
        let xr = zInstruction.index
        if (xr != 0) {
            xv = getRegisterUnsignedWord(xr) & 0x7F
            shift += xv
            shift &= 0x7F
        }
        
        let isLong = ((iw & 0x100) != 0)
        var v = (UInt64(getRegisterUnsignedWord(r)) << 32) | UInt64(isLong ? getRegisterUnsignedWord(r.u1) : 0)
        
        let isNegative = ((v & 0x8000000000000000) != 0)
        if (isNegative) {
            v = v.twosComplement
        }
        
        var characteristic = Int(v >> 56)
        var fraction = UInt(v & 0xFFFFFFFFFFFFFF)
        
        psd.zCC = 0
        if (shift < 0x40) {
            // left shift
            if (fraction == 0) {
                psd.zCC1 = true
                v = 0
            }
            else {
                while ((fraction & 0xF0000000000000) == 0) && (characteristic >= 0) && (shift > 0) {
                    fraction <<= 4
                    shift -= 1
                    characteristic -= 1
                }
                
                if ((fraction & 0xF0000000000000) != 0) {
                    // Normalized
                    psd.zCC1 = true
                }
                
                if (characteristic < 0) {
                    v = (UInt64(0x7F) << 56) | UInt64(fraction)
                    psd.zCC2 = true
                }
                else {
                    v = (UInt64(characteristic) << 56) | UInt64(fraction)
                }
            }
        }
        else {
            shift = 0x80 - shift
            repeat {
                fraction >>= 4
                shift -= 1
                characteristic += 1
            } while (fraction != 0) && (characteristic < 0x80) && (shift > 0)
            
            if !isLong { fraction &= 0xFFFFFF00000000 }
            if (fraction == 0) {
                v = 0
            }
            else if (characteristic >= 0x80) {
                v = UInt64(fraction)                // Characteristic is zero
                psd.zCC2 = true
            }
            else {
                v = (UInt64(characteristic) << 56) | UInt64(fraction)
            }
        }
        
        //  Revert negative
        if (isNegative) { v = v.twosComplement }
        
        // Set result
        if (isLong) { setRegister(r.u1, unsigned: UInt32(v & 0xFFFFFFFF)) }
        setRegister(r, unsigned: UInt32(v >> 32))
        
        if (isNegative) && (v != 0) {
            psd.zCC4 = true
        }
        else if (v > 0) {
            psd.zCC3 = true
        }
        
    }
    
    //25: S - SHIFT, various forms
    @objc func iS1() {
        let r = zInstruction.register
        var iw = zInstruction.value
        if (zInstruction.indirect) {
            // Calculate unindexed effective address using indirection.  This will be used as the shift type, length, etc
            iw = UInt32(effectiveAddress(reference: zInstruction.reference, indexRegister: 0, indexAlignment: .word, indirect: true))
            if (trapPending) { return }
        }
        
        var unsignedCount = iw & 0x7F
        var xv: UInt32 = 0
        let xr = zInstruction.index
        if (xr != 0) {
            xv = getRegisterUnsignedWord(xr) & 0x7F
            unsignedCount += xv
            unsignedCount &= 0x7F
        }
        
        var shiftType = (iw & 0x700) >> 8
        if (model == .s7) && (shiftType >= 6) { shiftType = 4 }

        // Now we can clear CC1 and 2; They may get set if left shift.
        psd.zCC &= 0x3
        

        let isLeft = (unsignedCount <= 0x3F)
        var shiftCount = isLeft ? Int(unsignedCount) : (Int(0x80 - unsignedCount))
        guard (shiftCount != 0) else { return }

        
        if ((shiftType & 1) == 0) {
            //MARK: SINGLE, Get the register contents
            let rv = getRegisterUnsignedWord(r)
            var v = rv

            if ((shiftType >> 1) == 1) {
                // MARK: SPECIAL CASES FOR CIRCULAR SHIFTS
                // Identity, always a right shift, so no CC.
                guard (shiftCount < 64) else { return }
                
                // Identity, count bits
                guard (shiftCount != 32) else {
                    let nb = v.nonzeroBitCount
                    psd.zCC1 = ((nb & 1) != 0)
                    if (nb != 0) && (nb != shiftCount) {
                        psd.zCC2 = true
                    }
                    return
                }
            }


            if (isLeft) {
                var mask = UInt32.max << (32-shiftCount)
                var bits = v & mask
                
                switch (shiftType >> 1) {
                case 0:                                 //MARK: LOGICAL
                    v <<= shiftCount
                    
                case 1:                                 //MARK: CIRCULAR
                    if (shiftCount > 32) {
                        shiftCount &= 0x1F
                        
                        mask = UInt32.max << (32-shiftCount)
                        bits = v & mask

                        psd.zCC1 = ((v.nonzeroBitCount & 1) != 0)
                        psd.zCC2 = (v != 0)
                        // MARK: Fall thru.  CC1 will get XORed with shift result
                    }
                    
                    v <<= shiftCount
                    v |= bits >> (32-shiftCount)
                    
                case 2:                                 //MARK: ARITHMETIC
                    v <<= shiftCount
                    
                default:                                //MARK: Not implemented
                    iUnimplemented()
                    return
                }
                
                psd.zCC ^= UInt4((bits.nonzeroBitCount & 1) << 3)    // CC1
                if !psd.zCC2 {
                    if (bits == mask) {
                        psd.zCC2 = ((v & u32b0) == 0)   // All one bits shifted out, but sign is positive
                    }
                    else if (bits == 0) {
                        psd.zCC2 = ((v & u32b0) != 0)   // All zero bits shifted out, but sign is negative
                    }
                    else {
                        psd.zCC2 = true
                    }
                }
            }
            else {
                var mask = UInt32.max >> (32-shiftCount)
                var bits = v & mask
                
                switch (shiftType >> 1) {
                case 0:                                 //MARK: LOGICAL
                    v >>= shiftCount
                    
                case 1:                                 //MARK: CIRCULAR
                    // MARK: SPECIAL CASES FOR CIRCULAR SHIFTS
                    if (shiftCount > 32) {
                        shiftCount &= 0x1F
                        
                        mask = UInt32.max << (32-shiftCount)
                        bits = v & mask
                    }
                    
                    v >>= shiftCount
                    v |= bits << (32-shiftCount)
                    
                case 2:                                 //MARK: ARITHMETIC
                    v = UInt32(bitPattern: Int32(bitPattern: v) >> shiftCount)

                default:                                //MARK: SEARCH
                    iUnimplemented()
                    return
                }
            }
            setRegister(r, unsigned: v)
        }
        else {
            //MARK: DOUBLE
            let rv = getRegisterUnsignedDouble(r)
            var v = rv
            
            if ((shiftType >> 1) == 1) {
                // MARK: SPECIAL CASE FOR CIRCULAR SHIFTS
                // Identity, always a right shift, so no CC
                guard (shiftCount < 64) else { return }
            }

            if (isLeft) {
                let mask = UInt64.max << (64-shiftCount)
                let bits = v & mask
                
                switch (shiftType >> 1) {
                case 0:                                 //MARK: LOGICAL
                    v <<= shiftCount
                    
                case 1:                                 //MARK: CIRCULAR
                    v <<= shiftCount
                    v |= bits >> (64-shiftCount)
                    
                case 2:                                 //MARK: ARITHMETIC
                    v <<= shiftCount
                    
                default:                                //MARK: Not implemented
                    iUnimplemented()
                    return
                }
                
                psd.zCC1 = ((bits.nonzeroBitCount & 1) != 0)    // CC1
                if !psd.zCC2 {
                    if (bits == mask) {
                        psd.zCC2 = ((v & u64b0) == 0)   // All one bits shifted out, but sign is positive
                    }
                    else if (bits == 0) {
                        psd.zCC2 = ((v & u64b0) != 0)   // All zero bits shifted out, but sign is negative
                    }
                    else {
                        psd.zCC2 = true
                    }
                }
            }
            else {
                let mask = UInt64.max >> (64-shiftCount)
                let bits = v & mask
                
                switch (shiftType >> 1) {
                case 0:                                 //MARK: LOGICAL
                    v >>= shiftCount
                    
                case 1:                                 //MARK: CIRCULAR
                    v >>= shiftCount
                    v |= bits << (64-shiftCount)
                    
                case 2:                                 //MARK: ARITHMETIC
                    v = UInt64(bitPattern: Int64(bitPattern: v) >> shiftCount)

                default:                                //MARK: SEARCH
                    iUnimplemented()
                    return
                }
            }
            setRegisterDouble(r, unsigned: v)
        }
        
    }
    

    
    //26: LAS
    @objc func iLAS() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        // TODO: Does this need to be memory atomic?
        let w = memory.loadAndSetRawWord(wa: wa)
        if (trapPending) { return }
        
        setRegisterRawWord(zInstruction.register, unsigned: w)
        setCC34(rawValue: w)
    }
    
    
    //28: CVS - Convert by Subtraction
    @objc func iCVS() {
        var mask: UInt32 = u32b0
        
        var ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        var registerB: UInt32 = 0
        var registerA = Int(getRegisterUnsignedWord(r))
        
        while (mask > 0) {
            let w = Int(loadUnsignedWord(wa: ea))
            if (w <= registerA) {
                registerA -= w
                registerB |= mask
            }
            mask >>= 1
            ea += 1
        }
        
        let a = UInt32(registerA & 0xFFFFFFFF)
        setRegister(r, unsigned: a)
        setRegister(r.u1, unsigned: registerB)
        setCC34(registerB)
    }
    
    //29: CVA - Convert by Addition
    @objc func iCVA() {
        var carry = false
        var registerA: Int = 0
        var mask: UInt32 = u32b0
        
        var ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let ru = getRegisterUnsignedWord(r.u1)
        
        while (mask > 0) {
            if ((ru & mask) != 0) {
                registerA += Int(loadUnsignedWord(wa: ea))
                if (registerA > UInt32.max) {
                    carry = true
                }
            }
            mask >>= 1
            ea += 1
        }
        
        let a = UInt32(registerA & 0xFFFFFFFF)
        setRegister(r, unsigned: a)
        setCC34(a)
        psd.zCC1 = carry
    }
    
    
    //2A: LM
    @objc func iLM() {
        var wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var r = zInstruction.register
        var count = UInt8(psd.zCC)
        if (count == 0) { count = 0x10 }
        while (count > 0) {
            let w = loadRawWord(wa: wa)
            if (trapPending) { return }
            
            setRegisterRawWord(r, unsigned: w)
            wa += 1
            r = r.next
            count -= 1
        }
    }
    
    //2B: STM
    @objc func iSTM() {
        var wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var r = zInstruction.register
        var count = UInt8(psd.zCC)
        if (count == 0) { count = 0x10 }
        while (count > 0) {
            let w = getRegisterRawWord(r)
            storeRawWord(wa: wa, unsigned: w)
            if (trapPending) { return }
            wa += 1
            r = r.next
            count -= 1
        }
    }
    
    //2C: LRA
    @objc func iLRA() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }

        let alignment = IndexAlignment(rawValue: Int(psd.zCC12))!
        let dwShift = 3 - alignment.rawValue
        
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: alignment, indirect: zInstruction.indirect)
        let ew = loadUnsignedWord(wa: ea)
        
        trap (addr: 0x40, ccMask: 8)
        
        if (trapPending) { return }
        
        // Mask address bits and dword align.
        let a = Int(ew >> dwShift) & 0xFFFF
        let x = Int(ew) & (0x7 >> alignment.rawValue)
        
        // SHORT EXIT WHEN REGISTER ADDRESS HERE?
        if (a < 0x8) {
            setRegister(zInstruction.register, unsigned: UInt32(a << 1) | (ew & 0x1))
            psd.zCC = 0xC
            return
        }
        
        let (rba, exists, lock, access) = memory.mapDoubleWordAddress(a)
        let ra = (rba << dwShift) | x
        
        setRegister(zInstruction.register, unsigned: (UInt32(lock) << 24) | UInt32(ra))
        psd.zCC12 = exists ? 0 : 3
        psd.zCC34 = UInt4(access)
    }
    
    //2D: LMS
    @objc func iLMS() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        switch (psd.zCC) {
        case 0:                                     // SAME AS LAS
            let w = memory.loadAndSetRawWord(wa: wa)
            if (trapPending) { return }
            setRegisterRawWord(zInstruction.register, unsigned: w)
        
        case 1:
            let w = memory.loadRawWord(wa: wa)
            setRegisterRawWord(zInstruction.register, unsigned: w)
            psd.zCC = 0

        case 2:                                     // SET BAD PARITY..
            let w = memory.loadRawWord(wa: wa)
            setRegisterRawWord(zInstruction.register, unsigned: w)

        case 7:                                     // SET CLOCK MARGIN - TODO: DOES THIS ALTER EFFECTIVE WORD?
            break
            
        case 8, 9, 10, 12, 13, 14:                  // GET STATUS WORD (0-2); GET STATUS AND CLEAR (0-2)
            setRegisterRawWord(zInstruction.register, unsigned: 0)
            
        case 15:
            memory.storeRawWord(wa: wa, unsigned: 0)
            if (trapPending) { return }
            
        default:
            return
        }
        
        //TODO: DOES ANYTHING OTHER THAN CASE 1 SET THE CONDITION CODE?
    }
    
    //2E: WAIT
    @objc func iWAIT() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        //_ = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        //if (trapPending) { return }
        
        if(kMinimumWaitTime > 0) {
            Thread.sleep(forTimeInterval: kMinimumWaitTime)
        }

        // Construct a semaphore to wait on.  This will happen at the top of the main CPU loop.
        setWait()
    }
    
    //2F: LRP - LOAD REGISTER POINTER
    @objc func iLRP() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let ew = loadWord(wa: ea)
        psd.zRegisterPointer = Int(ew & 0x0F0)
        registerSetBA = psd.zRegisterPointer << 2
    }
    
    //30: AW
    @objc func iAW () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegisterUnsignedWord(r)
        let (sv, carry, overflow) = rv.addReportingCarryAndOverflow(wv)

        setRegister(r, unsigned: sv)
        setCC1(carry)
        setCC2(overflow)
        setCC34(sv)
    }
    
    
    //31: CW
    @objc func iCW () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let mw = loadWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rw = getRegister(r)
        
        psd.zCC &= 0xC
        psd.zCC3 = (rw > mw)
        psd.zCC4 = (rw < mw)
        
        psd.zCC2 = ((rw & mw) != 0)
    }
    
    //32: LW
    @objc func iLW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let w = loadRawWord(wa: wa)
        if (trapPending) { return }
        
        setRegisterRawWord(zInstruction.register, unsigned: w)
        setCC34(rawValue: w)
    }
    
    //33: MTW
    //MARK: MEMORY ATOMIC.
    @objc func iMTW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = Int32(zInstruction.register)
        let delta = (r < 8) ? r : (r - 0x10)
        
        psd.zCC = 0                         // Clear ALL

        if (wa > 0xF) {
            if (delta != 0) {
                let (r, o, c) = memory.atomicModifyWord(wa: wa, by: delta)
                setCC1(c)
                setCC2(o)
                setCC34(r)
            }
            else {
                let r = memory.loadWord(wa: wa)
                setCC34(r)
            }
            return
        }
        
        // Target is a register, no need to worry about atomicity
        let ra = UInt4(wa)
        let rv = getRegisterUnsignedWord(ra)
        if (delta != 0) {
            let ru = UInt32(bitPattern: delta)
            let (ur, c, o) = rv.addReportingCarryAndOverflow(ru)
            
            setRegister(ra, unsigned: ur)
            setCC1(c)
            setCC2(o)
            setCC34(ur)
            return
        }
        
        /* MTW,0 <register> */
        setCC34(rv)
    }
    
    //35: STW
    @objc func iSTW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let w = getRegisterRawWord(zInstruction.register)
        storeRawWord(wa: wa, unsigned: w)
    }
    
    //36: DW
    @objc func iDW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        
        var dividend: Int64 = 0
        if r.isOdd {
            dividend = Int64(getRegister(r))
        }
        else {
            dividend = getRegisterDouble(r)
        }
        
        if (wv != 0) {
            let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: Int64(wv))
            if (quotient > Int32.min) && (quotient <= Int32.max) {
                setCC2(false)
                setRegister(r, Int32(remainder))
                setRegister(r.u1, Int32(quotient))
                setCC34(quotient)
                return
            }
        }
        setCC2(true)
    }
    
    //37: MW
    @objc func iMW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegister(r.u1)
        let mr = Int64(rv) * Int64(wv)
        let highWord = Int32(mr >> 32)
        let lowWord = UInt32(mr & 0xffffffff)
        setRegister(r, highWord)
        setRegister(r.u1, unsigned: lowWord)

        psd.zCC2 = false
        setCC34(mr)

        // CC2 says 64 bits required for result...
        if ((lowWord & u32b0) == 0) {
            psd.zCC2 = (highWord != 0)
        }
        else {
            psd.zCC2 = (highWord != -1)
        }
    }
    
    //38: SW
    @objc func iSW() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let uv = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        let (cv, cc) = uv.twosComplementReportingCarry
        
        let r = zInstruction.register
        let rv = getRegisterUnsignedWord(r)
        let (sv, ac, ao) = rv.addReportingCarryAndOverflow(cv)
        
        setRegister(r, unsigned: sv)
        setCC1(ac || cc)
        setCC2(ao)
        setCC34(sv)
    }
    
    //39: CLR
    @objc func iCLR() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let mw = loadWord(wa: wa)
        if (trapPending) { return }
        
        let r = getRegister(zInstruction.register)
        let ru1 = getRegister(zInstruction.register.u1)
    
        psd.zCC = 0
        psd.zCC1 = (ru1 > mw)
        psd.zCC2 = (ru1 < mw)
        psd.zCC3 = (r > mw)
        psd.zCC4 = (r < mw)
    }
    
    
    //3A: LCW
    @objc func iLCW () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var w = loadWord(wa: wa)
        if (trapPending) { return }
        
        let overflow = (w == Int32.min)
        if (!overflow) { w = -w }
        setRegister(zInstruction.register, Int32(w))
        setCC34(w)
        setCC2(overflow)
    }
    
    //3B: LAW
    @objc func iLAW () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var w = loadWord(wa: wa)
        if (trapPending) { return }
        
        let overflow = (w == Int32.min)
        if (!overflow) && (w < 0) { w = -w }
        setRegister(zInstruction.register, Int32(w))
        setCC34(w)
        setCC2(overflow)
    }
    
    
    //40: TTBS
    @objc func iTTBS () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        if (r == r.u1) {
            // "Unpredictable" says the manual.  Presumably a true quantum event.  For our purposes, let's trap
            iNonexistent()
            return
        }
        
        let ru1 = getRegisterUnsignedWord(r.u1)
        var tt = Int(zInstruction.unsignedDisplacement)             // Translation table  (if r=0))
        var mask: UInt8 = 0xFF
        if (r > 0) {
            let rv = getRegisterUnsignedWord(r)
            tt += Int(rv & 0x7FFFF)                                 // Finalize source address (i.e translation table)
            mask = UInt8(rv >> 24)
        }
        var da = Int(ru1 & 0xFFFFF)                                 // Destination
        var count = Int(ru1 >> 24)
        
        while (count > 0) {
            let b = loadByte(ba: da)
            let x = loadByte(ba: tt+Int(b))
            if ((x & mask) != 0) {
                setRegisterByte(UInt8(r) << 2, x & mask)
                setRegister(r.u1, unsigned: UInt32((count << 24) | da))
                psd.zCC4 = true
                return
            }
            
            da += 1
            count -= 1
        }
        setRegister(r.u1, unsigned: UInt32((count << 24) | da))
        psd.zCC4 = false
    }
    
    
    //41: TBS
    //MARK: Not currently interruptable
    @objc func iTBS () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        if (r == r.u1) {
            // "Unpredictable" says the manual.  Presumably a true quantum event.  For our purposes, let's trap
            iNonexistent()
            return
        }
        
        let ru1 = getRegisterUnsignedWord(r.u1)
        var tt = Int(zInstruction.unsignedDisplacement)             // Translation table  (if r=0))
        if (r > 0) {
            tt += Int(getRegisterUnsignedWord(r) & 0x7FFFF)         // Finalize source address (i.e translation table)
        }
        var da = Int(ru1 & 0xFFFFF)                                 // Destination
        var count = Int(ru1 >> 24)
        
        while (count > 0) {
            let b = loadByte(ba: da)
            let x = loadByte(ba: tt+Int(b))
            storeByte(ba: da, x)
            
            da += 1
            count -= 1
        }
        setRegister(r.u1, unsigned: UInt32((count << 24) | da))
    }
    
    
    //44:ANLZ
    @objc func iANLZ() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let w = Instruction(loadUnsignedWord(wa: wa))
        if (trapPending) { return }
        
        // set CC3 if indirect.
        psd.zCC = w.indirect ? 0x2 : 0x0
        
        let opCode = w.opCode
        if ((opCode & 0x5F) < 0x4) {
            // Immediate: set CC and done.
            // MARK: Probably these should reset CC3
            if (opCode < 0x40) {
                // Word:
                psd.zCC |= 0x9
            }
            else {
                psd.zCC |= 0x1
            }
        }
        else if (opCode >= 0x70) {
            // Byte
            let ea = effectiveAddress(reference: w.reference, indexRegister: w.index, indexAlignment: .byte, indirect: w.indirect)
            if (trapPending) { return }
            setRegister(zInstruction.register, Int32(ea))
        }
        else if (opCode >= 0x50) && (opCode < 0x60) {
            // Half
            let ea = effectiveAddress(reference: w.reference, indexRegister: w.index, indexAlignment: .half, indirect: w.indirect)
            if (trapPending) { return }
            setRegister(zInstruction.register, Int32(ea))
            psd.zCC |= 0x4
        }
        else if (opCode >= 0x08) && (opCode < 0x20) {
            // Doubleword
            let ea = effectiveAddress(reference: w.reference, indexRegister: w.index, indexAlignment: .double, indirect: w.indirect)
            if (trapPending) { return }
            setRegister(zInstruction.register, Int32(ea))
            psd.zCC |= 0xC
        }
        else {
            // Word
            let ea = effectiveAddress(reference: w.reference, indexRegister: w.index, indexAlignment: .word, indirect: w.indirect)
            if (trapPending) { return }
            setRegister(zInstruction.register, Int32(ea))
            psd.zCC |= 0x8
        }
    }
    
    //45: CS
    @objc func iCS () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var mw = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        var rw = getRegisterUnsignedWord(r)
        if r.isOdd {
            mw &= rw
        }
        else {
            let r1 = getRegisterUnsignedWord(r.u1)
            mw &= r1
            rw &= r1
        }
        
        // This instruction does not set CC2
        // MARK: (JAN 9, 24) CC34 is result of unsigned not signed setcomparison.
        psd.zCC34 = (rw == mw) ? 0 : ((rw < mw) ? 1 : 2)
    }
    
    //46: XW
    @objc func iXW () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        var w = getRegisterRawWord(r)
        if (wa <= 0xF) {
            let r2 = UInt4(wa)
            let t = w
            w = getRegisterRawWord(r2)
            setRegisterRawWord(r2, unsigned: t)
            setRegisterRawWord(r, unsigned: w)
        }
        else {
            w = memory.exchangeRawWord(wa: wa, unsigned: w)
            if (trapPending) { return }
            
            setRegisterRawWord(r, unsigned: w)
        }
        setCC34(rawValue: w)
    }
    
    //47: STS
    // MARK: This could get pushed down to the VirtualMemory object to make it faster, however then need to be aware of possibly storing into regs.
    @objc func iSTS() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let ew = loadRawWord(wa: wa)
        let r = zInstruction.register
        if r.isOdd {
            storeRawWord(wa: wa, unsigned: ew | getRegisterRawWord(r))
        }
        else {
            let m = getRegisterRawWord(r.u1)
            let v = (getRegisterRawWord(r) & m) | (ew & ~m)
            storeRawWord(wa: wa, unsigned: v)
        }
    }
    
    
    //48: EOR
    @objc func iEOR () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegisterUnsignedWord(r)
        let nv = rv ^ wv
        setRegister(r, unsigned: nv)
        setCC34(nv)
    }
    
    //49: OR
    @objc func iOR () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegisterUnsignedWord(r)
        let nv = rv | wv
        setRegister(r, unsigned: nv)
        setCC34(nv)
    }
    
    //4A: LS
    @objc func iLS () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let w = loadWord(wa: wa)
        if (trapPending) { return }
        let mask = getRegister(r.u1)
        var v = w & mask
        
        if r.isEven {
            let u = getRegister(r) & ~mask
            v |= u
        }
        setRegister(r, v)
        setCC34(v)
    }
    
    //4B: AND
    @objc func iAND () {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let wv = loadRawWord(wa: wa)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegisterRawWord(r)
        let nv = rv & wv
        
        setRegisterRawWord(r, unsigned: nv)
        setCC34(rawValue: nv)
    }
    
    //4C: SIO
    @objc func iSIO () {
        commonIO (ioType: .SIO, command: Int(getRegisterUnsignedWord(0) & 0x1FFFFF))
    }
    
    //4D: TIO
    @objc func iTIO () {
        commonIO (ioType: .TIO, command: 0)
    }
    
    //4E: TDV
    @objc func iTDV () {
        if (kTDVTime > 0) {
            Thread.sleep(forTimeInterval: kTDVTime)
        }
        commonIO (ioType: .TDV, command: 0)
    }
    
    //4F: HIO
    @objc func iHIO () {
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        let s9x = ea >> 14

        switch (s9x) {
        case 0:                                 //MARK: A REAL HIO
            commonIO (ioType: .HIO, command: 0)
            
        default:                                //MARK: RETURN ADDRESS RECOGNIZED.
            setRegister(zInstruction.register, 0)
            psd.zCC = (psd.zCC & 0x1)
        }
    }
    
    
    //50: AH
    @objc func iAH () {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let mh = UInt32(bitPattern: Int32(loadHalf(ha: ha)))
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rw = getRegisterUnsignedWord(r)
        let (ar, carry, overflow)  = rw.addReportingCarryAndOverflow(mh)
        
        setRegister(r, unsigned: ar)
        setCC1(carry)
        setCC2(overflow)
        setCC34(ar)
    }
    
    
    //51: CH
    @objc func iCH () {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let mh = Int32(loadHalf(ha: ha))
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rh = getRegister(r)
        
        psd.zCC &= 0xC
        psd.zCC3 = (rh > mh)
        psd.zCC4 = (rh < mh)
        
        psd.zCC2 = ((rh & mh) != 0)
    }
    
    //52: LH
    @objc func iLH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let h = loadHalf(ha: ha)
        if (trapPending) { return }
        
        setRegister(zInstruction.register, Int32(h))
        setCC34(h)
    }
    
    //53: MTH
    //MARK: MEMORY ATOMIC.
    @objc func iMTH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = Int8(zInstruction.register)
        let delta = (r < 8) ? r : (r - 0x10)

        psd.zCC = 0                     // Clear ALL

        if (ha > 0x1F) {
            if (delta != 0) {
                let (h, o, c) = memory.atomicModifyHalf(ha: ha, by: delta)
                setCC1(c)
                setCC2(o)
                setCC34(h)
                return
            }
            
            let h = memory.loadHalf(ha: ha)
            setCC34(h)
            return
        }
        
        // Target is a register, no need to worry about atomicity
        let uh = UInt16(getRegisterUnsignedHalf(UInt8(ha)))
        if (delta != 0) {
            let ud = UInt16(bitPattern: Int16(delta))
            let (n, c, o) = uh.addReportingCarryAndOverflow(ud)
            
            setRegisterHalf(UInt8(ha), unsigned: n)
            setCC1(c)
            setCC2(o)
            setCC34(n)
            return
        }
        
        // MTH,0 <reg>
        setCC34(uh)
    }
    
    //55: STH
    @objc func iSTH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let w = getRegisterUnsignedWord(zInstruction.register)
        let lh = UInt16(w & 0xFFFF)
        storeHalf(ha: ha, unsigned: lh)
        
        // MARK: Set CC2 appropriately, but do not trap
        let sign = lh & u16b0
        let hh = w >> 16
        psd.zCC2 =  (sign == 0) ? (hh > 0) : (hh < 0xFFFF)
    }
    
    
    //56: DH
    @objc func iDH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let hv = loadHalf(ha: ha)
        if (trapPending) { return }
        
        if (hv == 0) {
            setCC2(true)
            return
        }
        
        let r = zInstruction.register
        
        let dividend = getRegister(r)
        let (quotient, _) = dividend.quotientAndRemainder(dividingBy: Int32(hv))
        if (quotient < Int32.min) || (quotient > Int32.max) {
            setCC2(true)
        }
        else {
            setCC2(false)
            setRegister(r, quotient)
            setCC34(quotient)
        }
    }
    
    //57: MH
    @objc func iMH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let h = loadHalf(ha: ha)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let rv = getRegisterHalf((UInt8(r) << 1)+1)     // Get low half of register signed.
        
        let mr = Int32(rv) * Int32(h)
        setRegister(r.u1, mr)
        setCC34(mr)
    }
    
    //58: SH
    @objc func iSH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let uh = UInt32(bitPattern: Int32(loadHalf(ha: ha)))
        if (trapPending) { return }
        let (ch, cc) = uh.twosComplementReportingCarry
        
        let r = zInstruction.register
        let rw = getRegisterUnsignedWord(r)
        let (ar, carry, overflow)  = rw.addReportingCarryAndOverflow(ch)
        
        setRegister(r, unsigned: ar)
        setCC1(carry || cc)
        setCC2(overflow)
        setCC34(ar)
    }
    
    //5A: LCH
    @objc func iLCH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let h = -Int32(loadHalf(ha: ha))
        if (trapPending) { return }
        
        setRegister(zInstruction.register, h)
        setCC34(h)
    }
    
    //5B: LAH
    @objc func iLAH() {
        let ha = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .half, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        var h = Int32(loadHalf(ha: ha))
        if (trapPending) { return }
        
        if (h < 0) { h = -h }
        setRegister(zInstruction.register, h)
        setCC34(h)
    }
    
    
    //60: CBS
    @objc func iCBS () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        let ru1 = getRegisterUnsignedWord(r.u1)
        
        let count = Int(ru1 >> 24)
        var da = Int(ru1 & 0x7FFFF)
        checkDataBreakpoint(ba: UInt32(da), bl: UInt32(count), psd.zMapped, .read)

        let sr = (r > 0) ? Int(getRegister(r) & 0x7FFFF) : 0
        let sd = Int(zInstruction.unsignedDisplacement)
        var sa = (sd + sr) & 0x7FFFF
        if (r > 0) {
            checkDataBreakpoint(ba: UInt32(sa), bl: UInt32(count), psd.zMapped, .read)
        }

        var sb: UInt8 = 0
        var db: UInt8 = 0
        var n = count
        while (n > 0) {
            sb = loadByte(ba: sa)
            db = loadByte(ba: da)
            if (trapPending) { break }
            
            if (sb != db) { break }
            
            da += 1
            if (r > 0) {
                sa += 1
            }
            n -= 1
        }
        
        if (r > 0) && (r.isEven) {
            setRegister(r, (Int32((sa-sd) & 0x7FFFF)))
        }
        setRegister(r.u1, unsigned: UInt32((n << 24) | da))
        setCC34(Int(sb)-Int(db))
    }
    
    
    //61: MBS
    @objc func iMBS () {
        guard !(zInstruction.indirect) else { iNonexistent(); return }
        
        let r = zInstruction.register
        let ru1 = getRegisterUnsignedWord(r.u1)
        
        let count = Int(ru1 >> 24)
        var da = Int(ru1 & 0x7FFFF)
        checkDataBreakpoint(ba: UInt32(da), bl: UInt32(count), psd.zMapped, .write)

        let sr = (r > 0) ? Int(getRegister(r) & 0x7FFFF) : 0
        let sd = Int(zInstruction.unsignedDisplacement)
        let s0 = (sd + sr) & 0x7FFFF
        var sa = s0
        if (r > 0) {
            checkDataBreakpoint(ba: UInt32(sa), bl: UInt32(count), psd.zMapped, .read)
        }

        var n = count
        while (n > 0) {
            let sb = loadByte(ba: sa)
            if (trapPending) { break }

            storeByte(ba: da, sb)
            if (trapPending) { break }
            
            da += 1
            if (r > 0) {
                sa += 1
            }
            n -= 1
        }
        
        if (r > 0) && (r.isEven) {
            setRegister(r, Int32(sa-sd) & 0x7FFFF)
        }
        setRegister(r.u1, unsigned: UInt32((n << 24) | da))
    }
    

    //64: BDR
    @objc func iBDR () {
        branchInstruction = true
        let ea = UInt32(effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect))
        let r = zInstruction.register
        let v = getRegister(r)
        
        if (machine.optimizeWaits) && (v > 0) && (ea == psd.zInstructionAddress-1) {
            // This is a hard wait loop. Simulate wall clock elapsing, but not til the end of the control mutex.
            hardWaitInterval = Double(v) / 100000000.0  // * 100 on Aug 25, 2024
            
            // Pretend we did it n times.  (Main loop will count 1)
            opCount[zInstruction.opCode] += Int(v-1)
            
            setRegister(r, 0)
        }
        else {
            // Not branching to self, check boundary
            if (v == Int32.min) {
                setRegister(r, Int32.max)
                setInstructionAddress(to: ea)
            }
            else {
                setRegister(r, v-1)
                if (v > 1) {
                    setInstructionAddress(to: ea)
                }
            }
        }
    }
    
    //65: BIR
    @objc func iBIR () {
        branchInstruction = true
        let ea = UInt32(effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect))
        
        let r = zInstruction.register
        let v = getRegister(r)
        if (v == Int32.max) {
            //MARK: Boundary condition...
            setRegister(r, Int32.min)
            setInstructionAddress(to: ea)
        }
        else {
            setRegister(r, v+1)
            if (v < -1) {
                setInstructionAddress(to: ea)
            }
        }
    }
    
    
    
    //66: AWM
    //MARK: MEMORY ATOMIC.
    @objc func iAWM() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let delta = getRegister(r)
        if (wa > 0xF) {
            let (w, o, c) = memory.atomicModifyWord(wa: wa, by: delta)
            setCC1(c)
            setCC2(o)
            setCC34(w)
            return
        }
        
        // Target is a register, no need to worry about atomicity
        let ud = UInt32(bitPattern: delta)
        let ra = UInt4(wa)
        let w = getRegisterUnsignedWord(ra)
        let (n, c, o) = w.addReportingCarryAndOverflow(ud)
        
        setRegister(ra, unsigned: n)
        setCC1(c)
        setCC2(o)
        setCC34(n)
    }
    
    //67: EXU
    @objc func iEXU () {
        exuCount += 1
        if (exuCount >= 1024) {
            trap(addr: 0x46, ccMask: 0)           // WD Timer
        }
        else {
            // Going to recurse, so save current instruction.
            let savedInstruction = zInstruction
            let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
            if (ea < 0x10) {
                zInstruction.value = getRegisterUnsignedWord(UInt4(ea))
            }
            else {
                zInstruction.value = memory.loadUnsignedWord(wa: ea)
            }
            
            //FIXME: THIS IS KLUDGEY
            if (stopOnInstruction > 0), ((zInstruction.value & stopOnInstructionMask) == stopOnInstruction) {
                if breakOnRegister {
                    let v = getRegisterUnsignedWord(breakOnRegisterNumber)
                    if ((v & breakOnRegisterMask) == breakOnRegisterValue) {
                        breakMode = .operation
                        psd.zInstructionAddress -= 1
                        zInstruction = savedInstruction
                        return
                    }
                }
                else {
                    breakMode = .operation
                    psd.zInstructionAddress -= 1
                    zInstruction = savedInstruction
                    return
                }
            }
            
            let opCode = zInstruction.opCode
            perform(instructionExecute[opCode])
            zInstruction = savedInstruction
        }
    }
    
    //68: BCR
    @objc func iBCR () {
        branchInstruction = true
        let r = zInstruction.register & psd.zCC
        if (r == 0) {
            let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
            setInstructionAddress(to: UInt32(ea))
        }
    }
    
    //69: BCS
    @objc func iBCS () {
        branchInstruction = true
        let r = zInstruction.register & psd.zCC
        if (r != 0) {
            let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
            setInstructionAddress(to: UInt32(ea))
        }
    }
    
    //6A: BAL
    @objc func iBAL () {
        branchInstruction = true
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        setRegister(zInstruction.register, unsigned: psd.zInstructionAddress)
        setInstructionAddress(to: UInt32(ea))
    }
    
    
    //6B: INT
    @objc func iINT() {
        let wa = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let w = loadUnsignedWord(wa: wa)
        if (trapPending) { return }
        
        psd.zCC = UInt4(w >> 28)
        let r = zInstruction.register
        if (r.isOdd) {
            setRegister(r, unsigned: UInt32(w & 0xFFFF))
        }
        else {
            setRegister(r, unsigned: UInt32((w & 0xFFF0000) >> 16))
            setRegister(r.u1, unsigned: UInt32(w & 0xFFFF))
        }
    }
    
    //6C: RD
    @objc func iRD () {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        func packed(_ v: Int) -> Int32 {
            let (t,u) = v.quotientAndRemainder(dividingBy: 10)
            return Int32((t << 4) | u)
        }
        
        let mode = (zInstruction.reference >> 12) & 0x0F
        let function = (zInstruction.reference & 0xFFF)
        let r = zInstruction.register
        switch (mode) {
        case 0:
            switch (function) {
            case 0:
                psd.zCC = machine.senseSwitches                 // MARK: GET SENSE FROM PANEL

            case 0x10:                                          // MARK: READ MEM FAULT
                if (r > 0) {
                    setRegister(r, 0)
                }
                psd.zCC = machine.senseSwitches

            case 0x048:                                         // MARK: GET INHIBITS  (S9?)
                if (r > 0) {
                    setRegister(r, Int32(psd.zInhibit))
                }
             
            case 0x31D:                                         // MARK: READ BRANCH REGISTER
                if (r > 0) {
                    setRegister(r, 0)
                }
                
            default:
                machine.log(level: .always, "READ DIRECT MODE: \(mode), FUNCTION: \(function)")
                //trap(addr: 0x40)
                
            }
            
            break
            
        case 3:                                                 // MARK: COC
            if ((function & 0xf00) != 0) {
                trap(addr: 0x46, ccMask: 0)                     // Watchdog Timer
            }
            psd.zCC = 0
            
            var  d: UInt32 = 0
            let x = function >> 4
            if (x < machine.cocList.count) {
                let coc = machine.cocList[x]
                if let id = interrupts.currentActiveInterrupt(),
                   (id.device == coc) && (id.line < 64) {
                    d = UInt32((id.line & 0x3F) | 0x40)
                    if coc.lineData[Int(id.line)]!.trace {
                        machine.log("COC RD \(coc.name): \(hexOut(d,width:2)) -> Reg \(hexOut(UInt8(r),width: 1))")
                    }
                }
                else {
                    // Nobody interrupted recently, so fake the result
                    d = coc.readDirect (function & 0xf)
                }
                
            }
            
            if (r != 0) {
                setRegister(r, unsigned: d)
            }
            break
            
        case 15:
            if (r == 0) { break }
            let t = MSDate()
            let c = t.components()
            
            // Find a year (1971-1998) that matches days of the week and leap.
            var year = c.year - 28
            while (year >= 1999) {
                year -= 28
            }
            
            machine.log(level: .debug, "READ DIRECT MODE: \(mode), FUNCTION: \(function)")
            switch (function) {
            case 0:  setRegister(r, packed(c.second));   break;
            case 2:  setRegister(r, packed(c.minute));   break;
            case 4:  setRegister(r, packed(c.hour));     break;
            case 7:  setRegister(r, packed(c.day));      break;
            case 8:  setRegister(r, packed(c.month));    break;
            case 9:  setRegister(r, packed(year%100));   break;
            case 32: setRegister(r, packed(19));         break;
            default: setRegister(r, 0); break
            }
            break
            
        default:
            machine.log(level: .always, "READ DIRECT MODE: \(mode), FUNCTION: \(function)")
            psd.zCC = 0
        }
    }
    
    //6D: WD
    @objc func iWD () {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        let ea = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        let mode = (ea >> 12) & 0x0F
        switch (mode) {
        case 0:
            let function = ea & 0xFF8
            let cie = UInt4(ea & 0x7)
            switch (function) {
            case 0x020:                             // RESET INTERRUPT INHIBITS
                psd.zInhibit &= ~cie
                                
            case 0x030:                             // SET INTERRUPT INHIBITS
                psd.zInhibit |= cie
                
            case 0x040:                             // ALARM + OTHERS
                switch (cie) {
                case 0: zAlarm = false
                case 1: zAlarm = true
                case 2: zAlarmOutput = !zAlarmOutput
                    
                case 5: break                       // SET INTERNAL CONTROLS: IGNORE
                case 6: psd.zMA = false             // MODE ALTERED OFF
                case 7: psd.zMA = true              // MODE ALTERED ON
                    
                default: break
                }

            case 0x048:
                switch (cie) {
                case 0:                             // .048: SET INHIBITS
                    let r = zInstruction.register
                    psd.zInhibit  = UInt4(getRegister(r) & 0x7)
                
                case 1:                             // .049: SET SNAPSHOT REGISTER
                    break
                    
                default:
                    break
                }
                
            default:
                machine.log(level: .always, "WRITE DIRECT MODE: \(mode), FUNCTION: \(function)")
                break
            }
            psd.zCC = 0                             // MARK: KLUDGE, TEMP

            
        case 1:
            let group = (ea & 0xf)
            if (group <= 2) {
                let function = ((ea >> 8) & 0x7)
                let r = zInstruction.register
                let selection = (r > 0) ? getRegisterUnsignedWord(r) & 0xFFFF : 0
                var mask: UInt32 = 0x8000
                
                //MARK: TRANSLASTE GROUP to LEVEL RANGE. ASSUME GROUP 0
                var level =  0x02
                var last =  0x0D
                if (group > 0) {
                    //MARK: NOT 0, THERE IS NOT GROUP 1, SO THIS IS GROUP 2 (EXTERNAL, E.G. COCS)
                    level = 0x10
                    last = 0x1F
                }
                while (level <= last) {
                    if ((mask & selection) != 0) {
                        let levelName = hexOut(level,width:2)
                        switch (function) {
                        case 1:                     // DISARM SELECTED
                            interrupts.disarm(level, clear: true, instruction: zInstruction.value)
                            break
                        case 2:                     // ARM AND ENABLE
                            interrupts.armEnable(level, clear: true, instruction: zInstruction.value)
                            break
                        case 3:                     // ARM AND DISABLE
                            interrupts.armDisable(level, clear: true, instruction: zInstruction.value)
                            break
                        case 4:                     // ENABLE
                            interrupts.enable(level)
                            break
                        case 5:                     // DISABLE
                            interrupts.disable(level)
                            break
                        case 6:                     // ENABLE if bit set (See below)
                            interrupts.enable(level)
                            break
                        case 7:                     // TRIGGER
                            _ = interrupts.post(level, priority: 4)
                            // Do not interrupt before next instruction...CONSOLE CODE IN IOQ (@ CTOCINT) ASSUMES THIS
                            interruptSuppress = 1
                            break
                        default:
                            machine.log(level: .error, "WRITE DIRECT LEVEL: \(levelName), MODE: \(mode), FUNCTION: \(function)")
                            break
                        }
                    }
                    else {
                        if (function == 6) {
                            interrupts.disable(level)
                        }
                    }
                    mask >>= 1
                    level += 1
                }
            }
            psd.zCC &= 3                                        //MARK: FROM EMU?
            break
            
        case 3:
            let r = zInstruction.register
            let cocFunction = zInstruction.reference & 0xFFF
            if ((cocFunction & 0xf00) != 0) {
                trap(addr: 0x46, ccMask: 0)                     // Watchdog Timer
            }
            
            var zCC34: UInt4 = 0
            let x = cocFunction >> 4
            if (x < machine.cocList.count) {
                let coc = machine.cocList[x]
                zCC34 = coc.writeDirect (cocFunction & 0xf, data: getRegisterUnsignedHalf((UInt8(r) << 1)+1))
            }
            psd.zCC34 = zCC34
            break
            
        default:
            machine.log(level: .always, "WRITE DIRECT MODE: \(mode)")
            psd.zCC = 0
        }
        
        
    }
    
    //6E: AIO
    @objc func iAIO () {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        
        var address = zInstruction.reference
        if (zInstruction.indirect) {
            address = Int(loadUnsignedWord(wa: address))
        }
        
        if (((address >> 8) & 0x7) != 0) {
            // RESERVED.
            machine.log(level: .error, "Unexpected non-zero AIO reference field @ "+String(format:"%X",psd.zInstructionAddress-1))
            psd.zCC12 = 1
            return
        }
        
        if let id = interrupts.currentActiveInterrupt() {
            let devAddr = id.deviceAddr
            
            if let iop = machine.iopTable[Int(devAddr >> 8) & 0x7] {
                let (unrecognized, cc2, iopResult) = iop.aio(unitAddr: UInt8(devAddr & 0xff))
                
                if (unrecognized) {
                    machine.log(level: .error, "AIO: No interrupt recognized")
                    psd.zCC12 = 3
                    return
                }
                
                let aioResult = (UInt32(iopResult) << 16) | UInt32(devAddr)
                machine.log(level: .debug, "AIO: "+hexOut(aioResult))
                
                let r = zInstruction.register
                if (r > 0) {
                    setRegister(r, unsigned: aioResult)
                }
                
                psd.zCC1 = false
                psd.zCC2 = cc2
                addIOTrace(zInstruction.value, devAddr, iopResult, psd.zCC)
                return
            }
            
            // NO IOP for this interrupt
            machine.log(level: .debug, "Unexpected AIO attempt for device: "+String(format:"%X",devAddr)+" (IOP DOES NOT EXIST)")
            psd.zCC12 = 1
        }
        else {
            // THERE IS NO INTERRUPT
            psd.zCC12 = 3
        }
    }
    
    //6F: MMC - MOVE TO MEMORY CONTROL
    @objc func iMMC() {
        guard (psd.zMaster) else { trap(addr: 0x40, ccMask: 0x2); return }
        let _ = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .word, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let r = zInstruction.register
        let cc = getRegisterUnsignedWord(r.u1)
        var ea = Int(getRegister(r))
        var count = Int(cc >> 24)
        if (count == 0) {
            //machine.log(level: .debug, "MMC: Zero count... using 256")
            count = 256
        }
        let loadType = zInstruction.index
        switch (loadType) {
        case 1: // WRITE PROTECTION LOCKS (UNMAPPED)
            var start = UInt ((cc >> 9) & 0xFF)
            while (count > 0) {
                unmapped.setWriteLocks(word: loadUnsignedWord(wa: ea), startPage: start)
                ea += 1
                count -= 1
                start = ((start + 16) & 0x1FFF)
            }
            setRegister(r, Int32(ea))
            setRegister(r.u1, unsigned: (cc & 0x01ff) |  UInt32(start << 9))
            break
            
        case 2: // ACCESS PROTECTION
            var start = UInt ((cc >> 9) & 0xFF)
            while (count > 0) {
                memory.setAccess(word: loadUnsignedWord(wa: ea), startPage: start)
                ea += 1
                count -= 1
                start = ((start + 16) & 0xFF)
            }
            setRegister(r, Int32(ea))
            setRegister(r.u1, unsigned: (cc & 0x01ff) |  UInt32(start << 9))
            break
            
        case 4: // MEMORY MAP
            var start = UInt ((cc >> 9) & 0xFF)
            while (count > 0) {
                memory.setMap(word: loadUnsignedWord(wa: ea), startPage: start)
                ea += 1
                count -= 1
                start = ((start + 4) & 0xFF)
            }
            setRegister(r, Int32(ea))
            setRegister(r.u1, unsigned: (cc & 0x01ff) |  UInt32(start << 9))
            break
            
        case 5: // 13 bit form
            var start = UInt ((cc >> 9) & 0xFF)
            while (count > 0) {
                memory.setMapWide(word: loadUnsignedWord(wa: ea), startPage: start)
                ea += 1
                count -= 1
                start = ((start + 2) & 0xFF)
            }
            setRegister(r, Int32(ea))
            setRegister(r.u1, unsigned: (cc & 0x01ff) |  UInt32(start << 9))
            break
            
        default:
            //MARK: SIGMA 9 TRAPS TO '4D'
            iNonexistent()
        }
    }
    
    //70: LCF
    @objc func iLCF() {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let b = loadByte(ba: ba)
        if (trapPending) { return }
        
        if zInstruction.value.bitIsSet(bit: 10) {
            psd.zCC = UInt4(b >> 4)
        }
        if zInstruction.value.bitIsSet(bit: 11) {
            psd.zFloat.rawValue = UInt4(b & 0x7)
        }
    }
    
    //71: CB
    @objc func iCB () {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let b = loadByte(ba: ba)
        if (trapPending) { return }
        
        //let r = UInt8(getRegisterUnsignedWord(zInstruction.register) & 0xFF)
        // Faster?
        let r = getRegisterByte((UInt8(zInstruction.register) << 2) | 0x3)

        psd.zCC &= 0x8                      // Retain CC1
        psd.zCC2 = ((r & b) != 0)
        psd.zCC3 = (r > b)
        psd.zCC4 = (r < b)
    }
    
    //72: LB
    @objc func iLB() {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        let b = loadByte(ba: ba)
        if (trapPending) { return }
        
        setRegisterRawWord(zInstruction.register, unsigned: UInt32(b) << 24)
        setCC34(b)
    }
    
    //73: MTB
    //MARK: MEMORY ATOMIC.
    //MARK: Unlike MTH and MTW, this is an unsigned byte add
    @objc func iMTB() {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        // Extend 4-bit "R" field to 8 bits
        let r = UInt8(zInstruction.register)
        let delta = (r < 8) ? r : (r | 0xF0)
        
        psd.zCC = 0
        
        if (ba > 0x3F) {
            if (delta != 0) {
                let (b, o, c) = memory.atomicModifyByte(ba: ba, by: delta)
                setCC1(c)
                setCC2(o)                   // Always false
                setCC34(b)
                return
            }
            let b = memory.loadByte(ba: ba)
            setCC34(b)
            return
        }
        
        // Target is a register, no need to worry about atomicity
        // MARK: CC1, and CC2 are set if delta is non-zero
        let ra = UInt8(ba)
        var n = UInt(getRegisterByte(ra))
        if (delta != 0) {
            n += UInt(delta)
            setRegisterByte(ra, UInt8(n & 0xff))
            psd.zCC1 = (n > 0xff)
            psd.zCC2 = false
        }
        psd.zCC3 = ((n & 0xff) != 0)
        psd.zCC4 = false
    }
    
    //74: STCF
    @objc func iSTCF() {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        storeByte(ba: ba, (UInt8(psd.zCC) << 4) | UInt8(psd.zFloat.rawValue))
    }
    
    //75: STB
    @objc func iSTB() {
        let ba = effectiveAddress(reference: zInstruction.reference, indexRegister: zInstruction.index, indexAlignment: .byte, indirect: zInstruction.indirect)
        if (trapPending) { return }
        
        storeByte(ba: ba, UInt8(getRegister(zInstruction.register) & 0xFF))
    }
    
}

class EventTrace {
    var access = SimpleMutex()
    
    enum EventType: Int {
        case none = 0
        
        // Instruction events
        case branch = 1
        case cal = 2
        case ioInstruction = 3
        
        // Async IO events
        case interrupt = 4
        case interruptCleared = 5
        case interruptIgnored = 6
        
        case ioSIOStart = 7
        case ioSIODone = 8
        
        // State changes
        case ioStateDisarmed = 10
        case ioStateArmed = 11
        case ioStateActive = 12
        case ioStateWaiting = 13
        
        case other = 0x7f
    }
    
    class func eventTypeName(_ et: EventType) -> String {
        switch (et) {
        case .none:             return "NONE"
        case .branch:           return "BRANCH"
        case .cal:              return "CAL"
        case .ioInstruction:    return "IOINSTR"
        case .interrupt:        return "INTRRUPT"
        case .interruptCleared: return "CLEARED"
        case .interruptIgnored: return "IGNORED"
        case .ioSIOStart:       return "SIOSTART"
        case .ioSIODone:        return "SIODONE"
        case .ioStateArmed:     return "ARMED"
        case .ioStateDisarmed:  return "DISARM"
        case .ioStateActive:    return "ACTIVE"
        case .ioStateWaiting:   return "WAITING"
        default: break
        }
        return "OTHER"
    }
    
    struct EventTraceEntry {
        var type: EventType
        var count: Int              // # times repeated
        
        var ts: MSTimestamp         // When
        var ic: Int                 // Instrcution count
        var repeated: Int           // How many times this was repeated
        var user: UInt32            // S:CUN
        var psd: UInt64             // Where it happened (probably +1)
        var ins: UInt32             // The instruction
        var ea: UInt32              // The effective address or IO address.
        var cc: UInt4               // The condition code after the instruction
        var level: UInt8            // Interrupt Level, if applicable
        var deviceInfo: UInt16      // Device status or other information
        
        var ia: UInt32          { get { return CPU.PSD(psd).zInstructionAddress }}
        var mapped: Bool        { get { return CPU.PSD(psd).zMapped }}
    }
    
    
    var name: String
    var repeats: Bool
    var machine: VirtualMachine!
    
    var bufferSize: Int
    var bufferMask: Int
    var bufferTop: Int
    
    var eBuffer: [EventTraceEntry]  // Wraparaound buffer for 'capacity' events
    var eventCount: Int             // Total all time
    
    init (_ traceName: String, capacity: Int, countRepeats: Bool = false,_ machine: VirtualMachine!) {
        name = traceName
        repeats = countRepeats
        self.machine = machine
        
        // Force capacity to a power of 2
        let b = capacity.nonzeroBitCount
        if (b == 1) {
            bufferSize = capacity
        }
        else {
            bufferSize = (capacity << 1) & (Int.max >> capacity.leadingZeroBitCount)
        }
        bufferMask = bufferSize - 1
        
        bufferTop = bufferMask                  // First entry will be number 0
        eBuffer = Array(repeating: EventTraceEntry(type: .none, count: 0, ts: 0, ic: 0, repeated: 0, user: 0, psd: 0, ins: 0, ea: 0, cc: 0, level: 0, deviceInfo: 0), count: capacity)
        eventCount = 0
    }
    
    func eventCompare (_ a: EventTraceEntry, _ b: EventTraceEntry) -> Bool {
        return (a.ts < b.ts)
    }
    
    func entry(_ n: Int) -> EventTraceEntry? {
        var row: EventTraceEntry? = nil
        
        access.acquire()
        if (n < eventCount) && (n < bufferSize) {
            let x = (bufferTop - n) & bufferMask
            row = eBuffer[x]
        }
        access.release()
        return row
    }
    
    func addEvent (type: EventType, user: UInt32 = 0, psd: UInt64, ins: UInt32 = 0, address: UInt32 = 0, cc: UInt4 = 0, level: UInt8 = 0, deviceInfo: UInt16 = 0) {
        let p = CPU.PSD(psd)
        let ia = p.zInstructionAddress
        let mapped = p.zMapped
        
        access.acquire()
        if (repeats) && (ia == eBuffer[bufferTop].ia) && (mapped == eBuffer[bufferTop].mapped) {
            eBuffer[bufferTop].count += 1
            eBuffer[bufferTop].ic = machine.cpu.instructionCount
            eBuffer[bufferTop].ts = MSClock.shared.gmtTimestamp()
        }
        else {
            bufferTop = (bufferTop+1) & bufferMask
            eBuffer[bufferTop].type = type
            eBuffer[bufferTop].ts = MSClock.shared.gmtTimestamp()
            eBuffer[bufferTop].ic = machine?.cpu?.instructionCount ?? 0
            
            eBuffer[bufferTop].user = user
            eBuffer[bufferTop].psd = psd
            eBuffer[bufferTop].ea = address
            eBuffer[bufferTop].ins = ins
            eBuffer[bufferTop].cc = cc
            eBuffer[bufferTop].level = level
            eBuffer[bufferTop].deviceInfo = deviceInfo
            eBuffer[bufferTop].count = 1
        }
        eventCount += 1
        access.release()
    }
}
