//
//  CPV.swift
//  Siggy
//
//  Created by ms on 2024-10-19.
//
//MARK: This file contains CP-V specific definitions and routines.

//MARK: CAL tables for intruction display and logging.

let cal11Table: [String] = [
    "?",        "REW",      "WEOF",     "CVOL",     "DEV(PAGE)","DEV(VFC)", "SETDCB",   "?",
    "?",        "?",        "?",        "DEV(DRC)", "?",        "DELREC",   "MOVE",     "TFILE",
    "READ",     "WRITE",    "TRUNC",    "ADJDCB",   "OPEN",     "CLOSE",    "?",        "?",
    "?",        "?",        "?",        "?",        "PFIL",     "PRECORD",  "?",        "?",
    "DEV(LNS)", "DEV(FORM)","DEV(SIZE)","DEV(DATA)","DEV(CNT)", "DEV(SPC)", "DEV(HEAD)","DEV(SEQ)",
    "DEV(TAB)", "CHECK",    "DEV(NLNS)","DEV(COR)", "PC",       "RAMR",     "WAMR",     "JOB"
]
let cal12Table: [String] = [
    "MESSAGE",  "PRINT",    "TYPE",     "?",        "KEYIN",    "?",        "?",        "?",
    "ENQ",      "DEQ",      "MERC"
]
let cal13Table: [String] = [
    "SNAP",     "SNAPC",    "IF",       "AND",      "OR",       "COUNT"
]
let cal14Table: [String] = [
    "?",        "?",        "SAVEGET2", "SAVEGET3", "ASSOC",    "DISASSOC", "CLRERR"
]
let cal15Table: [String] = [
    "?",        "?",        "?",        "?",        "?",        "?",        "?",        "SLAVE",
    "MASTER",   "?",        "?",        "?",        "?",        "?",        "?",        "?",
    "?",        "?",        "?",        "?",        "?",        "?",        "?",        "?",
    "?",        "?",        "?",        "?",        "STOPIO",   "STARTIO",  "IOEX-SIO", "IOEX-OTH",
    "GJOBCON",  "CONNECT",  "DISCONNECT", "INTCON", "QFI",      "HOLD",     "CLOCK",    "INTSTAT",
    "EXU"
]
let cal16Table: [String] = [
    "RDERLOG",  "WRERLOG",  "MAP",      "SIO",      "LOCK",     "DOPEN",    "INITJOB",  "DCLOSE",
    "SYS?",     "BLIST",    "MODPRTRT"
]
let cal17Table: [String] = [
    "GETLINE",  "RLSLINE",  "BUFSTAT",  "PURGE",    "MDFLST",   "ECBCHECK", "Q-UNLOCK", "Q-DEFINE",
    "Q-PUT",    "Q-GET",    "Q-STATS",  "Q-PURGE",  "Q-LOCK",   "GETID"
]
let cal18Table: [String] = [
    "?",        "SEGLD",    "LINK",     "LDTRC",    "GVP",      "FVP",      "CT",       "CVM",
    "GP",       "FP",       "SMPRT",    "GDDL?0E",  "GCP",      "FCP",      "INT",      "WAIT",
    "TIME",     "STIMER",   "TTIMER",   "DISPLAY",  "TRAP",     "RES(15)",  "RES(16)",  "RES(17)",
    "RES(18)",  "XCON",     "LDEV",     "GDDL"
]
let cal19Table: [String] = [
    "?",        "?",        "ERR",      "XXX",      "STRAP",    "TRTN",     "CALMUL2",  "CLEAT",
    "TERM",     "EXEC",     "INTRTN",   "STRUNC"
]
let calNameTable: [[String]?] = [
    nil, cal11Table, cal12Table, cal13Table, cal14Table, cal15Table, cal16Table, cal17Table, cal18Table, cal19Table
]



func cal1Decode(i: Instruction, ea: Int, cpu: CPU!) -> String {
    var detail = ""
    
    let i = Int(i.register)
    if (i > 0), (i < 10), let t = calNameTable[i] {
        if (i < 9) {                        // Takes FPT
            if (cpu != nil) && (ea >= 0) && (ea < 0x1FFFF) {
                let fpt0 = cpu.loadUnsignedWord(wa: ea)
                let fun = Int(fpt0 >> 24) & 0x7F
                if (fun > 0) && (fun < t.count) {
                    detail = "M:" + t[fun]
                    
                    //if (i == 1) {
                    //TODO: GO GET DCB INFORMATION
                    //    var dcbAddress = fpt0 & 0x1FFFF
                    //    if ((fpt0 & u32b0) != 0) {
                    //        dcbAddress = cpu.loadUnsignedWord(wa: Int(dcbAddress))
                    //    }
                    //}
                }
                detail += " Value: ." + hexOut(fpt0, width: 5)
            }
        }
        else {
            if (ea > 0) && (ea < t.count) {
                detail = "M:" + t[ea]
            }
        }
    }
    return detail
}




struct MonitorReferences {
    // This structure contains CP-V information and symbol definitions for debugging and displays.
    // It is determined once, at the time that the first mapped instrcution is executed
    var version: UInt16 = 0                 // CP-V Version
    
    // Current user & processor name table: determined dynamically the first time the map is enabled.
    var currentUserAddress: Int = 0
    var pnameAddress: Int = 0
    var umovAddress: Int = 0
    
    var maxovly: Int = 0
    var ovlyName: [String] = []
    
    var t_se: Int = 0                       // Address of scheduler start
    var sb_hq: Int = 0                      // Head of scheduler state queues
    var ub_fl: Int = 0                      // Flink for scheduler queues
    var uh_flg: Int = 0                     // User State flags
    var ux_jit: Int = 0                     // Page table for JITs in memory.

    init (_ realMemory: RealMemory!) {
        //MARK: 1. Find the IDLE WAIT Instruction.
        //MARK: 2. Find the LAW,0 J:JIT instruction at SSE1
        //MARK: 3. 3 instructions later is a LW,4 S:CUN
        var wait = 0
        var a = 0x7FFF
        while (a > 0) {
            let w = realMemory.loadRawWord(word: a)
            if (w == 0x0000002E) {
                wait = a
            }
            
            //MARK: Check for LAW,0 J:JIT
            else if (w == 0x008C003B) {
                let lw = realMemory.loadUnsignedWord(word: a+3)
                if ((lw >> 16) == 0x3240) {
                    currentUserAddress = Int(lw & 0x7FFF)
                    
                    //Wait should have been found already...
                    if (wait > 0) {
                        t_se = Int(realMemory.loadUnsignedWord(word: wait+1) & 0x7FFF)      // Next instruction is a branch to T;SE
                        let ld = realMemory.loadUnsignedWord(word: t_se+6)                  // SHOULD be LD,2 SB:HQ
                        if (ld >> 16) == 0x1220 {
                            sb_hq = Int(ld & 0x7FFF)
                            let flg = realMemory.loadUnsignedWord(word: t_se+17)             // SHOULD be CH,15 UH:FLG,4
                            if (flg >> 16 == 0x51F8) {
                                uh_flg = Int(flg & 0x7FFF)
                            }
                            let fl = realMemory.loadUnsignedWord(word: t_se+19)             // SHOULD be LB,4 UB:FL,4
                            if (fl >> 16 == 0x7248) {
                                ub_fl = Int(fl & 0x7FFF)
                            }
                        }
                        let lu = realMemory.loadUnsignedWord(word: wait+6)                  // Should be lh,11 UX:JIT,4
                        if (lu >> 16) == 0x52B8 {
                            ux_jit = Int(lu & 0x7FFF)
                        }
                    }
                }
            }
            
            //MARK: Looking for TEXTC 'UMOV" TO IDENTIFY THE P:NAME TABLE.
            else if (w == 0x404040E5) {
                if (realMemory.loadRawWord(word: a-1) == 0xD6D4E404) {
                    let pna = a - 3
                    
                    //MARK: USING PNAME, WE FIND THE CD,2 PNAME,4 INSTRUCTION AT OV1 in T:OV.
                    //MARK: THE PREVIOUS INSTRUCTION IS A LI,4 MAXOVLY
                    //MARK: THE NEXT INSTRUCTION BRANCHES TO T:OV2, WHICH CONTAINS LI,15 UB:OV
                    let cdi = UInt32(0x11280000 | pna)
                    var cda = 0x7FFF
                    while (cda > 0x1000) && (umovAddress <= 0) {
                        if (cdi == realMemory.loadUnsignedWord(word: cda)) {
                            let li = realMemory.loadUnsignedWord(word: cda-1)
                            if ((li >> 20) == 0x224) {
                                pnameAddress = pna
                                maxovly = Int(li & 0x3f)
                                ovlyName = []
                                for i in 1 ... maxovly {
                                    let name = realMemory.loadUnsignedRawDoubleWord((pna+2*Int(i)) << 2)
                                    ovlyName.append(asciiBytes(name, textc: true))
                                }
                            }
                            
                            let br = realMemory.loadUnsignedWord(word: cda+1)
                            if ((br >> 20) == 0x683) {
                                let lia = Int(br & 0x7FFF)
                                let ovi = realMemory.loadUnsignedWord(word: lia)
                                if ((ovi >> 20) == 0x22f) {
                                    umovAddress = Int(ovi & 0x7FFF)
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
        // Now it is not really necessary, except possibly for the various report windows, which can do something similar
        // individually as required.
        /**
        let xd1 = realMemory.loadUnsignedWord(word: 0xEA00)
        if ((xd1 >> 24) == 0x68) {
            let xdb = xd1 & 0x1FFFF
            if (xdb > 0xEA03) && (xdb < 0xFFFF) {
                // It is here, get the end of the symbol table
                var xd2 = Int(realMemory.loadUnsignedWord(word: 0xEA02))
                if (xd2 > 0xF000) && (xd2 < 0xFFFF) {
                    var done = false
                    while !done {
                        xd2 -= 3
                        let address = realMemory.loadUnsignedWord(word: xd2)
                        var a = (xd2 + 1) << 2
                        let b = realMemory.loadByte(a)
                        if (b > 0) {
                            let c = Character(Unicode.Scalar(asciiFromEbcdic(b)))
                            var name = String(c)
                            for _ in 0...6 {
                                a += 1
                                let b = realMemory.loadByte(a)
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

