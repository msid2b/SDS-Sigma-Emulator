//
//  BreakpointViewController.swift
//  Siggy
//
//  Created by MS on 2023-04-02.
//

import Cocoa

class BreakpointViewController: NSViewController {
    @IBOutlet weak var labelBreakPoint: NSTextField!
    @IBOutlet weak var textAddress: NSTextField!
    
    @IBOutlet weak var checkMapped: NSButton!
    @IBOutlet weak var checkUnmapped: NSButton!
    @IBOutlet weak var checkLogAndGo: NSButton!
    
    @IBOutlet weak var checkExecute: NSButton!
    @IBOutlet weak var checkRead: NSButton!
    @IBOutlet weak var checkWrite: NSButton!
    @IBOutlet weak var checkTransition: NSButton!
    
    @IBOutlet weak var checkOverlay: NSButton!
    @IBOutlet weak var comboOverlay: NSComboBox!
    @IBOutlet weak var checkUser: NSButton!
    @IBOutlet weak var textUserNumber: NSTextField!
    @IBOutlet weak var textSkipCount: NSTextField!

    @IBOutlet weak var labelCurrentInstruction: NSTextField!
    
    @IBOutlet weak var buttonDelete: NSButton!
    var cpu: CPU!
    var position: NSPoint!
    var breakpoint: CPU.Breakpoint!
    var breakpointNumber: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear() {
        view.window?.setFrameOrigin(position)
        labelBreakPoint.stringValue = "Breakpoint \(breakpointNumber)"
        
        buttonDelete.isEnabled = true
        if (breakpoint == nil) {
            breakpoint = CPU.Breakpoint()
            if let mapped = cpu?.psd?.zMapped {
                breakpoint.mapped = mapped
                breakpoint.unmapped = !mapped
            }
            buttonDelete.isEnabled = false
        }
        
        if (breakpoint.address > 0xf) && (breakpoint.address <= 0x1ffff) {
            textAddress.stringValue = hexOut(breakpoint.address, width: 4)
            let i = Instruction(cpu.loadUnsignedWord(wa: Int(breakpoint.address)))
            labelCurrentInstruction.stringValue = i.getDisplayText()
        }
        else {
            textAddress.stringValue = ""
            labelCurrentInstruction.stringValue = ""
        }
        
        checkMapped.state = controlState(breakpoint.mapped)
        checkUnmapped.state = controlState(breakpoint.unmapped)
        checkExecute.state = controlState(breakpoint.execute)
        checkTransition.state = controlState(breakpoint.transition)
        checkRead.state = controlState(breakpoint.read)
        checkWrite.state = controlState(breakpoint.write)

        checkOverlay.state = .off
        if (breakpoint.overlay > 0) {
            checkOverlay.state = .on
            if (breakpoint.overlay < comboOverlay.numberOfItems) {
                comboOverlay.selectItem(at: Int(breakpoint.overlay)-1)
            }
        }

        checkUser.state = .off
        if (breakpoint.user > 0) {
            checkUser.state = .on
            textUserNumber.stringValue = hexOut(breakpoint.user,width:2)
        }
        checkLogAndGo.state = controlState(breakpoint.logAndGo)
        textSkipCount.integerValue = breakpoint.count
    }
    
    func runModal ( _ n: Int,_ cpu: CPU?,_ screenPosition: NSPoint) -> NSApplication.ModalResponse {
        self.cpu = cpu
        self.position = screenPosition
        self.breakpoint = cpu?.getBreakpoint(n: n)
        self.breakpointNumber = n
        
        comboOverlay.removeAllItems()
        var maxovly = 13
        var maxname = 0
        if let m = cpu?.machine, let c = m.monitorReferences?.ovlyName.count {
            maxovly = (m.monitorReferences!.maxovly)-1
            maxname = c
            if (maxovly > 0) {
                for n in 0 ... maxovly {
                    comboOverlay.addItem(withObjectValue: String(format: "%2d ",n)+((n >= maxname) ? "" : m.monitorReferences!.ovlyName[n]) )
                }}
        }
        return NSApp.runModal(for: self.view.window!)
    }
    
    
    @IBAction func buttonCancelClick(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    @IBAction func buttonDeleteClick(_ sender: Any) {
        cpu.clearBreakpoint(n: breakpointNumber)
        NSApp.stopModal(withCode: .OK)
    }
        
    @IBAction func buttonOKClick(_ sender: Any) {
        if (checkExecute.state == .off) && (checkRead.state == .off) && (checkWrite.state == .off) && (checkTransition.state == .off) {
            checkExecute.state = .on
            return
        }
        
        if (checkUnmapped.state == .off) && (checkMapped.state == .off)  {
            checkUnmapped.state = .on
            return
        }

        var user = 0
        if (checkUser.state == .on) {
            if let u = hexIn(hex: textUserNumber.stringValue),
               (u <= 0xFF) {
                user = u
            }
            else {
                return
            }
        }
            
        if let address = hexIn(hex: textAddress.stringValue) ,
           (address >= 0x10) && ((address <= 0x1FFFF) || ((checkUnmapped.state == .on) && (address <= 0x3FFFFF))) {
            
            breakpoint.address = UInt32(address)
            breakpoint.user = UInt8(user)
            breakpoint.overlay = controlBool(checkOverlay) ? UInt8(comboOverlay.indexOfSelectedItem+1) : 0
            breakpoint.mapped = controlBool(checkMapped)
            breakpoint.unmapped = controlBool(checkUnmapped)
            breakpoint.logAndGo = controlBool(checkLogAndGo)
            breakpoint.count = textSkipCount.integerValue
            breakpoint.execute = controlBool(checkExecute)
            breakpoint.read = controlBool(checkRead)
            breakpoint.write = controlBool(checkWrite)
            breakpoint.transition = controlBool(checkTransition)

            cpu.setBreakpoint(breakpoint, n: breakpointNumber)
            NSApp.stopModal(withCode: .OK)
        }
    }
    
    @IBAction func textAddressChange(_ sender: Any) {
        if let address = hexIn(hex: textAddress.stringValue),
           (address >= 0x10) && (address <= 0x1FFFF) {
            let i = Instruction(cpu.loadUnsignedWord(wa: address))
            labelCurrentInstruction.stringValue = i.getDisplayText()
            labelCurrentInstruction.textColor = NSColor.textColor
        }
        else {
            labelCurrentInstruction.stringValue = "Invalid Address"
            labelCurrentInstruction.textColor = NSColor.red
        }
    }
    
    @IBAction func comboOverlayChange(_ sender: Any) {
        checkOverlay.state = .on
    }

    @IBAction func checkUserChange(_ sender: Any) {
    }
    
    @IBAction func textUserChange(_ sender: Any) {
        if let u = hexIn(hex: textUserNumber.stringValue) {
            if (u > 0) && (u <= 0xFF) {
                checkUser.state = .on
            }
            else {
                checkUser.state = .off
            }
        }
    }
    
    @IBAction func checkBPClick(_ sender: Any) {
//        if let rb = sender as? NSButton {
//            rb.state = (rb.state == .on) ? .off : .on
//            if (checkMapped.state == .off) && (checkUnmapped.state == .off) {
//                rb.state = .on
//            }
//            if (checkExecute.state == .off) && (checkRead.state == .off) && (checkWrite.state == .off) {
//                rb.state = .on
 //           }
//        }
    }
    
    

}
