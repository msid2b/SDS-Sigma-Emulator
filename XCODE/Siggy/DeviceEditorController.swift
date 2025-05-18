//
//  DeviceEditorController.swift
//  Siggy
//
//  Created by MS on 2024-02-12.
//

import Cocoa

//MARK: DEVICE MODEL INFORMATION
struct DMI {
    var deviceType: Device.DType
    var modelNumber: Int
    var note: String
    var deviceSpecifics: [ Int ]
    
    init (_ dt: Device.DType,_ modelNumber: Int,note: String = "",_ specifics: [Int] = []) {
        self.deviceType = dt
        self.modelNumber = modelNumber
        self.note = note
        self.deviceSpecifics = specifics
    }
}

let deviceModelInfo: [DMI] = [
    DMI ( .tty,  33 ),
    DMI ( .lp, 7450 ),
    DMI ( .cp, 7465 ),
    DMI ( .cr, 7120, note: "400 cards/minute" ),
    DMI ( .cr, 7121, note: "200 cards/minute" ),
    DMI ( .cr, 7122, note: "400 cards/minute" ),
    DMI ( .cr, 7140, note: "1500 cards/minute" ),
    DMI ( .me, 7611 ),
    DMI ( .mt, 7323, [65536]),
    DMI ( .bt, 0000 ),
    DMI ( .dp, 7277, note: "84MB", [2048]),
    DMI ( .dc, 3214, note: "2.88MB", [2048])
]


class DeviceEditorController: NSViewController {
    @IBOutlet weak var textDeviceAddress: NSTextField!
    @IBOutlet weak var labelAddressStatus: NSTextField!
    @IBOutlet weak var cellDeviceAddress: NSTextFieldCell!
    @IBOutlet weak var comboDeviceType: NSComboBox!
    @IBOutlet weak var comboModel: NSComboBox!
    @IBOutlet weak var imageDevice: NSImageView!
    @IBOutlet weak var labelDeviceDetails: NSTextField!
    @IBOutlet weak var checkTrace: NSButton!
    @IBOutlet weak var checkBurst: NSButton!
    @IBOutlet weak var textLinesPerPage: NSTextField!
    @IBOutlet weak var checkShowVFC: NSButton!
    @IBOutlet weak var checkSplitPunch: NSButton!
    @IBOutlet weak var checkPublic: NSButton!
    @IBOutlet weak var textPath: NSTextField!


    @IBOutlet weak var tabViewDeviceDetails: NSTabView!
    @IBOutlet weak var tabViewBlank: NSTabViewItem!
    @IBOutlet weak var tabViewCardReader: NSTabViewItem!
    @IBOutlet weak var tabViewCardPunch: NSTabViewItem!
    @IBOutlet weak var tabViewDisk: NSTabViewItem!
    @IBOutlet weak var tabViewPrinter: NSTabViewItem!

    @IBOutlet weak var comboFont: NSComboBox!
    @IBOutlet weak var comboPaperSize: NSComboBox!

    @IBOutlet weak var tabViewCOC: NSTabViewItem!
    @IBOutlet weak var comboCOCInterrupt: NSComboBox!
    @IBOutlet weak var textCOCLines: NSTextField!
    @IBOutlet weak var textCOCFirstLine: NSTextField!
    @IBOutlet weak var textCOCLineTrace: NSTextField!
    @IBOutlet weak var textCOCAutoStart: NSTextField!
    
    var machine: VirtualMachine!
    var newDevice: Bool = false
    
    struct Settings {
        var name: String = ""
        var type: Device.DType = .mt
        var model: Int = 7323
        var blockSize: Int = 0
        var path: String = ""
        var publicDisk: Bool = false
        var iop: UInt8 = 0
        var unit: UInt8 = 0
        var trace: Bool = false
        var burst: Bool = false
        var showVFC: Bool = false
        var lpParms: String = ""
        var linesPerPage: Int = 0
        var cocParms: COCDevice.COCConfiguration?
    }
    var settings = Settings()
    
    func setDeviceDetails (_ t: Device.DType) {
        tabViewDeviceDetails.selectTabViewItem(tabViewBlank)
        var model: Int = 0
        
        switch (t) {
        case .tty:
            imageDevice.image = nil
            model = setComboItems(comboModel, .tty)

        case .cr:
            tabViewDeviceDetails.selectTabViewItem(tabViewCardReader)
            imageDevice.image = NSImage(named: "CardReader.jpg")
            model = setComboItems (comboModel, .cr)

        case .cp:
            tabViewDeviceDetails.selectTabViewItem(tabViewCardPunch)
            imageDevice.image = NSImage(named: "CardPunch.jpg")
            model = setComboItems(comboModel, .cp)


        case .lp:
            tabViewDeviceDetails.selectTabViewItem(tabViewPrinter)
            imageDevice.image = NSImage(named: "LinePrinter.jpg")
            model = setComboItems(comboModel, .lp)

        case .me:
            tabViewDeviceDetails.selectTabViewItem(tabViewCOC)
            imageDevice.image = NSImage(named: "COC.jpg")
            model = setComboItems(comboModel, .me)

        case .mt:
            imageDevice.image = NSImage(named: "TapeDrive.jpg")
            model = setComboItems(comboModel, .mt)

        case .bt:
            imageDevice.image = nil
            model = setComboItems(comboModel, .bt)

        case .dp:
            tabViewDeviceDetails.selectTabViewItem(tabViewDisk)
            imageDevice.image = NSImage(named: "DiskDrive.jpg")
            model = setComboItems(comboModel, .dp)

        case .dc:
            imageDevice.image = NSImage(named: "RAD.jpg")
            model = setComboItems(comboModel, .dc)
        }
        setDeviceDetails(t, model)
    }
    
    func setDeviceDetails (_ t: Device.DType,_ model: Int) {
        let info = deviceModelInfo.first(where: { (i) -> Bool in return (i.deviceType == t) && (i.modelNumber == model) })
        labelDeviceDetails.stringValue = Device.DType.typeName[t.rawValue] + "\nModel: \(model)\n" + (info?.note ?? "N/A")
        
        if newDevice {
            switch (t) {
            case .me:
                textCOCLines.integerValue = 8
                textCOCFirstLine.integerValue = 0
                textCOCLineTrace.stringValue = hexOut(0, width: 16)
                textCOCAutoStart.stringValue = hexOut(0, width: 16)
                comboCOCInterrupt.selectItem(at: 0)
                
            case .lp:
                checkBurst.state = .off
                checkShowVFC.state = .off
                comboFont.stringValue = "font"
                comboFont.isEnabled = false
                comboPaperSize.stringValue = "paper"
                comboPaperSize.isEnabled = false
            
            case .cp:
                checkSplitPunch.state = .off
                
            case .dp:
                checkPublic.state = .off
                
            default: break
            }
        }
    }
    
    func setComboItems (_ combo: NSComboBox!,_ type: Device.DType) -> Int {
        combo.removeAllItems()
        for i in deviceModelInfo {
            if (i.deviceType == type) {
                combo.addItem(withObjectValue: String(format: "%04d", i.modelNumber))
            }
        }
        
        if (combo.numberOfItems > 0) {
            combo.selectItem(at: 0)
            return Int(combo.objectValueOfSelectedItem as! String) ?? 0
        }
        return 0
    }
    
    @IBAction func comboDeviceTypeChange(_ sender: Any) {
        let t = Device.DType.value(prefix: comboDeviceType.stringValue)
        if (t > 0) {
            setDeviceDetails(Device.DType(rawValue: t)!)
        }
    }
    
    @IBAction func comboModelChange(_ sender: Any) {
        setDeviceDetails(Device.DType(rawValue: Device.DType.value(prefix: (comboDeviceType.objectValueOfSelectedItem as! String)))!, Int(comboModel.objectValueOfSelectedItem as! String) ?? 0)

    }
    
    @IBAction func checkBurstChange(_ sender: Any) {
        let e = (checkBurst.state == .on)
        comboFont.isEnabled = e
        comboPaperSize.isEnabled = e
    }
    
    @IBAction func checkSplitPunchChange(_ sender: Any) {
    }
    
    @IBAction func textDeviceAddressChange(_ sender: Any) {
        if let a = hexIn(hex: textDeviceAddress.stringValue), (a > 0), (a < 0x600) {
            if (machine.device(from: a) == nil) {
                textDeviceAddress.backgroundColor = NSColor.textBackgroundColor
                cellDeviceAddress.backgroundColor = NSColor.textBackgroundColor
                labelAddressStatus.stringValue = ""
                return
            }
            labelAddressStatus.stringValue = "Address in Use"
        }
        else {
            labelAddressStatus.stringValue = "Invalid Address"
        }
        cellDeviceAddress.backgroundColor = textDeviceAddress.backgroundColor
        textDeviceAddress.backgroundColor = NSColor(red: 1, green: 0, blue: 0, alpha: 0.2)
        labelAddressStatus.textColor = NSColor.red
    }

    
    @IBAction func buttonCancel(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    @IBAction func pathButtonClick(_ sender: Any) {
        var openPanel: NSSavePanel!
        
        let type = Device.DType(rawValue: Device.DType.value(prefix: comboDeviceType.stringValue))!

        let p = textPath.stringValue
        let directory = (p == "") ? machine.tapeURL : URL(fileURLWithPath: p).deletingLastPathComponent()
        
        if (type == .mt) {
            let ring: Bool = siggyApp.alertYesNo(message: "Mount with Ring?", detail: "Is this tape to be written?", yesText: "WRITE", noText: "READ")
            if (ring) {
                openPanel = NSSavePanel()
                openPanel.message                 = "Select Ouput .tap File"
            }
            else {
                openPanel = NSOpenPanel();
                openPanel.message                 = "Select .mt or .tap format Media"
            }
            openPanel.directoryURL = directory
            openPanel.treatsFilePackagesAsDirectories = true
            openPanel.showsResizeIndicator    = true
            openPanel.showsHiddenFiles        = true
            openPanel.canCreateDirectories    = ring
            openPanel.allowedFileTypes        = ["tap", "mt"]
            openPanel.allowsOtherFileTypes    = true
        }
        else if (type == .dc) || (type == .dp)  {
            let ext = (type == .dc) ? ".dc" : ".dp"
            let ro: Bool = siggyApp.alertYesNo(message: "Mount Read-Only?", detail: "Prevent data from being changed?", yesText: "READ", noText: "UPDATE")
            if (!ro) {
                openPanel = NSSavePanel()
                openPanel.message                 = "Select Ouput \(ext) File"
            }
            else {
                openPanel = NSOpenPanel();
                openPanel.message                 = "Select \(ext) format Media"
            }
            openPanel.directoryURL            = directory
            openPanel.treatsFilePackagesAsDirectories = true
            openPanel.showsResizeIndicator    = true
            openPanel.showsHiddenFiles        = true
            openPanel.canCreateDirectories    = !ro
            openPanel.allowedFileTypes        = ["dp", "dc"]
            openPanel.allowsOtherFileTypes    = true
        }
        
        else {
            openPanel = NSOpenPanel();
            openPanel.message                 = "Select Media"
            openPanel.directoryURL = directory
            openPanel.canCreateDirectories = true
        }
        
        let result = openPanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = openPanel.url {
            var p = url.path
            if (url.deletingLastPathComponent() == machine.url) {
                // Save as relative path
                p = "./"+url.lastPathComponent
            }
            textPath.stringValue = p
            machine.tapeURL = url.deletingLastPathComponent()
        }
    }
    
    @IBAction func buttonDone(_ sender: Any) {
        if let a = hexIn(hex: textDeviceAddress.stringValue), (a > 0), (a < 0x600) {
            if !newDevice || (machine.device(from: a) == nil) {
                settings.type = Device.DType(rawValue: Device.DType.value(prefix: comboDeviceType.stringValue))!
                settings.iop = UInt8(a >> 8)
                settings.unit = UInt8(a & 0xFF)
                settings.trace = checkTrace.state == .on
                settings.name =  Device.DType.prefix[settings.type.rawValue] + String(format:"%X",settings.iop+(settings.type.isMultiplexed ? 10 : 0)) + String(format:"%02X",settings.unit)
                settings.model = Int(comboModel.stringValue) ?? 0
                settings.path = textPath.stringValue
                settings.cocParms = nil
                settings.lpParms = ""
                settings.showVFC = false
                
                switch (settings.type) {
                case .me:
                    let interrupt = UInt8(hexIn64(comboCOCInterrupt.stringValue, ignoreLeading: ["."]) ?? 0xFE)
                    settings.cocParms = COCDevice.COCConfiguration(interruptA: interrupt, interruptB: interrupt+1, numberOfLines: UInt8(textCOCLines.integerValue), firstLine: UInt8(textCOCFirstLine.integerValue), autoStart: hexIn64(textCOCAutoStart.stringValue) ?? 0, traceLines: hexIn64(textCOCLineTrace.stringValue) ?? 0)
                case .lp:
                    settings.burst = (checkBurst.state == .on)
                    settings.lpParms = (settings.burst) ? "FONT:\(comboFont.stringValue); PAPER:\(comboPaperSize.stringValue)" :""
                    settings.linesPerPage = textLinesPerPage.integerValue
                    settings.showVFC = controlBool(checkShowVFC)
                    
                case .cp:
                    settings.burst = controlBool(checkSplitPunch)
                    
                case .dp:
                    settings.publicDisk = controlBool(checkPublic)
                    
                default: break
                }
                NSApp.stopModal(withCode: .OK)
            }
            else {
                labelAddressStatus.stringValue = "Device address in use"
            }
        }
        else {
            labelAddressStatus.stringValue = "Invalid Address"
        }
        cellDeviceAddress.backgroundColor = textDeviceAddress.backgroundColor
        textDeviceAddress.backgroundColor = NSColor(red: 1, green: 0, blue: 0, alpha: 0.2)
        labelAddressStatus.textColor = NSColor.red
    }
    
    func runModal (machine: VirtualMachine, device: Device?, deviceList: [Device]) -> NSApplication.ModalResponse{
        if let w = view.window {
            self.machine = machine
            
            var cocUsed: [Int] = []
            for d in deviceList {
                if (d != device), let coc = d as? COCDevice {
                    cocUsed.append(Int(coc.cocConfiguration.interruptA))
                }
            }
                
            comboCOCInterrupt.removeAllItems()
            for i in stride(from: 0x60, to: 0x6E, by: 2) {
                if !cocUsed.contains(i) {
                    comboCOCInterrupt.addItem(withObjectValue: String(format: ".%02X", i))
                }
            }

            comboFont.removeAllItems()
            comboFont.addItem(withObjectValue: "Courier")
            let allFonts = NSFontManager.shared.availableFonts
            for f in allFonts {
                if (NSFontManager.shared.fontNamed(f, hasTraits: .fixedPitchFontMask)) {
                    comboFont.addItem(withObjectValue: f)
                }
            }

            comboPaperSize.removeAllItems()
            comboPaperSize.addItems(withObjectValues: ["Printer", "A4", "Legal", "Letter", ])
            
            if let d = device {
                newDevice = false
                w.title = d.name
                textDeviceAddress.stringValue = hexOut(d.deviceAddress, width:3)
                textDeviceAddress.isEnabled = false
                comboDeviceType.selectItem(withObjectValue: d.typeString)
                if let p = d as? PDFDevice {
                    checkBurst.state = .on
                    checkShowVFC.state = controlState(p.config.showVFC)
                    textLinesPerPage.integerValue = p.config.linesPerPage
                    comboFont.selectItem(withObjectValue: p.config.fontName)
                    comboPaperSize.selectItem(withObjectValue: p.config.paper.rawValue.capitalized)
                }
                else if let p = d as? LPDevice {
                    checkBurst.state = .off
                    checkShowVFC.state = controlState(p.config.showVFC)
                    textLinesPerPage.integerValue = p.config.linesPerPage
                    comboFont.stringValue = "Font"
                    comboPaperSize.stringValue = "Paper"
                }
                else if let p = d as? CPDevice {
                    checkSplitPunch.state = controlState(p.mode == .directory)
                }
                else if let p = d as? DPDevice {
                    checkPublic.state = controlState(!p.mountable)
                }
               else if let coc = d as? COCDevice {
                    comboCOCInterrupt.selectItem(withObjectValue: String(format: ".%02X", coc.cocConfiguration.interruptA))
                    textCOCLines.integerValue = Int(min(coc.cocConfiguration.numberOfLines,64))
                    textCOCFirstLine.integerValue = Int(min(coc.cocConfiguration.firstLine,64))
                    textCOCLineTrace.stringValue = hexOut(coc.cocConfiguration.traceLines, width: 16)
                    textCOCAutoStart.stringValue = hexOut(coc.cocConfiguration.autoStart, width: 16)
                }
                textPath.stringValue = d.hostPath ?? ""
            }
            else {
                newDevice = true
                w.title = "Create New Device"
                textDeviceAddress.stringValue = ""
                textDeviceAddress.isEnabled = true
                comboDeviceType.selectItem(at: 0)
                textPath.stringValue = ""
            }
            let t = Device.DType.value(prefix: comboDeviceType.stringValue)
            setDeviceDetails(Device.DType(rawValue: t)!)
            labelAddressStatus.stringValue = ""
            return NSApp.runModal(for: w)
        }
        return .abort
    }
}
