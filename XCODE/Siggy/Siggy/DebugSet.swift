//
//  DebugSet.swift
//  Siggy
//
//  Created by MS on 2025-02-23.
//
import Cocoa


class DebugSetViewController: NSViewController {
    @IBOutlet weak var registerTableView: NSTableView!
    @IBOutlet weak var registerScrollView: NSScrollView!
    
    @IBOutlet weak var psd2: NSTextField!
    @IBOutlet weak var psd1: NSTextField!
    
    
    var cpu: CPU!
    var psd: UInt64 = 0
    var dsRegisters: DSRegisterSet!
    
    func runModal (_ cpu: CPU!) -> NSApplication.ModalResponse {
        if let w = view.window {
            w.title = "Set Execution State"
            
            psd = cpu.psd.value
            psd1.stringValue = hexOut(psd >> 32, width:8)
            psd2.stringValue = hexOut(psd & 0xFFFFFFFF, width:8)
            
            if (dsRegisters == nil) {
                dsRegisters = DSRegisterSet(cpu)
            }
            registerTableView.dataSource = dsRegisters
            registerTableView.reloadData()
            
            return NSApp.runModal(for: w)
        }
        return .abort
    }
    
    
    @IBAction func buttonCancelClick(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    @IBAction func buttonApplyClick(_ sender: Any) {
        if let v = hexIn64(psd1.stringValue+psd2.stringValue) {
            cpu.psd = CPU.PSD(v)
            
            
            NSApp.stopModal(withCode: .OK)
        }
    }

}


// TODO: Make register display a tableview, with value and text, maybe allow register set selection.
class DSRegisterSet: NSObject, NSTableViewDataSource {
    var register: [UInt32]
    
    init (_ c: CPU!) {
        register = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]
        for r in 0...15 {
            register[r] = c.getRegisterUnsignedWord(UInt4(r))
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return (16)
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard (row < 16) else { return  "" }
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("NUMBER") {
            return hexOut(row,width:1)
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("VALUE") {
            return hexOut(register[row])
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TEXT") {
            var r = register[row]
            var t: String = ""
            var bx: UInt8 = 0
            while (bx < 4) {
                t = dottedAsciiFromEbcdic(UInt8(r & 0xFF)) + t
                r >>= 8
                bx += 1
            }
            return t
        }
        return ""
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("VALUE") {
            if let s = object as? String {
                if let h = hexIn(hex: s) {
                    register[row] = UInt32(h)
                }
            }
        }
    }
}


