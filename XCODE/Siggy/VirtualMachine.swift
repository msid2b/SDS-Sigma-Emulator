//
//  VirtualMachine.swift
//  Siggy
//
//  Created by MS on 2023-08-22.
//  This object is used to represent a single Virtual Machine.


import Foundation
import Quartz

// Various Thread priorities:
var kCPUPriority =  0.2
var kIOPriority =   0.6
var kInterruptPriority = 0.9

// Max number of active IOs on a single IOP - NO LONGER USED.
//let kIOPMaxActiveIOs = 16                   // MUST BE > #COCs, SHOULD BE 16

// These simulate time elapsing at "normal" or at least tolerable siggy speeds.
let kPowerOnTime = 1.0
let kInterruptCycleTime = 0.0002            // Check clock every 200 microseconds
let kIOStartTime = 0.000                    // IO Set-up time
let kIOCompletionTime = 0.000               // Wait time at end of IO
let kCPUFault = 0.01                        // Loop wait after CPU fault
let kCPURelease = 0.0                       // Time to wait after every n instructions.. This is only to cause threads to be rescheduled
let kPrinterLineTime = 0.01                 // Time for lineprinter to print a line
let kPunchLineTime = 0.01                   // Time to deliver the joke
let kCardReadTime = 0.01                    // Time to read a card
let kTapeRewindTime = 1.0                   // Pretty fast, really.
let kTapeSpaceTime = 0.01                   // Pretty fast, really.
let kTDVTime = 0.00                         // KLUDGE. Wait for things to quiesce.
let kMinimumWaitTime = 0.00                 // KLUDGE. Wait for things to quiesce.
let kCharacterTransmissionTime = 0.001      // Approx 10K Baud

// MARK: Generalized disk address
struct DiskAddress {
    let sectorExtension: [UInt32] = [0,2,1,3]
    
    var dctx: UInt8
    var sector: UInt32
    var wordValue: UInt32 { get { return UInt32((dctx) << 16) | (sector & 0xFFFF) | (sectorExtension[Int(sector >> 16)] << 16)}}
    
    init (dctx: UInt8, sector: UInt32) {
        self.dctx = dctx
        self.sector = sector
    }
    
    init (_ word: UInt32) {
        dctx = UInt8((word >> 16) & 0x3F)
        let sx = sectorExtension[Int(word >> 22) & 0x3]
        sector = (word & 0xFFFF) | (sx << 16)
    }
    
    init (_ d: Data) {
        dctx = d[0] & 0x3F
        let sx = sectorExtension[Int(d[0] >> 6)]
        sector = (sx << 16) | (UInt32(d[1]) << 8) | UInt32(d[2])
    }
}

class EventTrace {
    var access = SimpleMutex()
    
    enum EventType: Int {
        case none = 0
        
        // Instruction events
        case branch = 1
        case trap = 2
        case ioInstruction = 3

        case map = 4                // LPSD or XPSD caused map on or off
        case mmc = 5                // MMC instruction start
        case mmcWriteLock = 6
        case mmcAccess = 7
        case mmcMap = 8
        case mmcMapBig = 9
        
        // Async IO events
        case interrupt = 10
        case interruptCleared = 11
        case interruptIgnored = 12
        
        case ioSIOStart = 16
        case ioSIODone = 17
        
        // IO State changes
        case ioStateDisarmed = 20
        case ioStateArmed = 21
        case ioStateActive = 22
        case ioStateWaiting = 23
        
        case other = 0x7f
    }
    
    class func eventTypeName(_ et: EventType) -> String {
        switch (et) {
        case .none:             return "NONE"
        case .branch:           return "BRANCH"
        case .trap:             return "TRAP"
        case .ioInstruction:    return "IOINSTR"
        case .map:              return "MAPCHG"
        case .mmcWriteLock:     return "WRLOCK"
        case .mmcAccess:        return "ACCESS"
        case .mmcMap:           return "MAPPGS"
        case .mmcMapBig:        return "MAPBIG"

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
        var data: UInt64            // More data
        var registers: [UInt32]
        
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
        eBuffer = Array(repeating: EventTraceEntry(type: .none, count: 0, ts: 0, ic: 0, repeated: 0, user: 0, psd: 0, ins: 0, ea: 0, cc: 0, level: 0, deviceInfo: 0, data: 0, registers: []), count: capacity)
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
    
    func addEvent (type: EventType, user: UInt32 = 0, psd: UInt64, ins: UInt32 = 0, address: UInt32 = 0, cc: UInt4 = 0, level: UInt8 = 0, deviceInfo: UInt16 = 0, data: UInt64 = 0, registers: UnsafeMutablePointer<UInt32>? = nil) {
        let p = CPU.PSD(psd)
        let ia = p.zInstructionAddress
        let mapped = p.zMapped
        
        access.acquire()
        if (repeats) && (ia == eBuffer[bufferTop].ia) && (mapped == eBuffer[bufferTop].mapped) && (registers == nil) {
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
            eBuffer[bufferTop].data = data
            eBuffer[bufferTop].count = 1
            if (registers == nil) {
                eBuffer[bufferTop].registers = []
            }
            else {
                try! eBuffer[bufferTop].registers = Array(unsafeUninitializedCapacity: 16, initializingWith: addRegisters)
            }
            eventCount += 1
        }
        access.release()
        
        func addRegisters (rBuffer: inout UnsafeMutableBufferPointer<UInt32>, count: inout Int) throws -> Void {
            for i in 0...15 {
                rBuffer[i] = registers![i]
            }
            count = 16
        }
    }
    
}



// *********************************************** Memory Class ****************************************************
// Implements the real memory. Each page is protected by a semaphore mutex so that IO and CPU threads
// can work as independently as possible.
// This class handles the write-lock mechanism

class RealMemory: Any {
    // Emulated "Real" i.e. non-virtual memory.
    // Access is controlled at a page level.  This allows the CPU and IO devices to be modifying different pages concurrently.
    // TODO: Consider "banks" of memory which are the unit of access and which are multiples of the page size.
    
    struct Page {
        var access: SimpleMutex
        var writeLock: UInt8 = 0
        var bytes: UnsafeMutableRawPointer
    }

    let pageWordMask = 0x1ff
    let pageWordMaskU = UInt(0x1ff)
    let pageWordSize = 0x200
    let pageByteSize = 0x800

    private(set) var pageReads: UnsafeMutableBufferPointer<UInt>
    private(set) var pageWrites: UnsafeMutableBufferPointer<UInt>
    private(set) var executionCount: UnsafeMutableBufferPointer<UInt>

    
    private(set) var realPages: [Page?] = []
    private(set) var pageCount: Int
    let pageOffsetMask = 0x7FF
    
    var zeroBytes: UnsafeMutableRawPointer

    
    init (pages: Int) {
        pageCount = pages
        
        realPages = Array(repeating: nil, count: pageCount)
        for i in 0 ... pageCount-1 {
            realPages[i] = Page(access: SimpleMutex(), bytes: UnsafeMutableRawPointer.allocate(byteCount: pageByteSize, alignment: 8))
        }
        
        pageReads = UnsafeMutableBufferPointer<UInt>.allocate(capacity: pages)
        pageWrites = UnsafeMutableBufferPointer<UInt>.allocate(capacity: pages)
        executionCount = UnsafeMutableBufferPointer<UInt>.allocate(capacity: pages * 0x200)
        executionCount.initialize(repeating: 0)
        
        zeroBytes = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
        zeroBytes.initializeMemory(as: UInt64.self, to: 0)
        
        clear()
    }
    
    func clear() {
        for p in realPages {
            p?.bytes.initializeMemory(as: UInt64.self, repeating: 0, count: pageByteSize >> 3)
        }
    }

    //MARK: If a CPU accesses non-existent memory, trap it.
    private func trap(_ ba: Int, cc: UInt4 = 4) {
        if let cpu = Thread.current as? CPU {
            cpu.trap(addr: 0x40, ccMask: cc, ba: UInt32(ba & 0xFFFFFFFF))
        }
    }
    
    func writeLock(forAddress: Int) -> UInt8 {
        let px = Int(forAddress >> 11)
        
        //MARK: Writelocks are only applicable to the lower 128KW
        if (px <= 0x0ff) {
            if let page = realPages[px] {
                return page.writeLock
            }
        }
        return 0
    }
    
   // Load a word full of write locks (16 per word)
    func setWriteLocks (word: UInt32, startPage: UInt) {
        var w = word
        var c = UInt(16)
        var p = Int(startPage + c) & 0xFF
        
        while (c > 0) {
            c -= 1
            p = (p == 0) ? 0xFF : (p - 1)
            if (p > pageCount) { siggyApp.panic(message: "Page does not exist: "+hexOut(p)+": Lock "+hexOut(w)); return }
            
            realPages[p]?.writeLock = UInt8(w & 0x3)
            w >>= 2
        }
    }
    
    @inlinable func checkWriteLock(_ page: Page!) -> Bool {
        if let cpu = Thread.current as? CPU {
            let lock = page.writeLock & 0x3
            if (lock > 0) {
                let key = cpu.psd.zWriteKey
                if (key > 0) && (key != lock) {
                    return false
                }
            }
        }
        return true
   }
   
    
    @inlinable public func load<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
        let px = Int(offset >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = offset & pageOffsetMask
            page.access.acquire()
            let result = page.bytes.load(fromByteOffset: pbo, as: type)
            pageReads[px] += 1
            page.access.release()
            return result
        }
        trap(offset)
        return zeroBytes.load(as: type)
    }
    
    @inlinable public func storeBytes<T>(of value: T, toByteOffset offset: Int = 0, as type: T.Type) {
        let px = Int(offset >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = offset & pageOffsetMask
            page.access.acquire()
            if checkWriteLock(page) {
                page.bytes.storeBytes (of: value, toByteOffset: pbo, as: type)
                pageWrites[px] += 1
            }
            else {
                trap (offset, cc: 1)
            }
            page.access.release()
            return
        }
        trap(offset)
    }
    
    // Atomic Exchange
    public func exchangeRawWord (ba: Int,_ w: UInt32) -> UInt32 {
        let px = Int(ba >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = ba & pageOffsetMask
            page.access.acquire()
            let v = page.bytes.load(fromByteOffset: pbo, as: UInt32.self)
            if checkWriteLock(page) {
                page.bytes.storeBytes (of: w, toByteOffset: pbo, as: UInt32.self)
                pageWrites[px] += 1
            }
            else {
                trap (ba, cc: 1)
            }
            page.access.release()
            return v
        }
        trap(ba)
        return 0
    }
    

    // Memory atomic, modify operations: return (result, overflow, carry)
    public func atomicModifyByte(by delta: UInt8, atByteOffset offset: Int = 0) -> (UInt8, Bool, Bool) {
        let px = Int(offset >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = offset & pageOffsetMask
            page.access.acquire()
            let v = page.bytes.load(fromByteOffset: pbo, as: UInt8.self)
            let (sv, carry) = v.addingReportingOverflow(delta)
            if checkWriteLock(page) {
                page.bytes.storeBytes (of: sv, toByteOffset: pbo, as: UInt8.self)
                pageWrites[px] += 1
            }
            else {
                trap (offset, cc: 1)
            }
            page.access.release()
            return (sv, false, carry)
        }
        trap(offset)
        return (0, false, false)
    }
    
    public func atomicModifyHalf(by value: Int8, atByteOffset offset: Int = 0) -> (Int16, Bool, Bool) {
        let px = Int(offset >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = offset & pageOffsetMask
            page.access.acquire()
            
            let mv = (value >= 0) ? UInt16(value) : (value > Int16.min) ? (UInt16(-value).twosComplement) : 0x8000
            let v = page.bytes.load(fromByteOffset: pbo, as: UInt16.self).bigEndian
            let (sv, carry) = v.addingReportingOverflow(mv)
            if checkWriteLock(page) {
                page.bytes.storeBytes (of: sv.bigEndian, toByteOffset: pbo, as: UInt16.self)
                pageWrites[px] += 1
            }
            else {
                trap (offset, cc: 1)
            }
            page.access.release()
            let op = (value > 0) && (v <= 0x7FFF) && ((sv & 0x8000) != 0)
            let on = (value < 0) && (v > 0x7FFF) && ((sv & 0x8000) == 0)
            
            return (Int16(bitPattern: sv), op || on , carry)
        }
        trap(offset)
        return (0, false, false)
    }
    
    public func atomicModifyWord(by value: Int32, atByteOffset offset: Int = 0) -> (Int32, Bool, Bool) {
        let px = Int(offset >> 11)
        if (px < pageCount), let page = realPages[px] {
            let pbo = offset & pageOffsetMask
            page.access.acquire()
            
            let mv = (value >= 0) ? UInt32(value) : (value > Int32.min) ? (UInt32(-value).twosComplement) : 0x80000000
            let v = page.bytes.load(fromByteOffset: pbo, as: UInt32.self).bigEndian
            let (sv, carry) = v.addingReportingOverflow(mv)
            if checkWriteLock(page) {
                page.bytes.storeBytes (of: sv.bigEndian, toByteOffset: pbo, as: UInt32.self)
                pageWrites[px] += 1
            }
            else {
                trap (offset, cc: 1)
            }
            page.access.release()
            let op = (value > 0) && (v <= 0x7FFFFFFF) && ((sv & 0x80000000) != 0)
            let on = (value < 0) && (v > 0x7FFFFFFF) && ((sv & 0x80000000) == 0)
            
            return (Int32(bitPattern: sv), op || on , carry)
        }
        trap(offset)
        return (0, false, false)
    }
    
    
    func loadInstruction (word: Int) -> UInt32 {
        executionCount[word] += 1
        return load(fromByteOffset: word << 2, as: UInt32.self).bigEndian
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
        
        while (count > 0) && (px < pageCount) {
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
            
            //if (px > pageCount) {
            //    MSLog("moveData: Page wrapped to 0")
            //    px = 0
            //}
        }
    }
    
    // MARK: getData is used by devices for output operations.
    func getData (from address: Int, count: Int) -> Data {
        var px = address >> 11
        var offset = address & 0x7FF
        
        var remaining = count
        let data = NSMutableData()
        
        while (remaining > 0) && (px < pageCount) {
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
            
            //if (px > pageCount) {
            //    MSLog("getata: Page wrapped to 0")
            //    px = 0
            //}

        }
        return (data as Data)
    }
    
    
}



class VirtualMachine: NSObject {
    private(set) var pViewController: VMViewController!
    var viewController: VMViewController { get { return pViewController }}
    func setViewController (_ vc: VMViewController!) {
        pViewController = vc
    }
    
    func showWindow(_ sender: Any?) {
        viewController.view.window?.windowController?.showWindow(sender)
    }
    
    private var toolbar: ToolbarViewController!

    
    var name: String = "?"
    var url: URL!
    var cardURL: URL!
    var diskURL: URL!
    var tapeURL: URL!
    var reportURL: URL!
    var openStatus: OpenStatus = .none
    var startTime: Int64 = 0
    var db: SQLDB! = SQLDB()
    var consoleTTY: TTYDevice!
    var terminals: [TTYWindowController?] = []
    
    private var autoBoot: Bool = false
    private var bootDevice: Int = 0
    private var bootedLast: Int = 0
    private var memoryPages: Int = 0
    
    private(set) var mapClock4: Bool = true
    private(set) var optimizeClocks: Bool = true
    private(set) var optimizeWaits: Bool = true
    
    static let kAutoBoot = "AutoBoot"
    static let kAutoDate = "AutoDate"
    static let kAutoDelta = "AutoDelta"
    static let kAutoHGP = "AutoHGP"
    static let kAutoBatch = "AutoBatch"
    static let kBootDevice = "BootDevice"
    static let kBootedLast = "BootedLast"
    static let kDateCreated = "DateCreated"
    static let kMemoryPages = "MemoryPages"
    static let kName = "Name"
    static let kMapClock4 = "MapClock4"
    static let kOptimizeClocks = "OptimizeClocks"
    static let kOptimizeWaits = "OptimizeBDRWait"
    static let kDecimalInstructions = "DecimalInstructions"
    static let kDecimalTrace = "DecimalTrace"
    static let kFloatingPoint = "FloatInstructions"
    static let kFloatTrace = "FloatTrace"
    static let kReportDirectory = "ReportDirectory"
    static let kTapeDirectory = "TapeDirectory"
    static let kDiskDirectory = "DiskDirectory"
    static let kCardDirectory = "CardDirectory"
    static let kLogConsoleReads = "LogConsoleReads"
    static let kLogConsoleWrites = "LogConsoleWrites"
    
    
    // CP-V related data
    var monitorReferences: MonitorReferences?
    var currentUser: Int { get { return (monitorReferences == nil) ? 0 : Int(realMemory.loadUnsignedWord(word: monitorReferences!.currentUserAddress))  }}
    
    // HARDWARE
    var realMemory: RealMemory!
    var cpu: CPU!
    var iopTable: [IOP?] = []
    var iopCount: Int { get { var c = 0; for i in iopTable { if (i != nil) {c += 1}}; return c }}
    var senseSwitches: UInt4 { return viewController.senseSwitches }
    var isRunning: Bool { return (cpu != nil) && (cpu.isRunning) }
    
    init(_ url: URL!,_ create: Bool,_ installBase: Bool = false) {
        super.init()

        self.url = url
        self.tapeURL = FileManager.default.homeDirectoryForCurrentUser
        self.reportURL = FileManager.default.homeDirectoryForCurrentUser
        
        if (create) {
            openStatus = createVMDirectory(url, installBase)
        }
        else {
            openStatus = openVMDirectory(url)
        }
        
        log (level: .detail, "Opened \(url.path), Status: \(openStatus.rawValue)")
    }
    
    private func logPrefix() -> String {
        if (cpu != nil) {
            return "\(name) [PSD:"+hexOut(cpu.psd.value, width:16)+"] "
        }
        return "\(name) "
    }
    var prefix: String { get { return logPrefix() }}
    
    func log(level: MSLogManager.LogLevel = .always,_ line: String, functionName: String = #function, lineNumber: Int = #line) {
        MSLog (level: level, logPrefix()+": "+line, function: functionName, line: lineNumber)
    }
    
    // MARK: Put a marker in the log
    private var markerNumber: Int = 0
    func logMarker() {
        log(" *************************************************************************************************************************** MARK \(markerNumber)")
        markerNumber += 1
    }
    

    public enum OpenStatus: String {
        case none,
             ok,
             //okUpgradeRequired,
             
             failedDoesNotExist,
             failedAlreadyExists,
             failedCancelled,
             failedCannotCreate,
             failedCreateTableError,
             failedCreateIndexError,
             failedNotDirectory,
             failedNoDatabase,
             failedDatabaseOpenError,
             failedDatabaseError
        //failedDefaultsTableError
    }
    
    func sqlError (_ message: String) {
        // Log the error in any case.
        log (level: .warning, message + ": " + db.message)
        siggyApp.alert (.warning, message: message, detail: db.message)
    }
    
    private func createTables () -> OpenStatus {
        if !db.execute("CREATE TABLE IF NOT EXISTS SETTINGS (name TEXT PRIMARY KEY, value TEXT)") {
            sqlError("Cannot create SETTINGS table")
            db.close()
            return .failedCreateTableError
        }
        
        if !db.execute("CREATE TABLE IF NOT EXISTS BUFFERS (id INTEGER PRIMARY KEY, groupname TEXT, value TEXT)") {
            sqlError("Cannot create BUFFERS table")
            db.close()
            return .failedCreateTableError
        }
        
        if !db.execute("CREATE TABLE IF NOT EXISTS DEVICES (address INTEGER PRIMARY KEY, type CHAR(2), model INTEGER" +
                       ", hostpath TEXT, trace CHAR(1), mountable CHAR(1), interrupt INTEGER" +
                       ", flags0, LARGEINT, flags1 LARGEINT, intdata0 INTEGER, intdata1 INTEGER, intdata2 INTEGER, intdata3 INTEGER" +
                       ", stringdata TEXT) ")
        {
            sqlError ("Cannot create DEVICES table");
            db.close()
            return .failedCreateTableError
        }
        
        if !db.execute("CREATE UNIQUE INDEX IF NOT EXISTS DEVICEXPATH ON DEVICES (hostpath)") {
            sqlError ("Cannot create DEVICEXPATH index");
            db.close()
            return .failedCreateIndexError
        }
        
        return .ok
    }
    
    func set (_ name: String,_ value: String) {
        let stmt = SQLStatement(db)
        
        if !stmt.prepare (statement: "INSERT OR REPLACE INTO SETTINGS (name, value) VALUES (?,?)") {
            siggyApp.applicationDBSQLError ("INSERT PREPARE failed");
            return
        }
        
        stmt.bind_string (1, name)
        stmt.bind_string (2, value)
        
        if !stmt.execute() {
            siggyApp.applicationDBSQLError ("INSERT OR REPLACE failed")
        }
        stmt.done()
    }
    
    func getSetting (_ name: String) -> String? {
        let stmt = SQLStatement(db)
        
        if !stmt.prepare (statement: "SELECT value FROM SETTINGS WHERE name = ?") {
            siggyApp.applicationDBSQLError ("SELECT PREPARE failed");
            return "";
        }
        
        stmt.bind_string (1, name)
        
        if stmt.row() {
            let result = stmt.column_string(0)
            stmt.done()
            return result
        }
        stmt.done()
        return nil;
    }
    
    // Get a global setting but provide a default value
    func getSetting (_ name: String, _ d: String) -> String {
        if let v = getSetting(name) {
            return v
        }
        return (d)
    }
    
    // Get a global integer setting
    func getIntegerSetting(_ name: String,_ d: Int) -> Int {
        if let s = getSetting(name), let i = Int(s) { return i }
        return d
    }
    
    // Get a global float setting
    func getDoubleSetting(_ name: String,_ d: Double) -> Double {
        if let s = getSetting(name), let d = Double(s) { return d }
        return d
    }
    
    

    func setPasteBuffer (_ id: Int64,_ group: String?,_ text: String) {
        let stmt = SQLStatement(db)
        
        if !stmt.prepare (statement: "INSERT OR REPLACE INTO BUFFERS (id, groupname, value) VALUES (?,?,?)") {
            siggyApp.applicationDBSQLError ("INSERT PREPARE failed");
            return
        }
        
        stmt.bind_int64(1, (id <= 0) ? MSDate().gmtTimestamp : id)
        stmt.bind_string (2, group)
        stmt.bind_string (3, text)
        
        if !stmt.execute() {
            siggyApp.applicationDBSQLError ("INSERT OR REPLACE failed")
        }
        stmt.done()
    }
    
    var getPasteBufferStmt: SQLStatement? = nil
    func getPasteBuffer() -> (Int64?, String?, String?)? {
        if getPasteBufferStmt == nil {
            getPasteBufferStmt = SQLStatement(db)
            
            if !getPasteBufferStmt!.prepare (statement: "SELECT id, groupname, value FROM BUFFERS ORDER BY value") {
                siggyApp.applicationDBSQLError ("SELECT PREPARE failed");
                return nil
            }
        }
        
        if (getPasteBufferStmt!.row()) {
            let id = getPasteBufferStmt!.column_int64(0)
            let group = getPasteBufferStmt!.column_string(1)
            let text = getPasteBufferStmt!.column_string(2)
            let result = (id, group, text)
            return result
        }
        
        getPasteBufferStmt = nil
        return nil
    }
    
    
    func addDevice (address: Int, type: String, model: Int, hostFile: String? = nil, hostPath: String? = nil, mountable: Bool = false, interrupt: UInt8 = 0,
                    trace: Bool = false, intData: [Int] = [], flags: [UInt64] = [], stringData: String? = nil) -> Device? {
        
        let iopx = address >> 8
        if (iopx >= 6) { return nil }
        let unit = UInt8(address & 0xFF)
        
        let f0 = (flags.count > 0) ? flags[0] : 0
        let i0 = (intData.count > 0) ? intData[0] : 0

        
        // Create if necessary
        while (iopTable.count <= iopx) {
            iopTable.append(nil)
        }
        if (iopTable[iopx] == nil) {
            iopTable[iopx] = IOP(UInt8(iopx))
        }
        
        if let iop = iopTable[iopx] {
            if (iop.dxFromAddress(unit) >= 0) { return nil }
            switch (type) {
            case "TY":
                return iop.configure(machine: self, prefix: "TY", model: model, unitAddr: unit, trace: trace, hostPath: nil)
                
            case "LP":
                let path = (hostFile != nil) ? ("./"+hostFile!) : hostPath
                return iop.configure(machine: self, prefix: type, model: model, unitAddr: unit, trace: trace, hostPath: path, lpParms: PrintDevice.Configuration(i0, (f0 & 0x1) != 0, stringData))
                
            case "CP":
                let path = (hostFile != nil) ? ("./"+hostFile!) : hostPath
                return iop.configure(machine: self, prefix: type, model: model, unitAddr: unit, trace: trace, hostPath: path, flags: f0)  //flags: Directory mode,
            
            case "CR":
                //MARK: Ensure any previous path content is cleaned up. Otherwise it gets hotcarded
                return iop.configure(machine: self, prefix: type, model: model, unitAddr: unit, trace: trace, hostPath: nil)  //NOTE: ALWAYS MOUNTABLE.
                
            case "9T", "DP":
                let path = (hostFile != nil) ? ("./"+hostFile!) : hostPath
                return iop.configure(machine: self, prefix: type, model: model, unitAddr: unit, trace: trace, hostPath: path, mountable: mountable)
                
            case "DC":
                let path = (hostFile != nil) ? ("./"+hostFile!) : hostPath
                return iop.configure(machine: self, prefix: type, model: model, unitAddr: unit, trace: trace, hostPath: path)
                
            case "ME":
                return iop.configure(machine: self, prefix: "ME", model: model, unitAddr: unit, trace: trace,
                                     cocData: COCDevice.COCConfiguration(interruptA: interrupt, interruptB: interrupt+1,
                                                                numberOfLines: UInt8(intData[0]), firstLine: UInt8(intData[1]),
                                                                autoStart: flags[0], traceLines: flags[1]))
                
            default: break
            }
        }
        
        return nil
    }
    
    func device(from address: Int) -> Device? {
        let iop = address >> 8
        guard (iop < iopTable.count) else { return nil }
        
        let unit = UInt8(address & 0xFF)
        if let iopEntry = iopTable[iop] {
            let dx = iopEntry.dxFromAddress(unit)
            if (dx >= 0)  {
                return iopEntry.deviceList[dx]
            }
        }
        return nil
    }
    
    func device(withAddress: UInt16) -> Device? {
        return device(from: Int(withAddress))
    }
    
    func updateDeviceDB (deleting d: Device) {
        let stmt = SQLStatement(db)
        if !stmt.prepare (statement: "DELETE FROM DEVICES WHERE (address = ?)") {
            siggyApp.applicationDBSQLError ("DELETE PREPARE failed");
        }
        stmt.bind_int (1, Int(d.deviceAddress))
        
        if !stmt.execute() {
            siggyApp.applicationDBSQLError ("DELETE failed")
        }
        stmt.done()
    }
    
    func updateDeviceDB (from d: Device) {
        
        let stmt = SQLStatement(db)
        if !stmt.prepare (statement: "INSERT OR REPLACE INTO DEVICES (address, type, model, hostpath, trace, mountable, interrupt, stringdata, intdata0, intdata1, flags0, flags1) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)") {
            siggyApp.applicationDBSQLError ("INSERT PREPARE failed");
        }
        
        if let path = d.hostPath?.trimmingCharacters(in: [" "]), !path.isEmpty {
            stmt.bind_string (4, path)
        }
        
        stmt.bind_int (1, Int(d.deviceAddress))
        stmt.bind_string (2, String(d.typeString))
        stmt.bind_int (3, d.model)
        stmt.bind_bool (5, d.trace)
        stmt.bind_bool (6, d.mountable)
        if let lp = d as? PrintDevice {
            stmt.bind_string (8, "FONT:"+lp.config.fontName+";PAPER:"+lp.config.paper.rawValue)
            stmt.bind_int(9, lp.config.linesPerPage)
            stmt.bind_int64(11, Int64(lp.config.showVFC ? 0x1 : 0x0))
        }
        else if let cp = d as? CPDevice {
            stmt.bind_int64(11, Int64((cp.mode == .directory) ? 0x1 : 0))
        }
        else if let coc = d as? COCDevice {
            stmt.bind_int (7, coc.cocConfiguration.interruptA)
            stmt.bind_int (9, coc.cocConfiguration.numberOfLines)
            stmt.bind_int (10, coc.cocConfiguration.firstLine)
            stmt.bind_int64 (11, coc.cocConfiguration.autoStart)
            stmt.bind_int64 (12, coc.cocConfiguration.traceLines)
        }
        
        if !stmt.execute() {
            siggyApp.applicationDBSQLError ("INSERT OR REPLACE failed")
        }
        stmt.done()
    }
    
    
    func copyBase(_ url: URL!) {
        // Move copy of baseline devices to Data diredtory, create if necessary
        let deviceList: [(String,String)] = [("dpbf0","dp"), ("dpbf1","dp"), ("audiag","mt"), ("cpcp","mt"), ("cpcu","mt"), ("dttm","mt"), ("mtlu00","mt"), ("sighgp","cr")]
        
        
        for (baseName, baseType) in deviceList {
            var path: String?
            let baseFilename = baseName+"."+baseType
            
            if let d = siggyApp.bundle?.path(forResource: baseName, ofType: baseType) {
                path = d
            }
            else if let d = siggyApp.bundle?.path(forResource: baseFilename, ofType: "zip") {
                path = d
            }
            
            if (path != nil) {
                let u = URL(fileURLWithPath: path!) 
                _ = copyOrUnzip(u, toDirectory: url, toFile: baseFilename)
            }
            else {
                MSLog("Cannot copy baseline image for \(baseName)")
            }
        }
    }
    
    
    func createVMDirectory (_ url: URL!,_ installBase: Bool = false) -> OpenStatus {
        log(level: .detail, "Creating Virtual Machine: "+url.path)
        let mn = url.path
        
        if (!FileManager.default.fileExists(atPath: url.path)) {
            // Create the directory.
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            catch {
                siggyApp.FileManagerThrew(error, message: "Cannot create "+url.path)
                return .failedCannotCreate
            }
        }
        
        if !db.open(dbPath: url.appendingPathComponent("siggy.db").path) {
            sqlError("Could not open siggy.db")
            return .failedDatabaseOpenError
        }
        
        let createStatus = createTables()
        if createStatus != .ok {
            return createStatus
        }
        
        let dc = MSDate().displayString
        set(VirtualMachine.kDateCreated, dc)
        
        memoryPages = 256
        set(VirtualMachine.kMemoryPages, String(memoryPages))
                
        var tapeFile: String = "POTape"
        if (installBase) {
            copyBase(url)
            bootDevice = 0x1F0
        }
        else {
            bootDevice = 0x080
            
            let openPanel = NSOpenPanel();
            openPanel.message                 = "Choose PO Tape image - The tape image will be copied to the machine directory."
            openPanel.treatsFilePackagesAsDirectories = true
            openPanel.showsResizeIndicator    = true
            openPanel.showsHiddenFiles        = false
            openPanel.canCreateDirectories    = false;
            
            
            let result = openPanel.runModal()
            if (result == NSApplication.ModalResponse.OK),
               let source = openPanel.url,
               let t =  copyOrUnzip (source, toDirectory: url, toFile: tapeFile, useSourceExtension: true) {
                tapeFile = t
            }
        }
        
        // Create initial device configs
        let console = addDevice(address: 0x001, type: "TY", model: 7012) as? TTYDevice
        _ = addDevice(address: 0x002, type: "LP", model: 7450, hostFile: "lpa02", intData: [42], stringData: "FONT:MENLO;PAPER:PRINTER" )
        _ = addDevice(address: 0x003, type: "CR", model: 7140, hostFile: "cra03")
        _ = addDevice(address: 0x004, type: "CP", model: 7165, hostFile: "cpa04", flags: [1,0])
        _ = addDevice(address: 0x006, type: "ME", model: 7611, interrupt: 0x60, intData: [60,1], flags: [0,0])

        _ = addDevice(address: 0x080, type: "9T", model: 7323, hostFile:  tapeFile, mountable: true)
        _ = addDevice(address: 0x081, type: "9T", model: 7323, mountable: true)
        
        if !installBase {
            _ = addDevice(address: 0x082, type: "9T", model: 7323, mountable: true)
            _ = addDevice(address: 0x083, type: "9T", model: 7323, mountable: true)
        }
        
        _ = addDevice(address: 0x1F0, type: "DP", model: 7277, hostFile: "dpbf0.dp")
        _ = addDevice(address: 0x1F1, type: "DP", model: 7277, hostFile: "dpbf1.dp")
        _ = addDevice(address: 0x1F2, type: "DP", model: 7277, hostFile: "dpbf2.dp")
        _ = addDevice(address: 0x1F3, type: "DP", model: 7277, hostFile: "dpbf3.dp")
        
        if !installBase {
            _ = addDevice(address: 0x1F4, type: "DP", model: 7277, mountable: true)
            _ = addDevice(address: 0x1F5, type: "DP", model: 7277, mountable: true)
            _ = addDevice(address: 0x1F6, type: "DP", model: 7277, mountable: true)
            _ = addDevice(address: 0x1F7, type: "DP", model: 7277, mountable: true)
            
            _ = addDevice(address: 0x2f0, type: "DC", model: 3214, hostFile: "dccf0.dc")
            _ = addDevice(address: 0x2f1, type: "DC", model: 3214, hostFile: "dccf1.dc")
            _ = addDevice(address: 0x2f2, type: "DC", model: 3214, hostFile: "dccf2.dc")
            _ = addDevice(address: 0x2f3, type: "DC", model: 3214, hostFile: "dccf3.dc")
        }

        set(VirtualMachine.kBootDevice, hexOut(bootDevice, width:3))
        set("DateCreated", MSDate().displayString)

        
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "SettingsWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? SettingsViewController {
            if (.OK == vc.runModal (self)) {
                // make sure disks exist
                
            }
            else {
                // Remove what we have done so far.
                wc.close()
                do {
                    try FileManager.default.removeItem(at: url)
                }
                catch {
                    siggyApp.FileManagerThrew(error, message: "Cannot remove incomplete virtual machine: "+url.path)
                }
                
                return .failedCancelled
            }
            wc.close()
        }
        
        memoryPages = Int(getSetting(VirtualMachine.kMemoryPages, "256")) ?? 256
        if let lr = getSetting(VirtualMachine.kLogConsoleReads) {
            console?.logReads = (lr != "N") && (lr != "F")
        }
        if let lw = getSetting(VirtualMachine.kLogConsoleWrites) {
            console?.logWrites = (lw != "N") && (lw != "F")
        }

        self.name = mn
        self.url = url
        if let icon = siggyApp.machineIcon {
            NSWorkspace.shared.setIcon(icon, forFile: url.path)
        }
        return .ok
    }
    
    func openVMDirectory (_ url: URL!) -> OpenStatus {
        log(level: .detail, "Opening Virtual Machine: "+url.path)
        
        if !db.open(dbPath: url.appendingPathComponent("siggy.db").path) {
            sqlError("Could not open siggy.db")
            return .failedDatabaseOpenError
        }
        
        let createStatus = createTables()
        if createStatus != .ok {
            return createStatus
        }
        
        loadConfiguration(url)
        return .ok
    }
    
    func loadConfiguration (_ url: URL!) {
        var console: TTYDevice?
        
        name = url.deletingPathExtension().lastPathComponent + ":" + getSetting(VirtualMachine.kName, "*")
        
        if let aa = getSetting(VirtualMachine.kAutoBoot) {
            autoBoot = (aa == "Y")
        }
        bootDevice = hexIn(hex: getSetting(VirtualMachine.kBootDevice), defaultValue: 0)
        bootedLast = hexIn(hex: getSetting(VirtualMachine.kBootedLast), defaultValue: 0)
        memoryPages = Int(getSetting(VirtualMachine.kMemoryPages, "256")) ?? 256
        
        mapClock4 = true
        if let m4 = getSetting(VirtualMachine.kMapClock4) {
            if ((m4 == "N") || (m4 == "F")) {
                mapClock4 = false
            }
        }
        if let oc = getSetting(VirtualMachine.kOptimizeClocks) {
            optimizeClocks = (oc != "N") && (oc != "F")
        }
        if let ow = getSetting(VirtualMachine.kOptimizeWaits) {
            optimizeWaits = (ow != "N") && (ow != "F")
        }
        

        let s = SQLStatement(db)
        // Check for upgrade required
        if db.execute("ALTER TABLE DEVICES ADD COLUMN model INTEGER") {
            if db.execute("ALTER TABLE DEVICES RENAME COLUMN autostart TO flags0"),
               db.execute("ALTER TABLE DEVICES RENAME COLUMN linetrace TO flags1"),
               db.execute("ALTER TABLE DEVICES RENAME COLUMN lines TO intdata0"),
               db.execute("ALTER TABLE DEVICES RENAME COLUMN first TO intdata1"),
               db.execute("ALTER TABLE DEVICES ADD COLUMN intdata2 INTEGER"),
               db.execute("ALTER TABLE DEVICES ADD COLUMN intdata3 INTEGER"),
               db.execute("ALTER TABLE DEVICES ADD COLUMN stringdata INTEGER") {
                MSLog("DEVICES table updated...")
            }
        }

        if s.prepare(statement: "SELECT address, type, model, hostpath, trace, mountable, interrupt, intdata0, intdata1, flags0, flags1, stringdata  FROM DEVICES") {
            while (s.row()) {
                let address = s.column_int(0, defaultValue: 0)
                let type = s.column_string(1)
                let model = s.column_int(2, defaultValue: 0)
                var hostPath = s.column_string(3)
                let trace = s.column_bool(4, defaultValue: false)
                let mountable = s.column_bool(5, defaultValue: false)
                let interrupt = s.column_int(6,defaultValue: 0)
                let int0 = s.column_int(7,defaultValue: 0)
                let int1 = s.column_int(8,defaultValue: 0)
                let flags0 = s.column_uint64(9,defaultValue: 0)
                let flags1 = s.column_uint64(10,defaultValue: 0)
                let stringData = s.column_string(11)
                if let dt = type {
                // MARK: Clean up any remnant host path for tapes, else will get automatically mounted, which we probably don't want.
                    if (dt == "9T") && (address != bootDevice) && (mountable) { hostPath = nil }
                    let d = addDevice(address: address, type: dt, model: model, hostPath: hostPath, mountable: mountable, interrupt: UInt8(interrupt), trace: trace,
                                      intData: [int0, int1], flags: [flags0, flags1], stringData: stringData)
                    if (dt == "TY") { console = d as? TTYDevice }
                }
            }
        }
        
        if let lr = getSetting(VirtualMachine.kLogConsoleReads) {
            console?.logReads = (lr != "N") && (lr != "F")
        }
        if let lw = getSetting(VirtualMachine.kLogConsoleWrites) {
            console?.logWrites = (lw != "N") && (lw != "F")
        }

        if let p = getSetting(VirtualMachine.kReportDirectory) {
            reportURL = URL(fileURLWithPath: p)
        }
        if let p = getSetting(VirtualMachine.kTapeDirectory) {
            tapeURL = URL(fileURLWithPath: p)
        }

        if let icon = siggyApp.machineIcon {
            NSWorkspace.shared.setIcon(icon, forFile: url.path)
        }
    }
    
    
    func powerOff() {
        NotificationCenter.default.removeObserver(self)
        db.quiesce()
        db.close()
        openStatus = .none
        
        if (cpu != nil) {
            _ = cpu.control.acquire(waitFor: MSDate.ticksPerSecond)
            cpu.interrupts.cancel()
            cpu.cancel()
            cpu = nil
            
            realMemory = nil
        }
        
        for iop in iopTable {
            iop?.shutdown()
        }
        
        if let c = consoleTTY {
            c.controller.close()
            consoleTTY = nil
        }

        iopTable.removeAll()
    }
    
    @objc func powerOn (_ sender: Any?) {
        if (openStatus == .none) {
            if (openVMDirectory(self.url) != .ok) {
                siggyApp.alert(.warning, message: "PowerOn failed: Cannot open DB: \(self.url.path)", detail: "")
                return
            }
            openStatus = .ok
        }
        guard (openStatus == .ok) else { return }
        
        //TODO: Real Memory belongs to the Virtual Machine, so the object should be defined here...
        realMemory = RealMemory(pages: memoryPages)
        cpu = CPU(self, realMemory: realMemory)
        
        // Tell us if it stops
        NotificationCenter.default.addObserver(self, selector: #selector(cpuDidExit), name: .NSThreadWillExit, object: self)
        
        // reser view to panel
        viewController.showPanelTab()
        
        // Start it
        cpu.start()
        initForBoot(cpu)
    }
    
    func initForBoot(_ cpu: CPU!) {
        guard (cpu != nil) else { return }
        consoleTTY.start("Console (\(name))")
        
        // Now update Panel
        let dev = (bootDevice > 0) ? bootDevice : bootedLast
        viewController.panelViewController.setBootDevice(dev)
        
        if (dev > 0) {
            cpu.resetSystem()
            cpu.load(dev)
            set(VirtualMachine.kBootedLast, hexOut(dev, width:3))
            if (autoBoot) {
                cpu.setRun(stepMode: .none)
            }
        }
        
        startTime = MSClock.shared.gmtTimestamp()
        if (getSetting("Toolbar", "N") == "Y") {
            siggyApp.menuToolbar.state = .on
            toolbarStart()
        }
    }
    
    func toolbarStart() {
        if (toolbar == nil) {
            toolbar = ToolbarViewController(nibName: nil, bundle: nil)
            let w = NSWindow(contentViewController: toolbar)
            w.styleMask = NSWindow.StyleMask([.titled])
            w.level = .floating

            let wc = NSWindowController(window: w)
            toolbar.setMachine(self)
            
            toolbar.addWindow(consoleTTY.controller.windowController, label: "Console")
            
            for t in terminals {
                toolbar.addWindow(t)
            }
            
            wc.showWindow(self)
            wc.window?.title = name
            wc.windowFrameAutosaveName = "Toolbar"
            
            set("Toolbar", "Y")
        }
    }
    
    func toolbarStop() {
        if (toolbar != nil) {
            toolbar.view.window?.close()
            toolbar = nil
            set("Toolbar", "N")
        }
    }
    
    func addTerminalWindow(_ wc: TTYWindowController?) {
        if (wc != nil) {
            terminals.append(wc)
            toolbar?.addWindow(wc)
        }
    }
    
    func removeTerminalWindow(_ wc: TTYWindowController?) {
        if (wc != nil) {
            terminals.removeAll(where: { (t) -> Bool in return (t == wc) })
            toolbar?.removeWindow(wc)
        }
    }

    var IODevicesWC: SiggyWindowController?
    func IODeviceWindowStart (_ sender: Any) {
        if (IODevicesWC == nil),
           let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "IODevicesWindowController") as? SiggyWindowController,
           let vc = wc.contentViewController as? IODevicesViewController {
            vc.configure (self)
            IODevicesWC = wc
            toolbar?.addWindow(wc)
        }
        IODevicesWC?.showWindow(self)
    }
    
    func IODeviceWindowStop() {
        toolbar?.removeWindow(IODevicesWC)
        IODevicesWC = nil
    }


    
    //MARK: Called by CPU on first mapped instruction.  Now is  the time to determine the address of some useful CP-V items.
    //MARK: Don't do this if optimizeClocks is off, in that case we are probably running DIAGs.
    func getMonitorReferences() {
        if optimizeClocks {
            monitorReferences = MonitorReferences(realMemory)
            log("Detected S_CUN = \(hexOut(monitorReferences!.currentUserAddress)), P_NAME = \(hexOut(monitorReferences!.pnameAddress))")
        }
    }

    
    //MARK: Called by CPU thread when wait cycle happens.
    func waitCycle() {
        for iop in iopTable {
            iop?.waitCycle()
        }
    }
    
    
    // MARK: Special Handling for COC devices.
    var cocList: [COCDevice] = []
    func cocStart (_ tty: TTYViewController) -> Bool {
        var availableCOC: COCDevice?
        var availableLine: Int = -1
        
        for coc in cocList {
            // The COC must have been started with an SIO, which has not been completed.
            if ((coc.deviceStatus & 0xEF) != 0) {
                // See if there is an available line on the COC
                var k = 0
                while (k < coc.lineData.count) && (availableLine < 0) {
                    if let line = coc.lineData[k],
                       !line.disable,
                       line.tty == nil {
                        availableCOC = coc
                        availableLine = k
                    }
                    k += 1
                }
                
                if let a = availableCOC {
                    return a.startLine (availableLine, tty)
                }
            }
        }
        
        return false
    }
    
    @objc func cpuDidExit() {
        cpu = nil
        log ("CPUHALT")
    }
    
    
    // MARK: SNAPSHOTS.
    func copySnapshot(from source: URL!, to destination: URL!, operation: String = "copy") {
        let localFileManager = FileManager()
        let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .producesRelativePathURLs,.skipsSubdirectoryDescendants]
        
        if let fileEnumerator = localFileManager.enumerator(at: source, includingPropertiesForKeys: Array(resourceKeys), options: options) {
            var isDir: ObjCBool = false
            if localFileManager.fileExists(atPath: source.path, isDirectory: &isDir) && (isDir.boolValue) {
                if !localFileManager.fileExists(atPath: destination.path, isDirectory: &isDir) && (isDir.boolValue) {
                    do {
                        try localFileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                    }
                    catch {
                        siggyApp.FileManagerThrew(error, message: "Cannot create \(destination.path)")
                        return
                    }
                }
                
                powerOff()
                
                var count = 0
                var errors = 0
                for case let fromURL as URL in fileEnumerator {
                    let destURL = destination.appendingPathComponent(fromURL.lastPathComponent)
                    do {
                        if (localFileManager.fileExists(atPath: destURL.path)) {
                            try localFileManager.removeItem(at: destURL)
                        }
                        try localFileManager.copyItem(at: fromURL, to: destURL)
                    } catch {
                        siggyApp.FileManagerThrew(error, message: "Cannot copy \(fromURL.path) to \(destURL.path)")
                        errors += 1
                    }
                    count += 1
                }
                siggyApp.alert(.informational, message: "\(operation.capitalized) of \(count) files completed", detail: ((errors > 0) ? "\(errors)" : "No") + " errors encountered")

                if (errors <= 0) && (openVMDirectory(self.url) != .ok) {
                    siggyApp.alert(.warning, message: "Copy from "+source.path+" failed", detail: "\(errors) errors")
                }
                
                perform(#selector(powerOn), with: self, afterDelay: kPowerOnTime)
                return
            }
        }
        siggyApp.alert(.warning, message: "\(operation.capitalized) of "+source.path+" failed", detail: "")
    }
    
    
    
    // MARK: Snapshot routines
    func takeSnapshot(name: String) {
        let directory = (name != "") ? name : (self.name + MSDate().ISO8601Format())
        let snapshot = siggyApp.snapshotDirectory.appendingPathComponent(directory)
        copySnapshot(from: self.url, to: snapshot, operation: "save")
    }
    
    func restoreSnapshot(snapshot: URL!) {
        copySnapshot(from: snapshot, to: self.url, operation: "restore")
    }
    
    func deleteSnapshot(snapshot: URL!) -> Bool {
        do {
            try FileManager.default.removeItem(at: snapshot)
            siggyApp.alert(.informational, message: "The snapshot \(snapshot.lastPathComponent) was removed", detail: "")
        }
        catch {
            siggyApp.FileManagerThrew(error, message: "Cannot delete \(snapshot.path)")
            return false
        }
        return true
    }
}
