//
//  MachineViewController.swift
//  Siggy
//
//  Created by MS on 2023-08-22.
//

import Cocoa
class VMWindowController: NSWindowController {
    // MARK: DO NOT USE AUTOSAVE ON THIS WINDOW. IT SCREWS UP THE SCALE.
    
    func setTitle (_ title: String) {
        self.window?.title = title
    }

}

class VMViewController:  NSViewController, NSWindowDelegate {
    @IBOutlet weak var mainTabViewController: VMTabView!
    
    var mainWindow: NSWindow!
    var mainWindowScale: CGFloat = 1.0
    
    var panelViewController: SiggyPanelController!
    var panelTab: NSTabViewItem!
    
    var debugViewController: DebugViewController!
    var debugTab: NSTabViewItem!
    
    let designSize = CGSize(width: 1200, height: 850)
    let designHead = CGFloat(20)
    
    var machine: VirtualMachine!
    
    func setMachine(_ m: VirtualMachine?) {
        machine = m
        if let dvc = debugViewController {
            dvc.setMachine(m)
        }
        if let pvc = panelViewController {
            pvc.setMachine(m)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Start with the panel.
        if let vc = self.storyboard?.instantiateController (withIdentifier: "SiggyPanelViewController") as? SiggyPanelController {
            panelViewController = vc
            panelTab = NSTabViewItem.init(viewController: vc)
            mainTabViewController.addTabViewItem(panelTab!)
        }
        
        // Add the debug Tab
        if let vc = self.storyboard?.instantiateController (withIdentifier: "DebugViewController") as? DebugViewController {
            debugViewController = vc
            debugTab = NSTabViewItem.init(viewController: vc)
            mainTabViewController.addTabViewItem(debugTab!)
        }
        
        // Show the panel.
        mainTabViewController.selectTabViewItem(panelTab)
        
        // Ready
        let notification = Notification.Name("CPUStepComplete")
        NotificationCenter.default.addObserver(self, selector: #selector(stepComplete), name: notification, object: machine)
    }
            
    override func viewDidAppear() {
        // the window controller should be instantiated by now
        // become the window delegate, so that we can deal with it closing
        if let mw = self.view.window {
            mainWindow = mw
            mw.delegate = self
            if let m = machine {
                mw.title = siggyApp.applicationName + " Processor Control Panel (\(m.name))"
                let px = m.getDoubleSetting("PanelX", 0)
                let py = m.getDoubleSetting("PanelY", 0)
                let pw = m.getDoubleSetting("PanelW", designSize.width)
                let ph = m.getDoubleSetting("PanelH", designSize.height)
                if (pw != designSize.width) || (ph != designSize.height)  {
                    view.scaleUnitSquare(to: NSSize(width: pw/designSize.width, height: ph/designSize.height))
                }
                mw.setFrame(NSRect(origin: CGPoint(x: px,y: py+(designSize.height-ph)), size: CGSize(width: pw, height: ph+designHead)), display: true)
                
            }
        }
        
        view.window?.makeFirstResponder(self)
        
        
    }
    
    
    // WindowDelegate Methods
    func windowShouldClose (_ sender: NSWindow) -> Bool {
        return (siggyApp.alertYesNo(message: "Terminate " + siggyApp.applicationName + "?", detail: "The machine will be stopped!"))
    }
    
    
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            NSLog ("Window closing: "+w.title)
            machine.powerOff()
            siggyApp.machineWindowClosing(machine: machine)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        view.setBoundsSize(designSize)
        if let m = machine, let w = view.window {
            m.set ("PanelW", "\(w.frame.width)")
            m.set ("PanelH", "\(w.frame.height-designHead)")
        }
    }
        
    func windowDidMove(_ notification: Notification) {
        if let w = notification.object as? NSWindow, let m = machine {
            m.set ("PanelX", "\(w.frame.minX)")
            m.set ("PanelY", "\(w.frame.minY)")
        }
    }
    
    
    func resetPanel() {
        if let m = machine, let w = view.window {
            m.set ("PanelW", "\(designSize.width)")
            m.set ("PanelH", "\(designSize.height)")
            view.scaleUnitSquare(to: NSSize(width: designSize.width/w.frame.width, height: designSize.height/w.frame.height))
        }
    }
    
    
    func showDebugTab() {
        mainTabViewController.selectTabViewItem(debugTab)
    }
    
    func showPanelTab() {
        mainTabViewController.selectTabViewItem(panelTab)
    }
    
    var isPanelView: Bool { return (mainTabViewController.selectedTabViewItem == panelTab) }
    var senseSwitches: UInt4 { return panelViewController.senseSwitches }
    
    @objc func powerOn () {
    }

    @objc func stepComplete() {
        // Make sure the panel completion routine is invoked by the main thread, not this one, which is ultimately the CPU thread
        RunLoop.main.perform(panelViewController.stepComplete)
        RunLoop.main.perform(debugViewController.stepComplete)
    }

}
