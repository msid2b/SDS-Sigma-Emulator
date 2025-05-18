//
//  AboutViewController.swift
//  Siggy
//
//  Created by MS on 2025-04-09.
//

import Cocoa

class AboutViewController: NSViewController {
    
    @IBOutlet var textCredit: NSTextView!
    @IBOutlet weak var labelVersion: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    @IBAction func buttonOKClick(_ sender: Any) {
        NSApp.stopModal(withCode: .OK)
        view.window?.close()
    }
    
    func runModal (_ machine: VirtualMachine!) -> NSApplication.ModalResponse {
        if let w = view.window {
            w.title = "Machine Settings"
            labelVersion.stringValue = "Version 2.0 - "+applicationCompileDate()+", "+applicationCompileTime()
            if let t = textCredit.textStorage,
               let u = siggyApp.bundle?.url(forResource: "About", withExtension: "rtf") {
                do {
                    try t.read(from: u, options: [:], documentAttributes: nil, error: ())
                }
                catch { }
            }
            return NSApp.runModal(for: w)
        }
        return .abort
    }
}
