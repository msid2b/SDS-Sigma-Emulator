//
//  MainViewController.swift
//  Siggy
//
//  Created by MS on 2023-02-22.
//

import Cocoa

class MainViewController: NSViewController, NSWindowDelegate {

    @IBOutlet weak var mainTabViewController: NSTabView!
    
    var mainWindow: NSWindow!
    var mainWindowScale: CGFloat = 1.0

    var panelViewController: SiggyPanelController!
    var panelTab: NSTabViewItem!
    
    var debugViewController: DebugViewController!
    var debugTab: NSTabViewItem!
    
    var cpu: CPU!
    
    var designX: CGFloat = 1200
    var designY: CGFloat = 850
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        designX = view.frame.width
        designY = view.frame.height
    }
    
    override func viewDidAppear() {
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

        // the window controller should be instantiated by now
        // become the window delegate, so that we can deal with it closing
        mainWindow = self.view.window
        mainWindow.delegate = self
        mainWindow.title = siggyApp.applicationName + " Processor Control Panel"
        
        // Make main view available
        siggyApp.mainViewController = self
        mainWindowScale = siggyApp.defaults.double(forKey: "MainWindowScale")
        if (mainWindowScale < 0.25) { mainWindowScale = 1.0 }
        zoomSize(factor: mainWindowScale)

        // Ready
        perform (#selector(powerOn), with: nil, afterDelay: 0.1)
    }
    
    
    
    // WindowDelegate Methods
    func windowShouldClose (_ sender: NSWindow) -> Bool {
        return (siggyApp.alertYesNo(message: "Terminate " + siggyApp.applicationName + "?", detail: "All will be lost!"))
    }
    
    
    func windowWillClose(_ notification: Notification) {
        siggyApp.startWindowClosing()
    }
        

    // Anon...
    private func zoomSize(factor: CGFloat) {
        if let w = view.window {
            view.scaleUnitSquare(to: NSSize(width: factor, height: factor))
            
            let f = w.frame
            let newRect = NSRect(x: f.minX, y: f.minY, width: f.width*factor, height: f.height*factor)
            w.setFrame(newRect, display: true)
        }
    }
    
    func doZoom() {
        if (mainWindowScale <= 0.35) {
            zoomSize(factor: 1.0/mainWindowScale)
            mainWindowScale = 1.0
        }
        else {
            zoomSize(factor: 0.70)
            mainWindowScale *= 0.70
        }
        siggyApp.defaults.set(mainWindowScale, forKey: "MainWindowScale")
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
        let memory = Memory(pages: 256)
        cpu = CPU(name: "0", realMemory: memory, maxVirtualPages: 256)
        resetIO(cpu)

        // Tell us if it stops
        NotificationCenter.default.addObserver(self, selector: #selector(cpuDidExit), name: .NSThreadWillExit, object: cpu)
        
        // Start it
        cpu.start()
        
        // Now update Panel
        let hex = siggyApp.defaults.string(forKey: "BootDevice")
        let dev = hexIn(hex: hex, defaultValue: 0)
        panelViewController.setBootDevice(dev)
        
        if (dev > 0) {
            cpu.resetSystem()
            cpu.load(dev)
            if (siggyApp.defaults.bool(forKey: "AutoBoot")) {
                cpu.control.release()
                panelViewController.running()
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(stepComplete), name: siggyApp.stepComplete, object: nil)
    }
    
    @objc func stepComplete() {
        // Make sure the panel completion routine is invoked by the main thread, not this one, which is ultimately the CPU thread
        RunLoop.main.perform(panelViewController.stepComplete)
        RunLoop.main.perform(debugViewController.stepComplete)
    }
    
    
    @objc func cpuDidExit() {
        cpu = nil
        //RunLoop.main.perform(panelViewController.cpuFault)
        //RunLoop.main.perform(panelViewController.cpuFault)
    }

}
