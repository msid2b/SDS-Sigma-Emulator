//
//  ReportViewController.swift
//  Siggy
//
import Cocoa



class PDFReport: Thread {
    var machine: VirtualMachine!
    var output: PDFOutputFile!
    var outputFile: String

    static let reportFontName = "Courier"
    let fontBody = NSFont(name: reportFontName, size: 13)!
    let fontHeading = NSFont(name: reportFontName, size: 16)!
    let fontMessage = NSFont(name: reportFontName, size: 14)!
    
    
    // Indent is expressed as a number of characters of the basic "Body" font.
    private(set) var indent = 0
    func setIndent(_ n: Int) { indent = n }
    func setIndent(increaseBy: Int) { indent += increaseBy}
    func setIndent(decreaseBy: Int) { indent -= decreaseBy}
    
    var errorCount: Int = 0
    var warningCount: Int = 0
    
    
    init (_ m: VirtualMachine!,_ outputFile: String) {
        self.machine = m
        self.outputFile = outputFile
        self.output = PDFOutputFile(outputFile)
        
        errorCount = 0
        warningCount = 0

        super.init()
        setIndent(0)

        self.output.beginOutput(producer: siggyApp.applicationName, author: "MGS", paper: .printer, orientation: PDFOutputFile.Orientation.landscape, margins: NSSize(width: 10,height: 10))
        self.output.newPage()
    }
    
    func endReport() {
        if (errorCount > 0) {
            printLine ("\(errorCount) ERRORS ENCOUNTERED", color: .red)
        }
        
        if (warningCount > 0) {
            printLine("\(warningCount) WARNINGS", color: .orange)
        }
        setIndent(0)
        
        output.finalizeOutput()
        
        let path = URL(fileURLWithPath: outputFile)
        let error:OSStatus = LSOpenCFURLRef(path as CFURL, nil)
        if (error != 0) { print("OSError: \(error), Opening: \(path)")}
    }

    @inlinable func newPage() {
        output.newPage()
    }

    @inlinable func printLine(_ s: String = "", font: NSFont? = nil, color: NSColor = .textColor, skip: Int = 0) {
        let ns = String(repeating: " ", count: indent) + s
        let f = (font == nil) ? fontBody : font!
        output.lineOut(ns, f, color, skip: skip)
    }
    
    func printHeading(_ h: String, color: NSColor = .textColor, threshold: CGFloat = 100) {
        output.lineOut(h, fontHeading, color, pageThresh: threshold)
    }
    
    func printError(_ m: String, color: NSColor = .red, skip: Int = 0) {
        printLine (m, color: color, skip: skip)
        errorCount += 1
    }
    
    func printWarning(_ m: String, color: NSColor = .orange, skip: Int = 0) {
        printLine (m, color: color, skip: skip)
        warningCount += 1
    }
    
    
    // MARK: Dump from an array of words.
    func hexDump (words: UnsafePointer<UInt32>, count: Int, apparentAddress: UInt32 = 0, addressWidth: Int = 0, abbreviate: Bool = false) {
        let aw  = UInt32((addressWidth > 0) ? addressWidth : 6)        
        var prv = ""
        var abbreviated = false
        
        let bytes = UnsafePointer(words)
        var x: Int32 = 0
        let n = Int32(count << 2)
        while (x < n) {
            let line = hexDumpLineC (bytes, x, n, apparentAddress, aw, 2)!
            x += 32
            
            if (!abbreviate) || (line.dropFirst(Int(aw)) != prv.dropFirst(Int(aw))) || (x >= n) {
                printLine (line)
                abbreviated = false
                prv = line
            }
            else if (!abbreviated) {
                printLine (String (repeating: "*", count: addressWidth))
                abbreviated = true
            }
        }
    }
    
    // MARK: Dump words from unmapped memory (or registers).
    func hexDump (from address: Int,  count: Int, apparentAddress: Int = 0, addressWidth: Int = 0, indent: Int = 0) {
        setIndent(increaseBy: indent)
        let cpu = machine.cpu!
        let m = cpu.realMemory!
        
        let w = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
        var i = 0
        while (i < count) {
            let wa = address + i
            w[i] = (wa < 0x10) ? cpu.getRegisterRawWord(UInt4(wa)) : m.loadRawWord(word: wa)
            i += 1
        }
        
        let aw = (addressWidth > 0) ? addressWidth : 6
        hexDump (words: w, count: count, apparentAddress: UInt32(apparentAddress), addressWidth: aw, abbreviate: true)
        setIndent(decreaseBy: indent)
    }
    
    
    override func main() {
        output.lineOut ("Hello World", fontBody, .blue)
        endReport()
    }
}
    


class SystemStatusReport: PDFReport {
    
    let interruptLevelName: [String] = ["POWER-ON  ", "POWER-OFF ", "CLK1 PULSE", "CLK2 PULSE", "CLK3 PULSE", "CLK4 PULSE", "MEM PARITY", "RESERVED  ",
                                        "CLK1 ZERO ", "CLK2 ZERO ", "CLK3 ZERO ", "CLK4 ZERO ", "I/O       ", "PANEL     ", "RESERVED  ", "RESERVED  ",
                                        "COC-0     ", "COC-1     ", "COC-2     ", "COC-3     ", "COC-4     ", "COC-5     ", "COC-6     ", "COC-7     ",
                                        "COC-8     ", "COC-9     ", "COC-A     ", "COC-B     ", "COC-C     ", "COC-D     ", "COC-E     ", "COC-F     "]
    
    let schedulerStateName: [String] = ["ZERO", "SRT", "SCO", "SC1", "SC2", "SC3", "SC4", "SC5", "SC6", "SC7", "SC8", "SC9", "SC10", "SCU",
                                        "STOB", "STOBO", "SIOW", "SIOMF", "SW", "SQA", "SQR", "SQRO", "STI", "STIO", "SQFI", "SNULL"]
    
    let actype: [String] = ["WRITE", "EXECUTE", "READ", "NONE"]
    
    
    func tsa(_ s: String = "",_ font: NSFont? = nil,_ color: NSColor = .textColor, pre: Int = 0) {
        printLine(s, font: font, color: color, skip: pre)
    }
    
    var redCount = 0
    func tsaRed (_ s: String, pre: Int = 0) {
        printError(s, color: .red)
        redCount += 1
    }
    
    func tsaTraceHeading() {
        let s = "TIMESTAMP              TYPE      REPEAT  ICOUNTER USR     PSD         EA CC LVL INFO  INSTRUCTION"
        printHeading(s, threshold: 0.7)
    }
    
    func tsaTrace (_ e: EventTrace.EventTraceEntry) {
        let  s = MSDate(gmtTimestamp: e.ts).ISO8601Format(timeZone: MSDate.GMT) +
        "  \(EventTrace.eventTypeName(e.type).pad(10)) " +
        String(format: "%8d", e.repeated) +
        String(format: "%12d", e.ic) +
        "  "+hexOut(e.user,width:2) +
        "  "+hexOut(e.psd, width: 16) +
        "  "+hexOut(e.ea, width: 5) +
        "  "+hexOut(UInt8(e.cc),width: 1) +
        "   "+hexOut(e.level, width:2) +
        "  "+hexOut(e.deviceInfo, width:4) +
        "   "+Instruction(e.ins).getDisplayText(blankZero: true)
        printLine(s)
        if !e.registers.isEmpty {
            setIndent(increaseBy: 4)
            hexDump(words: e.registers, count: 16)
            setIndent(decreaseBy: 4)
        }
    }
    
    func tsaInterrupt (_ id: InterruptSubsystem.InterruptData) {
        let  s = MSDate(gmtTimestamp: id.timestamp).ISO8601Format(timeZone: MSDate.GMT) +
        "  " + hexOut(id.deviceAddr, width:3) +
        "  " + hexOut(id.level,width:2) +
        "  " + hexOut(id.line, width:2) +
        "  " + hexOut(id.char, width:2)
        printLine(s)
    }
    
    
    
    func trapStatus(_ cpu: CPU!, _ address: Int) -> String {
        var r = hexOut(address, width:2)
        let ii = Instruction(cpu.realMemory.loadUnsignedWord(word: address))
        var iText = ii.getDisplayText()
        while (iText.count < 22) { iText += " " }
        r += "   " + iText
        
        if (ii.opCode == 0x0F) {
            let psdba = ii.reference << 2
            r += "[" + hexOut(cpu.realMemory.loadUnsignedDoubleWord(psdba),width:16) + " " + hexOut(cpu.realMemory.loadUnsignedDoubleWord(psdba+8),width:16) + "]"
        }
        
        let c = cpu.trapCount[address & 0xF]
        if (c > 0) {
            r += "  Count: \(c)"
        }
        return r
    }
    
    func interruptStatus(_ cpu: CPU!, _ level: Int) -> String {
        var r = "?"
        if let iss = cpu.interrupts {
            let address = level + 0x50
            r = hexOut(address, width:2) + "   " + interruptLevelName[level] + "   " + (iss.enabled(level) ? "ENABLED " : "DISABLED") + "   "
            r += iss.state[level].name().padding(toLength: 8, withPad: " ", startingAt: 0)
            
            let ii = Instruction(cpu.realMemory.loadUnsignedWord(word: address))
            var iText = ii.getDisplayText()
            while (iText.count < 22) { iText += " " }
            r += "   " + iText
            
            if (ii.opCode == 0x0F) {
                let psdba = ii.reference << 2
                r += "[" + hexOut(cpu.realMemory.loadUnsignedDoubleWord(psdba),width:16) + " " + hexOut(cpu.realMemory.loadUnsignedDoubleWord(psdba+8),width:16) + "]"
            }
            
            let c = cpu.interrupts.count[level]
            if (c > 0) {
                r += "  Count: \(c)"
            }
        }
        return r
    }
    
    func dumpInterruptQ (_ q: Queue) {
        if (q.isEmpty) { return }
        tsa ("Interrupt Queue "+q.name)
        var i = q.firstObject()
        while (i != nil) {
            if let id = i as? InterruptSubsystem.InterruptData {
                tsa("Level: X'\(hexOut(id.level,width: 2))', Device: \(hexOut(id.deviceAddr,width:3)), Time: \(id.timestamp)")
            }
            i = q.nextObject()
        }
    }
    

    var maxUserNumber: Int = 0
    func schedulerQueue(_ q: Int) -> String {
        var t: String = ""
        if let sb_hq = machine.monitorReferences?.sb_hq,
           let ub_fl = machine.monitorReferences?.ub_fl {
            var j = Int(machine.realMemory.loadByte((sb_hq << 2)+q))
            var x = Array(repeating: false, count: 256)
            while (j > 0) && (j < 0xFF) {
                if (j > maxUserNumber) {
                    maxUserNumber = j
                }
                if (x[j]) {
                    return t+"...*CIRCULAR LIST*"
                }
                x[j] = true
                if (t.count > 0) { t += ", " }
                t += hexOut(j, width: 2)
                j = Int(machine.realMemory.loadByte((ub_fl << 2)+j))
            }
        }
        return t
    }
    
    

    override func main() {
        let cpu = machine.cpu!
        let iss = cpu.interrupts!
        
        printHeading("STATUS REPORT GENERATED: \(MSDate().displayString)  FOR: \(machine.name)")
        tsa("")
        printHeading("CPU")
        tsa("PSD: "+hexOut(cpu.psd.value))
        tsa("INSTRUCTIONS EXECUTED:"+String(cpu.instructionCount))
        tsa("INTERRUPTS:"+String(cpu.interruptCount))
        tsa("REGISTERS:")
        hexDump(from: 0, count: 0x10)
        tsa("")
        tsa("MEMORY:")
        tsa("  Total Pages: \(machine.realMemory.pageCount)")
        
        tsa("")
        tsa("MAP: " + ((cpu.psd.zMapped) ? "ENABLED" : "DISABLED"))
        var ll = ""
        for p in 0 ... cpu.virtualMemory.pageCount-1 {
            let rp = Int(cpu.virtualMemory.map(virtualPage: p))
            let ac = Int(cpu.virtualMemory.access(virtualPage: p) & 0x3)
            var ln = hexOut(p, width: 2) + " [" + hexOut(p << 9, width: 5) + "]  --> "
            ln += hexOut(rp, width: 4) + " [" + hexOut(rp << 9, width: 6) + "] "
            ln += actype[ac]
            
            if ((p & 0x3) == 3) {
                tsa(ll+ln)
                ll = ""
            }
            else {
                ll += ln.pad(40)
            }
        }
        tsa("")
        
        printHeading("BRANCH TRACE", threshold: 0.8)
        tsaTraceHeading()
        var i = 0
        var e = cpu.branchTrace?.entry(i)
        while (e != nil ) {
            tsaTrace(e!)
            i += 1
            e = cpu.branchTrace?.entry(i)
        }
        tsa("")
        
        printHeading("TRAP TRACE", threshold: 0.8)
        tsaTraceHeading()
        i = 0
        e = cpu.trapTrace?.entry(i)
        while (e != nil ) {
            tsaTrace(e!)
            i += 1
            e = cpu.trapTrace?.entry(i)
        }
        tsa("")
        
        printHeading("TRAPS", threshold: 0.8)
        for trapAddress in 0x40 ... 0x4E {
            tsa(trapStatus(cpu, trapAddress))
        }
        tsa("")
        
        printHeading("INTERRUPT SUBSYSTEM", threshold: 0.8)
        tsa("Total Interrupts: \(cpu.interruptCount)")
        tsa("")
        for level in 0...31 {
            tsa(interruptStatus(cpu, level))
        }
        tsa("")
        
        if (iss.waiting.isEmpty) {
            tsa("NO WAITING INTERRUPTS")
        }
        else {
            tsa("WAITING INTERRUPTS")
            var id = iss.waiting.firstObject() as? InterruptSubsystem.InterruptData
            while (id != nil) {
                tsaInterrupt(id!)
                id = iss.waiting.nextObject() as? InterruptSubsystem.InterruptData
            }
        }
        tsa("")
        
        printHeading("IO and INTERRUPT TRACE", threshold: 0.8)
        tsaTraceHeading()
        var iox = 0
        var inx = 0
        var merged = false
        while (!merged) {
            if let ioe = cpu.ioTrace?.entry(iox) {
                if let ine = iss.interruptTrace?.entry(inx) {
                    if (ioe.ts > ine.ts) {
                        tsaTrace(ioe)
                        iox += 1
                    }
                    else {
                        tsaTrace(ine)
                        inx += 1
                    }
                }
                else {
                    // No more interrupt entries, dump rest of ios
                    while (!merged ) {
                        if let ioe = cpu.ioTrace?.entry(iox) {
                            tsaTrace(ioe)
                            iox += 1
                        }
                        else {
                            merged = true
                        }
                    }
                }
            }
            else {
                // No more io entries, dump rest of interrupts
                while (!merged) {
                    if let ine  = iss.interruptTrace?.entry(inx) {
                        tsaTrace(ine)
                        inx += 1
                    }
                    else {
                        merged = true
                    }
                }
            }
        }
        
        
        tsa("")
        printHeading("DEVICES")
        for i in machine.iopTable {
            if let iop = i {
                for d in iop.deviceList {
                    tsa(d.getStatusDetail())
                    let (m, p, f, t) = d.mediaStatus()
                    if (m) {
                        tsa("       POSITION: \(p), FILE: \(f), "+t)
                    }
                    let q = d.ioQueue
                    tsa ("      Suspended: "+(q.isSuspended ? "YES" : "no"))
                    tsa ("      Operations: \(q.operationCount)")
                    for op in q.operations {
                        if let sop = op as? SIOOperation {
                            tsa ("      "+hexOut(sop.rq.unitAddr, width:3)+", ORDER: "+hexOut(cpu.realMemory.loadByte(Int(sop.rq.command) << 3), width:2))
                            tsa ("      PSD: \(hexOut(sop.psd, width: 16))")
                            tsa ("      CMD ADDR: \(hexOut(sop.rq.command))")
                            tsa ("      Completed: "+(sop.sioComplete ? "YES" : "no"))
                        }
                    }
                    if let coc = d as? COCDevice {
                        for x in 0...(coc.lineData.count-1) {
                            if let ld = coc.lineData[x] {
                                if (ld.inputCount > 0) || (ld.outputCount > 0) {
                                    tsa ("      Line \(hexOut(x,width: 2)): \(ld.inputCount) in, \(ld.outputCount) out")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        
        tsa("")
        let schedulerQueueNames = ["SQ0","RTC","SC0","SC1","SC2","SC3","SC4","SC5",
                                   "SC6","SC7","SC8","SC9","SC10","SCU","STOB","STOBO",
                                   "SIOW","SIOMF","SW","SQA","SQR","SQRO","STI","STIO",
                                   "SQFI","S25","S26","S27","S28","S29","SNULL"]
        printHeading("SCHEDULER STATE QUEUES")
        for i in 1...30 {
            var text = schedulerQueue(i)
            if (text.count > 0) {
                var label = schedulerQueueNames[i].pad(8)
                while (text.count > 100) {
                    tsa(label + text.prefix(100))
                    text = String(text.dropFirst(100))
                    label = "        "
                }
                tsa(label + text)
            }
        }
        
        // Running the queues has determined the biggest user number
        if let ux_jit = machine.monitorReferences?.ux_jit,
           let uh_flg = machine.monitorReferences?.uh_flg {
            tsa("")
            printHeading("MONITOR JIT")
            hexDump(from: 0x8c00, count: 0x100)
            tsa("")
            printHeading("JITS IN MEMORY")
            if (maxUserNumber > 0) {
                for i in 1...maxUserNumber {
                    let f = Int(machine.realMemory.loadHalf((uh_flg << 2) + (i << 1)))
                    if f.bitTest(mask: 0x0200) {
                        //MARK: JIT IS IN
                        let p = Int(machine.realMemory.loadHalf((ux_jit << 2) + (i << 1)))
                        if (p > 0) {
                            tsa("User \(hexOut(i, width:2)), Page \(hexOut(p, width: 3))")
                            let wa = p << 9
                            hexDump(from: wa, count: 0x100, apparentAddress: 0x8c00)
                            tsa("")
                        }
                    }
                }
            }
        }
        tsa("")
        

        endReport()
    }
}

class InstructionTimingReport: PDFReport {
    
    override func main() {

        struct PageExecuteReference: Comparable {
            static func < (lhs: PageExecuteReference, rhs: PageExecuteReference) -> Bool {
                return (lhs.count > rhs.count)
            }
            
            var page: Int = 0
            var count: UInt = 0
        }
        
        
        
        let cpu = machine.cpu!
        
        printHeading("INSTRUCTION REPORT GENERATED: \(MSDate().displayString)  FOR: \(machine.name)")
        printLine("Instruction Count: \(cpu.instructionCount)", skip: 1)
        
        var totCount = 0
        var totTime: Int64 = 0
        var typeCount: [Int] = Array(repeating: 0, count: 6)
        var typeTime: [Int64] = Array(repeating: 0, count: 6)
        
        let opCount = cpu.opCount
        let opTime = cpu.opTime
        let opBiggest = Queue(name:"")
        
        for i in 0...63 {
            var line = ""
            for j in 0...1 {
                let ix = i*2+j
                let oc = opCount[ix]
                let ot = opTime[ix]
                var s = ""
                if (oc > 0) {
                    s = hexOut(ix, width: 2)+" "+instructionName[ix].pad(8)+String(format:" : %8ld",oc)+String(format:" : %12ld", ot)+String(format:" = %6ld",ot/Int64(oc))

                    let tx = instructionType[ix].rawValue
                    typeCount[tx] += oc
                    typeTime[tx] += ot

                    totTime += ot
                    totCount += oc
                    
                    opBiggest.enqueue(object: ix, priority: -ot)
                }
                line += s.pad(60)
            }
            
            let tl = line.trimmingCharacters(in: [" "])
            if (tl.count > 0) {
                printLine(line)
            }
        }
        
        let ans = (totCount > 0) ? totTime / Int64(totCount) : 0
        printLine("TOTALS: "+String(totCount)+", "+String(totTime))
        printLine("AVERAGE INSTRUCTION: "+String(format:"%d",ans)+" ns.")
        
        
        printLine("BY INSTRUCTION TYPE:", skip: 5)
        for x in 0 ... 5 {
            let oc = typeCount[x]
            let ot = typeTime[x]
            var line = InstructionType(rawValue: x)!.name().pad(11) + String(format:": %8ld",oc)+String(format:" : %12ld", ot)
            if (oc > 0) { line += String(format:" = %6ld",ot/Int64(oc)) }
            printLine(line)
        }
        
        
        printLine("BY TOTAL TIME:", skip: 5)
        var rtPCT: Double = 0
        while (!opBiggest.isEmpty) {
            if let v = opBiggest.dequeue() as? Int {
                let opPCT = Double(opTime[v]*100)/Double(totTime)
                rtPCT += opPCT
                printLine(hexOut(v, width: 2)+" "+instructionName[v].pad(8)+String(format:" : %6.2f%%", opPCT)+String(format: "    %6.2f%", rtPCT))
            }
        }

        var pageExecutes: [PageExecuteReference] = []
        
        if let m = machine.realMemory {
            newPage()
            printHeading("PHYSICAL MEMORY")
            
            printLine("       Page  Address           ")
            
            var s1 = "READS    000  000000"
            var s2 = "WRITES              "
            var s3 = "EXECUTES            "
            var nonZero = false
            for i in 0 ... m.realPages.count-1 {
                if let _ = m.realPages[i] {
                    s1 += String(format: "%14d", m.pageReads[i])
                    s2 += String(format: "%14d", m.pageWrites[i])
                    
                    var x = UInt(0)
                    let a = i * 0x200
                    var k = a + 0x1FF
                    while (k >= a) {
                        x += m.executionCount[k]
                        k -= 1
                    }
                    pageExecutes.append(PageExecuteReference(page: i,count: x))
                    s3 += String(format: "%14d", x)
                    
                    if (x > 0) || (m.pageReads[i] > 0) || (m.pageWrites[i] > 0) {
                        nonZero = true
                    }
                    
                    if ((i & 0x7) == 0x7) {
                        if (nonZero) {
                            printLine(s1)
                            printLine(s2)
                            printLine(s3)
                            printLine()
                        }
                        let np = hexOut(i+1,width:3)
                        let pa = hexOut((i+1) << 9,width:6)
                        s1 = "READS    "+np+"  "+pa
                        s2 = "WRITES              "
                        s3 = "EXECUTES            "
                        nonZero = false
                    }
                }
            }
            
            newPage()
            printLine ("Busiest Pages by Execution")
            pageExecutes.sort()
            var i = 0
            while (i < 16) {
                let p = pageExecutes[i].page
                printLine ("Page \(hexOut(p)):")
                printLine ("Reads: \(m.pageReads[p]), Writes: \(m.pageWrites[p])")
                printLine ("Execution Counts:")
                var a = p << 9
                var w = 0
                var s = hexOut(a,width:6)+":"
                while (w < 0x200) {
                    s += String(format: " %8d", m.executionCount[a])
                    w += 1
                    a += 1
                    if ((w & 0xF) == 0) {
                        printLine(s)
                        s = hexOut(a,width:6)+":"
                    }
                }
                i += 1
                newPage()
            }
        }

        endReport()
    }
}
