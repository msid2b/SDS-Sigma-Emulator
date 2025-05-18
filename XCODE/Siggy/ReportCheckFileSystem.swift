//
//  ReportCheckFileSystem.swift
//  Siggy
//
//  Created by MS on 2024-03-22.
//

import Foundation

//MARK: Check Public File System and report
//MARK: THIS CODE IS BEING RENOVATED


class CheckFileSystemReport: ReportViewController {
    /**struct PFSDevice {
        var path: String
        var fh: FileHandle?
        
        var pfaFirstSector: UInt32
        var pfaGranuleCount: UInt32
        
        var hgpMap: BitMap!
        var checkMap: BitMap!
        
        init(path: String) {
            self.device = device
            self.position = position
            self.hgp = hgp
            dctx = hgp.dctx
            
            pfaGranuleCount = UInt32(hgp.pfa_mapwl) << 2
            pfaFirstSector = UInt32(hgp.pfa_first)
            let wa = hgp.address + Int(hgp.pfa_mapwd)
            let d = hgp.c.unmappedMemory.getData(from: wa << 2, count: Int(pfaGranuleCount))
            hgpMap = BitMap(count: d.count, from: d)
            checkMap = BitMap(count: d.count, 0xFF)
        }
    }
    var pfs: [UInt8 : PFSDevice] = [:]*/
    
    class WordArray {
        var count: Int
        var buffer: UnsafeMutablePointer<UInt8>!
        var bytes: UnsafeMutableRawPointer!
        
        init() {
            count = 0
            buffer = nil
            bytes = nil
        }
        
        init(preamble: Int = 0, _ data: Data) {
            count = preamble + (data.count + 3) >> 2
            buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count << 2)
            bytes = UnsafeMutableRawPointer(buffer)
            data.copyBytes(to: &buffer[preamble << 2], count: data.count)
        }
        
        func byte(_ b: Int) -> UInt8 {
            return buffer[b]
        }
        
        func bytes(at: Int, count: Int) -> Data {
            var x = at
            let rem = 2048 - x
            let m = min(count,rem)
            let n = x + m
            var d = Data()
            while (x < n) {
                d.append(buffer[x])
                x += 1
            }
            return d
        }
        
        func word(_ w: Int) -> UInt32 {
            return bytes.load(fromByteOffset: (w << 2), as: UInt32.self).bigEndian
        }
        
        func setWord(_ w: Int, _ value: UInt32) {
            bytes.storeBytes (of: value.bigEndian, toByteOffset: w << 2, as: UInt32.self)
        }
        
        func diskAddress3(at: Int) -> DiskAddress {
            let d = bytes(at: at, count: 3)
            return DiskAddress(d)
        }
        
        func isEqual(_ other: WordArray) -> Bool {
            if (other.count == count) {
                for i in 0 ... (count << 2) {
                    if buffer[i] != other.buffer[i] {
                        return false
                    }
                }
                return true
            }
            return false
        }

    }
    
    class Granule : WordArray {
        var blink: UInt32   { get { return word(0) }}
        var flink: UInt32   { get { return word(1) }}
        
        var gaval: UInt32   { get { return word(509) & 0xFFFFFF }}
        
        var fst: UInt32     { get { return word(510) }}
        var dblink: UInt32  { get { return word(510) }}
        var dflink: UInt32  { get { return word(511) }}
        
        // MARK: Index granule fields
        var nav: UInt16     { get { return UInt16(word(2) >> 16) }}
        var f: Bool         { get { return (word(2) & 0x8000) != 0 }}
        var s: Bool         { get { return (word(2) & 0x4000) != 0 }}
        var level: UInt8    { get { return UInt8(word(2) >> 10) & 0xF }}
        var a: Bool         { get { return (word(2) & 0x10) != 0 }}
        var scr: UInt8      { get { return byte(11)} }
        
        
    }
    
    //MARK: HGP in memory. NOT USED.  Parked here.
    class HGPMemory {
        var address: Int = 0
        var ba: Int = 0
        var c: CPU!
        
        var iscat: Bool         { get { return !priv }}
        var flink: UInt32       { get { return c.loadUnsignedWord(wa: address) }}
        var dctx: UInt8         { get { return c.loadByte(ba: ba+5)}}
        var cyl: Bool           { get { return (c.loadByte(ba: ba+6) & 0x80) != 0}}
        var priv: Bool          { get { return (c.loadByte(ba: ba+6) & 0x40) != 0}}
        var type: UInt8         { get { return c.loadByte(ba: ba+6) & 0x3F }}
        var ngc: UInt8          { get { return c.loadByte(ba: ba+7) }}
        var nst: UInt32         { get { return c.loadUnsignedWord(wa: address+2) }}
        var sflnk: UInt32       { get { return c.loadUnsignedWord(wa: address+2) }}
        var lbp: UInt16         { get { return UInt16(c.loadUnsignedWord(wa: address+3) >> 16) }}
        var nsg: UInt16         { get { return UInt16(c.loadUnsignedWord(wa: address+3) & 0xFFFF) }}
        var lbd: UInt16         { get { return UInt16(c.loadUnsignedWord(wa: address+3) & 0xFFFF) }}
        var per_mapwl: UInt16   { get { return UInt16(c.loadUnsignedWord(wa: address+4) >> 16) }}
        var pfa_mapwl: UInt16   { get { return UInt16(c.loadUnsignedWord(wa: address+4) & 0xFFFF) }}
        var nvat: UInt32        { get { return c.loadUnsignedWord(wa: address+5) }}
        var per_empty: Bool     { get { return c.loadWord(wa: address+5) < 0}}
        var per_mapwd: UInt16   { get { return UInt16(c.loadWord(wa: address+5) >> 16)}}
        var per_first: UInt16   { get { return UInt16(c.loadWord(wa: address+5) & 0xFFFF)}}
        var pfa_empty: Bool     { get { return c.loadWord(wa: address+6) < 0}}
        var pfa_mapwd: UInt16   { get { return UInt16(c.loadWord(wa: address+6) >> 16)}}
        var pfa_first: UInt16   { get { return UInt16(c.loadWord(wa: address+6) & 0xFFFF)}}
        
        init (_ cpu: CPU!,_ address: Int) {
            self.c = cpu
            self.address = address
            self.ba = address << 2
        }
    }

    class HGP : WordArray {
        var iscat: Bool         { get { return !priv }}
        var flink: UInt32       { get { return word(0) }}
        var dctx: UInt8         { get { return buffer[5] }}
        var cyl: Bool           { get { return (buffer[6] & 0x80) != 0}}
        var priv: Bool          { get { return (buffer[6] & 0x40) != 0}}
        var type: UInt8         { get { return buffer[6] & 0x3F }}
        var ngc: UInt8          { get { return buffer[7] }}
        var nst: UInt32         { get { return word(2) }}
        var sflnk: UInt32       { get { return word(2) }}
        var lbp: UInt16         { get { return UInt16(word(3) >> 16) }}
        var nsg: UInt16         { get { return UInt16(word(3) & 0xFFFF) }}
        var lbd: UInt16         { get { return UInt16(word(3) & 0xFFFF) }}
        var per_mapwl: UInt16   { get { return UInt16(word(4) >> 16) }}
        var pfa_mapwl: UInt16   { get { return UInt16(word(4) & 0xFFFF) }}
        var nvat: UInt32        { get { return word(5) }}
        var per_empty: Bool     { get { return word(5) < 0}}
        var per_mapwd: UInt16   { get { return UInt16(word(5) >> 16)}}
        var per_first: UInt16   { get { return UInt16(word(5) & 0xFFFF)}}
        var pfa_empty: Bool     { get { return word(6) < 0}}
        var pfa_mapwd: UInt16   { get { return UInt16(word(6) >> 16)}}
        var pfa_first: UInt16   { get { return UInt16(word(6) & 0xFFFF)}}
        
    }
    

    func readGranule (atLogicalSector: Int) -> Granule? {
//        if let fh = fileHandle {
            var physicalSector = atLogicalSector
            
//            if let m = model as? Model, (m.physicalSPC > m.logicalSPC) {
//                let (cyl, sector) = physicalSector.quotientAndRemainder(dividingBy: m.logicalSPC)
//                physicalSector = (cyl * m.physicalSPC) + sector
//            }
//            do {
//                try fh.seek(toOffset: UInt64(physicalSector*1024))
//                let data = try fh.read(upToCount: 2048)!
//                return Granule(data)
//            }
//            catch { return nil }
//        }
        return nil
    }
    
    func readGranule (number: Int) -> Granule? {
        return readGranule(atLogicalSector: number << 1)
    }
    
    func readGranule (da: DiskAddress) -> Granule? {
//        if let c = cpu, let dct1 = c.monitorInfo?.dct1 {
//            let devAddr = cpu.loadUnsignedHalf(ha: (dct1 << 1) + Int(da.dctx))
//            if (devAddr > 0), let d = device(withAddress: devAddr) as? RandomAccessDevice {
//                return d.readGranule(atLogicalSector: Int(da.sector))
//            }
//        }
        return nil
    }


    //MARK: Check the whole public file system.
    func checkPFS(_ m: VirtualMachine) {
        beginReport(title: "Public File System", machine: m)
        
        var deviceList: [(Int, String)] = []
        
        // Scan for disks and rads.
        let s = SQLStatement(m.db)
        if s.prepare(statement: "SELECT address, type, hostpath FROM DEVICES") {
            while (s.row()) {
                deviceList.append((s.column_int(0, defaultValue: 0), s.column_string(2, defaultValue: "")))
            }
            checkPFS(m.url, deviceList)
        }
    }

    
    func checkPFS(_ directory: URL,_ devices: [(Int, String)]) {
        
        var systemImageSector: UInt64 = 0
        var bootFileHandle: FileHandle!
        var bootDevice: String = ""
        var systemImage: WordArray!
        var hgps: [(HGP?, WordArray?)] = []

        var dx = 0
        while (bootFileHandle == nil) && (dx < devices.count) {
            var p = devices[dx].1
            
            if (p.first == ".") {
                p = directory.appendingPathComponent(String(p.dropFirst(2))).path
            }
            let fh = FileHandle(forReadingAtPath: p)
            do {
                if let d = try fh?.read(upToCount: 0x58) {
                    if (d[0] == 0x6C), (d[1] == 0x00), (d[2] == 0x00), (d[3] == 0x00),
                       (d[4] == 0x68), (d[5] == 0x20), (d[6] == 0x00), (d[7] == 0x2E) {
                        // LOOKS LIKE A CPV BOOTSTRAP
                        if (d[16] == 0x22), (d[17] == 0), (d[18] == 0) {
                            // CALCULATE THE BYTE OFFSET IN THE BOOK RECORD TO THE SEEK COMMAND.
                            let sca = (Int(d[19]) << 3) - 0xA8
                            // DETERMINE BYTE OFFSET TO THE SEEK DATA
                            let sda = ((Int(d[sca+2]) << 8) | Int(d[sca+3])) - 0xA8
                            // AND GET SEEK DATA LENGTH
                            let sdl = ((Int(d[sca+6]) << 8) | Int(d[sca+7]))
                            
                            //TODO: DEVICE TABLE NEEDS MODEL NUMBER INFORMATION
                            switch (sdl) {
                            case 2:
                                //MARK: RAD, Assume 7212
                                let b = (Int(d[sda]) << 1) | Int(d[sda+1] >> 7)
                                let s = Int(d[sda+1]) & 0x7F
                                systemImageSector = UInt64(b * 82 + s)
                                bootFileHandle = fh
                                
                            case 4:
                                //MARK: DISK, Assume 7275
                                let c = (Int(d[sda]) << 8) | Int(d[sda+1])
                                let h = (Int(d[sda+2]))
                                let s = (Int(d[sda+3]))
                                // Physical sector 208 of each cylinder are not used but present.
                                systemImageSector = UInt64((c * 209) + (h * 11) + s)
                                bootFileHandle = fh
                                
                            default:
                                printWarning ("\(p)): Can't determine sector for system image")
                            }
                        }
                    }
                }
            }
            catch { printError("Unable to read: "+p)}
            dx += 1
        } // while
            
        // Did we find a candidate?
        if let fh = bootFileHandle, (systemImageSector > 0) {
            // READ HGPs FROM SECTOR 8.
            do {
                try fh.seek(toOffset: 0x2000)
                
                var hgpFlink: UInt32 = 0xA000
                while (hgpFlink > 0) {
                    hgpFlink = 0
                    if let hgpData = try fh.read(upToCount: 28) {
                        let hgp = HGP(hgpData)
                        
                        let bitmapSize = Int(hgp.per_mapwl) + Int(hgp.pfa_mapwl)
                        if let bitmap = try fh.read(upToCount: bitmapSize << 2) {
                            hgps.append((hgp, WordArray(bitmap)))
                            hgpFlink = hgp.flink
                            
                        }
                    }
                }
            }
            catch { printError("\(bootDevice): Can't read HGPs")}
            
            // .8000 BYTES FROM THE SYSTEM IMAGE MIGHT NOT DO.
            do {
                try fh.seek(toOffset: systemImageSector * 1024)
                let systemImageData = try fh.read(upToCount: 0x8000)
                systemImage = WordArray(systemImageData!)
            }
            catch { printError("\(bootDevice): Can't read system image")}
            
            // Go look for TYA01.  That should be the start of DCT22.   Convert the names into addresses -- good enough.
            
            
            
            

        }
    }
    
    
    
    func dumpGranule (_ title: String, _ g: Granule!,_ wordCount: Int = 512) {
        printHeading(title)
        
        let w = UnsafeMutablePointer<UInt32>.allocate(capacity: wordCount)
        for i in 0 ... wordCount {
            w[i] = g.word(i)
        }
        
        hexDump (words: w, count: wordCount, addressWidth: 3, abbreviate: true)
    }
    
    func validateGranule (_ a: DiskAddress) {
        /**
         if let x = publicFileSystem.firstIndex(where: { (d) in return(d.dctx == a.dctx) } ) {
         if (a.sector >= publicFileSystem[x].pfaFirstSector) {
         let g = Int(a.sector - publicFileSystem[x].pfaFirstSector) >> 1
         if (g < publicFileSystem[x].pfaGranuleCount) {
         if (publicFileSystem[x].checkMap.isReset(g)) {
         printError("\(publicFileSystem[x].device.name): Granule \(hexOut(g)) is already allocated.")
         }
         publicFileSystem[x].checkMap.resetBit(g)
         
         if (publicFileSystem[x].hgpMap.isSet(g)) {
         printError("\(publicFileSystem[x].device.name): Granule \(hexOut(g)) not allocated in HGP.")
         }
         return
         }
         }
         
         printWarning("Not in public file area: \(hexOut(a.dctx)):\(hexOut(a.sector))")
         return
         }
         
         printError("Invalid disk address: \(hexOut(a.dctx)):\(hexOut(a.sector))")
         */
    }
    
    // Returns false if any messages produced.
    func checkIndexGranule(_ g: Granule!, expectedFlink: UInt32? = nil, expectedBlink: UInt32? = nil, expectedSCR: UInt8 = 0) -> Bool {
        let granuleSize = g.s ? 2048 : 1024
        let ec = errorCount
        
        if let e = expectedFlink, (g.flink != e) {
            printError("FLINK: .\(hexOut(g.flink)) <-- Expected .\(hexOut(e))")
        }
        if let e = expectedBlink, (g.blink != e) {
            printError("BLINK: .\(hexOut(g.blink)) <-- Expected .\(hexOut(e))")
        }
        if (g.nav < 0x1C) || (g.nav >= granuleSize) {
            printError("Invalid NAV: .\(hexOut(g.nav))")
        }
        if (expectedSCR > 0) && (g.scr != expectedSCR) {
            printError("Invalid SCR: .\(hexOut(g.scr))")
        }
        
        if (errorCount == ec) {
            return true
        }
        
        dumpGranule("Index Granule", g, granuleSize >> 2)
        return false
    }
    
    func checkFileDirectory (_ m: VirtualMachine,_ name: String,_ dap: DiskAddress!,_ dab: DiskAddress!) {
        var granuleNumber = 0
        var dp = dap!
        var db = dab!
        while (dp.wordValue != 0), (db.wordValue != 0) {
            if let gp = readGranule(da: dp), let gb = readGranule(da: db) {
                validateGranule(dp)
                validateGranule(db)
                
                if (gp.isEqual(gb)) {
                    _ = checkIndexGranule(gp, expectedSCR: 0x20)
                    
                    if (granuleNumber == 0) {
                        //TODO:  check free pool.
                    }
                    
                    var x = 0x0c
                    while (x < gp.nav) {
                        let len = Int(gp.byte(x))
                        if (len > 0x20) {
                            printError("Invalid key length (\(len)) at offset .\(hexOut(x,width:2)), should be <= 32")
                            break
                        }
                        x += 1
                        
                        let fileName = asciiBytes(gp.bytes(at: x, count: len))
                        x += 32
                        let dablk = gp.diskAddress3(at: x)
                        x += 3
                        let descriptors = gp.bytes(at: x, count: 5)
                        x += 5
                        
                        printLine("\(pad(fileName,32)) DA=[\(hexOut(dablk.dctx,width:2)), \(hexOut(dablk.sector,width:4))]," +
                                  " Descriptors: \(hexOut(descriptors[0], width: 2)) \(hexOut(descriptors[1], width: 2)) \(hexOut(descriptors[2], width: 2)) \(hexOut(descriptors[3], width: 2)) \(hexOut(descriptors[4], width: 2))")
                    }
                    
                    // Get next granule
                    dp = DiskAddress(gp.flink)
                    db = DiskAddress(gb.dflink)
                }
                else {
                    printError(name+": primary / backup file directories don't match for granule #\(granuleNumber)")
                    dumpGranule("Primary", gp)
                    dumpGranule("Backup", gb)
                    
                    dp = DiskAddress(0)
                    db = DiskAddress(0)
                }
                granuleNumber += 1
            }
        }
        
        if (granuleNumber == 0) {
            printError(name+": Can't read primary or backup file directory (or both)")
        }
    }
    
    
    //MARK: Check the whole public file system.
    func checkPFS2(_ m: VirtualMachine) {
        beginReport(title: "Public File System", machine: m)
        var adg: Granule!
        
        if let c = m.cpu {
            c.control.acquire()
            if let mon = c.monitorInfo {
                let dct1 = c.monitorInfo.dct1
                var hgpp = monSymbol(c, "HGP")
                
                setIndent(increaseBy: 2)
                printLine("DCT1: .\(hexOut(dct1,width:4))")
                printLine("HGP:  .\(hexOut(hgpp,width:4))")
                setIndent(decreaseBy: 2)
                
                printLine("... LOOKING FOR TROUBLE ...", color: .red, skip: 1)
                
                while (hgpp > 0) {
                    printLine("HGP [.\(hexOut(hgpp,width:4))]", skip: 1)
                    let hgp = HGPMemory(c, hgpp)
                    printLine("DCT: .\(hexOut(hgp.dctx)), CYL: \(hgp.cyl ? "Y": "N"),  PRIV: \(hgp.priv ? "Y": "N"), NGC: \(hgp.ngc)")
                    if (hgp.iscat) {
                        printLine("SFLNK:      .\(hexOut(hgp.sflnk))")
                        printLine("LBP:        .\(hexOut(hgp.lbp))")
                        printLine("LBD:        .\(hexOut(hgp.lbd))")
                        if (hgp.per_empty) {
                            printLine("PER_EMPTY")
                        }
                        else {
                            printLine("PER_MAPWL:  .\(hexOut(hgp.per_mapwl))")
                            printLine("PER_MAPWD:  .\(hexOut(hgp.per_mapwd))")
                            printLine("PER_FIRST:  .\(hexOut(hgp.per_first))")
                        }
                        if (hgp.pfa_empty) {
                            printLine("PFA_EMPTY")
                        }
                        else {
                            printLine("PFA_MAPWL:  .\(hexOut(hgp.pfa_mapwl))")
                            printLine("PFA_MAPWD:  .\(hexOut(hgp.pfa_mapwd))")
                            printLine("PFA_FIRST:  .\(hexOut(hgp.pfa_first))")
                        }
                        
                    }
                    else {
                        printLine("NST:        .\(hexOut(hgp.nst))")
                        printLine("LBP:        .\(hexOut(hgp.nsg))")
                        printLine("NVAT:       .\(hexOut(hgp.nvat))")
                    }
                    
                    if (hgp.pfa_mapwl > 0) {
                        let devAddr = c.loadUnsignedHalf(ha: (dct1 << 1) + Int(hgp.dctx))
//                        if let d = m.device(withAddress: devAddr) as? RandomAccessDevice {
//                            publicFileSystem.append(PFSDevice(device: d, position: d.savePosition(), hgp: hgp))
//                        }
                    }
                    
                    hgpp = Int(hgp.flink)
                }
                
                
                printLine("Public File Area:", skip: 1)
                setIndent(increaseBy: 2)
                //for pd in publicFileSystem {
                    //printLine("\(pd.device.name): \(pd.hgp.pfa_mapwl << 5) Granules")
                    //validateGranule(DiskAddress(dctx: pd.dctx,sector: 0))
                    //if let g0 = pd.device.readGranule(number: 0) {
                        //if (adg != nil) {
                            //if (!g0.isEqual(adg)) {
                                //printError("Account directory compare failed: \(pd.device.name)", skip: 1)
                                //dumpGranule(publicFileSystem[0].device.name, adg)
                                //dumpGranule(pd.device.name, g0)
                            //}
                        //}
                        //else {
                        //    adg = g0
                        //}
                    //}
                    //else {
                    //    printError("Could not read granule 0 of \(pd.device.name)")
                    //}
                //}
                
                printLine("")
                while (adg != nil) {
                    var flink: UInt32 = 0
                    
                    if checkIndexGranule(adg, expectedBlink: 0) {
                        var x = 0x0c
                        while (x < adg.nav) {
                            if (adg.byte(x) != 0x8) {
                                printError("Invalid key length at offset .\(hexOut(x,width:2)), should be .08")
                            }
                            x += 1
                            
                            let accountName = asciiBytes(adg.bytes(at: x, count: 8)).trimmingCharacters(in: [" "])
                            x += 8
                            let dablk = adg.diskAddress3(at: x)
                            x += 3
                            let dublk = adg.diskAddress3(at: x)
                            x += 3
                            let flags = adg.byte(x)
                            x += 1
                            
                            printHeading("\(accountName)", noNL: true)
                            printLine("           DA=[\(hexOut(dablk.dctx,width:2)), \(hexOut(dablk.sector,width:4))], DU=[\(hexOut(dublk.dctx,width:2)), \(hexOut(dublk.sector,width:4))], FL=.\(hexOut(flags))")
                            setIndent(increaseBy: 2)
                            checkFileDirectory(m, accountName, dablk, dublk)
                            setIndent(decreaseBy: 2)
                        }
                        
                        flink = adg.flink
                    }
                    
                    adg = (flink > 0) ? readGranule(da: DiskAddress(adg.flink)) : nil
                }
                
                //for pd in publicFileSystem {
                //    pd.device.restorePosition(pd.position)
                //}
                setIndent(decreaseBy: 2)
                printLine("")
            }
            else {
                printError("No symbols available")
            }
            c.control.release()
        }
        else {
            printError("No CPU available")
        }
        setIndent(0)
        endReport()
    }
    
}
 
