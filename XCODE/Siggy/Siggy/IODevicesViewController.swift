//
//  IODevicesViewController.swift
//  Siggy
//
//  Created by ms on 2024-11-07.
//

import Cocoa
import AppKit

class IODeviceWindowController: SiggyWindowController {
}


class IODeviceReference: NSObject {
    let device: Device!
    var cell: NSTableCellView!
    
    init(device: Device) {
        self.device = device
        super.init()
    }
    
    var path: String? { get { return device.hostPath }}
    var isWritable: Bool { get { return ((device is BlockDevice) ? (device as? BlockDevice)!.isWritable : false) }}
    var status: String { get { return deviceStatus() }}
    private func deviceStatus() -> String {
        let (m, p, _, details) = device.mediaStatus()
        if (m) {
            var ds = "POSITION: ."+hexOut(p,width:6)
            if (details != "") { ds.addToCommaSeparatedList(details) }
            return ds
        }
        return "NO MEDIA MOUNTED"
    }
    
    var burstOutput: Bool = false
    var showVFC: Bool = false
    var paper: PDFOutputFile.Paper = .printer
    var font: NSFont!
    var linesPerPage: Int = 0
    
    func shouldUpdatePath() -> Bool {
        if let p = path {
            if (device.isInUse) {
                if let t = device as? BlockDevice, t.mountable {
                    if !siggyApp.alertYesNo(message: "Device in Use!", detail: "Click UNLOAD to force dismount", yesText: "UNLOAD") {
                        return false
                    }
                    t.forceUnload()
                    return true
                }
                siggyApp.alert(.warning, message: "Device in Use!", detail: "")
                return false
            }
            
            if siggyApp.alertYesNo(message: "Unload \(device.name)?", detail: "This will remove the connection to "+p) {
                device.unload()
            }
        }
        return true
    }
}

// Objects used to represent items in an outline view
let mediaCellID = NSUserInterfaceItemIdentifier.init("MediaCellID")
class MediaCellView: NSTableCellView {
    @IBOutlet weak var deviceName: NSTextField!
    @IBOutlet weak var path: NSTextField!
    @IBOutlet weak var buttonBrowse: NSButton!
    @IBOutlet weak var buttonPathClear: NSButton!
    @IBOutlet weak var buttonAutomatic: NSButton!
    @IBOutlet weak var ring: NSButton!
    @IBOutlet weak var erase: NSButton!
    @IBOutlet weak var icon: NSImageView!
    @IBOutlet weak var status: NSTextField!
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if (sender.numberOfValidItemsForDrop == 1) {
            let pasteboard = sender.draggingPasteboard
            if let types = pasteboard.types, types.contains(.fileURL) {
                if let item = objectValue as? IODeviceReference,
                   !item.device.isInUse {
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
                let item = objectValue as? IODeviceReference {
                 if let device = item.device {
                     device.unload()
                     return device.load(url.path, mode: .read)
                 }
             }
         }
         return false
    }
    
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    }
    
    override func updateDraggingItemsForDrag(_ sender: (any NSDraggingInfo)?) {
    
    }
}

let printerCellID = NSUserInterfaceItemIdentifier.init("PrinterCellID")
class PrinterCellView: NSTableCellView {
    @IBOutlet weak var deviceName: NSTextField!
    @IBOutlet weak var checkBurst: NSButton!
    @IBOutlet weak var checkShowVFC: NSButton!
    @IBOutlet weak var textLinesPerPage: NSTextField!
    @IBOutlet weak var comboPaper: NSComboBox!
    @IBOutlet weak var comboFont: NSComboBox!
    @IBOutlet weak var buttonShowOutput: NSButton!
}

class IODevicesViewController: NSViewController, NSWindowDelegate, NSTabViewDelegate {
    var machine: VirtualMachine!
    var pathEditor: NSTextField?
    var statusTimer: Timer?

    @IBOutlet weak var ioTabView: NSTabView!
    @IBOutlet weak var mediaTab: NSTabViewItem!
    @IBOutlet weak var printerTab: NSTabViewItem!
    
    @IBOutlet weak var printerOutline: NSOutlineView!
    @IBOutlet weak var mediaOutline:NSOutlineView!

    @IBOutlet weak var mediaView: MediaView!
    @IBOutlet weak var printerView: PrinterView!
    

    func tabView(_ tabView: NSTabView, didSelect: NSTabViewItem?) {
        statusTimer?.invalidate()
        statusTimer = nil
        pathEditor = nil
        
        switch (didSelect) {
        case mediaTab:
            statusTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(statusTimerPop), userInfo: nil, repeats: true)
            mediaOutline.reloadData()
            
        case printerTab:
            printerOutline.reloadData()
            
        default: break
        }
    }
    
    @objc func statusTimerPop() {
        if (mediaOutline.selectedRow >= 0) {
            for i in 0...mediaView.deviceList.count-1 {
                if !mediaOutline.isRowSelected(i) {
                    mediaOutline.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
                }
            }
            return
        }
        mediaOutline.reloadData()
    }

    
    // Configuration
    func configure(_ m: VirtualMachine?) {
        self.machine = m
        mediaView.machine = m
        printerView.machine = m

        mediaOutline.dataSource = mediaView
        mediaOutline.delegate = mediaView
        mediaOutline.reloadData()
        
        printerOutline.dataSource = printerView
        printerOutline.delegate = printerView
        printerOutline.reloadData()

        ioTabView.delegate = self
        if let w = view.window {
            w.delegate = self
        }
        tabView(ioTabView, didSelect: mediaTab)
    }
    
    
// Mountable Devices Tab
    
    @IBAction func buttonClearPathClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           item.shouldUpdatePath() {
            cell.path.stringValue = ""
            mediaOutline.reloadItem(item)
        }
    }
    
    @IBAction func buttonBrowseClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           (item.shouldUpdatePath()) {
            var openPanel: NSSavePanel!

            if let t = item.device as? CRDevice {
                openPanel = NSOpenPanel();
                openPanel.message                 = "Select Media for \(item.device.name)"
                openPanel.directoryURL            = machine.cardURL
                openPanel.treatsFilePackagesAsDirectories = true
                openPanel.showsResizeIndicator    = true
                openPanel.showsHiddenFiles        = true
                openPanel.canCreateDirectories    = false
                openPanel.allowedFileTypes        = ["cr", "txt"]
                openPanel.allowsOtherFileTypes    = true
                
                let result = openPanel.runModal()
                if (result == NSApplication.ModalResponse.OK),
                   let url = openPanel.url {
                    _ = t.load(url.path, mode: .read)
                    machine.cardURL = url.deletingLastPathComponent()
                    machine.set (VirtualMachine.kCardDirectory, machine.cardURL.path)
                    mediaOutline.reloadItem(item)
                }
            }
            else if let t = item.device as? TapeDevice {
                let ring: Bool = siggyApp.alertNoYes(message: "Mount with Ring?", detail: "Is this tape to be written?", yesText: "WRITE", noText: "READ")
                if (ring) {
                    openPanel = NSSavePanel()
                    openPanel.message                 = "Select Ouput .tap File for \(item.device.name)"
                }
                else {
                    openPanel = NSOpenPanel();
                    openPanel.message                 = "Select .mt or .tap format Media for \(item.device.name)"
                }
                openPanel.directoryURL            = machine.tapeURL
                openPanel.treatsFilePackagesAsDirectories = true
                openPanel.showsResizeIndicator    = true
                openPanel.showsHiddenFiles        = true
                openPanel.canCreateDirectories    = ring
                openPanel.allowedFileTypes        = ["tap", "mt"]
                openPanel.allowsOtherFileTypes    = true
                
                let result = openPanel.runModal()
                if (result == NSApplication.ModalResponse.OK),
                   let url = openPanel.url {
                    _ = t.load(url.path, mode: ring ? .update : .read )
                    machine.tapeURL = url.deletingLastPathComponent()
                    machine.set (VirtualMachine.kTapeDirectory, machine.tapeURL.path)
                   mediaOutline.reloadItem(item)
                }
            }
            else if let d = item.device as? RandomAccessDevice {
                let ro: Bool = siggyApp.alertYesNo(message: "Mount Read-Only?", detail: "Prevent data from being changed?", yesText: "READ", noText: "UPDATE")
                if (!ro) {
                    openPanel = NSSavePanel()
                    openPanel.message                 = "Select Ouput .dp File for \(item.device.name)"
                }
                else {
                    openPanel = NSOpenPanel();
                    openPanel.message                 = "Select .dp or .dc format Media for \(item.device.name)"
                }
                openPanel.directoryURL            = machine.diskURL
                openPanel.treatsFilePackagesAsDirectories = true
                openPanel.showsResizeIndicator    = true
                openPanel.showsHiddenFiles        = true
                openPanel.canCreateDirectories    = !ro
                openPanel.allowedFileTypes        = ["dp", "dc"]
                openPanel.allowsOtherFileTypes    = true
                
                let result = openPanel.runModal()
                if (result == NSApplication.ModalResponse.OK),
                   let url = openPanel.url {
                    _ = d.load(url.path, mode: ro ? .read : .update)
                    mediaOutline.reloadItem(item)
                    
                    machine.diskURL = url.deletingLastPathComponent()
                    machine.set (VirtualMachine.kDiskDirectory, machine.diskURL.path)
                }
            }
        }
    }
    
    @IBAction func buttonAutomaticClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference {
                let a = !item.device.dsbAutomatic
                item.device.dsbAutomatic = a
                cell.buttonAutomatic.state = controlState(a)
                mediaOutline.reloadItem(item)
           
        }
    }
    
    @IBAction func buttonEraseClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? BlockDevice,
           let _ = d.hostPath,
           (cell.erase.state == .off) {
            // Light it up.
            cell.erase.state = .on
            mediaOutline.reloadItem (item)
            perform(#selector(buttonErasePart2), with: sender, afterDelay: 1.0)
        }
    }
    
    @objc func buttonErasePart2 (_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? BlockDevice {
            if (d.isInUse) {
                siggyApp.alert(.warning, message: "Device in Use!", detail: "")
                cell.erase.state = .off
                return
            }
            let p = d.resolvePath(d.hostPath ?? "")
            var isDir: ObjCBool = false
            if (!FileManager.default.fileExists(atPath: p, isDirectory: &isDir)) || (isDir.boolValue) {
                siggyApp.alert(.warning, message: "Unable to delete: \"\(d.hostPath ?? "?")\"", detail: isDir.boolValue ? "File is a Directory" : "File does not exist")
                cell.erase.state = .off
                return
            }
            
            if siggyApp.alertYesNo(message: "This will delete the file at \(p)", detail: "A new empty file will be created for writing", yesText: "DELETE") {
                d.unload()
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                }
                catch {
                    siggyApp.FileManagerThrew(error, message: "Could not delete \"\(p)\"")
                }
                _ = d.load (p, mode: .update)
            }
            cell.erase.state = .off
            mediaOutline.reloadItem (item)
        }
    }
    

    @IBAction func buttonRingClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? BlockDevice,
           let p = d.hostPath {
            if (d.isInUse) {
                siggyApp.alert(.warning, message: "Device in Use!", detail: "")
                return
            }

            if (d.isReadOnly) && (d.isWritable) {
                d.unload()
                _ = d.load(p, mode: .update)
            }
            else {
                d.unload()
                _ = d.load(p, mode: .read)
            }
            mediaOutline.reloadItem(item)
        }
    }

    
    //MARK: PRINTERS TAB

    @IBAction func buttonShowVFCClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? PrintDevice {
            d.config.showVFC = controlBool(cell.checkShowVFC)
            machine.updateDeviceDB(from: d)
        }
    }
    
    @IBAction func buttonShowOutputClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let cell = button.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let p = item.device as? PrintDevice,
           let s = p.hostPath {
            let u = URL(fileURLWithPath: p.resolvePath(s))
            let error:OSStatus = LSOpenCFURLRef(u as CFURL, nil)
            if (error != 0) { print("OSError: \(error), Opening: \(u.path)") }
        }
    }
    
    @IBAction func textLinesPerPageChanged(_ sender: Any) {
        if let tf = sender as? NSTextField,
           let cell = tf.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? PrintDevice {
            d.config.linesPerPage = tf.integerValue
            d.applyConfiguration()
            machine.updateDeviceDB(from: d)
        }
    }
    
    @IBAction func comboPaperChanged(_ sender: Any) {
        if let combo = sender as? NSComboBox,
           let cell = combo.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? PrintDevice,
           let p = PDFOutputFile.Paper(rawValue: combo.stringValue.lowercased()) {
            d.config.paper = p
            d.applyConfiguration()
            machine.updateDeviceDB(from: d)
        }
    }
    
    @IBAction func comboFontChanged(_ sender: Any) {
        if let combo = sender as? NSComboBox,
           let cell = combo.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? PrintDevice {
            d.config.fontName = combo.stringValue
            d.applyConfiguration()
            machine.updateDeviceDB(from: d)
        }
    }

    @IBAction func buttonFinishClick(_ sender: Any) {
        if let combo = sender as? NSComboBox,
           let cell = combo.superview as? PrinterCellView,
           let item = cell.objectValue as? IODeviceReference,
           let d = item.device as? PrintDevice {
            d.flush()
        }
    }
    
    
    @IBAction func buttonExitClick(_ sender: Any) {
        statusTimer?.invalidate()
        statusTimer = nil
        machine.IODeviceWindowStop()
        view.window?.close()
    }    
}

class MediaView: NSView, NSOutlineViewDelegate, NSOutlineViewDataSource {
    
    var machine: VirtualMachine?
    var deviceList: [IODeviceReference] = []
    var pathEditor: NSTextField!
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if (deviceList.count == 0), let m = machine {
            for iop in m.iopTable {
                if let i = iop {
                    for d in i.deviceList {
                        if (d.mountable) {
                            let a = IODeviceReference(device: d)
                            deviceList.append(a)
                        }
                    }
                }
            }
        }
        
        return deviceList.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return deviceList[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
    
    
    //MARK:  DELEGATE FUNCTIONS
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let view = outlineView.makeView(withIdentifier: mediaCellID, owner: self) as? MediaCellView,
           let ioDevice = item as? IODeviceReference {
            if let name = view.deviceName {
                name.stringValue = ioDevice.device.name
            }
            
            if let imageView = view.icon {
                switch (ioDevice.device.type) {
                case .lp:
                    imageView.image = NSImage(named: "LinePrinter")
                case .cr:
                    imageView.image = NSImage(named: "CardReader")
                case .cp:
                    imageView.image = NSImage(named: "CardPunch")
                case .mt, .bt:
                    imageView.image = NSImage(named: "TapeDrive")
                case .dp:
                    imageView.image = NSImage(named: "DiskDrive")
                default:
                    imageView.image = nil
                }
                imageView.imageScaling = .scaleProportionallyUpOrDown
            }
            
            if let ready = view.buttonAutomatic {
                ready.state = controlState(ioDevice.device.dsbAutomatic)
            }
            
            if let path = view.path {
                if ioDevice.device is CharacterDevice {
                    path.stringValue = ioDevice.path ?? ""
                    view.ring.isHidden = true
                    view.erase.isHidden = true
                    view.buttonAutomatic.isEnabled = ioDevice.device.isReady()
                    view.buttonAutomatic.state = controlState(ioDevice.device.dsbAutomatic)
                }
                else if let ap = ioDevice.path {
                    path.stringValue = ap
                    view.ring.state = controlState(ioDevice.isWritable)
                    view.ring.isHidden = false
                    view.ring.isEnabled = true
                    view.ring.tag = deviceList.firstIndex(of: ioDevice) ?? -1
                    view.erase.isHidden = false
                }
                else {
                    path.stringValue = ""
                    view.ring.isHidden = false
                    view.ring.state = .off
                    view.ring.isEnabled = false
                    view.erase.isHidden = false
                }
            }
            
            if let status = view.status {
                status.stringValue = ioDevice.status
            }
            
            if let disconnect = view.buttonPathClear {
                if (disconnect.image == nil) {
                    disconnect.title = "X"
                }
            }
            
            view.objectValue = item
            ioDevice.cell = view
            view.registerForDraggedTypes([.fileURL])
            return view
        }
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem: Any) -> Bool
    {
        let row = outlineView.selectedRow
        if (row >= 0),
           let item = outlineView.item(atRow: row) as? IODeviceReference,
           let cell = item.cell as? MediaCellView,
           let p = cell.path,
           let e = pathEditor {
            p.stringValue = e.stringValue
            
            pathEditor?.removeFromSuperview()
            pathEditor = nil
        }
        return true
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }
        
        let row = outlineView.selectedRow
        if let item = outlineView.item(atRow: row) as? IODeviceReference,
           let cell = item.cell as? MediaCellView {
            if let p = cell.path {
                //let o = cell.convert(p.frame.origin, to: cell.superview)
                let o = p.frame.origin
                let s = CGSize(width: p.frame.width , height: p.frame.height)
                let f = NSRect(origin: o, size: s)
                pathEditor = NSTextField(frame: f)
                cell.addSubview(pathEditor!)
                
                pathEditor?.stringValue = p.stringValue
                pathEditor?.textColor = .black
                pathEditor?.alignment = .natural
                pathEditor?.isBordered = false
                pathEditor?.isEnabled = !item.device.isInUse
                pathEditor?.target = self
                pathEditor?.action = #selector(pathEditorChange)
            }
        }
    }
 
    @objc func pathEditorChange(_ sender: Any) {
        if let cell = pathEditor.superview as? MediaCellView,
           let item = cell.objectValue as? IODeviceReference,
           (item.shouldUpdatePath()),
           let rowView = cell.superview as? NSTableRowView,
           let outlineView = rowView.superview as? NSOutlineView,
           let newPath = pathEditor?.stringValue {
            let resolvedPath = item.device.resolvePath(newPath)
            
            let ro = (cell.ring?.state ?? .off) == .off
            if !ro && FileManager.default.fileExists(atPath: resolvedPath) {
                if !siggyApp.alertYesNo(message: "The file \"\(resolvedPath)\" will be overwritten", detail: "") {
                    return
                }
            }
            item.device.hostPath = newPath
            outlineView.reloadItem (item)
            outlineView.deselectAll(sender)
        }
        pathEditor?.removeFromSuperview()
        pathEditor = nil
    }

}



class PrinterView: NSView, NSOutlineViewDelegate, NSOutlineViewDataSource {
    var machine: VirtualMachine?
    var deviceList: [IODeviceReference] = []
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if (deviceList.count == 0), let m = machine {
            for iop in m.iopTable {
                if let i = iop {
                    for d in i.deviceList {
                        if (d is PrintDevice) {
                            let a = IODeviceReference(device: d)
                            deviceList.append(a)
                        }
                    }
                }
            }
        }
        
        return deviceList.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return deviceList[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
    
    
    
    //MARK:  DELEGATE FUNCTIONS
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let cell = outlineView.makeView(withIdentifier: printerCellID, owner: self) as? PrinterCellView,
           let ioDevice = item as? IODeviceReference,
           let printer = ioDevice.device as? PrintDevice {
            if let name = cell.deviceName {
                name.stringValue = ioDevice.device.name
            }

            if let check = cell.checkBurst {
                check.state = controlState(ioDevice.device is PDFDevice)
                check.isEnabled = false
            }
            
            if let check = cell.checkShowVFC {
                check.state = controlState(printer.config.showVFC)
            }
            
            if let lines = cell.textLinesPerPage {
                lines.integerValue = printer.config.linesPerPage
            }
            
            if let pdf = printer as? PDFDevice {
                if let paper = cell.comboPaper {
                    paper.selectItem(withObjectValue: pdf.config.paper.rawValue.capitalized)
                }
                    
                if let font = cell.comboFont {
                    font.removeAllItems()
                    font.addItem(withObjectValue: "Courier")
                    let allFonts = NSFontManager.shared.availableFonts
                    for f in allFonts {
                        if (NSFontManager.shared.fontNamed(f, hasTraits: .fixedPitchFontMask)) {
                            font.addItem(withObjectValue: f)
                        }
                    }
                    font.selectItem(withObjectValue: pdf.config.fontName)
                }
            }
            
            if let show = cell.buttonShowOutput {
                show.isEnabled = true
            }
            
            cell.objectValue = item
            ioDevice.cell = cell
            return cell
        }
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem: Any) -> Bool {
        return true
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
    }
}

