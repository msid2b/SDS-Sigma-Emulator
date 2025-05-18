//
//  AppDelegate.swift
//  Siggy
//
//  Created by MS on 2023-01-30.
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

//  The "application database" is typically located in the user's Library directory
//  It contains various globally applicable settings, and a list of recently used virtual
//  machines.
//
//  TODO: Move each virtual machine to a separate process.

import Cocoa
import UniformTypeIdentifiers

private let siggyApplicationName: String = "MacΣ"
private let siggyApplicationExtension: String = "siggy"


// MARK: This gets initialized when first required, which is before the siggyApp's "applicationWillFInishLaunching" gets called.
var applicationDB = ApplicationDB.shared

class ApplicationDB {
    static let shared = ApplicationDB()
    
    var applicationDBDirectory: URL!
    var applicationSQLDB = SQLDB()
    
    // TODO: Need alternative for Catalina (10.15)

    init() {
        // Sequentialize SQL operations
        sqlSetThreading();
        
        if #available(macOS 12.0, *) {
            var applicationUTType: UTType!
            applicationUTType = UTType.init(exportedAs: "com.ms."+siggyApplicationExtension, conformingTo: .package)
            let url = NSRunningApplication.current.bundleURL!
            
            NSWorkspace.shared.setDefaultApplication(at: url, toOpen: applicationUTType) {
                error in
                guard error == nil else {
                    print("Cannot set default Application:"+error!.localizedDescription)
                    print(error!)
                    return
                }
            }
        }
        
        
        applicationDBDirectory = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dbPath = applicationDBDirectory.appendingPathComponent(siggyApplicationName+".db").path
        if !applicationSQLDB.open(dbPath: dbPath) {
            MSLog (level: .always, "Cannot open database: "+dbPath)
            siggyApp.applicationDBSQLError("Application database open failed")
            NSApp.terminate(nil)
            return
        }
        MSLog (level: .always, "Opened application database: "+dbPath)
        
        if !applicationSQLDB.execute("CREATE TABLE IF NOT EXISTS SETTINGS (name TEXT PRIMARY KEY, value TEXT)") {
            siggyApp.applicationDBSQLError("Cannot create SETTINGS table")
            NSApp.terminate(nil)
            return
        }
    }
    
    // MARK: Application Settings
    func setGlobalSetting (_ name: String,_ value: String) {
        let stmt = SQLStatement(applicationSQLDB)
        
        if !stmt.prepare (statement: "INSERT OR REPLACE INTO SETTINGS (name, value) VALUES (?,?)") {
            siggyApp.applicationDBSQLError ("INSERT PREPARE failed");
            return
        }
        
        stmt.bind_string (1, name)
        stmt.bind_string (2, value)
        
        if !stmt.execute() {
            siggyApp.applicationDBSQLError ("INSERT OR REPLACE failed")
        }
        stmt.done()
    }
    
    func getGlobalSetting (_ name: String) -> String? {
        let stmt = SQLStatement(applicationSQLDB)
        
        if !stmt.prepare (statement: "SELECT value FROM SETTINGS WHERE name = ?") {
            siggyApp.applicationDBSQLError ("SELECT PREPARE failed");
            return "";
        }
        
        stmt.bind_string (1, name)
        
        if stmt.row() {
            let result = stmt.column_string(0)
            stmt.done()
            return result
        }
        stmt.done()
        return nil;
    }

    // Get a global setting but provide a default value
    func getGlobalSetting (_ name: String, _ d: String) -> String {
        if let v = getGlobalSetting(name) {
            return v
        }
        return (d)
    }
}


//MARK: AppDelegate begins here
let siggyApp = NSApplication.shared.delegate as! AppDelegate
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var bundle: Bundle?
    var storyboard: NSStoryboard? = nil
    var compilationDate: String = "?"
    var applicationName: String = siggyApplicationName
    var applicationExtension: String = siggyApplicationExtension
    
    var standardFont: NSFont! = NSFont(name: "Menlo", size: 13)
    var startViewController: SiggyStartViewController!
    
    var snapshotDirectory: URL!
    
    var openWith: Bool = false
    var machineList: [VirtualMachine?] = []
    var machineIcon: NSImage?
    
    var cardReaderIcon: NSImage?
    var linePrinterIcon: NSImage?
    var tapeDriveIcon: NSImage?
    var diskDriveIcon: NSImage?
    
    @IBOutlet weak var menuRestoreSnapshot: NSMenuItem!
    @IBOutlet weak var menuExecution: NSMenuItem!
    @IBOutlet weak var menuExecutionRun: NSMenuItem!
    @IBOutlet weak var menuExecutionRunUntil: NSMenuItem!
    @IBOutlet weak var menuExecutionSet: NSMenuItem!
    
    @IBOutlet weak var menuExecutionStepSingle: NSMenuItem!
    @IBOutlet weak var menuExecutionStepBranchPassed: NSMenuItem!
    @IBOutlet weak var menuExecutionStepBranchTaken: NSMenuItem!


    override init() {
        super.init()
        
        // SET logging directory and file prefix, before ApplicationDB.
        MSLogManager.shared.setLogDirectory(applicationName+".logs")
        MSLogManager.shared.setLogPrefix(applicationName)
    }
    
    func alert(_ style: NSAlert.Style, message: String, detail: String) {
        if Thread.isMainThread {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = message
            alert.informativeText = detail
            alert.addButton(withTitle: "OK")
            alert.runModal();
        }
        else {
            MSLog(level: .always, message)
            MSLog(level: .always, detail)
        }
    }
    
    func alertYesNo (message: String, detail: String, yesText: String = "OK", noText: String = "Cancel") -> Bool {
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.informational
        alert.messageText = message
        alert.informativeText = detail
        
        alert.addButton(withTitle: yesText)
        alert.addButton(withTitle: noText)
        
        let result = alert.runModal();
        return (result == NSApplication.ModalResponse.alertFirstButtonReturn)
    }
    
    func alertNoYes (message: String, detail: String, yesText: String = "OK", noText: String = "Cancel") -> Bool {
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.informational
        alert.messageText = message
        alert.informativeText = detail
        
        alert.addButton(withTitle: noText)
        alert.addButton(withTitle: yesText)
        
        let result = alert.runModal();
        return (result == NSApplication.ModalResponse.alertSecondButtonReturn)
    }
    

    func panic(message: String) {
        alert (.critical, message: message, detail: "Application will terminate")
        exit(0)
    }
    
    func debugPopup (message: String) {
        alert (.informational, message: message, detail: "This is a debugging message")
    }
    
    
    // MARK: Errors in catches.
    func FileManagerThrew(_ error: Error, message: String,_ function: String = #function, lineNumber: Int = #line) {
        let e = error.localizedDescription
        MSLog (level: .error, e, function: function, line: lineNumber)
        
        let t = Thread.current
        if (t.isMainThread) {
            alert (.informational, message: message, detail: e)
        }
    }
    
    
    @objc func applicationDBAlert (_ message: String) {
        let e = applicationDB.applicationSQLDB.message
        alert (.warning, message: message, detail: e)
    }
    
    func applicationDBSQLError (_ message: String,_ function: String = #function, lineNumber: Int = #line) {
        // If main thread, do a popup.
        // Log the error in any case.
        let e = applicationDB.applicationSQLDB.message
        MSLog (level: .error, e+": "+message, function: function, line: lineNumber)
        
        if Thread.current.isMainThread {
            applicationDBAlert(message)
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        compilationDate = applicationCompileDate() + ", " + applicationCompileTime();
        
        // Get logging level.
        var logLevel: MSLogManager.LogLevel = .detail
        if let ll = Int(ApplicationDB.shared.getGlobalSetting("LogLevel") ?? "0"), (ll > 0) {
            logLevel = MSLogManager.LogLevel(rawValue: ll) ?? .detail
            MSLogManager.shared.setLogLevel(level: logLevel)
        }
        MSLog (level: .always, siggyApplicationName+" starting.  Logging Level: "+logLevel.name)
        
        // Show readme if not suppressed.
        if let readme = Int(ApplicationDB.shared.getGlobalSetting("README") ?? "0"), (readme == 0) {
            // text-edit (siggy.readme.rtf)
            ApplicationDB.shared.setGlobalSetting("README", "1")
        }
        
        // Get snapshot direectoy
        let lib = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        snapshotDirectory = lib.appendingPathComponent(applicationName+".snapshots")
        
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        bundle = Bundle.main
        storyboard = NSStoryboard(name: "Main", bundle: bundle);
        MSLog (level: .always, "Application did finish launching")
        
        if (MSLogManager.shared.logLevel >= .debug) {
            validateMSDate()
        }
        
        menuRestoreSnapshot.isHidden = true
    }
    
    func startWindowClosing () {
        if machineList.isEmpty {
            NSApp.terminate(self)
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        MSLog (level: .always, "Application will terminate")
    }

    //MARK: About Box
    @IBAction func applicationAbout(_ sender: Any) {
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "SiggyAboutWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? AboutViewController {
            vc.runModal(getCurrentMachine())
        }
    }
    
    // MARK: Dock menu
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return menuFileRecentMenu
    }
    
    // MARK: Check open-with
    func application (_ application: NSApplication, openFile: String) -> Bool {
        let url = URL(fileURLWithPath: openFile)
        let ext = url.pathExtension.lowercased()
        if (ext == applicationExtension) {
            return true
        }
        // we do not know how to open this file.
        return (false)
    }
    
    // MARK: Handle the open-with operation
    func application(_ application: NSApplication, open urls: [URL]) {
        openWith = true
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if (ext == applicationExtension) {
                MSLog (level: .always, "Opening \(url.path)")
                perform (#selector(startMachineWindow), with: url, afterDelay: 0.05)
                //startMachineWindow(url, create: false)
            }
        }
    }
    
    @objc func startMachineWindow (_ url: URL!, create: Bool = false, installBase: Bool = false) {
        for m in machineList {
            if (m!.url == url) {
                m!.showWindow(self)
                MSLog (level: .detail, "\(m!.name) already started: \(url.path)")
                return
            }
        }
        
        let machine = VirtualMachine(url, create, installBase)
        switch machine.openStatus {
        case .ok:
            MSLog (level: .info, "Starting machine for: " + machine.url.path)
            if let wc = storyboard?.instantiateController(withIdentifier: "VMWindowController") as! VMWindowController?,
               let vc = wc.contentViewController as? VMViewController {
                vc.setMachine(machine)
                machine.setViewController(vc)
                machine.showWindow(self)
                machine.powerOn(self)
                machineList.append(machine)                
            }
            
            // Get rid of the startup window, if there is one.
            if let svc = startViewController,
               let wc = svc.view.window {
                wc.close()
                startViewController = nil
            }
            
            let db = applicationDB.applicationSQLDB
            if !db.execute("INSERT OR REPLACE INTO RECENTOPENS (path, name, lastopen) VALUES ('\(url.path)', '\(url.lastPathComponent)', '\(MSDate().ISO8601Format())')") {
                applicationDBSQLError("Cannot update RECENTOPENS table");
            }
            break;
            
        default:
            alert (.warning, message: url.path+" could not be opened", detail: machine.openStatus.rawValue)
            break;
        }
        
        openWith = false
    }
    
    func machineWindowClosing(machine: VirtualMachine!) {
        machineList.removeAll(where: { (x) in return (x == machine)})
        perform(#selector(terminationTest), with: nil, afterDelay: 0.5)
    }
    
    @objc func terminationTest (_ sender: Any?) {
        if machineList.isEmpty {
            NSApp.terminate(self)
        }
    }
    
    
    //MARK: Main Menu
    // Menu items typically act a specific machine
    var menuMachine = NSMenu()
    var menuMachineResult: VirtualMachine?
    @objc func chooseMachine (sender: Any) {
        menuMachineResult = nil             // FIXME: !
    }
    
    var currentMachine: VirtualMachine! { get { return getCurrentMachine() }}
    func getCurrentMachine() -> VirtualMachine? {
        if (machineList.isEmpty) {
            return nil
        }
        menuMachineResult = machineList[0]!
        if (machineList.count > 1) {
            menuMachine.removeAllItems()
            menuMachine.autoenablesItems = false
            for i in 0 ... machineList.count-1 {
                if let m = machineList[i] {
                    let item = NSMenuItem(title: "\(m.name) (\(m.url?.path ?? "?"))", action: #selector(chooseMachine), keyEquivalent: "\(i)")
                    item.tag = i
                    item.target = self
                    item.isEnabled = true
                }
            }
            
            //let position = NSPoint(x: frame.midX, y: frame.maxY)
            if !menuMachine.popUp(positioning: nil, at: NSPoint(x: 500,y: 500), in: nil) {
                return nil
            }
        }
        guard (menuMachineResult?.openStatus == .ok) else { return nil }
        return menuMachineResult
    }

    
    
    // TODO: Is there a preferences window?
    @IBAction func menuPreferences(_ sender: Any) {
    }
    
    @IBOutlet weak var menuEdit: NSMenuItem!
    
    @IBOutlet weak var menuFileRecentMenu: NSMenu!
    @IBOutlet weak var menuFileRecent: NSMenuItem!
    @IBAction func menuFileRecentClick(_ sender: Any) {
    }
    
    
    @IBOutlet weak var menuFileOpen: NSMenuItem!
    @IBAction func menuFileOpenClick(_ sender: Any) {
    }
    
    @IBOutlet weak var menuFileClose: NSMenuItem!
    @IBAction func menuFileCloseClick(_ sender: Any) {
    }
    
    @IBOutlet weak var menuFileSave: NSMenuItem!
    @IBAction func menuFileSaveClick(_ sender: Any) {
    }
    
    @IBOutlet weak var menuFileExport: NSMenuItem!
    @IBAction func menuFileExportClick(_ sender: Any) {
    }
    
    @IBOutlet weak var menuFileImport: NSMenuItem!
    @IBAction func menuFileImportClick(_ sender: Any) {
    }
    
    @IBAction func menuIODevicesClick(_ sender: Any) {
        if let m = currentMachine {
            m.IODeviceWindowStart(self)
        }
    }
    
    var ttyNumber: Int = 1
    @IBOutlet weak var menuNewTerminal: NSMenuItem!
    @IBAction func menuNewTerminalClick(_ sender: Any) {
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "TTYWindow") as? TTYWindowController,
           let vc = wc.contentViewController as? TTYViewController,
           let m = currentMachine {
            if (m.cocStart(vc)) {
                m.addTerminalWindow(wc)
                ttyNumber += 1
                wc.showWindow(self)
            }
            else {
                alert(.warning, message: "Unable to start a COC terminal", detail: "No running COC lines available")
                m.log(level: .error, "Unable to start a COC terminal")
                wc.close()
            }
        }
    }
    
    @IBAction func menuConfigureClick(_ sender: Any) {
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "SettingsWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? SettingsViewController,
           let m = currentMachine {
            let r = vc.runModal (m)
            if (r == .OK)  {
                m.powerOff()
                m.perform(#selector(m.powerOn), with: nil, afterDelay: kPowerOnTime)
            }
            else if (r != .cancel) {
                alert(.informational, message: "You must open a virtual machine in order to configure it", detail: "Double click on the recent machine list, or open or create a new machine")
            }
            wc.close()
        }
    }
    
    // Manage snapshots
    @IBAction func menuSnapshots (_ sender: Any) {
        if let m = currentMachine,
           let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "SnapshotWindow") as! NSWindowController?,
           let vc = wc.contentViewController as? SnapshotViewController {
            if (.OK == vc.runModal (m)) {
                if (m.isRunning) {
                    alert (.informational, message: "Changes will take effect after restart", detail: "")
                }
            }
            wc.close()
        }
        
    }
    
    // Restore a snapshot
    @IBAction func menuRestore(_ sender: Any) {
        if let m = currentMachine {
            let openPanel = NSOpenPanel();
            openPanel.title                   = "Select Snapshot Directory"
            openPanel.directoryURL            = snapshotDirectory
            openPanel.showsResizeIndicator    = true
            openPanel.showsHiddenFiles        = false
            openPanel.canChooseDirectories    = true
            openPanel.canChooseFiles          = false
            openPanel.canCreateDirectories    = false
            openPanel.allowsMultipleSelection = false
            //openPanel.allowedFileTypes        = [];
            if (openPanel.runModal() != NSApplication.ModalResponse.OK) {
                return                          // abort
            }
            
            if let url = openPanel.url {
                m.restoreSnapshot(snapshot: url)
            }
        }
    }
    
    
    // MARK: EXECUTION MENU IS IMLEMENTED USING FIRST RESPONDERS
    
    // MARK: View Menu
    @IBOutlet weak var menuItemProcessorView: NSMenuItem!
    @IBAction func menuProcessorStateClick(_ sender: Any) {
        if let m = currentMachine {
            if m.viewController.isPanelView {
                m.viewController.showDebugTab()
                menuItemProcessorView.title = "Processor Control Panel"
            }
            else {
                m.viewController.showPanelTab()
                menuItemProcessorView.title = "Debugging Window"
            }
        }
    }
    
    @IBAction func menuResetPanelClick(_ sender: Any) {
        if let m = currentMachine {
            let vc = m.viewController
            vc.resetPanel()
        }
    }


    
    @IBAction func LogFileDirectoryClick(_ sender: Any) {
        if let u = MSLogManager.shared.logURL {
            let error:OSStatus = LSOpenCFURLRef(u as CFURL, nil)
            if (error != 0) { NSLog("OSError: \(error), Opening: \(u.path)")}
        }
    }
    
    
    @IBAction func menuPrinterWindow(_ sender: Any) {
        if let m = currentMachine {
            for iop in m.iopTable {
                if let i = iop {
                    for d in i.deviceList {
                        if (d.type == .lp),
                           let p = d as? PDFDevice,
                           let s = p.hostPath {
                            let path = URL(fileURLWithPath: d.resolvePath(s))
                            let error:OSStatus = LSOpenCFURLRef(path as CFURL, nil)
                            if (error != 0) { print("OSError: \(error), Opening: \(path)")}
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func menuPunchWindow(_ sender: Any) {
        if let m = currentMachine {
            for iop in m.iopTable {
                if let i = iop {
                    for d in i.deviceList {
                        if (d.type == .cp),
                           let p = d as? CPDevice,
                           let s = p.hostPath {
                            let path = URL(fileURLWithPath: d.resolvePath(s))
                            let error:OSStatus = LSOpenCFURLRef(path as CFURL, nil)
                            if (error != 0) { print("OSError: \(error), Opening: \(path)")}
                        }
                    }
                }
            }
        }
    }
    
    @IBOutlet weak var menuToolbar: NSMenuItem!
    @IBAction func menuToolbarClick(_ sender: Any) {
        if let m = currentMachine {
            if (menuToolbar.state == .off) {
                menuToolbar.state = .on
                m.toolbarStart()
            }
            else {
                menuToolbar.state = .off
                m.toolbarStop()
            }
        }
    }
    
    
    
    //MARK: REPORTS
    func getReportDestination (_ m: VirtualMachine!,_ filename: String) -> URL? {
        var openPanel: NSSavePanel!
        
        openPanel = NSSavePanel()
        openPanel.message                 = "Save report"
        
        openPanel.directoryURL            = m.reportURL
        openPanel.nameFieldStringValue    = filename
        openPanel.treatsFilePackagesAsDirectories = true
        openPanel.showsResizeIndicator    = true
        openPanel.showsHiddenFiles        = true
        openPanel.canCreateDirectories    = true
        openPanel.allowedFileTypes        = ["pdf"]
        openPanel.allowsOtherFileTypes    = true
        
        let result = openPanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = openPanel.url {
            m.reportURL = url.deletingLastPathComponent()
            m.set (VirtualMachine.kReportDirectory, m.reportURL.path)
            return url
        }
        return nil
    }

    
    @IBAction func menuInstructionStats (_ sender: Any) {
        if let m = currentMachine, let url = getReportDestination(m, "Instruction Timing") {
            let r = InstructionTimingReport(m, url.path)
            r.start()
        }
    }
    
    
    @IBAction func menuCPVStatus(_ sender: Any) {
        if let m = currentMachine, let url = getReportDestination(m, "Machine Status") {
            let r = SystemStatusReport(m, url.path)
            r.start()
        }
    }

    
}
