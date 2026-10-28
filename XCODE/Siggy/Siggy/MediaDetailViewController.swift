//
//  MediaDetailViewController.swift
//  Siggy
//
//  Created by ms on 2026-09-03.
//

import Cocoa

class MediaDetailViewController: NSViewController, NSWindowDelegate {


    @IBOutlet weak var labelLabel: NSTextField!
    @IBOutlet weak var tabViewDetails: NSTabView!
    
    @IBOutlet weak var tabItemOther: NSTabViewItem!
    @IBOutlet weak var tabItemDisk: NSTabViewItem!
    @IBOutlet weak var tabItemTape: NSTabViewItem!
    
    @IBOutlet weak var labelMounted: NSTextField!
    @IBOutlet weak var labelModel: NSTextField!
    @IBOutlet weak var labelGeometry: NSTextField!
    @IBOutlet weak var utilization: NSLevelIndicator!
    
    @IBOutlet weak var labelGranules: NSTextField!
    @IBOutlet weak var labelFreeGranules: NSTextField!

    @IBOutlet weak var labelUsed: NSTextField!
    @IBOutlet weak var labelBitmap: NSTextField!
    @IBOutlet weak var labelSpaceUtilization: NSTextField!
    
    @IBOutlet weak var labelSecondaryVolumes: NSTextField!
    @IBOutlet weak var labelPrimaryVolume: NSTextField!
    @IBOutlet weak var labelAccountList: NSTextField!

    @IBOutlet weak var buttonInitialize: NSButton!
    var buttonInitializeImage: NSImage!
    
    var statusTimer: Timer?
    var device: Device!
    var totalSize: Int = 0
    var accounts: String = ""
    var sns: String = ""
    
    func windowWillClose(_ notification: Notification) {
        if let device = self.device as? RandomAccessDevice {
            device.mediaViewController = nil
        }
    }
    
    func windowDidResize(_ notification: Notification) {
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buttonInitializeImage = buttonInitialize.image
    }
    
    override func viewDidAppear() {
        statusTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(statusTimerPop), userInfo: nil, repeats: true)
        view.window?.makeFirstResponder(self)
    }

    override func viewDidDisappear() {
        statusTimer?.invalidate()
    }

    func setDevice(_ d: Device?) {
        self.device = d
        labelMounted.stringValue = device.name
        labelModel.stringValue = "Model "+String(device.model)
        if let device = d as? RandomAccessDevice {
            device.mediaViewController = nil
            tabViewDetails.selectTabViewItem(tabItemDisk)
            
            labelBitmap.stringValue = ""
            labelUsed.stringValue = ""
            labelFreeGranules.stringValue = ""
            labelAccountList.stringValue = "*Unavailable*"
            labelPrimaryVolume.stringValue = "Primary Volume Unknown"
            labelSecondaryVolumes.stringValue = "No Secondary Volumes"

            utilization.integerValue = 0
            
            if let sc = device.configuration as? RandomAccessDevice.StorageConfiguration {
                labelGeometry.stringValue = String(sc.cylinders) + " Cylinders, " + String(sc.heads) + " Heads, " + String(sc.sectorsPerTrack) + " Sectors / Track"
                totalSize = sc.logicalSPC * sc.cylinders / 2
                labelGranules.stringValue = String(totalSize) + " Total Granules"
            }
            buttonInitialize.isEnabled = false
            buttonInitialize.image = nil
        }
        else if (device is BlockDevice) {
            tabViewDetails.selectTabViewItem(tabItemTape)
        }
        else {
            tabViewDetails.selectTabViewItem(tabItemOther)
        }
        
        
        statusTimerPop()
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(statusTimerPop), userInfo: nil, repeats: true)
    }
    
    @objc func statusTimerPop() {
        if (device is RandomAccessDevice) {
            displayDiskMediaDetails()
        }
        else if (device is BlockDevice) {
            displayTapeMediaDetails()
        }
        else {
            displayDeviceMediaDetails()
        }
    }
    
    func displayDeviceMediaDetails() {
        
    }
 
    func displayTapeMediaDetails() {
        
    }

    func displayDiskMediaDetails() {
        if let dp = device as? DPDevice,
           let g0 = dp.granule0 as? NSData {
            let w = UnsafeRawPointer(g0.bytes)
            let labelSentinel = w.loadUnaligned(fromByteOffset: 0,as: UInt32.self).bigEndian
            if (labelSentinel != 0x7AD3C2D3) {
                labelLabel.stringValue = "????"
                buttonInitialize.isEnabled = true
                buttonInitialize.image = buttonInitializeImage
            }
            else {
                //TODO: IF CP-V HAS BOOTED, CHECK PARTITIONING STATUS
                buttonInitialize.isEnabled = (device.machine.monitorReferences == nil)
                buttonInitialize.image = buttonInitializeImage

                let label = w.loadUnaligned(fromByteOffset: 4,as: UInt32.self).bigEndian
                labelLabel.stringValue = ebcdicWordToString(label)
                
                let ngc = Int(w.loadUnaligned(fromByteOffset: 16,as: UInt16.self).bigEndian)
                let tlc = totalSize / ngc
                labelGranules.stringValue = String(totalSize) + " Total Granules, " + String(ngc) + " granules per logical cylinder, " + String(tlc) + " total cylinders"

                let mapwd = Int(w.loadUnaligned(fromByteOffset: 24, as: UInt16.self).bigEndian)
                let mapwl = Int(w.loadUnaligned(fromByteOffset: 18, as: UInt16.self).bigEndian)
                labelBitmap.stringValue = "Bitmap starts at word " + String(mapwd) + ", length " + String(mapwl) + " words"
                let gbms = ((tlc+31) >> 5)
                if (gbms != mapwl) {
                    labelBitmap.stringValue += " ** SHOULD BE: " + String(gbms) + " WORDS **"
                }
                
                var free = 0
                var i = 0
                while (i < mapwl) {
                    let mapword = w.loadUnaligned(fromByteOffset: (mapwd+i) << 2, as: UInt32.self)
                    free += mapword.nonzeroBitCount
                    i += 1
                }
                
                let used = tlc - free
                labelUsed.stringValue = String(used) + " cylinders are allocated (" + String(used * 100 / tlc) + "%)"
                
                utilization.integerValue = -(free * 100 / tlc)
                labelFreeGranules.stringValue = "(" + String(free * ngc) + " free granules)"
                
                var isPrimary = false
                if sns.isEmpty {
                    let snt = mapwd + mapwl
                    let snCount = min(31, w.loadUnaligned(fromByteOffset: (snt << 2), as: UInt32.self).bigEndian)
                    let psn = w.loadUnaligned(fromByteOffset: (snt+1) << 2, as: UInt32.self).bigEndian
                    sns = ebcdicWordToString(psn)
                    
                    var i = 2
                    while (i <= snCount) {
                        let n = w.loadUnaligned(fromByteOffset: (snt+i) << 2, as: UInt32.self).bigEndian
                        sns.addToCommaSeparatedList(ebcdicWordToString(n))
                        i += 1
                    }
                    
                    if (psn == label) {
                        isPrimary = true
                        labelPrimaryVolume.stringValue = "This volume is primary"
                    }
                    else {
                        labelPrimaryVolume.stringValue = "Primary volume: " + ebcdicWordToString(psn)
                    }
                    
                    if (snCount > 1) {
                        labelSecondaryVolumes.stringValue = "Volumes in set: " + sns
                    }
                    else {
                        labelSecondaryVolumes.stringValue = "No secondary volumes"
                    }
                }
                
                
                
                if accounts.isEmpty && isPrimary {
                    if let g1 = dp.granule1 as? NSData {
                        let w = UnsafeRawPointer(g1.bytes)
                        if (w.loadUnaligned(fromByteOffset: 0, as: UInt64.self) != 0) {
                            labelAccountList.stringValue = "*INVALID FLINK/BLINK*"
                        }
                        else {
                            let nav = w.loadUnaligned(fromByteOffset: 8, as: UInt16.self).bigEndian
                            var koff = 12
                            while (koff < nav) {
                                let ac1 = w.loadUnaligned(fromByteOffset: koff+4, as: UInt32.self).bigEndian
                                let ac2 = w.loadUnaligned(fromByteOffset: koff+8, as: UInt32.self).bigEndian
                                let ac = ebcdicWordToString(ac1)+ebcdicWordToString(ac2)
                                accounts.addToCommaSeparatedList(ac.trimmingCharacters(in: [" "]))
                                koff += 21
                            }
                            labelAccountList.stringValue = accounts
                        }
                    }
                    else {
                        labelAccountList.stringValue = "*Unavailable*"
                    }
                }
            }
        }
    }

    @IBAction func buttonInitializeClick(_ sender: Any) {
        if let d = device as? DPDevice {
            let vc = MediaInitializeController(nibName: nil, bundle: nil)
            let wc = SiggyWindowController(window: NSWindow(contentViewController: vc))
            wc.window?.title = device.name
            wc.windowFrameAutosaveName = "MediaInitialize"
            wc.window?.delegate = vc
            if (vc.runModal(d, label: stringToEbcdicWord(labelLabel.stringValue)) == .continue) {
                
                labelLabel.stringValue = ebcdicWordToString(vc.labelEBCDIC)
                labelAccountList.stringValue = "*Unavailable*"
                
                //MARK: Build the VTOC
                let g0 = UnsafeMutablePointer<UInt8>.allocate(capacity: 0x800)
                g0.initialize(repeating: 0, count: 0x800)
                let w = UnsafeMutableRawPointer(g0)
                w.storeBytes(of: UInt32(0x7AD3C2D3).bigEndian, toByteOffset: 0, as: UInt32.self)
                
            }
        }
    }


}
