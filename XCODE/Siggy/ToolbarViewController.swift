//
//  ToolbarViewController.swift
//  Siggy
//
//  Created by MS on 2025-04-26.
//

import Cocoa
class SiggyWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    @objc func toggleVisible() {
        if let v = window?.isVisible {
            window?.setIsVisible(!v)
        }
    }
}



class ToolbarViewController: NSViewController {
    @IBOutlet weak var labelPower: NSTextField!
    @IBOutlet weak var labelTime: NSTextField!
    @IBOutlet weak var buttonPanel: NSButton!
    @IBOutlet weak var labelPanel: NSTextField!

    
    
    var machine: VirtualMachine!
    var timer: Timer!
    var startTime: Int64 = 0
    var itemWidth: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        itemWidth = buttonPanel.frame.width
    }
    
    override func viewDidAppear() {
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(timerPop), userInfo: nil, repeats: true)
    }
    
    override func viewDidDisappear() {
        timer.invalidate()
        timer = nil
    }
    
    func setMachine(_ m: VirtualMachine!) {
        self.machine = m
        startTime = machine.startTime
    }
    
    func addWindow(_ w: SiggyWindowController?, label: String? = nil) {
        if let tc = w?.contentViewController as? NSViewController,
           let bm = tc.view.bitmapImageRepForCachingDisplay(in: tc.view.frame) {
            tc.view.cacheDisplay(in: tc.view.frame, to: bm)
            if let cgi = bm.cgImage {
                let image = NSImage(cgImage: cgi, size: tc.view.frame.size)
                
                if let sv = buttonPanel.superview,
                   let f = view.window?.frame {
                    
                    let button = NSButton(image: image, target: w, action: #selector(SiggyWindowController.toggleVisible))
                    button.setButtonType(.momentaryPushIn)
                    button.imagePosition = .imageOnly
                    button.bezelStyle = .smallSquare
                    button.setFrameSize(buttonPanel.frame.size)
                    button.image = image
                    button.setFrameOrigin(NSPoint(x: f.width, y:0))
                    sv.addSubview(button)
                    
                    let label = NSTextField(labelWithString: label ?? w?.window?.title ?? "?")
                    label.font = labelPanel.font
                    label.setFrameSize(labelPanel.frame.size)
                    label.setFrameOrigin(NSPoint(x: f.width, y: labelPanel.frame.minY))
                    label.target = w
                    sv.addSubview(label)
                    
                    var newFrame = f
                    newFrame.size.width += itemWidth
                    view.window?.setFrame(newFrame, display: true)
                }
            }
        }
    }
    
    func removeWindow (_ w: SiggyWindowController?) {
        if let sv = buttonPanel.superview {
            if let b = sv.subviews.first(where: { (v) -> Bool in
                if let b = v as? NSButton {
                    return (b.target as? SiggyWindowController == w)
                }
                return false
            })
            {
                let fillX = b.frame.minX
                for sub in  sv.subviews {
                    if let c = sub as? NSControl {
                        if (w == c.target as? SiggyWindowController) {
                            c.removeFromSuperview()
                        }
                        else {
                            if (c.frame.origin.x > fillX) {
                                c.frame.origin.x -= itemWidth
                            }
                        }
                    }
                }
                
                var newFrame = view.window!.frame
                newFrame.size.width -= itemWidth
                view.window?.setFrame(newFrame, display: true)
            }
        }
    }
    
    func updateButtons() {
        for v in buttonPanel.superview!.subviews {
            if let b = v as? NSButton {
                if (b == buttonPanel),
                   let pv = machine.pViewController,
                   let bm = pv.view.bitmapImageRepForCachingDisplay(in: pv.view.frame) {
                    pv.view.cacheDisplay(in: pv.view.frame, to: bm)
                    if let cgi = bm.cgImage {
                        let image = NSImage(cgImage: cgi, size: pv.view.frame.size)
                        b.image = image
                    }
                }
                else if let tc = b.target?.contentViewController as? NSViewController,
                   let bm = tc.view.bitmapImageRepForCachingDisplay(in: tc.view.frame) {
                    tc.view.cacheDisplay(in: tc.view.frame, to: bm)
                    if let cgi = bm.cgImage {
                        let image = NSImage(cgImage: cgi, size: tc.view.frame.size)
                        b.image = image
                    }
                }
            }
        }
    }
    
    
    @objc func timerPop() {
        let uptime = MSClock.shared.gmtTimestamp() - startTime
        var s = uptime / MSDate.ticksPerSecond64
        var m = s / 60
        s = s % 60
        let h = m / 60
        m = m % 60
        labelTime.stringValue = String(format: "%02d:%02d", m, s)
        if (s == 0) {
            if (h > 0) {
                labelPower.stringValue = "Power On: \(h) hour" + ((h > 1) ? "s" : "")
            }
            updateButtons()
        }
    }
    
    
    @IBAction func buttonPanelClick(_ sender: Any) {
        if let w = machine.pViewController.mainWindow {
            w.setIsVisible(!w.isVisible)
        }
    }
}
