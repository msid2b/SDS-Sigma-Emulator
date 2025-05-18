//
//  SiggyPanel.swift
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

class SiggyPanelController: NSViewController, NSMenuItemValidation {

    @IBOutlet weak var panelView: SiggyPanelView!

    // Maintenance Section
    // Appropriate the "Memory Fault" display for trap location.
    @IBOutlet weak var lightsTrapLocation: PLightBar!
    @IBOutlet weak var lightAlarm: PLight!
    

    @IBOutlet weak var lightsPreparation: PLightBar!
    @IBOutlet weak var lightsPCP: PLightBar!
    @IBOutlet weak var lightsExecution: PLightBar!
    @IBOutlet weak var lightsInterruptTrap: PLightBar!
    
    @IBOutlet weak var switchWatchdog: NSSlider!
    @IBOutlet weak var switchAudio: NSSlider!
    @IBOutlet weak var switchesSense: PSwitchBar!
    
    // Operator Section
    @IBOutlet weak var buttonPower: NSButton!
    @IBOutlet weak var buttonCPUReset: NSButton!
    @IBOutlet weak var buttonIOReset: NSButton!
    @IBOutlet weak var buttonLoad: NSButton!
    
    @IBOutlet weak var hexBoxLoadAddress: PHexBox!
    
    @IBOutlet weak var buttonSystemReset: NSButton!
    @IBOutlet weak var buttonNormalMode: NSButton!
    @IBOutlet weak var buttonRun: NSButton!
    @IBOutlet weak var buttonWait: NSButton!
    @IBOutlet weak var buttonInterrupt: NSButton!
    
    @IBOutlet weak var lightsPSD2: PLightBar!
    @IBOutlet weak var lightsPSD1: PLightBar!
    @IBOutlet weak var switchesInstructionAddr: PSwitchBar!
    @IBOutlet weak var lightsData: PLightBar!
    @IBOutlet weak var switchesData: PSwitchBar!
    
    @IBOutlet weak var switchCompute: PSwitch3Way!

    var statusTimer: Timer!
    var machine: VirtualMachine!
    var cpu: CPU! { get { return machine.cpu }}
    var senseSwitches: UInt4 { get { return UInt4(switchesSense.read() & 0xF) }}
    
    var cpuModel: Int = 0
    var memorySize: Int = 0
    var iopCount: Int = 0
    
    func setMachine(_ m: VirtualMachine?) {
        machine = m
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        lightsTrapLocation.configure(bits: 8, mask: 0xff, isLight: true, numberingPosition: -30, numberingOption: .from1)
        lightsTrapLocation.setLights(v: 0)
        lightAlarm.isLit = false
        
        //MARK: "Preparation" lights now show CPU type: 5/7/9
        lightsPreparation.configure(bits: 3, mask: 0x7, isLight: true, numberingPosition: +20, numberingOption: .custom, bitNames: ["5","7","9"])
        lightsPreparation.setLights(v: 0)
        
        //MARK: "PCP" shows number of active IOPs
        lightsPCP.configure(bits: 3, mask: 0x7, isLight: true, numberingPosition: +20, numberingOption: .bitValue)
        lightsPCP.setLights(v: 0)
        
        //MARK: "Execution" shows memory size in KW
        lightsExecution.configure(bits: 4, mask: 0xf, isLight: true, numberingPosition: +20, numberingOption: .bitValue)
        lightsExecution.setLights(v: 0)
        
        lightsInterruptTrap.configure(bits: 2, mask: 0x3, isLight: true, numberingPosition: +20, numberingOption: .bitValue)
        lightsInterruptTrap.setLights(v: 0)
        
        switchesSense.configure(bits: 4, mask: 0xf, isLight: false, numberingPosition: -30, numberingOption: .from1)
        
        hexBoxLoadAddress.isEnabled = true
        hexBoxLoadAddress.setHexValue (0x000)
        
        lightsPSD2.configure(bits: 32, mask: 0x37BF01F0)
        lightsPSD1.configure(bits: 32, mask: 0xF7F1FFFF)
        switchesInstructionAddr.configure(bits:17, mask: 0x1FFFF)
        lightsData.configure(bits:32, mask: 0xFFFFFFFF, numberingPosition: +20)
        switchesData.configure(bits:32, mask: 0xFFFFFFFF)
    }
    
    override func viewDidAppear() {
        statusTimer = Timer.scheduledTimer(timeInterval: 0.15, target: self, selector: #selector(statusTimerPop), userInfo: nil, repeats: true)
        buttonPower.state = .on
        buttonCPUReset.state = .on
        buttonIOReset.state = .on
        buttonSystemReset.state = .on
        
        view.window?.makeFirstResponder(self)
        panelView?.didAppear(machine)
    }
    
    override func viewDidDisappear() {
        statusTimer.invalidate()
        panelView?.didDisappear()
    }
    
    
    @objc func statusTimerPop() {
        guard (cpu != nil) else {
            buttonCPUReset.state = .on
            buttonIOReset.state = .on
            buttonSystemReset.state = .on
            buttonRun.state = .off
            buttonLoad.state = .off
            buttonWait.state = .off
            buttonInterrupt.state = .on
            buttonNormalMode.state = .off
            return
        }
        buttonCPUReset.state = .off
        buttonIOReset.state = .off
        buttonSystemReset.state = .off

        let status = cpu.getStatus()
        let psd = status.psd.value
        
        lightAlarm.isLit = status.alarm
        lightsPSD1.setLights(v: Int(psd >> 32))
        lightsPSD2.setLights(v: Int(psd & 0xffffffff))
        lightsData.setLights(v: Int(status.instruction.value))
        
        buttonWait.state = cpu.isWaiting ? .on : .off
        buttonRun.state = cpu.isRunning ? .on : .off
        switchCompute.integerValue = cpu.isRunning ? 1 : 0
        
        // MARK: MEMORY FAULT IS REPURPOSED FOR LAST INTERRUPT OR TRAP LOCATION.
        if (status.trapLocation > 0) {
            lightsTrapLocation.setLights(v: Int(status.trapLocation))
            lightsInterruptTrap.setLights(v: 0x1)
            buttonInterrupt.state = .off
        }
        else if (status.intLocation > 0) {
            lightsTrapLocation.setLights(v: Int(status.intLocation))
            lightsInterruptTrap.setLights(v: 0x2)
            buttonInterrupt.state = .on
        }
        else  {
            lightsTrapLocation.setLights(v: 0)
            lightsInterruptTrap.setLights(v: 0)
            buttonInterrupt.state = .off
        }

        // MARK: USE THESE FOR USEFUL INFORMATION ?
        if (cpu.isRunning) {
            buttonNormalMode.state =  .on
            
            if (cpuModel == 0) {
                switch (cpu.model) {
                case .s5: cpuModel = 1
                case .s7: cpuModel = 2
                case .s9: cpuModel = 4
                }
                
                memorySize = -1
                var p = cpu.realMemory.pageCount
                while (p != 0) {
                    memorySize += 1
                    p >>= 1
                }
                
                iopCount = machine?.iopCount ?? 0
            }
            
            
            lightsPreparation.setLights(v: cpuModel)
            lightsPCP.setLights(v: iopCount)
            lightsExecution.setLights(v: memorySize)
        }
        else {
            buttonNormalMode.state =  .off
            //lightsPreparation.setLights(v: 0x00)
            //lightsPCP.setLights(v: 0x2)
            //lightsExecution.setLights(v: 0x00)
        }

        if (status.fault) {
            buttonNormalMode.state =  .off
        }
    }
    
    @objc func buttonOff (sender: Any) {
        if let button = sender as? NSButton {
            button.state = .off
        }
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
        return false
    }
    

    
    @IBAction func switchAudioChange(_ sender: Any) {
    }
    
    func setBootDevice (_ device: Int) {
        hexBoxLoadAddress.setHexValue (device)
    }

    func running () {
        switchCompute.integerValue = 1
    }
    
    

    
    @IBAction func buttonPowerClick(_ sender: Any) {
        if (cpu == nil) {
            machine.powerOn(sender)
        }
        else if siggyApp.alertYesNo(message: "Power off \(machine.name)?", detail: "The machine will be stopped") {
            machine.powerOff()
        }
    }
    
    @IBAction func buttonLoadClick(_ sender: Any) {
        guard (cpu != nil) else { return }
        cpu.clearRun()
        cpu.clearWait()

        let address = hexBoxLoadAddress.getHexValue()
        machine.set("BootDevice", hexOut(address, width:3))
        cpu.load (address)
        perform (#selector(buttonOff), with: sender, afterDelay: 0.5)
    }
    
    @IBAction func buttonInterruptClick(_ sender: Any) {
        perform (#selector(buttonOff), with: sender, afterDelay: 0.5)
        machine.viewController.showDebugTab()
    }
    
    @objc func stepComplete() {
        buttonInterruptClick(buttonRun!)
    }

    @objc func switchReset(sender: Any) {
        if let s = sender as? PSwitch {
            s.integerValue = 0
        }
    }
    
    
    @IBAction func switchComputeChange(_ sender: Any) {
        guard (cpu != nil) else { return }
        
        switch(switchCompute.integerValue) {
        case 1:
            cpu.setRun(stepMode: .none)
            break
        
        case 0:
            cpu.clearRun()
            cpu.clearWait()
            break
            
        default:
            cpu.setRun(stepMode: .simple)
            perform (#selector(switchReset), with: sender, afterDelay: 0.2)
            break
            
        }
    }
    
    @IBAction func buttonRunClick(_ sender: Any) {
        if (buttonRun.state == .on) {
            cpu.setRun(stepMode: .none)
        }
        else {
            cpu.clearRun()
            cpu.clearWait()
        }
    }

    
    
}


class SiggyPanelView: NSView {
    var cardReader: CRDevice!
    
    func didAppear(_ m: VirtualMachine!) {
        for iop in m.iopTable {
            if let i = iop {
                for d in i.deviceList {
                    if (d is CRDevice) {
                        cardReader = d as? CRDevice
                        registerForDraggedTypes([.fileURL])
                        return
                    }
                }
            }
        }
    }
    
    func didDisappear() {
        if !registeredDraggedTypes.isEmpty {
            registerForDraggedTypes([])
        }
        cardReader = nil
    }
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if (sender.numberOfValidItemsForDrop == 1) {
            let pasteboard = sender.draggingPasteboard
            if let types = pasteboard.types, types.contains(.fileURL) {
                if let cr = cardReader, !cr.inUse() {
                     return .link
                }
            }
        }
        return []
    }
    
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return true
    }
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let types = pasteboard.types, types.contains(.fileURL) {
             if let file = pasteboard.string(forType: .fileURL),
                let url = URL(string:file),
                let cr = cardReader {
                 cr.unload()
                 return cr.load(url.path, mode: .read)
             }
         }
         return false
    }
    
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    }
    
    override func updateDraggingItemsForDrag(_ sender: (any NSDraggingInfo)?) {
    
    }
}
