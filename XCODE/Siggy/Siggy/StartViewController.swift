//
//  SiggyStartViewController.swift
//  Siggy
//
//  Created by MS on 2023-08-22.
//

import Cocoa
import UniformTypeIdentifiers

class SiggyStartViewController: NSViewController, NSWindowDelegate {
    @IBOutlet weak var imagePanel: NSButton!
    @IBOutlet weak var buttonCreateMachine: NSButton!
    @IBOutlet weak var buttonOpenMachine: NSButton!
    @IBOutlet weak var outlineRecentMachines: NSOutlineView!
    
    var recentOpens: [RecentlyOpenedMachine] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if (siggyApp.openWith) {
            self.view.isHidden = true
        }
        else {
            outlineRecentMachines.dataSource = self
            outlineRecentMachines.delegate = self
            outlineRecentMachines.reloadData()
        }
        siggyApp.startViewController = self
        
        siggyApp.machineIcon = imagePanel.image
        if #available(macOS 11.0, *) {
            if let u = UTType(siggyApp.applicationExtension) {
                siggyApp.machineIcon = NSWorkspace.shared.icon(for: u)
            }
        }
    }
    
    override func viewDidAppear() {
        // the window controller should be instantiated by now
        // become the window delegate, so that we can deal with it closing
        self.view.window?.delegate = self
        
        siggyApp.menuFileOpen.isEnabled = true
        siggyApp.menuFileRecent.isEnabled = false
        siggyApp.menuFileClose.isEnabled = true
//        siggyApp.menuFileSave.isEnabled = false
//        siggyApp.menuFileImport.isEnabled = false
//        siggyApp.menuFileExport.isEnabled = false
    }
    
    func windowWillClose(_ notification: Notification) {
        siggyApp.startWindowClosing()
    }
    
    @IBAction func buttonInstallPCP(_ sender: Any) {
        // Choose
        let savePanel = NSSavePanel();
        savePanel.title                   = "Install Andrews CPCP Virtual Machine";
        savePanel.showsResizeIndicator    = true;
        savePanel.showsHiddenFiles        = false
        savePanel.canCreateDirectories    = true;
        savePanel.allowedFileTypes        = ["siggy"];
        
        let result = savePanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = savePanel.url {
            lockAndLoad (url: url, install: true)
        }}
    
    @IBAction func buttonCreateMachineClick(_ sender: Any) {
        // Choose
        let savePanel = NSSavePanel();
        savePanel.title                   = "Create Virtual Machine"
        savePanel.treatsFilePackagesAsDirectories = false
        savePanel.showsResizeIndicator    = true
        savePanel.showsHiddenFiles        = false
        savePanel.canCreateDirectories    = true;
        savePanel.allowedFileTypes        = [siggyApp.applicationExtension]
        
        let result = savePanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = savePanel.url {
            lockAndLoad (url: url, create: true)
        }
    }
    
    
    @IBAction func buttonOpenMachineClick(_ sender: Any) {
        // Choose
        let openPanel = NSOpenPanel();
        openPanel.message                 = "Select Virtual Machine"
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.showsResizeIndicator    = true
        openPanel.showsHiddenFiles        = false
        openPanel.canChooseFiles          = true
        openPanel.canChooseDirectories    = true
        openPanel.canCreateDirectories    = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedFileTypes        = [siggyApp.applicationExtension]
        
        let result = openPanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = openPanel.url {
            lockAndLoad (url: url, create: false)
        }
    }
    
    
    @IBAction func buttonRemoveClick(_ sender: Any) {
        if let sb = sender as? NSButton,
           let ro = sb.cell?.representedObject as? RecentOpenView,
           let path = ro.path {
            let db = applicationDB.applicationSQLDB
            if !db.execute("DELETE FROM RECENTOPENS WHERE path = '\(path.stringValue)'") {
                siggyApp.applicationDBSQLError("Cannot update RECENTOPENS table");
            }
            recentOpens.removeAll()
            outlineRecentMachines.reloadData()
        }
    }

    @IBAction func outlineRecentMachinesDoubleClick(_ sender: Any) {
        let selectedIndex = outlineRecentMachines.selectedRow
        if let item = outlineRecentMachines.item(atRow: selectedIndex) as? RecentlyOpenedMachine {
            let db = applicationDB.applicationSQLDB
            if !db.execute("UPDATE RECENTOPENS SET lastopen = '\(MSDate().displayString)' WHERE path = '\(item.path)'") {
                siggyApp.applicationDBSQLError("Cannot update RECENTOPENS table");
            }
            lockAndLoad(url: URL(fileURLWithPath: item.path), create: false)
        }
    }

    func lockAndLoad (url: URL, create: Bool = false, install: Bool = false) {
        // Lock the other controls.
        outlineRecentMachines.isEnabled = false
        buttonCreateMachine.isEnabled = false
        buttonOpenMachine.isEnabled = false

        siggyApp.startMachineWindow(url, create: (create || install), installBase: install)
        
        // Now unlock
        outlineRecentMachines.isEnabled = true
        buttonCreateMachine.isEnabled = true
        buttonOpenMachine.isEnabled = true
    }

}


// Objects used to represent a recently opened archive in the outline view.
let RecentOpenCellID = NSUserInterfaceItemIdentifier.init("RecentOpenCellID")

class RecentOpenView: NSTableCellView {
    @IBOutlet weak var dateOpened: NSTextField!
    @IBOutlet weak var path: NSTextField!
    @IBOutlet weak var removeSiggy: NSButton!
}

class RecentlyOpenedMachine: NSObject {
    let name: String
    let dateOpened: MSDate?
    let path: String
    
    init(name: String, dateOpened: MSDate?, path: String) {
        self.name = name
        self.dateOpened = dateOpened
        self.path = path
        super.init()
    }
}

// Extensions to handle the OutlineViewDataSource
extension SiggyStartViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if (recentOpens.count == 0) {
            let db = applicationDB.applicationSQLDB
            if !db.execute("CREATE TABLE IF NOT EXISTS RECENTOPENS (path TEXT COLLATE NOCASE PRIMARY KEY, name TEXT, lastopen DATE, caption TEXT)") {
                siggyApp.applicationDBSQLError("Cannot create RECENTOPENS table");
                return 0
            }
            
            let stmtGetRecentOpens = SQLStatement(db)
            if !stmtGetRecentOpens.prepare (statement: "SELECT name, lastopen, path, caption FROM RECENTOPENS ORDER BY lastopen DESC") {
                siggyApp.applicationDBSQLError("Select failed")
                _ = db.execute("DROP TABLE RECENTOPENS")
                return 0
            }
            
            while (stmtGetRecentOpens.row()) {
                let name = stmtGetRecentOpens.column_string(0)
                let open = stmtGetRecentOpens.column_msdate(1)
                let path = stmtGetRecentOpens.column_string(2)
                
                if (name != nil) {
                    recentOpens.append(RecentlyOpenedMachine(name: name!, dateOpened: open, path: path ?? ""))
                }
            }
        }
        
        return recentOpens.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return recentOpens[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}


extension SiggyStartViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        if let view = outlineView.makeView(withIdentifier: RecentOpenCellID, owner: self) as? RecentOpenView,
           let recentOpen  = item as? RecentlyOpenedMachine {
            if let textField = view.textField {
                textField.stringValue = recentOpen.name
            }
            
            if let imageView = view.imageView {
                let fileURL = URL(fileURLWithPath: recentOpen.path)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.customIconKey]),
                   let customIcon =  resourceValues.customIcon {
                    imageView.image = customIcon
                }
                else {
                    imageView.image = NSWorkspace.shared.icon(forFile: recentOpen.path)
                }
                imageView.imageScaling = .scaleProportionallyUpOrDown
            }
            
            if let date = view.dateOpened {
                if let open = recentOpen.dateOpened {
                    date.stringValue = open.basicDatetimeString("-", ":")
                }
                else {
                    date.stringValue = "Never opened"
                }
            }
            
            if let path = view.path {
                path.stringValue = recentOpen.path
            }
            
            view.objectValue = item
            return view
        }
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 80
    }
    
    func outlineShouldChange(in outlineView: NSOutlineView) -> Bool {
        return (true)
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }
        
        let selectedIndex = outlineView.selectedRow
        if let item = outlineView.item(atRow: selectedIndex) as? RecentlyOpenedMachine {
            MSLog(level: .debug, "Selected: \(item.description)")
        }
    }
}

