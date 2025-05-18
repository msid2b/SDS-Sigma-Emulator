//
//  DebugViewController.swift
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

//

import Cocoa

let asciiZero = "0".unicodeScalars.first!.value

class DebugViewController: NSViewController, NSWindowDelegate, NSMenuItemValidation {
    @IBOutlet weak var labelHeading: NSTextField!
    @IBOutlet weak var labelInstructionCount: NSTextField!
    @IBOutlet weak var labelInstruction: NSTextField!
    @IBOutlet weak var comboLogLevel: NSComboBox!

    @IBOutlet weak var labelInterruptCount: NSTextFieldCell!
    @IBOutlet weak var labelMode: NSTextField!
    @IBOutlet weak var labelVirtual: NSTextField!
    
    @IBOutlet weak var labelRP: NSTextField!
    @IBOutlet weak var labelWK: NSTextField!
    @IBOutlet weak var labelInhibit: NSTextField!
    @IBOutlet weak var labelCC: NSTextField!
    @IBOutlet weak var labelFloatMode: NSTextField!
        
    @IBOutlet weak var labelUser: NSTextField!
    
    @IBOutlet weak var textPSD1: NSTextField!    
    @IBOutlet weak var textPSD2: NSTextField!
    
    @IBOutlet weak var checkMap: NSButton!
    @IBOutlet weak var segmentAddress: NSSegmentedControl!
    @IBOutlet weak var tvMemory: NSTableView!
    @IBOutlet weak var cvMemory: NSClipView!
    @IBOutlet weak var svMemory: NSScrollView!
    
    @IBOutlet weak var tabViewTraces: NSTabView!
    @IBOutlet weak var tvRegisters: NSTableView!
    @IBOutlet weak var tvInstructions: NSTableView!
    @IBOutlet weak var svInstructions: NSScrollView!
    @IBOutlet weak var cvInstructions: NSClipView!
    @IBOutlet weak var tvBranchTrace: NSTableView!
    @IBOutlet weak var tvUserBranchTrace: NSTableView!
    @IBOutlet weak var tvMapTrace: NSTableView!
    @IBOutlet weak var tvTrapTrace: NSTableView!
    @IBOutlet weak var tvIOTrace: NSTableView!
    @IBOutlet weak var tvInterruptTrace: NSTableView!

    @IBOutlet weak var textStepCount: NSTextField!
    @IBOutlet weak var buttonStep: NSButton!
    @IBOutlet weak var buttonGoto: NSButton!
    @IBOutlet weak var buttonRun: NSButton!

    @IBOutlet weak var buttonBP1: NSButton!
    @IBOutlet weak var buttonBP2: NSButton!
    @IBOutlet weak var buttonBP3: NSButton!
    @IBOutlet weak var buttonBP4: NSButton!
    @IBOutlet weak var boxBP: NSBox!

    @IBOutlet weak var textSearch: NSTextField!

    @IBOutlet weak var checkStopInstruction: NSButton!
    @IBOutlet weak var textStopInstruction: NSTextField!
    @IBOutlet weak var textStopInstructionMask: NSTextField!
    @IBOutlet weak var checkStopTrap: NSButton!
    @IBOutlet weak var textStopTrap: NSTextField!

    @IBOutlet weak var checkRegister: NSButton!
    @IBOutlet weak var textRegisterNumber: NSTextField!
    @IBOutlet weak var textRegisterValue: NSTextField!
    @IBOutlet weak var textRegisterMask: NSTextField!

    var machine: VirtualMachine!
    var cpu: CPU! { get { return machine.cpu }}
    var memory: RealMemory! { get { return machine.cpu.realMemory }}
    
    var dsRegisters: DSRegisters!
    var dsMemory: DSMemory!
    var dsInstructions: DSInstructions!
    var dsBranchTrace: DSTrace!
    var dsUserBranchTrace: DSTrace!
    var dsMapTrace: DSTrace!
    var dsTrapTrace: DSTrace!
    var dsIOTrace: DSTrace!
    var dsInterruptTrace: DSTrace!
    var statusTimer: Timer!
    var updateDetailsNeeded: Bool = false
    var isVisible: Bool = false
    var searchWordAddress: Int = 0
    var searchByteAddress: Int = 0
    var bezelStandardColor: NSColor?
    var instructionBrowsers: [InstructionViewController?] = []
        
    func setMachine(_ m: VirtualMachine?) {
        machine = m
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        buttonBP1.title = "+"
        buttonBP2.title = "+"
        buttonBP3.title = "+"
        buttonBP4.title = "+"
        
        comboLogLevel.selectItem(at: MSLogManager.shared.logLevel.rawValue)
    }
    
    override func viewDidAppear() {
        isVisible = true

        if (dsMemory == nil) {
            dsMemory = DSMemory(cpu: cpu, seg: segmentAddress, map: checkMap)
        }
        if (dsRegisters == nil) {
            dsRegisters = DSRegisters(cpu: cpu)
        }
        if (dsInstructions == nil) {
            dsInstructions = DSInstructions(cpu:cpu, rows: 256)
        }
        if (dsBranchTrace == nil) {
            dsBranchTrace = DSTrace(cpu:cpu, trace: cpu.branchTrace)
        }
        if (dsUserBranchTrace == nil) {
            dsUserBranchTrace = DSTrace(cpu:cpu, trace: cpu.userBranchTrace)
        }
        if (dsMapTrace == nil) {
            dsMapTrace = DSTrace(cpu:cpu, trace: cpu.mapTrace)
        }
        if (dsTrapTrace == nil) {
            dsTrapTrace = DSTrace(cpu:cpu, trace: cpu.trapTrace)
        }
        if (dsIOTrace == nil) {
            dsIOTrace = DSTrace(cpu:cpu, trace: cpu.ioTrace)
        }
        if (dsInterruptTrace == nil) {
            dsInterruptTrace = DSTrace(cpu:cpu, trace: cpu.interrupts.interruptTrace)
        }

        tvMemory.dataSource = dsMemory
        tvRegisters.dataSource = dsRegisters
        tvInstructions.dataSource = dsInstructions
        tvBranchTrace.dataSource = dsBranchTrace
        tvUserBranchTrace.dataSource = dsUserBranchTrace
        tvMapTrace.dataSource = dsMapTrace
        tvTrapTrace.dataSource = dsTrapTrace
        tvIOTrace.dataSource = dsIOTrace
        tvInterruptTrace.dataSource = dsInterruptTrace

        checkRegister.state = .off
        cpu.setRegisterBreak(false, r: 0, value: 0, mask: 0)
        
        updateDetailsNeeded = true
        displayStatus(cpu.getStatus())
        
        statusTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(statusTimerPop), userInfo: nil, repeats: true)
        bezelStandardColor = buttonBP1.bezelColor
        
        view.window?.makeFirstResponder(self)
    }
    
    override func viewDidDisappear() {
        isVisible = false
        
        tvMemory.dataSource = nil; dsMemory = nil
        tvRegisters.dataSource = nil; dsRegisters = nil
        tvInstructions.dataSource = nil; dsInstructions = nil
        tvBranchTrace.dataSource = nil; dsBranchTrace = nil
        tvUserBranchTrace.dataSource = nil; dsUserBranchTrace = nil
        tvMapTrace.dataSource = nil; dsMapTrace = nil
        tvTrapTrace.dataSource = nil; dsTrapTrace = nil
        tvIOTrace.dataSource = nil; dsIOTrace = nil
        tvInterruptTrace.dataSource = nil; dsInterruptTrace = nil

        statusTimer.invalidate()
    }
    
    func displayDetails(_ mapped: Bool) {
        guard (isVisible) && (cpu != nil) else { return }

        checkMap.state = mapped ? .on : .off

        tvMemory.reloadData()
        tvRegisters.reloadData()
        tvBranchTrace.reloadData()
        tvUserBranchTrace.reloadData()
        tvMapTrace.reloadData()
        tvTrapTrace.reloadData()
        tvIOTrace.reloadData()
        tvInterruptTrace.reloadData()
        
        tvInstructions.selectRowIndexes([dsInstructions.rows >> 1], byExtendingSelection: false)
        cvInstructions.scroll(to: NSPoint(x: 0, y: tvInstructions.rowHeight * CGFloat((dsInstructions.rows >> 1)-4)))
        svInstructions.reflectScrolledClipView(cvInstructions)
        tvInstructions.reloadData()

    }
    
    func booleanLabel(_ lbl: NSTextField!,_ value: Bool,_ tDisplay: String,_ tColor: NSColor,_ fDisplay: String,_ fColor: NSColor) {
        lbl.stringValue = value ? tDisplay : fDisplay
        lbl.textColor = value ? tColor : fColor
    }
    
    
    //MARK: Display
    func displayStatus (_ status: CPU.CPUStatus) {
        let p = status.psd!
        
        textPSD1.stringValue = hexOut(p.value >> 32, width: 8)
        textPSD2.stringValue = hexOut(p.value & 0xFFFFFFFF, width: 8)
        
        booleanLabel(labelMode, p.zMaster, "PRIV", NSColor.systemTeal, "USER", NSColor.magenta)
        if p.zMapped {
            booleanLabel(labelVirtual, p.zMA, "PROTECTED", NSColor.magenta, "MAPPED", NSColor.systemTeal)
        }
        else {
            booleanLabel(labelVirtual, p.zMA, "EXTENDED", NSColor.magenta, "UNMAPPED", NSColor.systemTeal)
        }
        
        labelWK.stringValue = "WK:"+String(format:"%X",UInt8(p.zWriteKey))
        labelWK.textColor = (p.zWriteKey == 0) ? NSColor.red : NSColor.textColor
        
        labelCC.stringValue = "CC:"+String(format:"%X",UInt8(p.zCC))
        labelInhibit.stringValue = "INH:"+(p.zInhibitCI ? "C" : " ")+(p.zInhibitIO ? "I" : " ")+(p.zInhibitEI ? "E" : " ")
        labelFloatMode.stringValue = "FL:"+(p.zFloat.significance ? "S" : " ")+(p.zFloat.zero ? "Z" : " ")+(p.zFloat.normalize ? "N" : " ")
        
        labelRP.stringValue = "REGISTER BLOCK:"+String(format:"%X",p.zRegisterPointer >> 4)
        labelRP.textColor = (p.zRegisterPointer != 0) ? NSColor.red : NSColor.textColor

        labelInterruptCount.stringValue = "INTERRUPTS: "+String(status.interruptCount)
        labelInstructionCount.integerValue = status.instructionCount

        if (status.fault) {
            labelHeading.stringValue = "CPU FAULT:"+status.faultMessage
            buttonRun.title = "RESET"
        }
        else if (cpu.isWaiting) {
            labelHeading.stringValue = "WAIT"
            buttonRun.title = "STOP"
            
            //MARK: SNEAK THIS IN WHILE WAITING.  TODO: IMPROVE THE EFFICIENCY OF displayDetails.
            displayDetails(p.zMapped)
        }
        else if (cpu.isRunning) {
            labelHeading.stringValue = "RUN"
            buttonRun.title = "STOP"
            textPSD1.isEnabled = false
            textPSD2.isEnabled = false
        }
        else {
            let bpButtons = [buttonBP1, buttonBP2, buttonBP3, buttonBP4, buttonGoto]
            func emphasizeBP(_ n: Int) {
                if (n >= 0) && (n < bpButtons.count),
                   let b = bpButtons[n] {
                    b.bezelColor = .red
                    view.needsDisplay = true
                }
            }

            for b in bpButtons {
                b!.bezelColor = bezelStandardColor
            }
            
            
            switch (status.breakMode) {
            case .access:
                labelHeading.stringValue = "DATA BREAKPOINT"
                emphasizeBP(status.breakIndex)
                break
            case .execution:
                if (status.breakIndex == (cpu.breakpointMax-1)) {     // Zero based
                    labelHeading.stringValue = "GOTO BREAKPOINT"
                    cpu.clearBreakpoint(n: cpu.breakpointMax)         // 1-based
                }
                else {
                    labelHeading.stringValue = "EXECUTION BREAKPOINT"
                }
                emphasizeBP(status.breakIndex)
                break
            case .operation:
                labelHeading.stringValue = "OPERATION STOP"
                break
            case .register:
                labelHeading.stringValue = "REGISTER STOP"
                break
            case .trap:
                labelHeading.stringValue = "TRAP"+hexOut(status.trapLocation)
                break
            case .screech:
                let screechcode = status.screechData
                labelHeading.stringValue = "SCREECH"+hexOut(screechcode,width:8)
                break
            default:
                labelHeading.stringValue = "STEP"
                break
            }
            buttonRun.title = "RUN"

            textPSD1.isEnabled = true
            textPSD2.isEnabled = true

            if (updateDetailsNeeded) {
                displayDetails(p.zMapped)
                instructionBrowserSync()
                updateDetailsNeeded = false
            }
            else {
                
            }
        }
        labelInstruction.stringValue = "IA="+hexOut(Int(status.psd.zInstructionAddress),width: 5)
        labelInterruptCount.stringValue = "INTERRUPTS: "+String(status.interruptCount)
        
        labelUser.stringValue = "CUN: \(hexOut(status.cun,width:2)), OV: \(asciiBytes(status.name, textc: true))"

    }
    
    
    @objc func statusTimerPop() {
        guard (cpu != nil) else {
            buttonRun.title = "RESET"
            return
        }
        displayStatus(cpu.getStatus())
    }
    
    @objc func stepComplete() {
        updateDetailsNeeded = true
    }
    
    
    //MARK: *** FIRST RESPONDER ***
    override var acceptsFirstResponder: Bool { get { return true }}
    override func becomeFirstResponder() -> Bool {
        MSLog (level: .debug, "\(self.className): Becoming First Responder")
        return true
    }
    override func resignFirstResponder() -> Bool {
        MSLog (level: .debug, "\(self.className): Resigning First Responder")
        return true
    }
    
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch (menuItem.action) {
        case #selector(buttonRunClick):
            menuItem.title = cpu.isPaused ? "Run" : "Pause"
            return true
            
        default:
            break;
        }
        return cpu.isPaused
    }
    
    
    //MARK: handlers.
    @IBAction func textPSD1Changed(_ sender: Any) {
        if let v = hexIn64(textPSD1.stringValue), (v <= UInt32.max) {
            cpu.psd.setHighWord(UInt32(v))
        }
        displayStatus(cpu.getStatus())
    }


    @IBAction func textPSD2Changed(_ sender: Any) {
        if let v = hexIn64(textPSD2.stringValue), (v <= UInt32.max) {
            cpu.psd.setLowWord(UInt32(v))
        }
        displayStatus(cpu.getStatus())
    }
    
    
    @IBAction func comboLogLevelChange(_ sender: Any) {
        let v = comboLogLevel.indexOfSelectedItem
        if let ll = MSLogManager.LogLevel(rawValue: v) {
            MSLogManager.shared.setLogLevel(level: ll)
            ApplicationDB.shared.setGlobalSetting("LogLevel", String(ll.rawValue))
            MSLog(level: .info, "Logging Level: "+ll.myName())
        }
    }

    @IBAction func buttonMarkClick(_ sender: Any) {
        machine.logMarker()
    }
    
    @IBAction func buttonFloatClick(_ sender: Any) {
        floatTest(CPU.PSD.FloatMode(rawValue: 0x7))
        decimalTest()
    }
    
    @IBAction func textStopInstructionChange(_ sender: Any) {
        if sender is NSTextField, let instruction = Instruction(textStopInstruction.stringValue) {
            let assumedMask = ((instruction.value & 0xFFFFFF) != 0) ? 0xFFFFFFFF : 0xFF000000
            let mask = hexIn(hex: textStopInstructionMask.stringValue, defaultValue: assumedMask)
            if ((instruction.value > 0) && (mask != 0)) {
                checkStopInstruction.state = .on
                checkStopInstruction.title = instruction.getDisplayText(pad: false)
                textStopInstruction.stringValue = hexOut(instruction.value, width: 8)
                textStopInstructionMask.stringValue = hexOut(mask)
                textStopInstruction.textColor = NSColor.textColor
                textStopInstructionMask.textColor = NSColor.textColor
                setCPUStops()
                return
            }
        }
        checkStopInstruction.state = .off
        checkStopInstruction.title = "Instruction"
        textStopInstruction.textColor = NSColor.red
        textStopInstructionMask.textColor = NSColor.red
        setCPUStops()
    }
    
    @IBAction func checkStopInstructionChange(_ sender: Any) {
        if (checkStopInstruction.state == .off) {
            checkStopInstruction.title = "Instruction"
        }
        textStopInstruction.stringValue = ""
        textStopInstructionMask.stringValue = ""
        setCPUStops()
    }
    
    @IBAction func textStopTrapChange(_ sender: Any) {
        if let tf = sender as? NSTextField {
            let ta = hexIn(hex: tf.stringValue, defaultValue: 0)
            checkStopTrap.state = (ta > 0) ? .on : .off
            setCPUStops()
        }
    }
    
    @IBAction func checkStopTrapChnage(_ sender: Any) {
        textStopTrap.stringValue = ""
    }
    
    @IBAction func checkScreechChange(_ sender: Any) {
        setCPUStops()
    }
    
    @IBAction func textStepCountChange(_ sender: Any) {
    }
    

    func setCPUStops() {
        if (checkStopInstruction.state == .on), let instruction = Instruction(textStopInstruction.stringValue)?.value {
            cpu.setInstructionStop(instruction, UInt32(hexIn(hex: textStopInstructionMask.stringValue, defaultValue: 0) & 0xFFFFFFFF))
        }
        else {
            cpu.setInstructionStop(0, 0)
        }
        cpu.stopOnTrap = (checkStopTrap.state == .on) ? UInt8(hexIn(hex: textStopTrap.stringValue, defaultValue: 0xFF)) : 0
    }

    @IBAction func buttonStepClick(_ sender: Any) {
        if (cpu != nil) {
            cpu.clearBreakpoint(n: 5)
            if (textStepCount.integerValue > 1) {
                cpu.setRun(stepMode: .count, textStepCount.integerValue)
            }
            else {
                cpu.setRun(stepMode: .simple)
                if (cpu.isWaiting) { cpu.clearWait() }
                updateDetailsNeeded = true
            }
        }
    }

    @IBAction func buttonStepBranchedClick(_ sender: Any) {
        if (cpu != nil) {
            setCPUStops()
            cpu.clearBreakpoint(n: 5)
            cpu.setRun(stepMode: .branched)
        }
    }
    
    @IBAction func buttonStepBranchFailedClick(_ sender: Any) {
        if (cpu != nil) {
            setCPUStops()
            cpu.clearBreakpoint(n: 5)
            cpu.setRun(stepMode: .branchFailed)
        }
    }
    
    @IBAction func buttonRunClick(_ sender: Any) {
        if (cpu != nil) {
            setCPUStops()
            if (cpu.isRunning) {
                cpu.clearBreakpoint(n: 5)
                cpu.clearRun()
                if (cpu.isWaiting) {
                    cpu.clearWait()
                }
                updateDetailsNeeded = true
                displayStatus(cpu.getStatus())
            }
            else {
                cpu.setRun(stepMode: .none)
            }
        }
        else {
            buttonRun.title = "RUN"
            machine.powerOn(self)
        }
    }
    
    @IBAction func buttonGotoClick(_ sender: Any) {
        if (!cpu.isRunning) {
            var r = tvInstructions.selectedRow
            if (r < 0) { r = 1 }
            
            let a = Int(cpu.psd.zInstructionAddress) - (dsInstructions.rows >> 1) + r
            cpu.setBreakpoint(CPU.Breakpoint(address: UInt32(a), mapped: cpu.psd.zMapped, unmapped: !cpu.psd.zMapped, execute: true, read: false, write: false, transition: false, user: 0), n: 5)
            cpu.setRun(stepMode: .none)
        }
    }
    
    @IBAction func buttonSetClick(_ sender: Any) {
        if let c = cpu,
           let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "DebugSetWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? DebugSetViewController {
            if (.OK == vc.runModal (c)) {
            }
            wc.close()
        }

    }
    
    
    @IBAction func buttonPanelClick(_ sender: Any) {
        if (cpu != nil) {
            machine.viewController.showPanelTab()
        }
    }
    
    @IBAction func checkMapClick(_ sender: Any) {
        tvMemory.reloadData()
    }

    @IBAction func segmentAddressChange(_ sender: Any) {
        tvMemory.reloadData()
    }
    
    @IBAction func textGotoChange(_ sender: Any) {
        let amax = UInt32((checkMap.state == .on) ? 0x1FFFF : memory.pageCount * memory.pageWordSize - 1 )
        if let tf = sender as? NSTextField,
           let address = hexIn(hex: tf.stringValue),
           (address >= 0) && (address <= amax) {
     
            tvMemory.selectRowIndexes([address >> 3], byExtendingSelection: false)
            cvMemory.scroll(to: NSPoint(x: 0, y: tvMemory.rowHeight * CGFloat(address >> 3)))
            svMemory.reflectScrolledClipView(cvMemory)
        }
    }
    
    @IBAction func textDataSearchChange(_ sender: Any) {
        //MARK: THIS IS STILL MESSY - FIX IT UP.
        let byteAddressMask = memory.pageCount * memory.pageByteSize - 1
        let wordAddressMask = byteAddressMask >> 2
        
        func compareBytes(_ e: [UInt8],_ a: Int) -> Bool {
            for x in 0 ... e.count-1 {
                if (e[x] != memory.loadByte((a+x) & byteAddressMask)) {
                    return false
                }
            }
            return true
        }
        
        if let f = sender as? NSTextField {
            var matchAddress = -1

            let s = f.stringValue
            
            if let le = Instruction(s)?.value {
                let v = UInt32(le & 0xffffffff).bigEndian
                
                
                //TODO: MAKE SUBR If mapped is set, search virtual mem
                searchWordAddress += 1
                searchWordAddress &= wordAddressMask
                var c = memory.pageCount * memory.pageWordSize
                while (c > 0) && (v != memory.loadRawWord(word: searchWordAddress)) {
                    searchWordAddress += 1
                    searchWordAddress &= wordAddressMask
                    c -= 1
                }
                if (c > 0) {
                    matchAddress = searchWordAddress << 2
                }
            }
            else {
                var e: [UInt8] = []
                if let le = hexIn(hex: s) {
                    var n = (s.count + 1) >> 1
                    while (n > 0) {
                        n -= 1
                        e.append(UInt8((le >> (n << 3)) & 0xff))
                    }
                }
                else {
                    for c in s {
                        e.append(ebcdicFromAscii(c.asciiValue!))
                    }
                    if (e.isEmpty) { return }
                }
                
                
                searchByteAddress += 1
                searchByteAddress &= byteAddressMask
                var c = byteAddressMask + 1
                while (matchAddress < 0) && (c > 0) {
                    while (c > 0) && (!compareBytes(e,searchByteAddress)) {
                        searchByteAddress += 1
                        searchByteAddress &= byteAddressMask
                        c -= 1
                    }
                    
                    if (c > 0) {
                        matchAddress = searchByteAddress
                    }
                }
            }
            
            if (matchAddress >= 0) {
                checkMap.state = .off
                tvMemory.selectRowIndexes([matchAddress >> 5], byExtendingSelection: false)
                cvMemory.scroll(to: NSPoint(x: 0, y: tvMemory.rowHeight * CGFloat(matchAddress >> 5)))
                svMemory.reflectScrolledClipView(cvMemory)
                textSearch.textColor = .controlTextColor
            }
            else {
                textSearch.textColor = .red
            }
        }
    }

    @IBAction func buttonBPClick(_ sender: Any) {
        if let bpb = sender as? NSButton {
            let n = bpb.tag
            
            if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "BreakpointWindowController") as! NSWindowController?,
               let vc = wc.contentViewController as? BreakpointViewController {
                var screenPosition = NSPoint (x: 0, y: 0)
                if let mainWindow = NSApp.mainWindow,
                   let mainView = mainWindow.contentViewController?.view {
                    let buttonPosition = mainView.convert(screenPosition, from: bpb)
                    screenPosition = mainWindow.convertPoint(toScreen: buttonPosition)
                    //screenPosition.x += 0
                    screenPosition.y -= (wc.window!.frame.height)
                }
                
                if (.OK == vc.runModal (n, cpu, screenPosition)) {
                    if let bpd = cpu.getBreakpoint(n: n) {
                        bpb.title = hexOut(bpd.address,width:5) + "/" + (bpd.mapped ? "M" : "") + (bpd.unmapped ? "U" : "") + (bpd.execute ? "E" : "") + (bpd.read ? "R" : "") + (bpd.write ? "W" : "")
                    }
                    else {
                        bpb.title = "+"
                    }
                }
                
                wc.close()
            }
        }
    }
    
    @IBAction func checkRegisterClick(_ sender: Any) {
        if (checkRegister.state == .on) {
            textRegisterValue.isEnabled = true
            textRegisterNumber.isEnabled = true
            textRegisterChange(sender)
        }
        else {
            textRegisterValue.isEnabled = false
            textRegisterNumber.isEnabled = false
            cpu.setRegisterBreak(false, r: 0, value: 0, mask: 0)
        }
    }
    
    @IBAction func textRegisterChange(_ sender: Any) {
        if let r = hexIn(hex: textRegisterNumber.stringValue), (r >= 0), (r <= 0xf) {
            if let v = hexIn(hex: textRegisterValue.stringValue) {
                if let m = hexIn(hex: textRegisterMask.stringValue) {
                    checkRegister.state = .on
                    cpu.setRegisterBreak(true, r: UInt4(r), value: UInt32(v & 0xFFFFFFFF), mask: UInt32(m & 0xFFFFFFFF))
                    
                    textRegisterNumber.textColor = .controlTextColor
                    textRegisterValue.textColor = .controlTextColor
                    textRegisterMask.textColor = .controlTextColor
                }
                else {
                    textRegisterMask.textColor = .red
                }
            }
            else {
                textRegisterValue.textColor = .red
            }
        }
        else {
            textRegisterNumber.textColor = .red
        }
    }
    
    @IBAction func buttonNewInstructionBrowser(_ sender: Any) {
        let vc = InstructionViewController(nibName: nil, bundle: nil)
        let wc = NSWindowController(window: NSWindow(contentViewController: vc))
        vc.setMachine(machine)
        wc.showWindow(self)
        wc.window?.delegate = self
        wc.window?.title = machine.name
        wc.windowFrameAutosaveName = "InstructionBrowser"
        instructionBrowsers.append(vc)
    }
    
    func instructionBrowserSync() {
        for ib in instructionBrowsers {
            ib?.sync()
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            let vc = w.contentViewController
            instructionBrowsers.removeAll(where: { (ib) in return (ib == vc) })
        }
    }
    
}


class InstructionViewController: NSViewController {
    @IBOutlet weak var svInstructions: NSScrollView!
    @IBOutlet weak var cvInstructions: NSClipView!
    @IBOutlet weak var tvInstructions: NSTableView!
    @IBOutlet weak var buttonSync: NSButton!
    @IBOutlet weak var textAddress: NSTextField!
    
    var needsReposition: Bool = false
    var nextToSync: InstructionViewController?
    
    var machine: VirtualMachine!
    var cpu: CPU! { get { return machine.cpu }}
    var memory: RealMemory! { get { return machine.cpu.realMemory }}
    
    var dsInstructions: DSInstructions!
    
    func setMachine(_ m: VirtualMachine?) {
        machine = m
        dsInstructions = DSInstructions(cpu:cpu, rows: memory.pageCount * 512)
        tvInstructions.dataSource = dsInstructions
    }
    
    func reposition (to address: Int) {
        textAddress.stringValue = hexOut(address,width:5)
        tvInstructions.selectRowIndexes([address], byExtendingSelection: false)
        cvInstructions.scroll(to: NSPoint(x: 0, y: tvInstructions.rowHeight * CGFloat(address-8)))
        svInstructions.reflectScrolledClipView(cvInstructions)
    }
    
    func sync () {
        if (buttonSync.state == .on) {
            reposition(to: Int(cpu.psd.zInstructionAddress))
        }
        tvInstructions.reloadData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        needsReposition = true
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if (needsReposition) {
            reposition(to: Int(cpu.psd.zInstructionAddress))
            needsReposition = false
        }
        tvInstructions.reloadData()
    }
    
    @IBAction func AddressChanged(_ sender: Any) {
        if let a = hexIn(hex: textAddress.stringValue) {
            reposition(to: a)
        }
        else {
            let x = tvInstructions.selectedRow
            reposition(to: x)
        }
    }
    
    @IBAction func buttonSyncClick(_ sender: Any) {
        if (buttonSync.state == .on) {
            reposition(to: Int(cpu.psd.zInstructionAddress))
        }
        tvInstructions.reloadData()
    }
}

class DSInstructions: NSObject, NSTableViewDataSource {
    var cpu: CPU!
    var memory: RealMemory!
    var rows: Int = 256
    var maxRows: Int
    
    init (cpu: CPU!, rows: Int) {
        self.cpu = cpu
        self.memory = cpu.realMemory
        
        maxRows = memory.pageCount * 512
        self.rows = max(16,min(rows,maxRows))
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return (rows)
    }
    
    
    //MARK: This gets infromation about the target of the instruction fr display.
    //MARK: However, it calls the CPU load methods directly, which can cause a trap.
    //MARK: The trap is ignored in the CPU trap method, but this is an extreme KLUDGE.
    //TODO: A better method os required.
    func getTarget(_ i: Instruction) -> String {
        func getDevice(addr: Int) -> Device? {
            let iopNumber = addr >> 8
            if (iopNumber < cpu.machine.iopTable.count), let iop = cpu.machine.iopTable[iopNumber] {
                let idx = iop.dxFromAddress(UInt8(addr & 0xFF))
                if (idx >= 0) {
                    return iop.deviceList[idx]
                }
            }
            return nil
        }
        
        func targetDeviceName() -> String {
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .word, indirect: i.indirect)
            if let d = getDevice(addr: ea & 0x7FF) {
                return d.name
            }
            return "Unknown Device"
        }
        
        func cf(_ f: UInt4,_ v: Int) -> String {
            var s = ""
            if ((f & 0x2) != 0) {
                s += "CC .\(hexOut((v >> 4) & 0xF, width:2)), "
            }
            else {
                s += "CC -, "
            }
            if ((f & 0x1) != 0) && ((v & 0x7) != 0) {
                if ((v & 0x4) != 0) { s += "FS "}
                if ((v & 0x2) != 0) { s += "FZ "}
                if ((v & 0x1) != 0) { s += "FN "}
            }
            else {
                s += "F -"
            }
            return s
        }
        
        var s = ""
        switch (i.opCode) {
        case 0x02:                                          // LCFI
            s = cf(i.register, i.reference)
         
        case 0x04:
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .word, indirect: i.indirect)
            if (ea > 0) {
                s = "WA: \(hexOut(ea,width: 5)), " + cal1Decode(i: i, ea: ea, cpu: cpu)
            }
            
        case 0x05, 0x06, 0x07:
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .word, indirect: i.indirect)
            if (ea > 0) {
                let ev = cpu.loadWord(wa: ea)
                s = "EA: \(hexOut(ea,width: 5)), Value: .\(hexOut(UInt32(bitPattern: ev))) [Decimal: \(ev)]"
            }
        case 0x08, 0x09, 0x0a, 0x0b, 0x13:                   // Stack
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .double, indirect: i.indirect)
            if (ea > 0) {
                let spd = CPU.SPD(dw: memory.loadUnsignedDoubleWord(Int(ea) << 3), cpu.psd.zRealExtended)
                s = "SPD(WA): \(hexOut(ea << 1,width: 7)), TOP: \(hexOut(spd.pointer, width:5)), USED: \(hexOut(spd.usedCount)) (\(spd.usedCount)), AVAIL: \(hexOut(spd.availableCount)) (\(spd.availableCount))"
                if (spd.trapUsed) { s += ", TU" }
                if (spd.trapAvailable) { s += ", TA" }
            }
        
        case 0x0E, 0x0F:
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .double, indirect: i.indirect)
            if (ea > 0) {
                let psd = CPU.PSD(memory.loadUnsignedDoubleWord(Int(ea) << 3))
                s = "PSD(WA): \(hexOut(ea << 1,width: 5)), Value: \(hexOut(psd.value,width:16))"
            }

        case 0x10, 0x11, 0x12, 0x18, 0x1a, 0x1b:            // AD, CD, LD, SD, LCD, LAD
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .double, indirect: i.indirect)
            let ev = cpu.loadUnsignedDoubleWord(da: ea)
            s = "WA: \(hexOut(ea << 1,width: 5)), Value: .\(hexOut(ev)) [Decimal: \(Int64(bitPattern:ev))]"

        case 0x15:
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .double, indirect: i.indirect)
            let ev = cpu.loadUnsignedDoubleWord(da: ea)
            let rv = cpu.getRegisterUnsignedDouble(i.register)
            s = "WA: \(hexOut(ea << 1,width: 5)), Current/New Value: .\(hexOut(ev))/\(hexOut(rv)) [Decimal: \(Int64(bitPattern:ev))/\(Int64(bitPattern: rv))]"

        case 0x19:                                          // CLM
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .double, indirect: i.indirect)
            let ev = cpu.loadUnsignedDoubleWord(da: ea)
            s = "WA: \(hexOut(ea << 1,width: 5)), Values: .\(hexOut(ev>>32))/\(hexOut(ev&0xFFFFFFFF))"
            
        case 0x20, 0x21, 0x22, 0x23:                        // Immediate instructions
            s = "Decimal: \(i.getSignedDisplacement())"
            
        case 0x28, 0x29:                                    // CVS, CVA
            s = ".."
        
        case 0x2a, 0x2b:                                    // LM, STM
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .word, indirect: i.indirect)
            let c = (cpu.psd.zCC == 0) ? 16 : Int(cpu.psd.zCC)
            s = "Count: .\(hexOut(c,width:2)) [D: \(c)],  EA: \(hexOut(ea,width: 5)) "
        
        case 0x30, 0x31, 0x32, 0x33:                        // AW, CW, LW, MTW
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .word, indirect: i.indirect)
            let ev = cpu.loadWord(wa: ea)
            s = "WA: \(hexOut(ea,width: 5)), Value: .\(hexOut(UInt32(bitPattern: ev))) [Decimal: \(ev)]"

        case 0x4c:                                          // SIO
            s = targetDeviceName()
            
            let a = Int(cpu.getRegisterUnsignedHalf(1))
            s += " R0:\(hexOut(a << 1)) - "
            let cdw = IOCommand(memory.loadUnsignedDoubleWord(a << 3))
            s += cdw.getDisplayText()
        
        case 0x4d, 0x4e, 0x4f:
            s = targetDeviceName()
        
        case 0x50, 0x51, 0x52, 0x53, 0x55, 0x56, 0x57, 0x58, 0x5A, 0x5b:
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .half, indirect: i.indirect)
            let ev = cpu.loadHalf(ha: ea)
            s = "HA: \(hexOut(ea,width: 5)), Value: .\(hexOut(ev)) [Decimal: \(ev)]"

            
        case 0x60, 0x61:
            let rv = cpu.getRegisterUnsignedWord(i.register)
            let ru = cpu.getRegisterUnsignedWord(i.register.u1)
            let sa = rv & 0x7FFFF
            let da = ru & 0x7FFFF
            let c = Int(ru >> 24)
            s = "COUNT: .\(hexOut(c)) [D: \(c)], S: \(hexOut(sa)) [WA: \(hexOut(sa >> 2)), D: \(hexOut(da)) [WA: \(hexOut(da >> 2))"
        
        case 0x70:                                          // LCF
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .byte, indirect: i.indirect)
            let ev = cpu.loadByte(ba: ea)
            s = cf(i.register, Int(ev))

        case 0x71, 0x72, 0x73:                              // CB, LB, MTB
            let ea = cpu.effectiveAddress(reference: i.reference, indexRegister: i.index, indexAlignment: .byte, indirect: i.indirect)
            let ev = cpu.loadByte(ba: ea)
            s = "BA: \(hexOut(ea,width: 5)), Value: .\(hexOut(ev)) [Decimal: \(ev)]"

        default: break
        }
        return (s)
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let addressOffset = (rows < maxRows) ?  Int(cpu.psd.zInstructionAddress)-(rows >> 1)   : 0
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("ADDRESS") {
            let a = row + addressOffset
            if (a >= 0) {
                return hexOut(a, width:5)
            }
        }
        else {
            let a = row + addressOffset
            var w: UInt32 = 0
            
            if (a >= 0) {
                if (a < 0xF) {
                    w = cpu.getRegisterUnsignedWord(UInt4(a))
                }
                else if cpu.psd.zMapped {
                    let (t, ra) = cpu.virtualMemory.mapWord(UInt32(a), .read, cpu.psd.zMaster)
                    if (t) {
                        return ("--------")
                    }
                    w = cpu.realMemory.loadUnsignedWord(word: Int(ra))
                }
                else {
                    w = cpu.realMemory.loadUnsignedWord(word: a)
                }
            }
            
            if (tableColumn?.identifier == NSUserInterfaceItemIdentifier("DATA")) {
                return hexOut(w, width: 8)
            }
            else if (tableColumn?.identifier == NSUserInterfaceItemIdentifier("INSTRUCTION")) {
                return Instruction(w).getDisplayText()
            }
            else if (tableColumn?.identifier == NSUserInterfaceItemIdentifier("OTHER")) {
                return getTarget(Instruction(w))
            }
        }
        return ""
    }
}


class DSMemory: NSObject, NSTableViewDataSource {
    
    var cpu: CPU!
    var memory: VirtualMemory!
    var segmentAddress: NSSegmentedControl!
    var map: NSButton!
    
    init (cpu: CPU!, seg: NSSegmentedControl!, map: NSButton!) {
        self.cpu = cpu
        self.memory = cpu.virtualMemory
        self.segmentAddress = seg
        self.map = map
    }
    
    //MARK: CLEAN UP VIRTUAL ACCESSes
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return 64*((map.state == .off) ? memory.realMemory.pageCount : memory.pageCount)
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {

        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("SDADDRESS") {
            switch (segmentAddress.selectedSegment) {
            case 0:
                return hexOut(row << 5, width: 6)
            case 2:
                return hexOut(row << 2, width: 6)
            default:
                return hexOut(row << 3, width: 6)
            }
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("SDTEXT") {
            var a = row << 5
            var t = ""
            for _ in 0 ... 31 {
                var b: UInt8 = 0
                if (a <= 0x3F) {
                    b = cpu.getRegisterByte(UInt8(a))
                }
                else if (map.state == .off) {
                    b = cpu.realMemory.loadByte(a)
                }
                else {
                    let (t, ra) = cpu.virtualMemory.mapWord(UInt32(a >> 2), .read, cpu.psd.zMaster)
                    if !t {
                        b = cpu.realMemory.loadByte(Int(ra << 2) | (a & 3))
                    }
                }
                
                t += dottedAsciiFromEbcdic(b)
                a += 1
            }
            return (t)
        }
        else if let c = tableColumn?.identifier.rawValue,
            (c >= "0") && (c <= "7") {
            let col = Int(c.unicodeScalars.first!.value - asciiZero)
            let wa = (row << 3) + col
            
            if (wa < 0x10) {
                let h = hexOut(cpu.getRegisterUnsignedWord(UInt4(wa)), width:8)
                return (h)
            }
            
            if (map.state == .off) {
                return hexOut(cpu.realMemory.loadUnsignedWord(word: wa), width:8)
            }
            
            let (t, ra) = cpu.virtualMemory.mapWord(UInt32(wa), .read, cpu.psd.zMaster)
            if (t) {
                return ("--------")
            }
            return hexOut(cpu.realMemory.loadUnsignedWord(word: Int(ra)), width: 8)
        }
        return "********"
    }
    
    // SET THE VALUE OF A WORD IN MEMORY..
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if let s = object as? String, let x = Instruction(s)?.value, let c = tableColumn?.identifier.rawValue {
            let col = Int(c.unicodeScalars.first!.value - asciiZero)
            let wa = (row << 3) + col
            let x32 =  UInt32(x & 0xFFFFFFFF)
            
            if (wa < 0x10) {
                cpu.setRegister(UInt4(wa), unsigned: x32)
                return
            }
            
            if (map.state == .off) {
                cpu.realMemory.storeWord(word: wa, unsigned: x32)
                return
            }
            
            let (t, ra) = cpu.virtualMemory.mapWord(UInt32(wa), .write, true)
            if (!t) {
                cpu.realMemory.storeWord(word: Int(ra), unsigned: x32)
            }
        }
    }
}


class DSRegisters: NSObject, NSTableViewDataSource {
    var cpu: CPU!
    init (cpu: CPU!) {
        self.cpu = cpu
    }
    func numberOfRows(in tableView: NSTableView) -> Int {
        return 4
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if let c = tableColumn?.identifier.rawValue,
           (c >= "0") && (c <= "3") {
            let col = Int(c.unicodeScalars.first!.value - asciiZero)
            let w = Int(cpu.getRegisterUnsignedWord(UInt4((row << 2) + col)))
            return (hexOut(w, width: 8))
        }
        return "********"
    }
    
    // SET THE VALUE OF A REGISTER
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if let s = object as? String, let x = Instruction(s)?.value, let c = tableColumn?.identifier.rawValue {
            let col = Int(c.unicodeScalars.first!.value - asciiZero)
            let wa = (row << 2) + col
            let x32 =  UInt32(x & 0xFFFFFFFF)
            
            if (wa < 0x10) {
                cpu.setRegister(UInt4(wa), unsigned: x32)
            }
        }
    }

}


class DSTrace: NSObject, NSTableViewDataSource {
    
    var cpu: CPU!
    var tt: EventTrace?
    
    init (cpu: CPU!, trace: EventTrace?) {
        self.cpu = cpu
        self.tt = trace
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if let rows = tt?.bufferSize {
            return rows
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        //FIXME: MAKE THESE NAMES CORRESPOND TO THE STRUCT FIELDS

        if let e = tt?.entry(row),
           let cID = tableColumn?.identifier.rawValue {
            if cID == "ADDR" {
                if (e.ia > 0) {
                    return hexOut(e.ia-1, width:5)
                }
                return "ZERO!"
            }
            else if cID == "TYPE" {
                return EventTrace.eventTypeName(e.type)
            }
            else if cID == "MAP" {
                return e.mapped ? "M" : "U"
            }
            else if cID == "COUNT" {
                return String(e.count)
            }
            else if cID == "INS" {
                if (e.ins != 0) {
                    return Instruction(e.ins).getDisplayText(pad: false)
                }
            }
            else if cID == "EFFADDR" {
                return hexOut(e.ea, width:5)
            }
            else if cID == "DEVADDR" {
                return hexOut(e.ea, width:3)
            }
            else if cID == "DEVSTATUS" {
                return hexOut(e.deviceInfo, width:4)
            }
            else if cID == "CC" {
                return hexOut(UInt8(e.cc), width:1)
            }
            else if cID == "LEVEL" {
                return hexOut(e.level, width:2)
            }
            else if cID.prefix(4) == "DATA" {
                let w = Int(cID.substr(4)) ?? 8
                return hexOut(e.data, width: w)
            }
            else if cID == "REGISTERS" {
                if !e.registers.isEmpty, e.registers.count == 16 {
                    var x = hexOut(e.registers[0].bigEndian, width:8, treatAsUnsigned: true)
                    for i in 1...15 { x += " " + hexOut(e.registers[i].bigEndian, width:8, treatAsUnsigned: true) }
                    return x
                }
            }
        }
        return ""
    }
}

