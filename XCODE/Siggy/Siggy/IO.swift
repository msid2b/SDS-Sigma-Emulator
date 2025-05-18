//
//  IO.swift
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

//  Emulation for IOPs and various devices.
//  This model does not attempt to emulate the subtleties of the actual intereaction of IOPs, device controllers, and devices.
//  Instead it porovides a more asyncronous work-alike model, that is hopefully indistinguishable from the point of view of the CPU(s).
//  Should be easily adaptable to a multi-CPU implementation.
//

import Foundation
import Quartz

struct IORequest {
    enum IOType {
        case SIO
        case HIO
        case TIO
        case TDV
    }
    
    var ioType: IOType
    var unitAddr: Int           // DC and Device
    var command: Int            // IO Command DW
    var status: UInt16 = 0
    var byteCount: UInt16 = 0
    
    var cpu: CPU!               // The CPU that made the request.
    var psd: UInt64             // The PSD when the SIO was executed.
}

class IOCommand: Any {
    var value: UInt64
    var order: UInt8  { get { return UInt8(value >> 56) }}
    var memoryAddress: Int { get { return Int((value >> 32) & 0xFFFFFF) }}

    var flags: UInt8 { get { return UInt8((value & 0x0FF000000) >> 24) }}
    var fDataChain:     Bool { get { return ((value & 0x80000000) != 0) }}
    var fInterruptZBC:  Bool { get { return ((value & 0x40000000) != 0) }}
    var fCommandChain:  Bool { get { return ((value & 0x20000000) != 0) }}
    var fInterruptCE:   Bool { get { return ((value & 0x10000000) != 0) }}
    var fHaltTE:        Bool { get { return ((value & 0x08000000) != 0) }}
    var fInterruptUE:   Bool { get { return ((value & 0x04000000) != 0) }}
    var fSuppressIL:    Bool { get { return ((value & 0x02000000) != 0) }}
    var fSkip:          Bool { get { return ((value & 0x01000000) != 0) }}

    var count: UInt16 { get { return UInt16(value & 0xFFFF) } set { value &= 0xFFFFFFFFFFFF0000; value |= UInt64(newValue) }}
        
    func getDisplayText() -> String {
        return "ORDER="+orderName()+", MBA/WA="+String(format:"%X/",memoryAddress)+hexOut(memoryAddress>>2,width:5)+", FLAGS="+String(format:"%X",flags)+", COUNT="+String(format:"%X",count)
    }
    
    func orderName() -> String {
        if ((order & 0x3) == 3) {
            switch (order & 0x7F) {
            case 0x03: return "SEEK"
            case 0x13: return "TEST"
            case 0x23: return "REWF"
            case 0x33: return "REWO"
            case 0x43: return "SRFW"
            case 0x4B: return "SRBK"
            case 0x53: return "SFFW"
            case 0x5B: return "SFBK"
            case 0x63: return "ERAS"
            case 0x73: return "MARK"
            default: return "?"+hexOut(order,width:2)+"?"
            }
        }
        else if ((order & 0x08) != 0) {
            return "TIC"
        }
        else {
            switch (order & 0x3) {
            case 0: return "STOP"
            case 1: return "WRIT"
            case 2: return "READ"
            default: return "CTRL"
            }
        }
    }
    
    init (_ rawValue: UInt64) {
        self.value = rawValue
    }
    

}


// MARK: IOP
// The IOP is a set of methods to simulate the IOP.
// The IOP is not a separate thread, instead it validates requests called by the CPU thread and submits them to an operation queue
// The operation queue feeds multiple threads that simulate devices.


class IOP: NSObject {
    var access = SimpleMutex()
    var iopNumber: UInt8                    // Three bits

    private var devices: [Device] = []      //  Built by "configure()"
    var deviceList: [Device] { get { return devices }}
    
    
    init(_ n: UInt8) {
        iopNumber = n
        super.init()
    }
    
    func dxFromAddress(_ unitAddr: UInt8) -> Int {
        if let dx = devices.firstIndex(where: { d in (d.unitAddr == unitAddr)}) {
            return dx
        }
        return -1
    }
    
    func devAddr (unit: UInt8) -> UInt16 {
        return (UInt16(iopNumber) << 8) | UInt16(unit)
    }
    
    func configure(machine: VirtualMachine!, prefix: String, model: Int, unitAddr: UInt8, trace: Bool = false, hostPath: String? = nil, mountable: Bool = false, flags: UInt64 = 0,
                   storageConfiguration: BlockDevice.StorageConfiguration? = nil, cocData: COCDevice.COCConfiguration? = nil, lpParms: PrintDevice.Configuration? = nil) -> Device? {
        if let dt = Device.DType.prefix.firstIndex(where: { s in (s == prefix)}) {
            if (dxFromAddress (unitAddr) >= 0) {
                MSLog(level: .error, "IOP \(iopNumber): Attampt to reconfigure unit: " + hexOut(unitAddr))
            }
            
            if let deviceType = Device.DType(rawValue: dt) {
                // Get the appropriate host file open.
                var device: Device?
                var fullPath: String?
                
                let deviceName = prefix + String(format:"%X",iopNumber+(deviceType.isMultiplexed ? 10 : 0)) + String(format:"%02X",unitAddr)
                
                if let hostPath = hostPath  {
                    fullPath = hostPath
                }
                else {
                    if  (deviceType != .tty) && (deviceType != .me) {
                        MSLog(level: .warning, "IOP \(iopNumber): Creating device without host path: " + deviceName)
                    }
                }

                switch (deviceType) {
                case .tty:
                    device = TTYDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model)
                    
                case .lp:
                    let path = fullPath ?? machine.url.appendingPathComponent(deviceName+".output").path
                    if let parms = lpParms {
                        if parms.burst {
                            device = PDFDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, directory: path, config: lpParms!)
                            break
                        }
                    }
                    device = LPDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, path: path, config: PrintDevice.Configuration(40, false, nil))
                    
                case .cr:
                    device = CRDevice (machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model)
                    if let p = fullPath, let t = device as? CRDevice {
                        _ = t.load(p, mode: .read)
                    }
                    
                case .cp:
                    let path = fullPath ?? machine.url.appendingPathComponent(deviceName+".output").path
                    device = CPDevice (machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, directory: path, flags: flags)
                    
                case .me:
                    if let cd = cocData {
                        device = COCDevice (machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, cocData: cd)
                        if let d = device as? COCDevice {
                            // Insert in interrupt order.
                            var x = 0
                            while (x < machine.cocList.count) && (d.cocConfiguration.interruptA > machine.cocList[x].cocConfiguration.interruptA) {
                                x += 1
                            }
                            if (x < machine.cocList.count) {
                                machine.cocList.insert(d, at: x)
                            }
                            else {
                                machine.cocList.append(d)
                            }
                        }
                    }
                    else  {
                        MSLog(level: .warning, "IOP \(iopNumber): COC configuration data missing: " + deviceName)
                    }
                    
                case .mt, .bt:
                    device = TapeDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, type: deviceType, model: model, mountable: true,
                                        configuration: BlockDevice.StorageConfiguration(access: .read, ioSize: 65536))
                    if let p = fullPath, let t = device as? TapeDevice {
                        _ = t.load(p, mode: .read)
                    }
                    
                case .dp:
                    device = DPDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, fullPath: fullPath, mountable: mountable)
                    
                case .dc:
                    device = DCDevice(machine, name: deviceName, iopNumber: iopNumber, unitAddr: unitAddr, model: model, fullPath: fullPath)
                }
                
                // Add the configured device.
                if let d = device {
                    devices.append(d)
                    d.trace = trace
                }
                else {
                    MSLog(level: .error, "IOP \(iopNumber): Unable to create device " + deviceName)
                }
                return device
            }
        }
        MSLog(level: .error, "IOP \(iopNumber): Unknown device prefix: " + prefix)
        return nil
    }
    
    
    // Validate and queue an IO request for a device on this IOP.
    // Result is value for CC 1&2
    func request (rq: inout IORequest) -> UInt4 {
        access.acquire()
        if let dev = devices.first(where: { (d) -> Bool in return (d.unitAddr == rq.unitAddr) }) {
            dev.access.acquire()
            
            if (dev.trace) {
                dev.log(level: .debug, "IOP REQUEST: \(rq.ioType), PSD \(hexOut(rq.psd)),  CDWADDR="+hexOut(rq.command,width:4))
            }
            
            // Determine if the device is busy
            if ((rq.ioType == .TIO) || (rq.ioType == .SIO)) && (dev.dsbCondition != 0) {
                
                if (dev is CardDevice) && (dev.dsbCondition == 3) {
                    if (dev.trace) {
                        dev.log ("IOP REQUEST: \(rq.ioType), PSD \(hexOut(rq.psd)),  CDWADDR="+hexOut(rq.command, width:4)+", Returning CC 02, BYTECOUNT="+hexOut(rq.byteCount, width:4)+", STATUS="+hexOut(rq.status, width:4))
                    }
                    dev.access.release()
                    access.release()
                    return 0x2                      // BUSY
                }
                
                rq.status = (UInt16(dev.deviceStatus) << 8) | UInt16(dev.operationalStatus)
                rq.command = dev.cdwAddress
                rq.byteCount = UInt16(dev.ioLength & 0xffff)
                if (dev.trace) {
                    dev.log ("IOP REQUEST: \(rq.ioType), PSD \(hexOut(rq.psd)),  CDWADDR="+hexOut(rq.command, width:4)+", Returning CC 01, BYTECOUNT="+hexOut(rq.byteCount, width:4)+", STATUS="+hexOut(rq.status, width:4))
                }
                dev.access.release()
                access.release()
                return 0x1                          // SIO NOT ACCEPTED
            }
            
            // clear operation status
            dev.operationalStatus = 0
            
            if (rq.ioType == .SIO) {
                dev.dsbCondition = 0x3              // NOW IT'S BUSY
                dev.dsbUnusualEnd = false
            }
            
            let ready = dev.isReady()
            dev.access.release()
            
            var cc: UInt4 = 0
            switch (rq.ioType) {
            case .SIO:
                if ready {
                    dev.sio(&rq)
                }
                else {
                    cc = 1
                }
                
            case .HIO:
                dev.hio(&rq)
                cc = ready ? 0 : 1
                break
                
            case .TIO:
                dev.tio(&rq)
                cc = ready ? 0 : 1
                break
                
            case .TDV:
                dev.tdv(&rq)
                break
            }
            
            access.release()
            
            if (dev.trace) {
                dev.log (level: .debug, "IOP REQUEST: \(rq.ioType), CDWADDR="+hexOut(rq.command,width:4)+", returning CC \(cc)")
            }
            return cc
        }
        
        // Cannot find this device
        access.release()
        return 0x3
    }
    
    func aio(unitAddr: UInt8) -> (Bool, Bool, UInt16) {
        access.acquire()
        if let dev = devices.first(where: { (d) -> Bool in return (d.unitAddr == unitAddr) }) {
            dev.access.acquire()
            
            var cc1 = false
            if (!dev.dsbInterruptPending) {
                dev.log("AIO, No pending interrupt?")
                cc1 = true
            }
            dev.dsbInterruptPending = false
            
            // return the status
            let (cc2, status) = dev.getAIOStatus()
            
            // Clear unusual end for next time
            dev.dsbUnusualEnd = false
            
            dev.access.release()
            access.release()
            
            if (dev.trace) || (MSLogManager.shared.logLevel >= .debug) {
                dev.log("AIO  STATUS="+hexOut(status,width: 4))
                
            }
            return (cc1, cc2, status)
        }
        access.release()
        return (true, true, 0)                  // No recognoition
    }
    
    //MARK: Called when CPU starts a wait cycle.
    func waitCycle() {
        for d in devices {
            d.waitCycle()
        }
    }
    
    
    func shutdown() {
        Thread.sleep(forTimeInterval: TimeInterval(2.0))
        for d in devices {
            d.ioQueue.cancelAllOperations()
            d.flush()
        }
    }
}


// MARK: ASYNCHRONOUS I/O OPERATIONS
// MARK: All device operations initiated by SIO are asyncronous.
// MARK: COC output operations are asynchronous.

protocol IOCompletionDelegate: AnyObject {
    func ioComplete (_ rq: IORequest,_ device: Device)
}

class SIOOperation: Operation, Sendable {
    var rq: IORequest
    var device: Device
    var psd: UInt64
    var sioComplete: Bool
    var ioCompletionDelegate: IOCompletionDelegate?
    
    init(rq: IORequest, device: Device) {
        self.rq = rq
        self.device = device
        self.psd = rq.cpu.psd.value
        self.sioComplete = false
        super.init()
    }
    
    override var isAsynchronous: Bool { return true }
    
    override func main() {
        Thread.current.name = device.name+".sio."+hexOut(rq.command,width:4)
        Thread.setThreadPriority(kIOPriority)
        switch (rq.ioType) {
        case .SIO:
            device.operationSIO(&rq)           // Just Do it.
            sioComplete = true
            ioCompletionDelegate?.ioComplete(rq, device)
            break
            
        default:
            MSLog(level: .error, "Non-SIO Asynchronous DeviceOperation.")
            break
        }
    }
}

protocol COCCompletionDelegate: AnyObject {
    func outputComplete (_ char: UInt8, _ line: UInt8)
}

class COCOperation: Operation, @unchecked Sendable {
    var char: UInt8
    var tty: TTYViewController!
    var cocname: String
    var psd: UInt64
    var ioCompletionDelegate: COCCompletionDelegate?
    
    init(char: UInt8, tty: TTYViewController!, cocname: String, cpu: CPU!) {
        self.char = char
        self.tty = tty
        self.cocname = cocname
        self.psd = cpu.psd.value
        super.init()
    }
    
    override var isAsynchronous: Bool { return true }
    
    override func main() {
        Thread.current.name = cocname+".Output"
        Thread.setThreadPriority(kIOPriority)
        tty.outputCharacter(char)
        
        Thread.sleep(forTimeInterval: kCharacterTransmissionTime)
        ioCompletionDelegate?.outputComplete(char, UInt8(tty.delegateID))
    }
}

// MARK: DEVICES
// Encapsulation for a DEVICE.
// Constructed by the IOP config method.
// Typically called by device operation threads

class Device: NSObject, IOCompletionDelegate {
    enum DType: Int {
        // CHARACTER DEVICES
        case tty = 0
        case lp = 1
        case cr = 2
        case cp = 3
        case me = 4                     // COC
        // BLOCK DEVICES
        case mt = 5
        case bt = 6
        case dp = 7
        case dc = 8
        
        var isBlockDevice: Bool { get { return self.rawValue >= 4 }}
        var isMultiplexed: Bool { get { return self.rawValue >= 0 }}
        
        static let prefix = ["TY","LP","CR","CP","ME","9T","BT","DP","DC"]
        static func value (prefix: String) -> Int {
            if let n = self.prefix.firstIndex(where: { (x) in (x == prefix) } ) {
                return n
            }
            return -1
        }
        
        static let typeName = ["Console", "Line Printer", "Card Reader", "Card Punch", "Character Oriented Communications Controller",
                               "9-Track Tape", "7-Track Tape", "Disc Pack", "High Speed RAD Storage"]
        
        
    }
    
    enum AccessMode: Int {
        case none = 0
        case read = 1
        case write = 2
        case update = 3
        case directory = 4
    }
    
    
    var machine: VirtualMachine!
    var access = SimpleMutex()
    var name: String                    // Full name
    var iopNumber: UInt8                // Which IOP device is attached to
    var unitAddr: UInt8                 // Device controller and Device number
    var deviceAddress: UInt16 { get { return (UInt16(iopNumber) << 8) | UInt16(unitAddr) }}
    var type: DType
    var typeString: String { get { return Device.DType.prefix[type.rawValue] }}
    var model: Int
    
    //var senseInfo: Data?
    var mountable: Bool
    var trace: Bool = false             // More logging if set
    
    var pendingHIO: Bool = false        // HIO requested.
    var cdwAddress: Int                 // Command DW address
    var ioLength: Int                   // Bytes remaining in buffer
    
    var mode: AccessMode
    var hostPath: String?
    var fileHandle: FileHandle!         // for hostPath; must be in sync
    var ioQueue: OperationQueue
    
    var isInUse: Bool { get { return inUse() }}
    func inUse() -> Bool { return fileHandle != nil }
    
    func maxTIC() -> Int { return 11 }   // MAX transfer in channel for a single SIO.
    
    
    var deviceStatus: UInt8
    var dsbInterruptPending: Bool       { get { return (deviceStatus & 0x80) != 0}  set { setInterruptPending (newValue) }}
    var dsbCondition: UInt8             { get { return (deviceStatus & 0x60) >> 5}  set { setCondition(newValue) }}
    var dsbAutomatic: Bool              { get { return (deviceStatus & 0x10) != 0}  set { setAutomatic (newValue) }}
    
    var dsbUnusualEnd: Bool             { get { return (deviceStatus & 0x08) != 0}  set { setUnusualEnd (newValue) }}
    
    func setInterruptPending ( _ newValue: Bool) {
        if newValue { deviceStatus |= 0x80 } else { deviceStatus &= 0x7f}
        if (trace) { log("*** Interrupt Pending, "+(newValue ? "ON" : "OFF")+", Dev: " + name) }
    }
    
    func setCondition (_ newValue: UInt8) {
        deviceStatus &= 0x9f; deviceStatus |= (newValue << 5)
        if (trace) {
            log ("*** Condition: \(newValue), Dev: \(name), \(String(describing: Thread.current.name))")
        }
    }
    
    func setUnusualEnd (_ newValue: Bool) {
        if newValue {
            deviceStatus |= 0x08
            if trace { log("UNUSUAL END")}
        }
        else {
            deviceStatus &= 0xf7
        }
    }
    
    func setAutomatic (_ newValue: Bool) {
        if newValue { deviceStatus |= 0x10 } else { deviceStatus &= 0xef}
    }
    
    
    var dsbController: UInt8            { get { return (deviceStatus & 0x06) >> 1}  set { deviceStatus &= 0xf9; deviceStatus |= (newValue << 1) }}
    var dsbUnassigned: Bool             { get { return (deviceStatus & 0x01) != 0}  set { if newValue { deviceStatus |= 0x01 } else { deviceStatus &= 0xfe} }}
    
    var operationalStatus: UInt8
    var osbIncorrectLength: Bool        { get { return (operationalStatus & 0x80) != 0}  set { if newValue { operationalStatus |= 0x80 } else { operationalStatus &= 0x7f} }}
    var osbTransmissionDataError: Bool  { get { return (operationalStatus & 0x40) != 0}  set { if newValue { operationalStatus |= 0x40 } else { operationalStatus &= 0xbf} }}
    var osbTransmissionMemoryError: Bool {get { return (operationalStatus & 0x20) != 0}  set { if newValue { operationalStatus |= 0x20 } else { operationalStatus &= 0xdf} }}
    var osbMemoryAddressError: Bool     { get { return (operationalStatus & 0x10) != 0}  set { if newValue { operationalStatus |= 0x10 } else { operationalStatus &= 0xef} }}
    
    var osbIOPMemoryError: Bool         { get { return (operationalStatus & 0x08) != 0}  set { if newValue { operationalStatus |= 0x08 } else { operationalStatus &= 0xf7} }}
    var osbIOPControlError: Bool        { get { return (operationalStatus & 0x04) != 0}  set { if newValue { operationalStatus |= 0x04 } else { operationalStatus &= 0xfb} }}
    var osbIOPHalt: Bool                { get { return (operationalStatus & 0x02) != 0}  set { if newValue { operationalStatus |= 0x02 } else { operationalStatus &= 0xfd} }}
    var osbSelectorIOPBusy: Bool        { get { return (operationalStatus & 0x01) != 0}  set { if newValue { operationalStatus |= 0x01 } else { operationalStatus &= 0xfe} }}
    
    // MARK: Typical, tapes are different.
    var aioStatus: UInt16
    var asbIncorrectLength: Bool        { get { return (aioStatus & 0x0080) != 0}  set { if newValue { aioStatus |= 0x0080 } else { aioStatus &= 0xff7f} }}
    var asbTransmissionError: Bool      { get { return (aioStatus & 0x0040) != 0}  set { if newValue { aioStatus |= 0x0040 } else { aioStatus &= 0xffbf} }}
    var asbZeroByteCount: Bool          { get { return (aioStatus & 0x0020) != 0}  set { if newValue { aioStatus |= 0x0020 } else { aioStatus &= 0xffdf} }}
    var asbChannelEnd: Bool             { get { return (aioStatus & 0x0010) != 0}  set { if newValue { aioStatus |= 0x0010 } else { aioStatus &= 0xffef} }}
    var asbUnusualEnd: Bool             { get { return (aioStatus & 0x0008) != 0}  set { if newValue { aioStatus |= 0x0008 } else { aioStatus &= 0xfff7} }}
    
    // MARK: Overlaps bit 7 of AIODetail for device.
    var asbStopCommand: Bool            { get { return (aioStatus & 0x0100) != 0}  set { if newValue { aioStatus |= 0x0100 } else { aioStatus &= 0xfeff} }}
    
    
    // Statistics
    var countSIOs: UInt = 0
    var countHIOs: UInt = 0
    var countTIOs: UInt = 0
    var countTDVs: UInt = 0
    var countCompletions: UInt = 0
    
    
    
    func getStatusDetail() -> String {
        _ = access.acquire(waitFor: 100)
        var r = name + " DS:"
        r += hexOut(deviceStatus) + " OS:" + hexOut(operationalStatus) + "  AIO:" + hexOut(aioStatus) + "  Counts "
        r += "[SIO: \(countSIOs), HIO: \(countHIOs), TIO: \(countTIOs), TDV: \(countTDVs), COMP: \(countCompletions)]"
        access.release()
        return r
    }
    
    func getTDVDetail() -> UInt8 {
        // Most devices return the usual device status byte.
        // Tapes, in particular, return different status for TDV and AIO
        return deviceStatus
    }
    
    func getAIODetail()-> UInt8 {
        return 0
    }
    
    func getAIOStatus() -> (Bool, UInt16) {
        // MARK: getAIODetail may reset channel end bit in aioStatus...
        let detail = UInt16(getAIODetail()) << 8
        
        return ((aioStatus & 0xE8) != 0, aioStatus | detail)
    }
    
    func logPrefix() -> String {
        return ("\(machine.name) [\(name)]")
    }
    
    func log(level: MSLogManager.LogLevel = .always, _ msg: String, functionName: String = #function, lineNumber: Int = #line) {
        MSLog(level: level, logPrefix()+": "+msg, function: functionName, line: lineNumber)
    }
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: Device.DType, model: Int, hostPath: String? = nil, mountable: Bool = false, mode: AccessMode) {
        self.model = model
        self.machine = machine
        self.name = name
        self.iopNumber = iopNumber
        self.unitAddr = unitAddr
        self.type = type
        self.ioLength = 0
        self.hostPath = hostPath
        self.mountable = mountable
        self.mode = mode
        
        self.cdwAddress = 0
        self.deviceStatus = 0
        self.operationalStatus = 0
        self.aioStatus = 0
        
        ioQueue = OperationQueue()
        ioQueue.qualityOfService = .utility
        ioQueue.maxConcurrentOperationCount = 1
        
        super.init()
        _ = load (hostPath, mode: mode)
        
    }
    
    
    func createDirectoryIfRequired(_ p: String) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
            if (!isDir.boolValue) {
                log (level: .error, "Removing file at: \(p), for device directory")
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL:nil)
                    try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
                }
                catch { log (level: .error, "Cannot remove exisiting: \(p): " + error.localizedDescription)}
            }
        }
        else {
            //MARK: Create a directory for device input or ouput.
            do { try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true) }
            catch { log (level: .error, "Cannot create device directory at: \(p): " + error.localizedDescription)}
        }
    }
    
    func unload() {
        if let fh = fileHandle {
            do { try fh.close() }
            catch { log (level: .error, "FileHandle close operation THREW.") }
            fileHandle = nil
        }
        hostPath = nil
    }
    
    func resolvePath(_ path: String) -> String {
        var p = path
        if (p.first == ".") {
            p = machine.url.appendingPathComponent(String(p.dropFirst(2))).path
        }
        return p
    }
    
    func load (_ path: String?, mode: AccessMode) -> Bool {
        if let p = path {
            return load (p, mode: mode)
        }
        dsbAutomatic = (type == .tty) 
        return true
    }
    
    func load (_ path: String, mode: AccessMode) -> Bool {
        var p = resolvePath(path)
        let url = URL(fileURLWithPath: p)
        
        switch (mode) {
        case .none:
            break
            
        case .read:
            do {
                let fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: p))
                fileHandle = fh
            }
            catch {
                log (level: .error, error.localizedDescription)
                return false
            }
            
        case .update:
            if FileManager.default.fileExists(atPath: p) {
                do {
                    let fh = try FileHandle(forUpdating: url)
                    fileHandle = fh
                }
                catch {
                    log (level: .error, error.localizedDescription)
                    return false
                }
            }
            else if FileManager.default.createFile(atPath: p, contents: Data(repeating: 0, count: 8)) {
                do {
                    let fh = try FileHandle(forUpdating: url)
                    fileHandle = fh
                }
                catch {
                    log (level: .error, error.localizedDescription)
                    return false
                }
            }
            else {
                log (level: .error, "The file \(p) could not be opened for update")
                return false
            }
            
        case .write:
            p = resolvePath(p)

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
                if (isDir.boolValue) {
                    log (level: .error, "Removing directory at: \(p), for device output")
                    do {
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL:nil)
                    }
                    catch { log (level: .error, "Cannot remove exisiting: \(p): " + error.localizedDescription)}
                }
            }

            if !FileManager.default.fileExists(atPath: p) {
                FileManager.default.createFile(atPath: p, contents: nil)
            }
            fileHandle = FileHandle(forWritingAtPath: p)
            
            
        case .directory:
            p = resolvePath(p)
            createDirectoryIfRequired(p)
            fileHandle = nil
        }
        
        
        if (url.deletingLastPathComponent() == machine.url) {
            // Save as relative path
            p = "./"+url.lastPathComponent
        }
        hostPath = p
        
        self.dsbAutomatic = (fileHandle != nil) || (mode == .directory)
        return true
    }
    
    //Get mount-state, position, media-file, and other device specific information
    func mediaStatus() -> (Bool, UInt64, String, String) {
        if let fh = fileHandle {
            var byteOffset: UInt64 = 0
            do {
                try byteOffset = fh.offset()
            }
            catch {
                log(level: .error, error.localizedDescription)
                return (false, 0, error.localizedDescription, "")
            }
            return (true, byteOffset, "\(hostPath ?? "N/A")", "")
        }
        return (false, 0, "", "")
    }
    
    //Get ready status -- just used for card reader
    func isReady() -> Bool {
        return true
    }
    
    // MARK: SIO
    func sio (_ rq: inout IORequest) {
        // Set up the async operation to do the IO
        let ioOperation = SIOOperation(rq: rq, device: self)
        ioOperation.ioCompletionDelegate = self
        
        // Start the device operation
        ioQueue.addOperation(ioOperation)
        
        rq.status = (UInt16(deviceStatus) << 8) | UInt16(operationalStatus)
        rq.command = cdwAddress
        sioQueued (rq)
    }
    
    // MARK: HIO
    func hio(_ rq: inout IORequest) {
        if (trace) || (MSLogManager.shared.logLevel >= .debug) {
            MSLog("\(name): HIO [\(Thread.current.description)]")
        }
        access.acquire()
        countHIOs += 1
        if (dsbCondition != 0) {
            pendingHIO = true
        }
        else {
            dsbInterruptPending = false
            asbChannelEnd = false
        }
        access.release()
    }
    
    // MARK: TIO
    func tio(_ rq: inout IORequest) {
        access.acquire()
        countTIOs += 1
        rq.status = (UInt16(deviceStatus) << 8) | UInt16(operationalStatus)
        rq.command = cdwAddress
        rq.byteCount = UInt16(ioLength & 0xffff)
        
        if (trace) || (MSLogManager.shared.logLevel >= .debug) {
            log("TIO STATUS="+hexOut(rq.status,width: 4)+", COUNT="+hexOut(rq.byteCount,width: 4))
            
        }
        access.release()
    }
    
    // MARK: TDV
    func tdv(_ rq: inout IORequest) {
        access.acquire()
        countTDVs += 1
        rq.status = (UInt16(getTDVDetail()) << 8) | UInt16(operationalStatus)
        rq.command = cdwAddress
        rq.byteCount = UInt16(ioLength & 0xffff)
        
        if (trace) || (MSLogManager.shared.logLevel >= .debug) {
            log("TDV STATUS="+hexOut(rq.status,width: 4)+", COUNT="+hexOut(rq.byteCount,width: 4))
        }
        access.release()
    }
    
    //MARK: Override if required..
    func sioQueued(_ rq: IORequest) {
        if (trace) {
            log("\(name): SIO OPERATION QUEUED [\(Thread.current.description)]")
        }
    }
    
    
    // MARK: operationSIO - This and subsequent methods execute asynchronously, called by the device operation thread
    func operationSIO(_ rq: inout IORequest) {
        if (trace) || (MSLogManager.shared.logLevel >= .debug) {
            log("SIO CDWA=\(hexOut(rq.command)) PSD=\(hexOut(rq.psd,width:16))[\(Thread.current.description)]")
        }
        
        access.acquire()
        sioStart(rq)
        countSIOs += 1
        aioStatus = 0
        operationalStatus = 0
        cdwAddress = rq.command
        
        var cdwCount = 0
        var tic = false                                         // last command was not Transfer in Channel
        var more = (cdwAddress > 0)
        let memory = rq.cpu.realMemory!
        var cdw = IOCommand(memory.loadUnsignedDoubleWord(cdwAddress << 3))
        var order = cdw.order
        while (more) {
            //FIXME: CHECK FOR MANUAL MODE.
            
            ioLength = (cdw.count > 0) ? Int(cdw.count) : 65536
            asbChannelEnd = false
            asbZeroByteCount = false
            
            var chainModify: Bool = false

            access.release()
            if (trace) || (MSLogManager.shared.logLevel >= .debug) {
                log("SIO(\(countSIOs)) CDW .\(hexOut(cdwAddress,width:4)) (\(cdwCount))="+cdw.getDisplayText())
            }
            cdwCount += 1
            
            //MARK:  ORDER EXECUTION
            if !special(cdw, order, memory) {
                
                switch (order & 0x3) {
                case 1: chainModify = write(cdw, order, memory)
                case 2: chainModify = read(cdw, order, memory)
                case 3: more = control(cdw, order, memory)
                default:
                    switch (order & 0xC) {
                    case 0x4: sense(cdw, order, memory); break
                    case 0xC: readBackward(cdw, order, memory); break
                        
                    default:
                        // TRANSFER IN CHANNEL?
                        if ((order & 0x0f) == 8) {
                            tic = true
                        }
                        
                        // STOP?
                        else if (order & 0x7f == 0) && (cdw.flags == 0) {
                            asbStopCommand = true
                            asbChannelEnd = true
                            dsbInterruptPending = true
                            if (trace) {
                                log("SIO: STOP COMMAND")
                            }
                            more = false
                        }
                        
                        else {
                            // UNKNOWN ORDER.
                            if (trace) {
                                log("SIO: UNKNOWN COMMAND")
                            }
                            osbIOPControlError = true
                            more = false
                        }
                    }
                }
            }
            
            
            access.acquire()
            
            //MARK: The operation is complete.
            //MARK: ioLength contains the number of bytes remaining (i.e. not used by the read/write/etc)
            //MARK: asbChannel end is set if appropriate
            
            // SET UP AIO status
            if (pendingHIO) {
                more = false
            }
            
            if (tic) {
                //MARK: S9 Manual says mask 24 bits, but this leads to problems for F00 no-rad system.  Is this not genned with 'BIG'?
                cdwAddress = cdw.memoryAddress & 0x7FFFFF
                cdw = IOCommand(memory.loadUnsignedDoubleWord(Int(cdwAddress) << 3))
                order = cdw.order
                if ((order & 0xf) == 8) {
                    osbIOPHalt = true
                    osbIOPControlError = true
                    more = false
                }
                tic = false
            }
            else {
                if (!dsbAutomatic) {
                    osbIOPHalt = true
                    more = false
                }
                
                if (cdw.fInterruptZBC) && (ioLength == 0) {
                    asbZeroByteCount = true
                    dsbInterruptPending = true
                    more = false
                }
                
                if (cdw.fInterruptUE) && (dsbUnusualEnd) {
                    asbUnusualEnd = true
                    dsbInterruptPending = true
                    more = false
                }
                
                if (more) {
                    if (cdw.fDataChain) || (cdw.fCommandChain) {
                        let newOrder = !(cdw.fDataChain) || (asbChannelEnd)
                        cdwAddress += (chainModify ? 2 : 1)
                        cdw = IOCommand(memory.loadUnsignedDoubleWord(Int(cdwAddress) << 3))
                        if newOrder {
                            order = cdw.order
                        }
                        else {
                            log("Data Chain, ioLen=\(ioLength)")
                        }
                    }
                    
                    else if (cdw.fInterruptCE) /* && (asbChannelEnd) */ {
                        if (!asbChannelEnd) {
                            log("ORDER=.\(hexOut(order,width:2)): Implied Channel End")
                        }
                        asbChannelEnd = true
                        dsbInterruptPending = true
                        more = false
                    }

                    else {
                        // The chain is complete with no speecific error
                        more = false
                    }
                }
            }
        }
        
        // Maybe somewhere wlse?
        //dsbCondition = isReady() ? 0 : 1        // Available or NOT
        dsbCondition = 0
        if (pendingHIO) {
            pendingHIO = false
            dsbInterruptPending = false
        }
        // Update status in IORequest
        rq.status = (UInt16(deviceStatus) << 8) | UInt16(operationalStatus)
        rq.command = cdwAddress
        sioDone(rq)
        
        access.release()
    }
    
    // Override these as appropriate (e.g. TapeDevice)
    func sioStart(_ rq: IORequest) {
        if (kIOStartTime > 0) { Thread.sleep(forTimeInterval: kIOStartTime) }
        rq.cpu.ioTrace?.addEvent(type: .ioSIOStart, psd: rq.psd, address: UInt32(deviceAddress), deviceInfo: UInt16(deviceStatus) << 8)
    }
    
    func sioDone(_ rq: IORequest) {
        if (kIOCompletionTime > 0) { Thread.sleep(forTimeInterval: kIOCompletionTime) }
        rq.cpu.ioTrace?.addEvent(type: .ioSIODone, psd: rq.psd, address: UInt32(deviceAddress), deviceInfo: rq.status)
    }
    

    // Functions to implement individual orders.  These should be overridden if appropriate
    func zero (_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        MSLog(level: .error, "\(name) SIO: ZERO COMMAND")
        osbIOPControlError = true
        return
    }
    
    // For READ and WRITE operations, the return value is the Chain-Modifier (used only by card-readers and card-punches)
    func read(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) -> Bool {
        osbIOPControlError = true
        return false
    }
    
    func write(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) -> Bool {
        osbIOPControlError = true
        return false
    }
    

    
    // Tape Only
    func readBackward(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        osbIOPControlError = true
        return
    }
    
    // The control result is true if processing should continue (e.g. with chaining)
    func control(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) -> Bool {
        osbIOPControlError = true
        return false
    }
    
    func sense(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        osbIOPControlError = true
        return
    }
    
    // The special routine returns true if it recognized and processed the command.
    func special(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) -> Bool {
        // Return true if recognized and handled
        return false
    }
    
    //MARK: Will be called by the thread that executed the IO.
    func ioComplete (_ rq: IORequest,_ device: Device) {
        device.countCompletions += 1
        
        // Set up the interrupt notification for the CPU.
        device.access.acquire()
        if (device.dsbInterruptPending) {
            let iss = rq.cpu.interrupts!
            
            //MARK: CONSIDER HOW TO DETERMINE PRIORITY
            if (iss.post(iss.levelIO, priority: 2, deviceAddr: (UInt16(iopNumber) << 8) | UInt16(unitAddr), device: device) == .disarmed) {
                // The interrupt will be ignored, so turn it off.
                device.dsbInterruptPending = false
            }
        }
        device.access.release()
    }
    
    //MARK: Called when CPU begins a wait cycle.
    func waitCycle() {
    }
    
    //MARK: Called when termination is imminent.
    func flush () {
    }
}

// MARK: CHARACTERDEVICE
class CharacterDevice: Device {
    override init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: Device.DType, model: Int, hostPath: String? = nil, mountable: Bool = false, mode: AccessMode = .none) {
        super.init (machine, name: name, iopNumber: iopNumber, unitAddr: (unitAddr & 0x7F), type: type, model: model, hostPath: hostPath, mountable: mountable, mode: mode)
    }
}

// MARK: TTYDEVICE
class TTYDevice: CharacterDevice, ConsoleDelegate {
    var controller: ConsoleController!
    var inputString: String
    var autoAnswer: String?
    
    var logReads: Bool = false
    var logWrites: Bool = false
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int) {
        inputString = ""
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .tty, model: model)
        machine.consoleTTY = self
    }
    
    func start(_ title: String) {
        if let c = ConsoleController(machine, title) {
            controller = c
            controller.delegate = self
            
            controller.write("\n"+siggyApp.applicationName+": CONSOLE STARTED.\n")
            return
        }
        MSLog(level: .error, "FAILED TO START CONSOLE DEVICE")
    }

    // LOG TO CONSOLE.   This is useful for example in running diagnostics, so that the trace infromation
    // is properly synced with the error messages.
    func logToConsole(_ message: String) {
        if let cv = controller {
            cv.write("\n"+machine.prefix+": "+message)
        }
    }
    
    func stop() {
        if let cv = controller {
            cv.close()
        }
        controller = nil
    }
    
    override func sio(_ rq: inout IORequest) {
        super.sio(&rq)
    }
    
    override func hio(_ rq: inout IORequest) {
        super.hio(&rq)
        
        access.acquire()
        controller?.readAbort()
        access.release()
    }
    
    func readComplete(_ s: String) {
        inputString = s + "\r"
    }
    
    
    override func read(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        MSLog(level: .debug, "CONSOLE READ POSTED")
        
        if let s = autoAnswer {
            controller?.write (s + "\n")
            inputString = s + "\r"
            autoAnswer = nil
        }
        else {
            controller?.readWaited(bufferLength: Int(cdw.count))
        }
        if (logReads) { machine.log("CONSOLE READ COMPLETED: \"\(inputString)\"") }
        
        if (pendingHIO) {
            return false                                        // it was cancelled
        }
        
        var data = Data()
        for c in inputString.uppercased() {
            if let a = c.asciiValue {
                var e = ebcdicFromAscii(a)
                data.append(&e, count: 1)
            }
        }
        
        let dc = data.count
        if (ioLength < dc) {
            data = data.dropLast(Int(dc-ioLength))
        }
            
        memory.moveData(from: data, to: cdw.memoryAddress)
        if (trace) {
            log("MOVED TO MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(data.count))' BYTES")
        }
        ioLength -= data.count
        asbChannelEnd = true
        return false
    }

    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        let buffer = memory.getData(from: cdw.memoryAddress, count: ioLength)
        let s = asciiBytes(buffer)
        
        if (logWrites) { machine.log("CONSOLE WRITE: \"\(s)\"") }

        controller?.write(s)
        ioLength = 0
        if ((order & 0x4) != 0)
        {
            asbChannelEnd = true
        }
        
        autoAnswer = controller.autoAnswer(s)
        
        return false
    }
    
    override func control(_ cdw: IOCommand, _ order: UInt8, _ memory: RealMemory) -> Bool {
        MSLog(level: .debug, "TTY CONTROL")
        return false
    }
}


//MARK: Printers
class PrintDevice: CharacterDevice {
    struct Configuration {
        var burst: Bool
        var showVFC: Bool
        var linesPerPage: Int = 0
        var paper: PDFOutputFile.Paper
        var fontName: String
        
        init(_ linesPerPage: Int,_ showVFC: Bool,_ settingsString: String?) {
            self.burst = (settingsString != nil)
            self.showVFC = showVFC
            
            //MARK: SHOULD MATCH SYSGEN VALUE. MAYBE WE CAN SET IT DYNAMICALLY LATER (NEEDS TO MODIFY APPROPRIATE DCT)
            self.linesPerPage = max(39,min(127,linesPerPage))
            
            self.paper = .printer
            self.fontName = "Courier"
            
            if let parms = settingsString {
                // Determine paper size and font from the lpParms string...
                let pc = parms.components(separatedBy: [" ",";",":","="])
                var i = 0
                while (i < pc.count-1) {
                    let pname = pc[i].uppercased()
                    if (pname == "FONT") {
                        let f = pc[i+1]
                        if (f != "FONT") { fontName = f }
                        i += 2
                    }
                    else if (pname == "PAPER") {
                        if let p = PDFOutputFile.Paper(rawValue: pc[i+1].lowercased()) {
                            paper = p
                        }
                        i += 2
                    }
                    else {
                        i += 1
                    }
                }
            }
        }
    }
    
    var config: Configuration
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: DType, model: Int, hostPath: String, mode: AccessMode, config: Configuration) {
        self.config = config
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .lp, model: model, hostPath: hostPath, mode: mode)
        applyConfiguration()
    }

    func applyConfiguration() {
    }
}


//MARK: LPDEVICE
class LPDevice: PrintDevice {
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, path: String, config: Configuration) {
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .lp, model: model, hostPath: path, mode: .write, config: config)
        
        if let fh = fileHandle {
            do {
                try fh.truncate(atOffset: 0)
            }
            catch {
                MSLog (level: .error, "\(name): FileHandle write operation THREW.")
                MSLog(name+": INITIALIZATION ERROR "+path)
            }
        }
        
    }
    
    //MARK: Writes structured data so it can be processed later.
    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        // Get the print line
        let ebcdic = memory.getData(from: cdw.memoryAddress, count: ioLength)
        
        // If vfc, get the control byte and remove from print line
        var vfc:UInt8 = 0x20
        var firstPrintChar = 0
        if (order > 1) && (ebcdic.count > 0) {
            vfc = ebcdic[0]
            firstPrintChar = 1
        }
        
        // Convert print data to ascii
        var ascii = Data(repeating: 0, count: ebcdic.count - firstPrintChar)
        var i = 0
        while (i < ascii.count) {
            let ch = asciiFromEbcdic(ebcdic[firstPrintChar+i])
            ascii[i] = ((ch != 0) ? ch : 0x20)
            i += 1
        }
        
        //MARK: Make it readable, but retain the length, order, and vfc
        if let fh = fileHandle, var data = (String(format: "{%02X%02X%02X",ioLength,order,vfc)).data(using: .utf8) {
            data.append(ascii)
            data.append(0x7D)               // closing brace
            data.append(0x0A)               // lf
            
            do { try fh.write(contentsOf: data)
                ioLength = 0                // *WAS* cdw.count = 0
            }
            catch {
                log(level: .error, "FileHandle write operation THREW.")
                dsbAutomatic = false
            }
        }
        Thread.sleep(forTimeInterval: kPrinterLineTime)

        asbChannelEnd = true
        return false
    }
    
    //MARK: Write the line in ascii to the output file including the VFC char.
    func write2(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        var lf: UInt8 = 0x0A
        var ebcdicBlank: UInt8 = 0x40
        
        let interruptOnCompletion = ((order & 0x40) > 0)
        let function = (order & 0x7)
        
        //MARK: If no VFC, put in a blank character
        var data = (function == 1) ? Data(bytes: &ebcdicBlank,count: 1) : Data()
        data.append(memory.getData(from: cdw.memoryAddress, count: ioLength))
        
        //MARK: Convert to ASCII, including the VFC character
        var i = data.count-1
        while (i >= 0) {
            let ascii = asciiFromEbcdic(data[i])
            data[i] = (ascii != 0) ? ascii : 0x20
            i -= 1
        }
        if (data.count > 1) { data.append(&lf, count: 1) }
        
        //MARK: Write to device file
        do { try fileHandle?.write(contentsOf: data)
            ioLength = 0                        // *WAS* cdw.count = 0
        }
        catch {
            log(level: .error, "FileHandle write operation THREW.")
            dsbAutomatic = false
        }
        
        //MARK: KLUDGE - SIMULATE TRANSMISSION TIME TO PRINTER
        //Otherwise the interrupt happens before the previous has been cleaned up,
        //and the monitor stack blows up.  If this was a 100 character line and a
        //reasonable transmission speed is 10000 CPS, it should take 1/100 of a second.
        Thread.sleep(forTimeInterval: kPrinterLineTime)
        
        asbChannelEnd = true
        if (interruptOnCompletion) {
            dsbInterruptPending = true
        }
        return false
    }
}

class PDFDevice: PrintDevice {
    var pageHeight: CGFloat = 0
    var pageWidth: CGFloat = 0
    
    var fontSize: CGFloat = 0
    var fontHorizontalScale: CGFloat = 100

    var leftMargin: CGFloat = 0
    var topMargin: CGFloat = 0
    var lineSize: CGFloat = 0

    var currentLine: Int = 0
    var lastLineDidNothing: Bool = false
    var bannerLine: Bool = false

    var pdfOut: PDFOutputFile?
    var jobID: String = ""
    var jobUser: String = ""
    var lastPrintLineTime: MSTimestamp = MSTimestamp.max

    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, directory: String, config: Configuration) {

        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .lp, model: model, hostPath: directory, mode: .directory, config: config)
            
        applyConfiguration()
        
        //MARK: MAKE SURE DIRECTORY WAS CREATED OK...
       
        if let p = hostPath {
            let dir = resolvePath(p)
            if FileManager.default.fileExists(atPath: dir) {
                dsbAutomatic = true
            }
            else {
                print ("\(dir) does not exist.")
            }
        }
    }
    
    override func applyConfiguration () {
        //MARK: COMPUTE FONT SIZE, etc.
        let pageSize = PDFOutputFile.paperSize(config.paper)
        pageHeight = pageSize.width             // orientation = landscape
        pageWidth = pageSize.height

        leftMargin = 12
        topMargin = 25
        
        let usableHeight = pageHeight-2*topMargin
        lineSize = usableHeight/CGFloat(config.linesPerPage-1)
        fontSize = (lineSize-2)
        
        //TODO: Compute horizontal scale.
        fontHorizontalScale = 100

        currentLine = 0
        lastLineDidNothing = false
        bannerLine = false
    }

    
    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        var inhibitUpspace: Bool = false
        
        // Get the print line
        let ebcdic = memory.getData(from: cdw.memoryAddress, count: ioLength)
        
        //MARK:  If vfc, get the control byte and remove from print line
        var vfc: UInt8 = 0
        
        if (order > 1) && (ebcdic.count > 0) {
            vfc = ebcdic[0]
        }
        
        if !lastLineDidNothing {
            
            //MARK: KLUDGE TO MAKE THE ONLINE BANNER FIT AFTER OUR RED ONE.
            if (bannerLine) {
                if (vfc > 0xC0) && (vfc < 0xC9) {
                    vfc -= 1
                }
            }
            
            switch(vfc) {
            case 0x60:
                inhibitUpspace = true
                
            case 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8:
                currentLine += Int(vfc-0xC0)
                
            case 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8:
                inhibitUpspace = true
                currentLine += Int(vfc-0xE0)
                
            case 0xF0:
                currentLine = config.linesPerPage-1
                
            case 0xF1:
                currentLine = config.linesPerPage
                
            default: break
            }
            
            if (currentLine >= config.linesPerPage) {
                if let p = pdfOut {
                    p.newPage()
                }
                currentLine = 0
            }
        }
        
        bannerLine = false
        if (ebcdic.count == 1) && (order == 0x05) && (vfc == 0xC0){
            // A Zero length do-nothing line typically introduces the start (or end) page of a job, but sometimes happens in the middle.
            // This actually prints a blank line, which is presumably the margin line.  This is not counted toward the # lines on the page?
            lastLineDidNothing = true
        }
        else {
            var textColor = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
            var typeFace = config.fontName
            var textSize = fontSize
            
            
            //MARK: Convert print data to ascii
            let offset = (order != 0x01) ? 1 : 0
            var ascii = Data(repeating: 0, count: ebcdic.count-offset)
            var i = 0
            while (i < ascii.count) {
                let ch = asciiFromEbcdic(ebcdic[offset+i])
                ascii[i] = ((ch != 0) ? ch : 0x20)
                i += 1
            }
            
            //MARK: WAS PREVIOUS LINE A DO-NOTHING?   IF SO, SEE IF THIS IS A BANNER LINE.
            if (lastLineDidNothing) {
                if (order == 0x01) && ((ioLength >= 32) && (ioLength < 50)) {
                    // MARK: PROBABLY...
                    // MARK: The first line of the job's output contains:
                    // JOBID (4 hex digits followed by a colon and three spaces)
                    // USERNAME,ACCOUNT (trailing blanks are trimmed.  minimum 3 bytes (X,Y); maximum 21 bytes.
                    // 4 spaces, then date MM/DD/YY; 4 spaces and then the time HH:MM.
                    // The online trailer is the same except has a page count at the end, so it can be disqualified by that
                    
                    jobID = "????"
                    if let banner = String(data: ascii, encoding: .ascii) {
                        if let j = hexIn(hex: banner.substr(0,4)),
                           (banner.substr(4,4) == ":   ") {
                            var p = 8
                            while (p < ioLength) && (banner.substr(p,1) != " ") {
                                p += 1
                                if (p > 29) { break }
                            }
                            if (p <= 29) && (banner.substr(p,4) == "    ") {
                                //MARK: OK SO FAR
                                jobUser = banner.substr(8,p-8)
                                
                                p += 4
                                let date = banner.substr(p,8)
                                p += 8
                                let blanks = banner.substr(p,4)
                                p += 4
                                let time = banner.substr(p,5)
                                p += 5
                                
                                //MARK: validate p and length.
                                if (p == ioLength) && (blanks == "    ") {
                                    // MARK: validate date and time, and fix the date.
                                    if (date.substr(2,1) == "/") && (date.substr(5,1) == "/")  && (time.substr(2, 1) == ":"),
                                       let mm = Int(date.substr(0,2)),
                                       let dd = Int(date.substr(3,2)),
                                       var yy = Int(date.substr(6,2)),
                                       let hh = Int(time.substr(0,2)),
                                       let nn = Int(time.substr(3,2)),
                                       let _ = MSDate(components: MSDateComponents(year: yy+1900, month: mm, day: dd, hour: hh, minute: nn, second: 0, tick: 0)) {
                                        //MARK: This is valid, fix the date.
                                        bannerLine = true
                                        
                                        while (yy < 125) { yy += 28 }; yy -= 100
                                        ascii[p-11] = UInt8(yy/10) + 0x30
                                        ascii[p-10] = UInt8(yy%10) + 0x30
                                        
                                        jobID = hexOut(j, width: 4)
                                        if (pdfOut != nil) {
                                            pdfOut?.finalizeOutput()
                                        }
                                        pdfOut = nil
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !bannerLine {
                    pdfOut?.newPage()
                    currentLine = 0
                }
                lastLineDidNothing = false
            }
            
            //MARK: WE HAVE OUTPUT, OPEN DESTINATION IF NOT ALREADY
            if dsbAutomatic, (pdfOut == nil), let p = hostPath {
                //MARK: Start a new Job.
                let dir = resolvePath(p) + "/" + jobUser.replacingOccurrences(of: ",", with: ".")
                createDirectoryIfRequired(dir)
                pdfOut = PDFOutputFile(dir + "/" + MSDate().filenameString + "-" + jobID + ".pdf")
                
                if (pdfOut == nil) {
                    dsbAutomatic = false
                }
                else {
                    pdfOut?.beginOutput(producer: "Burst", author: "MacSiggy", paper: config.paper, orientation: .landscape, margins: nil)
                    pdfOut?.newPage()
                    currentLine = 0
                    
                    textColor = .red
                    typeFace = "Courier"
                    textSize = 18
                }
            }
            
            if let text = String(data: ascii, encoding: .ascii) {
                let t = config.showVFC ? (hexOut(vfc,width:2)+":"+text) : text
                pdfOut?.textOut(t, at: NSPoint(x: leftMargin, y: topMargin+CGFloat(currentLine)*lineSize), typeFace: typeFace, textSize, horizontalScale: fontHorizontalScale, color: textColor)
            }
            
            if !inhibitUpspace {
                currentLine += 1
            }
        }
        ioLength = 0                                // MARK: cdw.count = 0
        
        //MARK: KLUDGE - SIMULATE PRINT TIME
        //Otherwise the interrupt happens before the previous has been cleaned up,
        //and the monitor stack blows up.  If this was a 100 character line and a
        //reasonable transmission speed is 10000 CPS, it should take 1/100 of a second.
        Thread.sleep(forTimeInterval: kPrinterLineTime)
        
        asbChannelEnd = true
        lastPrintLineTime = MSDate().gmtTimestamp

        if ((order & 0x40) != 0) {
            dsbInterruptPending = true
        }
        return false
    }
    
    //MARK: Called by main thread
    @objc func finishJob() {
        pdfOut?.finalizeOutput()
        pdfOut = nil
        jobID = ""
    }
    
    //MARK: Called by CPU thread
    override func waitCycle() {
        if ((MSDate().gmtTimestamp - lastPrintLineTime) > (30 * MSDate.ticksPerSecond64)) {
            lastPrintLineTime = MSTimestamp.max
            self.performSelector(onMainThread: #selector(finishJob), with: nil, waitUntilDone: false)
        }
    }
    
    //MARK: Called by main thread
    override func flush() {
        finishJob()
    }
    
    override func control(_ cdw: IOCommand, _ order: UInt8, _ memory: RealMemory) -> Bool {
        log("*** UNEXPECTED: LP CONTROL, ORDER \(hexOut(order)) ***")
        return false
    }

}

// MARK: Card Readers and Punches have slightly different AIO CC's
class CardDevice: CharacterDevice {
}

class CRDevice: CardDevice {
    var ready: Bool = false
    var a: String = ""          // ASCII buffer (for log)
    var b: Data?                // EBCDIC buffer
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int) {
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .cr, model: model, mountable: true, mode: .read)
        
    }
    
    override func load(_ path: String, mode: AccessMode) -> Bool {
        ready = super.load(path, mode: .read)
        return ready
    }
    
    override func unload() {
        ready = false
    }

    override func isReady() -> Bool {
        return ready
    }
    
    override func inUse() -> Bool {
       return ready && (fileHandle != nil) && (fileHandle.offsetInFile > 0)
    }

    // TDV and AIO produce special device status bytes for card readers
    // These have minor differences
    override func getTDVDetail() -> UInt8 {
        let status: UInt8 = 0
        // bit 0: Overrun, nope
        // bit 1: Validity Error
        // bit 2: Read Verify Error
        return status
    }

    override func getAIODetail() -> UInt8 {
        let status: UInt8 = 0
        // bit 0: Overrun, nope
        return status
    }
    

    
    override func read(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        var gotLine: Bool = false
        
        if (fileHandle == nil) {
            if let p = hostPath {
                fileHandle = FileHandle(forReadingAtPath: resolvePath(p))
            }
            else {
                // NOTHING MOUNTED.
                dsbAutomatic = false
            }
        }

        var p = 0
        if let fh = fileHandle {
            //MARK: DOES NOT HANLDE BINARY MODE
            
            let count = min(80, Int(cdw.count))
            var card = Data(repeating: 0x40, count: count)

            while !gotLine && (p < count) {
                do { b = try fh.read(upToCount: 1) } catch { log("*** READ THREW ***")}
                if let b = b, b.count > 0 {
                    let c = b[0]
                    if (c == 0x0A) {
                        gotLine = true
                    }
                    else {
                        card[p] = ebcdicFromAscii(c)
                        p += 1
                    }
                }
                else {
                    //MARK: Done with this file, but process last line.
                    gotLine = true
                    if (p == 0) {
                        try! fh.close()
                        fileHandle = nil
                        
                        log ("Done file")
                        ready = false
                        dsbAutomatic = false
                        dsbInterruptPending = true
                        
                        // MARK: add !FIN
                        card[0] = 0x5A
                        card[1] = 0xC6
                        card[2] = 0xC9
                        card[3] = 0xD5
                    }
                }
            }
            
            // Have the record image in EBCDIC
            memory.moveData(from: card, to: cdw.memoryAddress)
            if (trace) {
                log ("CARD")
                log ("MOVED TO MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(p))/\(hexOut(count))' BYTES")
                for s in hexDump(card) {
                    log(s)
                }

            }
            
            //Count the whole cardful
            ioLength -= count
            
            //MARK: KLUDGE - SIMULATE TRANSMISSION TIME FROM READER
            Thread.sleep(forTimeInterval: kCardReadTime)
            
            if ((order & 0x40) != 0) {
                dsbInterruptPending = true
            }
        }
        else {
            //MARK: READ issued but no input available.
            log ("No INPUT")
            ready = false
            dsbAutomatic = false
            dsbInterruptPending = true
        }
        
        asbChannelEnd = true
        return true
    }
}

class CPDevice: CardDevice {
    var ready: Bool = false
    var transmissionCompleteInterrupt: Bool = false
    var a: String = ""          // ASCII buffer (for log)
    var b: Data?                // EBCDIC buffer
    
    var jobID: String = ""
    var jobUser: String = ""
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, directory: String?, flags: UInt64) {
        let dMode = ((flags & 0x01) != 0)
        let aMode: AccessMode = dMode ? .directory : .update
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .cp, model: model, hostPath: directory, mountable: !dMode, mode: aMode)
    }
    
    override func load(_ path: String, mode: AccessMode) -> Bool {
        ready = super.load(path, mode: mode)
        return isReady()
    }

    override func isReady() -> Bool {
        return ((mode == .directory) || ready)
    }

    // TDV and AIO produce special device status bytes for punches
    // These have minor differences
    override func getTDVDetail() -> UInt8 {
        let status: UInt8 = 0
        // bit 0: Overrun, nope
        // bit 1: Unassigned for TDV
        // bit 2: Punch Error
        return status
    }

    override func getAIODetail() -> UInt8 {
        var status: UInt8 = 0
        // bit 0: Overrun, nope
        // bit 1: Data Transmission Complete Interrupt Occurred
        // bit 2: Punch Error
        if transmissionCompleteInterrupt { status |= 0x40 ; transmissionCompleteInterrupt = false }
        return status
    }
    

    override func sioStart(_ rq: IORequest) {
        //log ("Punching..")
    }

    
    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        let count = Int(cdw.count)
        
        // Gwt the record image in EBCDIC
        let e = memory.getData(from: cdw.memoryAddress, count: count)
        if (trace) {
            log ("CARD")
            log ("READ MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(e.count))/\(hexOut(count))' BYTES")
        }
        
        var punchMe = true
        if (mode == .directory) {
            //MARK: if banner card, get jobID and jobUser.
            //MARK: else if initial lace, open output.
            //MARK: else if terminating lace. close output
            //MARK: otherwise, fall thru and print the card.
            if ((order & 0x04) != 0) {
                // NOT BINARY, Banner should happen when fileHandle is nil
                if (fileHandle == nil) {
                    var banner = true
                    var i = 19
                    while (banner) && (i >= 0) {
                        banner = (e[i] == 0xff)
                        i -= 1
                    }
                    if (banner) {
                        //Get jobId
                        jobID = ""
                        var i = 24
                        while (i < 28) {
                            jobID += String(printableAsciiFromEbcdic(e[i], 0x2e))
                            i += 1
                        }
                        
                        //And Username
                        jobUser = ""
                        i = 32
                        while (i < 64) && (e[i] != 0x40) {
                            jobUser += String(printableAsciiFromEbcdic(e[i], 0x2e))
                            i += 1
                        }
                    }
                    punchMe = false
                }
                // Fall thru and punch me.
            }
            else {
                //BINARY.  Which one is it?
                if (fileHandle == nil) {
                    if let p = hostPath {
                        //START: Open destinaiton file
                        let dir = resolvePath(p) + "/" + jobUser.replacingOccurrences(of: ",", with: ".")
                        createDirectoryIfRequired(dir)
                        let path = dir + "/" + MSDate().filenameString + "-" + jobID + ".txt"
                        if !FileManager.default.fileExists(atPath: path) {
                            FileManager.default.createFile(atPath: path, contents: nil)
                        }
                        fileHandle = FileHandle(forWritingAtPath: path)
                        if (fileHandle == nil) {
                            log(level: .warning, "Punch File Open Failed" + path)
                            dsbAutomatic = false
                        }
                    }
                }
                else {
                    //END: Close the file.
                    try! fileHandle?.close()
                    fileHandle = nil
                }
                punchMe = false
            }
        }
        else {
            if (fileHandle == nil) {
                if let p = hostPath {
                    fileHandle = FileHandle(forUpdatingAtPath: resolvePath(p))
                }
                else {
                    // NOTHING MOUNTED.
                    dsbAutomatic = false
                    punchMe = false
                }
            }
            
            if ((order & 0x04) == 0), let fh = fileHandle {
                //MARK: PUNCH BINARY: --> HEX DUMP
                for s in hexDump(e) {
                    if var d = s.data(using: .ascii) {
                        d.append(contentsOf: [0x0a])
                        do { try fh.write(contentsOf: d)  }
                        catch { log("*** WRITE THREW ***")
                            //MARK: Done with this file.
                            try! fh.close()
                            fileHandle = nil
                        }
                    }
                }
                punchMe = false
            }
        }
        
        if punchMe, let fh = fileHandle {
            //MARK: PUNCH EBCDIC: --> WrITE ASCII TO FILE.
            var ascii = Data(repeating: 0x20, count: count+1)
            var p = 0
            while (p < count) {
                let a = asciiFromEbcdic(e[p])
                ascii[p] = ((a >= 0x20) && (a <= 0x7E)) ? a : 0x2E
                p += 1
            }
            
            // Trim card image, and add a newline
            while (p > 0) && (ascii[p] <= 0x20) {
                p -= 1
            }
            ascii[p+1] = 0x0a
            
            do { try fh.write(contentsOf: ascii.dropLast(count-p-1)) }
            catch { log("*** WRITE THREW ***")
                //MARK: Done with this file.
                try! fh.close()
                fileHandle = nil
            }
        }

        //MARK: SIMULATE PUNCH TIME
        Thread.sleep(forTimeInterval: kPunchLineTime)

        ioLength = 0
        asbChannelEnd = true
        if ((order & 0x40) != 0) {
            dsbInterruptPending = true
            transmissionCompleteInterrupt = true
        }
        return true
    }
}



// MARK: COCDEVICE
class COCDevice: CharacterDevice, TTYDelegate, COCCompletionDelegate {
    struct COCConfiguration {
        var interruptA: UInt8
        var interruptB: UInt8
        var numberOfLines: UInt8
        var firstLine: UInt8
        var autoStart: UInt64
        var traceLines: UInt64
    }
    
    struct LineData {
        var disable: Bool = false
        var trace: Bool = false
        var receiverOn: Bool = false
        var receiveDSR: Bool = false
        var transmitCTS: Bool = false
        var transmitCIP: Bool = false
        var rubKludge: Bool = false
        
        var tty: TTYViewController?
        var outputQueue: OperationQueue?
        
        var inputCount: UInt64 = 0                  // Input interrupts
        var outputCount: UInt64 = 0                 // Output interrupts

        func receiverStatus() -> UInt4 {
            if receiveDSR {
                return (receiverOn ? 1 : 2)
            }
            return 0
        }

        func transmitterStatus() -> UInt4 {
            if transmitCTS {
                return (transmitCIP ? 2 : 3)
            }
            return (transmitCIP ? 0 : 1)
        }
        
        func status() -> String {
            let s = (disable ? "Disabled," : "") + (receiverOn ? "R-On," : "R-Off,") + (receiveDSR ? "DSR," : "") + (transmitCTS ? "CTS," : "") + (transmitCIP ? "CIP" : "NO CIP")
            return s
        }

    }
    var cocConfiguration: COCConfiguration!

    var cocBuffer: Int
    var cocBufferSize: Int
    var cocReadCompletion = DispatchSemaphore(value: 0)
    
    var lineData: [LineData?]
    var memory: RealMemory!
    
    private var devices: [Device] = []      //  Built by "configure()"
    var deviceList: [Device] { get { return devices }}
    
    override func sio (_ rq: inout IORequest) {
        super.sio(&rq)
    }

    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, cocData: COCConfiguration) {
        cocConfiguration = cocData
        if (cocConfiguration.numberOfLines <= 0) {
            cocConfiguration.numberOfLines = 64
        }
        lineData = Array(repeating: LineData(), count: Int(cocConfiguration.numberOfLines))

        cocBuffer = 0
        cocBufferSize = 0
        
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .me, model: model)
        dsbAutomatic = true
        
        var i = 0
        var a = cocData.autoStart
        var t = cocData.traceLines
        while (i < cocData.numberOfLines) {
            lineData[i]!.disable = (i < cocConfiguration.firstLine)
            lineData[i]!.trace = t.bitIsSet(bit: i)
            if (a.bitIsSet(bit: i) && (i >= cocConfiguration.firstLine)) {
                if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "TTYWindow") as! TTYWindowController?,
                   let vc = wc.contentViewController as? TTYViewController {
                    _  = vc.configure(name: siggyApp.applicationName+" Terminal",
                                      defaultStyle: TTYViewController.Style(interruptButtonTitle: "BREAK", forceUppercase: true),
                                      styleSelection: 0, height: 50, width: 80)
                    wc.showWindow(self)
                    if !(startLine(i,vc)) {
                        MSLog(level: .error, "\(name): Failed to start line \(i)")
                        wc.close()
                    }
                }
            }
            a >>= 1
            t >>= 1
            i += 1
        }
    }
    
    func startLine (_ line: Int,_ tty: TTYViewController) -> Bool {
        tty.delegate = self
        tty.delegateID = line
        
        let lx = hexOut(deviceAddress,width: 3)+":"+hexOut(line,width:2)
        let style = machine.getIntegerSetting("TTY[\(lx)]S", 0)
        let h = max(10,machine.getIntegerSetting("TTY[\(lx)]H", 25))
        let w = max(15,machine.getIntegerSetting("TTY[\(lx)]W", 80))
        _ = tty.configure(name: name+"-\(hexOut(line,width:2))",
                         defaultStyle: TTYViewController.Style(interruptButtonTitle: "Break", forceUppercase: true),
                          styleSelection: style, height: h, width: w)

        let px = machine.getDoubleSetting("TTY[\(lx)]X", 0)
        let py = machine.getDoubleSetting("TTY[\(lx)]Y", 0)
        tty.setOrigin(NSPoint(x: px,y: py))
        
        if (lineData[line]!.trace) {
            MSLog(level: .detail, "\(name): STARTING LINE \(hexOut(line,width:2))")
        }
        
        lineData[line]!.tty = tty
        lineData[line]!.outputQueue = OperationQueue()
        lineData[line]!.outputQueue!.qualityOfService = .utility
        lineData[line]!.outputQueue!.maxConcurrentOperationCount = 1
        
        lineData[line]!.receiveDSR = true
        lineData[line]!.receiverOn = true
        lineData[line]!.transmitCTS = true
        lineData[line]!.transmitCIP = false
        
        lineData[line]!.inputCount = 0
        lineData[line]!.outputCount = 0
        
        characterIn(line, Character(Unicode.Scalar(0)), isBreak: true)
        
        tty.write("CONNECTED TO \(name), LINE \(hexOut(line,width:2))")
        return true
    }
    
    func characterIn (_ line: Int, _ c: Character, isBreak: Bool ) {
        if (lineData[line]!.trace) {
            log("COC IN "+hexOut(c.asciiValue!,width: 2)+", "+hexOut(line,width: 2)+(isBreak ? " B!" : ""))
        }
        if (cocBuffer > 0) {
            let b = UInt8(c.asciiValue ?? 0x7E)
            let d = Data([b, UInt8(line | (isBreak ? 0x80 : 0))])
            
            //FIXME: THIS IS A WORKAROUND,
            lineData[line]!.rubKludge = (b == 0x7F)
            
            memory.moveData(from: d, to: cocBuffer)
            if (trace) {
                log("MOVED TO MEMORY BA=\(hexOut(cocBuffer)), COUNT=X'2' BYTES")
            }

            lineData[line]!.inputCount += 1
            if (machine.cpu.interrupts.post (Int(cocConfiguration.interruptA)-0x50, priority: 0, deviceAddr: UInt16(unitAddr), device: self) != .disarmed) {
                
                cocBuffer += 2
                ioLength -= 2
                
                if (ioLength < 2) {
                    //Complete the IO.  Data chaining will cause a new one to be issued, and the buffer to be recycled.
                    asbChannelEnd = true
                    cocReadCompletion.signal()
                }
            }
            else {
                log("COC INTERRUPT DROPPED -- DISARMED")
            }
        }
    }
    
    func autoSettingChanged(_ id: Int, _ enabled: Bool) {
    }
    
    func windowShouldClose(_ line: Int) -> Bool {
        if (lineData[line] != nil) {
            lineData[line]!.transmitCTS = false
            lineData[line]!.receiveDSR = false
            characterIn(line, Character(Unicode.Scalar(0)), isBreak: true)
            
            machine.removeTerminalWindow(lineData[line]?.tty?.windowController)
            perform(#selector(clearLine), with: lineData[line]!.tty, afterDelay: 1.0)
        }
        return true
    }

    func windowDidMove(_ id: Int, _ origin: CGPoint) {
        let lx = hexOut(deviceAddress,width: 3)+":"+hexOut(id,width:2)
        machine.set("TTY[\(lx)]X", String(Double(origin.x)))
        machine.set("TTY[\(lx)]Y", String(Double(origin.y)))
    }

    func windowDidResize(_ id: Int, _ height: Int, _ width: Int) {
        let lx = hexOut(deviceAddress,width: 3)+":"+hexOut(id,width:2)
        machine.set("TTY[\(lx)]H", String(height))
        machine.set("TTY[\(lx)]W", String(width))
    }
    
    func styleDidChange(_ id: Int, _ styleNumber: Int) {
        let lx = hexOut(deviceAddress,width: 3)+":"+hexOut(id,width:2)
        machine.set("TTY[\(lx)]S", String(styleNumber))
    }
    
    func startPasteWindow(_ id: Int) {
        if let tty = lineData[id]?.tty {
            let pb = pasteBufferWindow(forMachine: machine, withDelgate: tty)
            pb?.showWindow(self)
        }
    }
    


    @objc func clearLine(_ tty: TTYViewController?) {
        if let x = lineData.firstIndex(where: { (l) in return (l != nil) && (l!.tty == tty) } ) {
            if (x >= 0) { lineData[x]!.tty = nil }
        }
    }

    
    override func read(_ cdw: IOCommand, _ order: UInt8, _ memory: RealMemory) -> Bool {
        self.memory = memory

        cocBuffer = cdw.memoryAddress
        cocBufferSize = Int(cdw.count)
        if (trace) {
            log("COC READ POSTED")
        }
        cocReadCompletion.wait()
        cocBuffer = 0
        return false
    }
    
    // Only called when not servicing an output interrupt.
    // After an output interrupt happens, the CPU's RD code fetches the line from the interrupt data block
    func readDirect (_ fn: Int) -> UInt32 {
        let r = UInt32(MSClock.shared.gmtTimestamp() & 0x3F)
        return (r | 0x40)
    }
    
    func writeDirect (_ fn: Int, data: UInt16) -> UInt4 {
        let outputLine = Int(data & 0x3F)
        if (outputLine >= cocConfiguration.numberOfLines) || (lineData[outputLine]!.disable) {
            return 0                                    // Not installed
        }

        let char = UInt8(data >> 8)
        if let ld = lineData[outputLine] {
            if (ld.trace) && (fn != 0) {
                log("COC WD LINE:\(hexOut(outputLine,width:2)), FN: \(hexOut(fn,width:2)), CHAR: \(hexOut(char,width:2)), STATUS: \(ld.status())")
            }
            
            if (fn < 4) {
                switch (fn) {
                case 1:                                     // Turn receiver L on
                    lineData[outputLine]!.receiverOn = true
                    
                case 2:                                     // Turn receiver L off
                    lineData[outputLine]!.receiverOn = false
                    
                case 3:                                     // Turn receive L dataset off
                    lineData[outputLine]!.receiveDSR = false
                    
                default:                                    // Sense receiver L status
                    break
                }
                
                if (ld.trace) {
                    MSLog("COC ** LINE:\(hexOut(outputLine,width:2)), STATUS: \(lineData[outputLine]!.status())")
                }
                return lineData[outputLine]!.receiverStatus()
            }
            
            switch (fn) {
            case 5, 6, 0x0D:                                // MARK: TRANSMIT CHARACTER ASYNCHRONOUSLY
                if let tty = ld.tty {
                    lineData[outputLine]!.transmitCIP = true
                    var c = char
                    
                    if (fn > 5) {
                        c = 0
                    }
                    else if ld.rubKludge && (char == 0x5C) {
                        lineData[outputLine]!.rubKludge = false
                        c = 0x7F
                    }
                    else if ((char & 0x7F) == 0x7F) {
                        c = 0x00
                    }
                    let outputOperation = COCOperation(char: c, tty: tty, cocname: "\(name)."+hexOut(outputLine,width: 2), cpu: machine.cpu)
                    outputOperation.ioCompletionDelegate = self
                    
                    // Start the device operation
                    ld.outputQueue?.addOperation(outputOperation)
                }

            case 7:                                         // Turn off transmitter
                lineData[outputLine]!.transmitCIP = false
                lineData[outputLine]!.transmitCTS = false

            case 0xE:                                       // Stop transmitting -- oops, too late
                lineData[outputLine]!.transmitCIP = false
                lineData[outputLine]!.transmitCTS = true

            default:
                break
            }
            return lineData[outputLine]!.transmitterStatus()
        }
        return 0
    }
    
    func outputComplete (_ char: UInt8,_ line: UInt8) {
        let x = Int(line)
        lineData[x]!.transmitCIP = false
        lineData[x]!.outputCount += 1
        
        _ = machine.cpu.interrupts.post (Int(cocConfiguration.interruptB)-0x50, priority: 0, deviceAddr: UInt16(unitAddr), device: self, line: line, char: char)
    }
}




class BlockDevice: Device {
    class StorageConfiguration {
        var access: AccessMode
        var ioSize: Int = 0
        var flags: UInt64 = 0
     
        init (access: AccessMode, ioSize: Int = 0,_ flags: UInt64 = 0) {
            self.access = access
            self.ioSize = ioSize
            self.flags = flags
        }
    }
    var configuration: StorageConfiguration?
    var isReadOnly: Bool { get {
        return (configuration != nil) && (configuration!.access == .read)
    }}
    var isWritable: Bool { get {
        guard !isReadOnly && (hostPath != nil) else { return false }
        return FileManager.default.isWritableFile(atPath: resolvePath(hostPath!))
    }}
    
    var filePosition: Int { get { return (fileHandle != nil) ? Int(fileHandle.offsetInFile) : -1 }}
    
    func mediaFailure() {
        log(level: .warning, "MEDIA FAILURE @\(hexOut(filePosition))")
        dsbUnusualEnd = true
        dsbAutomatic = false
    }


    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: Device.DType,_ model: Int, fullPath: String?, mountable: Bool, configuration: StorageConfiguration) {
        self.configuration = configuration
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: (unitAddr | 0x80), type: type, model: model, hostPath: fullPath, mountable: mountable, mode: configuration.access)
    }
    
    func forceUnload() {
        log(level: .warning, "UNLOAD BY OPERATOR")
        mediaFailure()
        
        if let fh = fileHandle {
            do { try fh.close() }
            catch { }
            fileHandle = nil
        }
        hostPath = nil
    }

}

// MARK: TAPEDEVICE
class TapeDevice: BlockDevice {
    enum TapeFormat {
        case none
        case mt
        case tap
    }
    private var format: TapeFormat = .none
    
    private var lastTapeMark: Int = 0
    private var currentFile: Int = 0
    private var readBuffer: Data!
    private var readSize: Int = 0
    private var readPosition: Int = 0
    private var writeBuffer: Data!
    
    var deviceEnd: Bool = false
    var protectionViolation: Bool = false
    var atBOT: Bool = false
    var atBOF: Bool = false
    var atEOF: Bool = false
    var atEOT: Bool = false
    
    var currentBlockLength: Int { get { return readSize }}
    var tapePosition: Int { get { return filePosition }}
    override func inUse() -> Bool { return super.inUse() && !atBOT }

    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: Device.DType, model: Int, mountable: Bool, configuration: StorageConfiguration) {
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: type, model, fullPath: nil, mountable: mountable, configuration: configuration)
    }
    
    // TDV and AIO produce special device status bytes for tapes
    // Not quite identical of course
    override func getTDVDetail() -> UInt8 {
        var status: UInt8 = 0
        if (!isReadOnly)            { status |= 0x40 }
        if (protectionViolation)    { status |= 0x20 }
        if (atEOF)                  { status |= 0x10 }
        if (atBOT)                  { status |= 0x04 }
        if (atEOT)                  { status |= 0x02 }
        return status
    }

    override func getAIODetail() -> UInt8 {
        var status: UInt8 = 0
        if deviceEnd                { status |= 0x40 }
        if (protectionViolation)    { status |= 0x20 }
        if (atEOF)                  { status |= 0x10 }
        if (atBOT)                  { status |= 0x04 }
        return status
    }
    
    override func getAIOStatus() -> (Bool, UInt16) {
        return (dsbUnusualEnd, (UInt16(getAIODetail()) << 8) | UInt16(aioStatus))
    }
    
    func mtlog(_ label: String = "") {
        if (trace) {
            if let fh = fileHandle {
                log("\(label): CURRENT=\(hexOut(fh.offsetInFile)), LAST MARK=\(hexOut(lastTapeMark))" + (atBOT ? ",BOT": "") + (atBOF ? ",BOF": "") + (atEOF ? ",EOF": "") + (atEOT ? ",EOT": ""))
            }
        }
    }

    //TODO: Return an object, not a tupple.
    override func mediaStatus() -> (Bool, UInt64, String, String) {
        let (mounted, position, file, statusText) = super.mediaStatus()
        if (mounted) {
            var t = statusText
            if (atBOT) { t.addToCommaSeparatedList("BOT")}
            if (atBOF) { t.addToCommaSeparatedList("BOF")}
            if (atEOF) { t.addToCommaSeparatedList("EOF")}
            if (atEOT) { t.addToCommaSeparatedList("EOT")}
            return (true, position, file, t)
        }
        return (false, position, file, statusText)
    }
    
    
    func position (to p: Int) -> Bool {
        if let fh = fileHandle {
            do {
                try fh.seek(toOffset: UInt64(p))
            }
            catch {
                mediaFailure()
                return false
            }
        }
        atBOT = (format == .mt) ? (p < 4) : (p == 0)
        if (atBOT) { atBOF = true }
        return true
    }
    
    func position (relative delta: Int) -> Bool {
        if (delta == 0) {
            log(level: .error, "Positioning relative: Zero")
        }
        let p = tapePosition
        if (delta < 0) {
            let m = -delta
            let n = (p < m) ? 0 : p-m
            return position(to: n)
        }
        
        let n = p+Int(delta)
        return position(to: n)
    }
    
    // REWIND:
    // Move to the beginning of the tape.  Read the header and determine the format.
    // Leave the tape positioned just before the first block length.
    func rewind() -> Bool {
        guard position(to: 0) else { return false }
        
        dsbAutomatic = true
        format = .none
        currentFile = 0
        lastTapeMark = 0
        protectionViolation = false
        
        if let le = readControlWord() {
            if (le < 0) {
                format = .mt
            }
            else if (le >= 0) {
                format = .tap
                guard position(to: 0) else { return false }
            }
            //else {
            // MAYBE there is a potential for a totally raw format?
            //}
        }
        else {
            mediaFailure()
            return false
        }
        
        atBOT = true
        atBOF = true
        atEOF = false
        atEOT = false
        
        return true
    }
    
    override func load(_ path: String, mode: AccessMode) -> Bool {
        if (super.load(path, mode: mode)) {
            guard rewind() else { return false }
            configuration?.access = mode
            
            //TODO: If a DEVICE END interrupt is posted now, will that invoke AVR?
            
            return true
        }
        mediaFailure()
        return false
    }
    
    
    // Called when a tape mark is encountered reading forward
    func processTapeMark(_ cw: Int, at position: Int = -1) {
        lastTapeMark = (position >= 0) ? position : tapePosition-4
        currentFile += 1
        
        switch (format) {
        case .none:
            break
        case .mt:
            // This control word is the negative file size of the preceding (just read) file..
            // Get filesize for next file..
            if let nw = readControlWord() {
                if (nw == 0) {
                    atEOT = true
                }
            }
            else {
                atEOT = true
            }
 
        case .tap:
            // This control word should be zero.
            if (cw != 0) { mediaFailure() }
        }
        atEOF = true    
    }
    
    
    func readControlWord() -> Int? {
        guard (fileHandle != nil) else { return nil }
        do {
            let pos = tapePosition
            let d = try fileHandle.read(upToCount: 4)
            if let nd = d as? NSData, (nd.length == 4) {
                let le = UnsafeRawPointer(nd.bytes).load(as: Int32.self)
                if (le > 0) {
                    //FIXME: if +ve, should always be <= 64K
                    if (le > 0x10000) {
                        log("Unexpected block length @\(hexOut(pos)): \(hexOut(Int(le)))")
                        mediaFailure()
                        return 0
                    }
                }
                return Int(le)
            }
        }
        catch {
            log(error.localizedDescription)
            mediaFailure()
            return nil
        }
        return nil
    }
    
    func writeControlWord(_ le: Int) -> Bool {
        if (le > 0) {
            //FIXME: if +ve, should always be <= 64K
            if (le > 0x10000) {
                log("Unexpected block length: \(le)")
                mediaFailure()
                return false
            }
        }
        
        var mle  = le
        do {
            try fileHandle.write(contentsOf: Data(bytes: &mle, count:4))
        }
        catch {
            log(error.localizedDescription)
            mediaFailure()
            return false
        }
        return true
    }
    


    override func sioStart(_ rq: IORequest) {
        super.sioStart(rq)
        readBuffer = nil
        writeBuffer = nil
    }
    
    override func sioDone(_ rq: IORequest) {
        super .sioDone(rq)
        
        if (readBuffer != nil) {
            readTrailingLength()
            readBuffer = nil
        }
        
        if (writeBuffer != nil) {
            // Now write blocksize and block
            var le = Int32(writeBuffer.count)
            if (format == .tap) && ((le&1) != 0) { writeBuffer.append(0x0) }
            do {
                try fileHandle.write(contentsOf: Data(bytes: &le, count:4))
                try fileHandle.write(contentsOf: writeBuffer)
                ioLength -= writeBuffer.count
                var previousBlockLength = Int(le)
                // Finally, write previous blocksize(little-endian).
                try fileHandle.write(contentsOf: Data(bytes: &previousBlockLength, count:4))
                atBOT = false
                atBOF = false
                atEOF = false
                atEOT = false
                if (trace) {
                    log ("WRITE: X'\(hexOut(Int(le)))' BYTES.  ")
                    var h: String = ""
                    var i: Int = 0
                    while (i < min(32, Int(le))) {
                        h += hexOut(writeBuffer[i])
                        i += 1
                    }
                    log (h)
                }
            }
            catch {
                log(error.localizedDescription)
                mediaFailure()
                return
            }
            
            mtlog("AFTER WRITE")
            writeBuffer = nil
        }
    }
    
    func readTrailingLength() {
        if var cw = readControlWord() {
            if (trace) {
                log ("TRAILING LENGTH @\(hexOut(readPosition)), LEADING=\(hexOut(currentBlockLength)), TRAILING=\(hexOut(cw)), POS=\(hexOut(tapePosition))")
            }
            if (format == .tap) && ((cw & 1) != 0) {
                cw += 1
            }
            if (cw != currentBlockLength) {
                mediaFailure()
                return
            }
        }
    }
    
    override func read(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        // Both Read1 (0x12)  and Read2 (0x02) function identically for our purposes.
        // Always positioned at the beginning of the length word for the next block to read.
        // Read operations can start partway through a block, within the context of a single SIO

        func readFromBuffer() {
            atEOF = false
            atBOT = false
            atBOF = false
            if !(cdw.fSkip) {
                memory.moveData(from: readBuffer, to: cdw.memoryAddress, maximum: ioLength)
                if (trace) {
                    log("MOVED TO MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(ioLength))' OF X'\(hexOut(readBuffer.count))' BYTES, FROM POSITION=\(hexOut(readPosition))")
                }
            }
            
            if (readBuffer.count <= ioLength) {
                // End of block. Read trailing length
                readTrailingLength()
                ioLength -= readBuffer.count
                readBuffer = nil
           }
            else {
                readBuffer = readBuffer.dropFirst(ioLength)
                ioLength = 0
            }
            return
        }
                
        if (readBuffer != nil) {
            readFromBuffer()
            mtlog("READ FROM BUFFER")
            return false
        }
        
        if (fileHandle == nil) || (atEOT) {
            asbChannelEnd = true
            dsbUnusualEnd = true
            if ((order & 0x80) != 0) {
                dsbInterruptPending = true
            }
            return false
        }
        
        //MARK: Always positioned before the next record length (or tape Mark)
        readPosition = Int(fileHandle.offsetInFile)
        if let cw = readControlWord() {
            if (cw > 0) {
                do {
                    //NOTE: .tap format has a pad byte when the length is odd.
                    readSize = (format == .tap) ? (cw+1) & 0xfffe : cw
                    
                    mtlog ("READBUFFER PRE")
                    readBuffer = try fileHandle.read(upToCount: readSize)
                }
                catch {
                    log(error.localizedDescription)
                    mediaFailure()
                    return false
                }
                readFromBuffer()
            }
            else {
                // Just read a tape mark...
                processTapeMark(cw, at: readPosition)
                
                dsbUnusualEnd = true
                asbChannelEnd = true
                                
                atBOF = true
            }
            atBOT = false
            mtlog("AFTER READ")
        }
        else { atEOF = true; atEOT = true; mtlog("atEOT" ) }
    
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return false
    }
    
    override func readBackward(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        // MARK: This appears never to be called.  Possibly SORT uses it.
        if (atBOT) || (atBOF) {
            dsbUnusualEnd = true
            asbChannelEnd = true
        }
        else {
            // Currently positioned just after the trailing lenghth.  Backup over the previous block and the trailing length
            guard position (relative: -4) else { mediaFailure(); return }
            let previousBlockLength = readControlWord()!
            if (previousBlockLength <= 0) {
                atBOF = true
                dsbUnusualEnd = true
                asbChannelEnd = true
            }
            
            guard position (relative: -(previousBlockLength+8)) else { mediaFailure(); return }

            // read forward from here, to get the block, then reposition
            let finalPosition = Int(fileHandle.offsetInFile)
            do {
                let blockLength = readControlWord()!
                if var buffer = try fileHandle.read(upToCount: min(blockLength,ioLength)) {
                    if (buffer.count > ioLength) {
                        log ("INCOMPLETE READ BACKWARDS")
                        buffer = buffer.dropFirst(buffer.count - ioLength)
                    }
                    if !(cdw.fSkip) {
                        memory.moveData(from: buffer, to: cdw.memoryAddress)
                        if (trace) {
                            log("MOVED TO MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(buffer.count))' OF X'\(hexOut(blockLength,width:0)) BYTES, FROM POSITION=\(hexOut(finalPosition))  BL=\(previousBlockLength),\(blockLength)")
                        }
                    }
                    ioLength -= buffer.count
                }
            }
            catch {
                log(error.localizedDescription)
                mediaFailure()
                return
            }
            guard position(to: finalPosition) else { mediaFailure(); return }
            mtlog("AFTER READ BACKWARDS")
        }
        
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
    }


    
    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        if (isReadOnly) {
            protectionViolation = true
            asbChannelEnd = true
            dsbUnusualEnd = true
        }
        else {
            protectionViolation = false
            let buffer = memory.getData(from: cdw.memoryAddress, count: ioLength)
            if (trace) {
                log("READ MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(buffer.count))' BYTES")
            }
            if (writeBuffer == nil) {
                writeBuffer = buffer
            }
            else {
                writeBuffer.append(buffer)
            }
        }

        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return false
    }
    
    
    override func special(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) -> Bool {
        // Most special purpose orders for tapes come through here.
        deviceEnd = false
        protectionViolation = false
        switch (order) {
        case 0x13:              // Rewind and Interrupt.
            guard rewind() else { mediaFailure(); return false }
            Thread.sleep(forTimeInterval: kTapeRewindTime)
            deviceEnd = true
            dsbInterruptPending = true
            return true
            
        case 0x23:              // Rewind Offline.
            guard rewind() else { mediaFailure(); return false }
            Thread.sleep(forTimeInterval: kTapeRewindTime)
            asbChannelEnd = true
            return true
            
        case 0x33:              // Rewind Online.
            guard rewind() else { mediaFailure(); return false }
            Thread.sleep(forTimeInterval: kTapeRewindTime)
            asbChannelEnd = true
            return true
            
        case 0x43:              // Space Record Forward.
        // Here we coukd be positioned on a regular record start (+ve length)
        // Or at BOF (tap same as above, mt -ve file size)
        // Or at EOF (tap: 0, mt: -ve trailing file size)

        // Logically however, we might have not read all of the data in the current block,
        // in which case we are already positioned just in front of the trailing lenght, and we need to get rid of the buffered  block.
            if (readBuffer != nil) {
                mtlog ("SRF, mid-block")
                readTrailingLength()
                return true
            }
            
            mtlog("SRF PRE")
            var previousPosition = tapePosition
            var cw = readControlWord() ?? 0
            if (cw > 0) {
                guard position(relative: cw) else { mediaFailure(); return false }
                readSize = cw
                readTrailingLength()
            }
            else {
                // Either EOF of BOF
                switch (format) {
                case .mt:
                    if (atEOF) {
                        // check cw is trailing file length
                        
                        previousPosition += 4
                        cw = readControlWord() ?? 0
                    }
                    
                    if (cw >= 0) {
                        atEOT = true
                    }
                    else {
                        atBOF = true
                    }
                    
                case .tap:
                    // Just read tape mark, so already at next file.
                    atBOF = true
                    
                case .none:
                    break
                }
                atEOF = true
                dsbUnusualEnd = true
            }
            //asbChannelEnd = true
            
            mtlog("SRF POST")
            return true
            
        case 0x4B:              // Space Record Backward.
            if (atBOT) || (atBOF) {
                dsbUnusualEnd = true
                asbChannelEnd = true
                return true
            }
            
            // Should be positioned just past the trailing record length.
            mtlog("SRB PRE")
            guard position(relative: -4) else { mediaFailure(); return false }
            let previousBlockLength = readControlWord() ?? 0
            
            if (previousBlockLength <= 0) {
                atBOF = true
                dsbUnusualEnd = true
                asbChannelEnd = true
                return true
            }
            
            guard position (relative: -(previousBlockLength+8)) else { mediaFailure(); return false }
            readSize = readControlWord() ?? 0
            if (readSize != previousBlockLength) { mediaFailure(); return false }
            guard position(relative: -4) else { mediaFailure(); return false }
            mtlog("SRB POST")
            
            //asbChannelEnd = true
            return true
            
        case 0x53:              // Space File Forward.
            mtlog("SFF PRE")
            if (format == .mt) {
                guard position (to: lastTapeMark) else { mediaFailure(); return false }
                if (lastTapeMark > 0) {
                    // Skip over previous file trailing size
                    _ = readControlWord()
                }
                
                if let cw = readControlWord() {
                    // Should be -ve filesize..
                    if (cw >= 0) {
                        mediaFailure()
                    }
                    guard position(relative: -cw) else { mediaFailure(); return false }
                    
                    // Now pointing at next trailing filesize
                    lastTapeMark = tapePosition
                    if let pw = readControlWord() {
                        if (pw != cw) {
                            log("*** TRAILING TAPE MARK MISMATCH @\(hexOut(lastTapeMark)), LEADING=\(hexOut(cw)), TRAILING=\(hexOut(pw)), CHECK=\(cw-pw)")
                        }
                        
                        if let _ = readControlWord() {
                            // Now correctly positioned...
                        }
                        else {
                            atEOT = true
                        }
                    }
                    else { mediaFailure() }
                }
            }
            else {
                readSize = readControlWord() ?? 0
                while (readSize > 0) {
                    guard position(relative: readSize) else { mediaFailure(); return false }
                    readTrailingLength()
                    readSize = readControlWord() ?? 0
                }
                lastTapeMark = tapePosition-4
            }
            
            atBOT = false
            atBOF = true
            atEOF = true                         // ?? Just read a tape Mark.
            asbChannelEnd = true

            mtlog("SFF POST")
            Thread.sleep(forTimeInterval: kTapeSpaceTime)
            return true
            
        case 0x5B:              // Space File Backward.
            if (atBOT) {
                dsbUnusualEnd = true
                asbChannelEnd = true
                return true
            }
            
            if (lastTapeMark == 0) {
                return rewind()
            }
            

            mtlog("SFB PRE")
            if (format == .mt) {
                let cpos = tapePosition
                while (cpos <= lastTapeMark) {
                    if !position(to: lastTapeMark) { mediaFailure() }
                    if let cw = readControlWord() {
                        lastTapeMark -= (cw+8)
                    }
                    else { mediaFailure() ; return true }
                }
                
            }
            else {
                let cpos = tapePosition
                while (cpos <= lastTapeMark) {
                    if !position(to: lastTapeMark-4) { mediaFailure() }
                    var previousBlockLength = readControlWord() ?? 0
                    while (previousBlockLength > 0) {
                        guard position(relative: -(previousBlockLength+12)) else { mediaFailure(); return false }
                        previousBlockLength = readControlWord() ?? 0
                    }
                    lastTapeMark = tapePosition-4
                }
            }

            if (lastTapeMark >= 0) {
                //  if !position (to: lastTapeMark-4) { mediaFailure(); return false }
                //    previousBlockLength = readControlWord() ?? 0
                //
                atEOT = false
                atBOT = false
                if !position(to: lastTapeMark) { mediaFailure(); return false }
            }
            else {
                _ = rewind()
            }

            atEOF = true                                // i.e. Just read a tape Mark.
            atBOF = false                               // Unknown until we reverse read/space
            asbChannelEnd = true

            mtlog("SFB POST")
            Thread.sleep(forTimeInterval: kTapeSpaceTime)
            return true

        case 0x63:              // Set Erase
            return true
            
        case 0x73:              // Write Tape Mark.
            if (isReadOnly) {
                protectionViolation = true
                asbChannelEnd = true
                dsbUnusualEnd = true
                return false
            }
            
            lastTapeMark = tapePosition
            _ = writeControlWord(0)
            return true
            
        default:
            return false
        }
    }
    
}

// MARK: RANDOMACCESSDEVICE
class RandomAccessDevice: BlockDevice {
    class StorageConfiguration : BlockDevice.StorageConfiguration {

        var cylinders: Int
        var heads: Int
        var sectorsPerTrack: Int
        
        var logicalSPC: Int
        var physicalSPC: Int
        
        init (chs: (Int, Int, Int),_ flags: UInt64 = 0) {
            self.cylinders = chs.0
            self.heads = chs.1
            self.sectorsPerTrack = chs.2
            self.physicalSPC = (heads * sectorsPerTrack)
            self.logicalSPC = physicalSPC & 0xFFFE
            
            super.init (access: .update, ioSize: 2048, flags)
        }
    }

    var seekData = Data()
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, type: Device.DType,_ model: Int, fullPath: String?, mountable: Bool, configuration: StorageConfiguration) {
        super.init (machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: type, model, fullPath: fullPath, mountable: mountable, configuration: configuration)
    }
    
    func loadAndCreateIfRequired (_ path: String, minimumSize: UInt64 = 0) -> Bool {
        // make sure this exists and has a label (which may contain junk)
        let p = resolvePath(path)
        
        //MARK: Quick check if it exists and has the minimum size.  In this cae the mode can be .read
        if FileManager.default.fileExists(atPath: p) {
            do {
                let a = try FileManager.default.attributesOfItem(atPath: p)
                if let size = a[.size] as? UInt64, (size >= minimumSize) {
                    return super.load(path, mode: mode)
                }
            }
            catch {
                log(level: .error, "Device file verification THREW.")
                dsbAutomatic = false
            }
        }
        
        guard (mode == .update) else { return false }
        
        if !FileManager.default.fileExists(atPath: p) {
            FileManager.default.createFile(atPath: p, contents: nil)
        }
        
        if !super.load(path, mode: .update) {
            return false
        }
        do {
            let a = try FileManager.default.attributesOfItem(atPath: p)
            if let size = a[.size] as? UInt64, (size < minimumSize) {
                let eof = try fileHandle?.seekToEnd()
                if var size = eof, (size < minimumSize) {
                    // Past the end of the existing data.  Extend the file.
                    if (MSLogManager.shared.logLevel >= .info) {
                        log("EXTENDING \(name) TO  \(minimumSize) FROM \(size)")
                    }
                    let block = Data(repeating: 0xff, count: 0x400)
                    while (size < minimumSize) {
                        try fileHandle?.write(contentsOf: block)
                        size += UInt64(block.count)
                    }
                }
            }
        }
        catch {
            log(level: .error, "Device file verification THREW.")
            dsbAutomatic = false
        }
        return true
    }

    //MARK: Geometry
    // Get cyl/head/sector information a relative sector number or from current file position.
    func CHS (relativeSector: Int = -1) -> (Int, Int, Int) {
        var rs = relativeSector
        if (rs < 0) {
            var byteOffset: UInt64 = 0
            do {
                try byteOffset = fileHandle!.offset()
                rs = Int(byteOffset / 1024)
            }
            catch {
                log(level: .error, "FileHandle sense operation THREW.")
                dsbAutomatic = false
            }
        }
        
        if let c = configuration as? StorageConfiguration {
            let (cylinder, r) = rs.quotientAndRemainder(dividingBy: c.physicalSPC)
            let (head, sector) = r.quotientAndRemainder(dividingBy: c.sectorsPerTrack)
            return (cylinder,head,sector)
        }
        
        siggyApp.panic(message: "Invalid model data for "+name)
        return (0,0,0)
    }
    
    override func mediaStatus() -> (Bool, UInt64, String, String) {
        let (mounted, position, file, statusText) = super.mediaStatus()
        if (mounted) {
            var t = statusText + ((statusText != "") ? ", " : "")
            let physicalSector = position/1024
            let (c,h,s) = CHS()
            t += "C=\(c), H=\(h), S=\(s) [Decimal]"
            t += ", Physical Sector=\(physicalSector)/X'\(hexOut(physicalSector,width:0)) "
            return (true, position, file, t)
        }
        return (false, position, file, statusText)
    }
    

    
    override func read(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        // Both Read1 (0x12)  and Read2 (0x02) function identically for our purposes.
        do { let buffer = try fileHandle?.read(upToCount: ioLength)
            if (buffer != nil) {
                var m = "MOVED"
                if (cdw.fSkip) {
                    m = "SKIPPED MOVE"
                }
                else {
                    memory.moveData(from: buffer!, to: cdw.memoryAddress)
                }
                if (trace) {
                    log(m + " TO MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(buffer!.count))' BYTES")
                }
                ioLength -= buffer!.count
            }
        }
        catch {
            log(level: .error, "FileHandle read operation THREW.")
            dsbAutomatic = false
        }
                
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return false
    }
    
    override func write(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        let buffer = memory.getData(from: cdw.memoryAddress, count: ioLength)
        if (trace) {
            log("READ MEMORY BA=\(hexOut(cdw.memoryAddress)), COUNT=X'\(hexOut(buffer.count))' BYTES")
        }

        do { try fileHandle?.write(contentsOf: buffer)
            ioLength -= buffer.count
        }
        catch {
            log(level: .error, "FileHandle write operation THREW.")
            dsbAutomatic = false
        }

        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return false
    }

    
    override func special(_ cdw: IOCommand, _ order: UInt8, _ memory: RealMemory) -> Bool {
        switch (order) {
        case 0x05:
            // Read the data, causing the file positioning to occur.
            do { let data = try fileHandle?.read(upToCount: ioLength)
                if (data == nil) {
                    dsbUnusualEnd = true
                    return true
                }
                
                // Could do a compare here...
                ioLength -= data!.count
            }
            catch {
                log(level: .error, "FileHandle read operation THREW.")
                dsbAutomatic = false
            }
            break
            
        case 0x0A:
            // Read our perfect headers - no flaws here.
            var data = Data(repeating: 0, count: ioLength)
            var (cylinder, head, sector) = CHS()
            
            if let c = configuration as? StorageConfiguration {
                var i = 0
                while (i < data.count) {
                    data[i+1] = UInt8(cylinder >> 8)
                    data[i+2] = UInt8(cylinder & 0xff)
                    data[i+3] = UInt8(head & 0x1f)
                    data[i+4] = UInt8(sector & 0xf)
                    
                    i += 8
                    sector += 1
                    if (sector >= c.sectorsPerTrack) {
                        sector = 0
                        head += 1
                        if (head >= c.heads) {
                            head = 0
                            cylinder += 1
                        }
                    }
                }
            }
            
            if (!cdw.fSkip) {
                memory.moveData(from: data, to: cdw.memoryAddress)
            }
            ioLength -= data.count
            
        default:
            return false
        }
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return true
    }
    
    
    func savePosition() -> UInt64 {
        // Wait for all outstanding I/O's to complete.
        ioQueue.waitUntilAllOperationsAreFinished()
        
        if let fh = fileHandle {
            let cp = try! fh.offset()
            return cp
        }
        return 0
    }
    
    func restorePosition (_ position: UInt64) {
        if let fh = fileHandle {
            try! fh.seek(toOffset: position)
        }
    }


    
}

//MARK: DPDEVICE
//MARK: CYL, HEAD, SPT values are for 86MB model 7275.
class DPDevice: RandomAccessDevice {
    var OnSector: Bool = false
    
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, fullPath: String?, mountable: Bool) {
        var chs: (Int, Int, Int) = (411, 19, 11)
        switch model {
        case 7275:  chs = (411, 19, 11)
        default: break
        }
        
        let configuration = RandomAccessDevice.StorageConfiguration(chs: chs, 0)
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .dp, model, fullPath: fullPath, mountable: mountable, configuration: configuration)
    }

      
    // TDV and AIO produce special device status bytes for DISKs
    // These happen to be the same.
    override func getTDVDetail() -> UInt8 {
        var status: UInt8 = 0
        let (c, _, _) = CHS()
        // bit 0: Overrun, nope
        // bit 1: Flaw, nope
        // bit 2: Programming error
        // bit 3: Write protection
        if (!isWritable)  { status |= 0x20 }
        return status
    }

    override func getAIODetail()-> UInt8 {
        if (OnSector) {
            OnSector = false
            asbChannelEnd = false
            return 0x08
        }
        return 0
    }
    

    
    
    override func load(_ path: String, mode: AccessMode) -> Bool {
        loadAndCreateIfRequired(path, minimumSize: 0x4000)
    }


    override func control(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        OnSector = false
        if ((order == 0x07) || (order == 0x17)) {
            // Could be X'07' (reserve) or X'17' (release);
            // For a single CPU these are superfluous.
        }
        else if ((order == 0x33) || (order == 0xB3)) {
            // RESTORE CARRIAGE.
            do {
                try fileHandle?.seek(toOffset: 0)
                OnSector = true
            }
            catch {
                log(level: .error, "FileHandle SEEK operation THREW.")
                dsbAutomatic = false
            }
        }
        else {
            seekData = memory.getData(from: cdw.memoryAddress, count: 4)
            // It's BigEndian
            let cylinder = (Int(seekData[0]) << 8) | Int(seekData[1])
            let head = Int(seekData[2])
            let sector = Int(seekData[3])
            
            if let c = configuration as? StorageConfiguration, (cylinder < c.cylinders) && (head < c.heads) && (sector < c.sectorsPerTrack){
                let diskSector = (cylinder * c.heads  +  head) * c.sectorsPerTrack + sector
                let byteOffset = UInt64(diskSector) * 1024
                if (trace) || (MSLogManager.shared.logLevel >= .debug) {
                    log("SEEK TO \(cylinder):\(head):\(sector) DISK SECTOR \(diskSector) ADDRESS \(byteOffset)")
                }
                do {
                    try fileHandle?.seek(toOffset: byteOffset)
                    OnSector = true
                }
                catch {
                    log(level: .error, "FileHandle SEEK operation THREW.")
                    dsbAutomatic = false
                }
            }
            else {
                if (trace) || (MSLogManager.shared.logLevel >= .debug) {
                    log("INVALID SEEK TO \(cylinder):\(head):\(sector)")
                }
                dsbUnusualEnd = true
            }
            ioLength -= 4
        }
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return true
    }
    

    override func sense(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        // Get cyl/head/sector information from current file position.
        let (cylinder, head, sector) = CHS()
        seekData[0] = UInt8(cylinder >> 8)
        seekData[1] = UInt8(cylinder & 0xFF)
        seekData[2] = UInt8(head)
        seekData[3] = UInt8(sector)
        
        var senseData = Data()
        senseData.append(seekData)
        while (senseData.count < ioLength) {
            senseData.append(0)
        }

        if (trace) || (MSLogManager.shared.logLevel >= .debug) {
            for h in hexDump(senseData) {
                log("SENSE: "+h)
            }
        }
        
        if !(cdw.fSkip) {
            memory.moveData(from: senseData, to: cdw.memoryAddress)
        }
        ioLength -= senseData.count
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
    }
    
    

}

//MARK: DCDEVICE
//MARK: BAND and SPB values are for a 5MB model 7212
class DCDevice: RandomAccessDevice {
    init(_ machine: VirtualMachine, name: String, iopNumber: UInt8, unitAddr: UInt8, model: Int, fullPath: String?) {
        var chs: (Int, Int, Int) = (1,64,82)
        switch model {
        case 7212:  chs = (1,64,82)
        default: break
        }
        
        let configuration = RandomAccessDevice.StorageConfiguration(chs: chs, 0)
        super.init(machine, name: name, iopNumber: iopNumber, unitAddr: unitAddr, type: .dc, model, fullPath: fullPath, mountable: false, configuration: configuration)
    }
    //Model(7212, chs: (1,64,82))
    
    // TDV and AIO produce special device status bytes for RADs
    // These happen to be the same.
    override func getTDVDetail() -> UInt8 {
        var status: UInt8 = 0
        let (c, _, _) = CHS()
        // bit 0: Overrun, nope
        // bit 1: Unassigned
        // bit 2: Sector unavailable
        // bit 3: Write protection violation, nope
        if (c > 0)  { status |= 0x20 }
        return status
    }
    
    override func getAIOStatus() -> (Bool, UInt16) {
        return (dsbUnusualEnd, (UInt16(getTDVDetail()) << 8) | UInt16(aioStatus))
    }

    override func load(_ path: String, mode: AccessMode) -> Bool {
        loadAndCreateIfRequired(path, minimumSize: 0x20000)
    }
    

    override func sense(_ cdw: IOCommand,_ order: UInt8,_ memory: RealMemory) {
        // Get band/sector information from current file position.
        let (_, h, s) = CHS()
        seekData[0] = UInt8(h >> 1)
        seekData[1] = UInt8(s | ((h & 0x1) << 7))
        
        var senseData = Data()
        senseData.append(seekData)
        senseData.append(0)                     // Current sector
        senseData.append(0)                     // Failed track(s) = none
        while (senseData.count < ioLength) {
            senseData.append(0)
        }
        
        if !(cdw.fSkip) {
            memory.moveData(from: senseData, to: cdw.memoryAddress)
        }
        ioLength -= senseData.count
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
    }
    
    
    override func control(_ cdw: IOCommand,_ order: UInt8, _ memory: RealMemory) -> Bool {
        if ((order == 0x07) || (order == 0x17)) {
            // Could be X'07' (reserve) or X'17' (release);
            // For a single CPU these are superfluous.
        }
        else if ((order == 0x33) || (order == 0xB3)) {
            log(level: .info, "ORDER: \(hexOut(order))")
        }
        else {
            seekData = memory.getData(from: cdw.memoryAddress, count: 2)
            // It's BigEndian
            let cylinder = 0
            let head = (Int(seekData[0]) << 1) | Int(seekData[1] >> 7)
            let sector = Int(seekData[1] & 0x7F)
            
            if let c = configuration as? StorageConfiguration, (cylinder < c.cylinders) && (head < c.heads) && (sector < c.sectorsPerTrack) {
                let rSector = head * c.sectorsPerTrack + sector
                let byteOffset = UInt64(rSector) * 1024
                if (trace) || (MSLogManager.shared.logLevel >= .debug) {
                    log("SEEK TO \(head):\(sector) RAD SECTOR \(rSector) ADDRESS \(byteOffset)")
                }
                do {
                    try fileHandle?.seek(toOffset: byteOffset) }
                catch {
                    log(level: .error, "FileHandle SEEK operation THREW.")
                    dsbAutomatic = false
                }
            }
            else {
                if (trace) || (MSLogManager.shared.logLevel >= .debug) {
                    log("INVALID SEEK TO \(cylinder):\(head):\(sector)")
                }
                dsbUnusualEnd = true
            }
        }
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return true
    }
    
    
    override func special(_ cdw: IOCommand, _ order: UInt8, _ memory: RealMemory) -> Bool {
        switch (order) {
        case 0x05:
            // Read the data, causing the file positioning to occur.
            do { let data = try fileHandle?.read(upToCount: ioLength)
                if (data == nil) {
                    dsbUnusualEnd = true
                    return true
                }
                
                // Could do a compare here...
                ioLength -= data!.count
            }
            catch {
                log(level: .error, "FileHandle read operation THREW.")
                dsbAutomatic = false
            }
            break
            
            
        case 0x33, 0xB3:
            do {
                try fileHandle?.seek(toOffset: 0) }
            catch {
                log(level: .error, "FileHandle SEEK operation THREW.")
                dsbAutomatic = false
            }
            
        default:
            return false
        }
        
        asbChannelEnd = true
        if ((order & 0x80) != 0) {
            dsbInterruptPending = true
        }
        return true
    }

}



