//
//  SettingsViewController.swift
//  Siggy
//
//  Created by MS on 2023-07-28.
//

import Cocoa

// TODO: Generalize and move somewhere else.
class RightClickView: NSTableView {
    var rightClickMenu: NSMenu?
    
    override func rightMouseDown(with event: NSEvent) {
        if let menu = rightClickMenu {
            let position = event.locationInWindow
            menu.popUp(positioning: nil, at: position, in: event.window?.contentView)
        }
    }
}

class ConnectedButton: NSButton {
    var other: NSButton?
    var trigger: NSControl.StateValue = .mixed
}

class SettingsViewController: NSViewController {
    @IBOutlet weak var labelPath: NSTextField!
    @IBOutlet weak var labelCreated: NSTextField!

    @IBOutlet weak var textMachineName: NSTextField!
    @IBOutlet weak var comboModel: NSComboBox!
    @IBOutlet weak var comboMemorySize: NSComboBox!
    @IBOutlet weak var comboIOPs: NSComboBox!

    @IBOutlet weak var checkOptimizeBDR: NSButton!
    @IBOutlet weak var checkOptimizeClocks: NSButton!

    @IBOutlet weak var checkDecimalInstructions: ConnectedButton!
    @IBOutlet weak var checkDecimalTrace: ConnectedButton!
    @IBOutlet weak var checkFloatingPoint: ConnectedButton!
    @IBOutlet weak var checkFloatTrace: ConnectedButton!
    
    @IBOutlet weak var checkAutoBoot: NSButton!
    @IBOutlet weak var comboBootDevice: NSComboBox!
    @IBOutlet weak var checkAutoDate: NSButton!

    @IBOutlet weak var comboDelta: NSComboBox!
    @IBOutlet weak var comboHGPRECON: NSComboBox!
    @IBOutlet weak var comboBatchRecovery: NSComboBox!
    @IBOutlet weak var tvDevices: RightClickView!
    
    var dsDevices: DSDevices!
    
    var url: URL!
    var machine: VirtualMachine!
    
    // Available memory sizes in pages
    let memorySizes: [Int] = [256, 512, 1024, 2048, 4096]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    func runModal (_ machine: VirtualMachine!) -> NSApplication.ModalResponse {
        self.machine = machine
        self.url = machine.url
        
        if let w = view.window {
            w.title = "Machine Settings"
            
            labelPath.stringValue = url.path
            labelCreated.stringValue = "Created: " + machine.getSetting("DateCreated", "-") + ", Last Configuration Change: " + machine.getSetting("DateChanged", "-")
            textMachineName.stringValue = machine.getSetting("Name", "*")

            comboModel.selectItem(at: 0)
            comboModel.isEnabled = false
            
            comboMemorySize.removeAllItems()
            for s in memorySizes {
                comboMemorySize.addItem(withObjectValue: String(s)+" Pages / "+String(s >> 1)+" KW")
            }
            comboMemorySize.selectItem(at: 1)
            if let ms = Int(machine.getSetting("MemoryPages", "256")),
               let mx = memorySizes.firstIndex(where: { (s) -> Bool in return (s >= ms) }) {
                comboMemorySize.selectItem(at: max(0,mx))
            }
            
            comboIOPs.selectItem(at: 0)
            comboIOPs.isEnabled = false

            checkOptimizeBDR.state = controlState((machine.getSetting(VirtualMachine.kOptimizeWaits)) != "N")
            checkOptimizeClocks.state = controlState((machine.getSetting(VirtualMachine.kOptimizeClocks)) != "N")

            
            checkDecimalInstructions.state = controlState((machine.getSetting(VirtualMachine.kDecimalInstructions)) != "N")
            checkDecimalTrace.state = controlState((machine.getSetting(VirtualMachine.kDecimalTrace)) == "Y")
            checkDecimalTrace.other = checkDecimalInstructions; checkDecimalTrace.trigger = .on
            checkDecimalInstructions.other = checkDecimalTrace; checkDecimalInstructions.trigger = .off

            checkFloatingPoint.state = controlState((machine.getSetting(VirtualMachine.kFloatingPoint)) != "N")
            checkFloatTrace.state = controlState((machine.getSetting(VirtualMachine.kFloatTrace)) == "Y")
            checkFloatTrace.other = checkFloatingPoint; checkFloatTrace.trigger = .on
            checkFloatingPoint.other = checkFloatTrace; checkFloatingPoint.trigger = .off

            checkAutoBoot.state = (machine.getSetting("AutoBoot", "N") == "Y") ? .on : .off
            checkAutoDate.state = (machine.getSetting("AutoDate", "N") == "Y") ? .on : .off

            switch (machine.getSetting("BootDevice")) {
            case "080":
                comboBootDevice.selectItem(at: 0)
            case "1F0":
                comboBootDevice.selectItem(at: 1)
            case "2F0":
                comboBootDevice.selectItem(at: 2)
            default:
                comboBootDevice.selectItem(at: 3)
            }
            
            switch (machine.getSetting("AutoDelta")) {
            case "N":
                comboDelta.selectItem(at: 0)
            case "Y":
                comboDelta.selectItem(at: 1)
            default:
                comboDelta.selectItem(at: 2)
            }
            
            switch (machine.getSetting("AutoHGP")) {
            case "N":
                comboHGPRECON.selectItem(at: 0)
            case "Y":
                comboHGPRECON.selectItem(at: 1)
            default:
                comboHGPRECON.selectItem(at: 2)
            }
            
            switch (machine.getSetting("AutoBatch")) {
            case "N":
                comboBatchRecovery.selectItem(at: 0)
            case "Y":
                comboBatchRecovery.selectItem(at: 1)
            default:
                comboBatchRecovery.selectItem(at: 2)
            }
            
            dsDevices = DSDevices(machine)
            tvDevices.dataSource = dsDevices
            tvDevices.reloadData()
            
            let rcMenu = NSMenu()
            rcMenu.items.append(NSMenuItem(title: "Edit", action: #selector(buttonDeviceDoubleClick), keyEquivalent: "E"))
            rcMenu.items.append(NSMenuItem(title: "Remove", action: #selector(buttonRemoveDeviceClick), keyEquivalent: ""))
            tvDevices.rightClickMenu = rcMenu
            
            
            return NSApp.runModal(for: w)
        }
        return .abort
    }
    
    @IBAction func buttonTraceClick (_ sender: Any) {
        if let s = sender as? ConnectedButton {
            if (s.state == s.trigger) {
                s.other?.state = s.state
            }
        }
    }
    
    func makeDeviceFromSettings (_ settings: DeviceEditorController.Settings ) -> Device {
        var d: Device!
        
        switch (settings.type) {
        case .tty:
            d = TTYDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model)
            
        case .cr:
            d = CRDevice (machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model)
            
        case .cp:
            d = CPDevice (machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, directory: settings.path, flags: settings.burst ? 1 : 0)
            
        case .me:
            d = COCDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, cocData: settings.cocParms!)
            
        case .lp:
            if settings.burst {
                d = PDFDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, directory: settings.path, config: PrintDevice.Configuration(settings.linesPerPage, settings.showVFC, settings.lpParms))
            }
            else {
                d = LPDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, path: settings.path, config: PrintDevice.Configuration(settings.linesPerPage, settings.showVFC, nil))
            }
            
        case .mt, .bt:
            d = TapeDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, type: settings.type, model: settings.model, mountable: true,
                                configuration: BlockDevice.StorageConfiguration(access: .read, ioSize: 65536))
            
        case .dp:
            d = DPDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, fullPath: settings.path, mountable: !settings.publicDisk)
            
        case .dc:
            d = DCDevice(machine, name: settings.name, iopNumber: settings.iop, unitAddr: settings.unit, model: settings.model, fullPath: settings.path)
        }


        d.trace = settings.trace
        return d
    }
        
    //MARK:  NO LONGER USED
    @IBAction func textTraceChange(_ sender: Any) {
        if let t = sender as? NSTextFieldCell {
            let trace = (t.stringValue.uppercased() == "Y")
            let r = tvDevices.selectedRow
            if (r >= 0) {
                let d = dsDevices.deviceList[r]
                d.trace = trace
            }
        }
    }
    
    @IBAction func buttonRemoveDeviceClick(_ sender: Any) {
        let r = tvDevices.selectedRow
        if (r >= 0) {
            let d = dsDevices.deviceList[r]
            if siggyApp.alertYesNo(message: "Delete \(d.name)?", detail: "This nasty device will go away") {
                dsDevices.deleteList.append(d)
                dsDevices.deviceList.remove(at: r)
                tvDevices.reloadData()
            }
        }
    }
    
    @IBAction func buttonAddDeviceClick(_ sender: Any) {
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "DeviceEditorWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? DeviceEditorController {
            if (.OK == vc.runModal (machine: machine, device: nil, deviceList: dsDevices.deviceList)) {
                let d = makeDeviceFromSettings(vc.settings)
                d.trace = vc.checkTrace.state == .on
                dsDevices.deviceList.append(d)
                tvDevices.reloadData()
            }
            wc.close()
        }
    }

    @IBAction func buttonDeviceDoubleClick(_ sender: Any) {
        let r = tvDevices.selectedRow
        if (r >= 0) {
            let d = dsDevices.deviceList[r]
            if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "DeviceEditorWindow") as! NSWindowController?,
               let vc = wc.contentViewController as? DeviceEditorController {
                if (.OK == vc.runModal (machine: machine, device: d, deviceList: dsDevices.deviceList)) {
                    let d = makeDeviceFromSettings(vc.settings)
                    d.trace = vc.checkTrace.state == .on
                    dsDevices.deviceList[r] = d
                    tvDevices.reloadData()
                }
                wc.close()
            }
        }
    }
    
    @IBAction func buttonCancelClick(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    @IBAction func buttonApplyClick(_ sender: Any) {
        // Update settings and devices tables
        if siggyApp.alertYesNo(message: "Reconfigure \(machine.name)?", detail: "The machine will be restarted") {

            machine.set("Name", textMachineName.stringValue)
            machine.set("DateChanged", MSDate().displayString)
            machine.set("MemoryPages", String(memorySizes[comboMemorySize.indexOfSelectedItem]))
            
            
            machine.set(VirtualMachine.kOptimizeWaits, controlYN(checkOptimizeBDR))
            machine.set(VirtualMachine.kOptimizeClocks, controlYN(checkOptimizeClocks))
            
            machine.set(VirtualMachine.kDecimalInstructions, controlYN(checkDecimalInstructions))
            machine.set(VirtualMachine.kDecimalTrace, controlYN(checkDecimalTrace))
            
            machine.set(VirtualMachine.kFloatingPoint, controlYN(checkFloatingPoint))
            machine.set(VirtualMachine.kFloatTrace, controlYN(checkFloatTrace))
            
            
            machine.set("AutoBoot", (checkAutoBoot.state == .on) ? "Y" : "N")
            machine.set("AutoDate", (checkAutoDate.state == .on) ? "Y" : "N")
            
            switch (comboBootDevice.stringValue) {
            case "080", "1F0", "2F0":
                machine.set("BootDevice", comboBootDevice.stringValue)
            default:
                machine.set("BootDevice", "*")
            }
            
            switch (comboDelta.stringValue) {
            case "N", "Y":
                machine.set("AutoDelta", comboDelta.stringValue)
            default:
                machine.set("AutoDelta", "*")
            }
            
            switch (comboHGPRECON.stringValue) {
            case "N", "Y":
                machine.set("AutoHGP", comboHGPRECON.stringValue)
            default:
                machine.set("AutoHGP", "*")
            }
            
            switch (comboBatchRecovery.stringValue) {
            case "N", "Y":
                machine.set("AutoBatch", comboBatchRecovery.stringValue)
            default:
                machine.set("AutoBatch", "*")
            }
            
            for d in dsDevices.deleteList {
                machine.updateDeviceDB(deleting: d)
            }
            
            for d in dsDevices.deviceList {
                machine.updateDeviceDB(from: d)
            }
            
            NSApp.stopModal(withCode: .OK)
        }
    }

}

class DSDevices: NSObject, NSTableViewDataSource {
    var machine: VirtualMachine!
    var deviceList: [Device] = []
    var deleteList: [Device] = []
    
    init (_ m: VirtualMachine!) {
        machine = m
    }
    
    func mask(_ v: UInt64,_ on: String,_ off: String) -> String {
        var r: String = ""
        var m: UInt64 = 0x8000000000000000

        while (m > 0) {
            r += ((v & m) != 0) ? on : off
            m >>= 1
        }
        return r
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if (deviceList.count <= 0) {
            for i in machine.iopTable {
                if let iop = i {
                    for d in iop.deviceList {
                        deviceList.append(d)
                    }
                }
            }
        }
        return (deviceList.count)
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard (row < deviceList.count) else { return  "" }
        
        let x = row
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("NAME") {
            return deviceList[x].name
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("IOP") {
            return String(deviceList[x].iopNumber)
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("UNIT") {
            return hexOut(deviceList[x].unitAddr, width:2)
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("PATH") {
            return deviceList[x].hostPath
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("MODEL") {
            return String(format:"%04d", deviceList[x].model)
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TRACE") {
            return (controlState(deviceList[x].trace))
        }
        return ""
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        let x = row
        let d = deviceList[x]
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TRACE") {
            if let v = object as? NSControl.StateValue {
                d.trace = (v == .on)
            }
        }
        else if (tableColumn?.identifier == NSUserInterfaceItemIdentifier("PATH")) {
            if let v = object as? String {
                let c = v.first
                d.hostPath = (c == ".") || (c == "/" ) ? v : "./"+v
            }
        }
    }
}


