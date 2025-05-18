//
//  SnapshotViewController.swift
//  Siggy
//
//  Created by MS on 2024-02-21.
//

import Cocoa

class SnapshotViewController: NSViewController {
    @IBOutlet weak var outlineSnapshots: NSOutlineView!
    @IBOutlet weak var textNewSnapshot: NSTextField!
    
    var machine: VirtualMachine!
    var snapshots: [Snapshot] = []
    
    func runModal (_ machine: VirtualMachine!) -> NSApplication.ModalResponse {
        self.machine = machine
        
        if let w = view.window {
            w.title = "Snapshots"
            outlineSnapshots.dataSource = self
            outlineSnapshots.delegate = self
            return NSApp.runModal(for: w)
        }
        return .abort
    }
    
    @IBAction func buttonCreateClick(_ sender: Any) {
        machine.set("SnapshotDate", MSDate().ISO8601Format())
        machine.set("SnapshotPath", machine.url.path)
        machine.takeSnapshot(name: textNewSnapshot.stringValue)
        //snapshots.removeAll()
        //outlineSnapshots.reloadData()
        NSApp.stopModal(withCode: .OK)
    }
    
    @IBAction func buttonRestoreClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let snap = button.cell?.representedObject as? SnapshotView {
            let path = siggyApp.snapshotDirectory.appendingPathComponent(snap.title.stringValue).path
            machine.restoreSnapshot(snapshot: URL(fileURLWithPath: path))
            machine.viewController.showPanelTab()
            NSApp.stopModal(withCode: .OK)
        }
     }
    
    @IBAction func buttonDeleteClick(_ sender: Any) {
        if let button = sender as? NSButton,
           let snap = button.cell?.representedObject as? SnapshotView {
            let path = siggyApp.snapshotDirectory.appendingPathComponent(snap.title.stringValue).path
            if machine.deleteSnapshot(snapshot: URL(fileURLWithPath: path)) {
                snapshots.removeAll()
                outlineSnapshots.reloadData()
            }
        }
    }
    
    @IBAction func buttonCancelClick(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
}

// Objects used to represent a recently opened archive in the outline view.
let SnapshotCellID = NSUserInterfaceItemIdentifier.init("SnapshotCellID")

class SnapshotView: NSTableCellView {
    @IBOutlet weak var date: NSTextField!
    @IBOutlet weak var path: NSTextField!
    @IBOutlet weak var title: NSTextField!
    @IBOutlet weak var deleteSnapshot: NSButton!
    @IBOutlet weak var restoreSnapshot: NSButton!
}

class Snapshot: NSObject {
    let name: String
    let date: MSDate?
    let path: String
    
    init(name: String, date: MSDate?, path: String) {
        self.name = name
        self.date = date
        self.path = path
        super.init()
    }
}

extension Snapshot: Comparable {
    static func < (lhs: Snapshot, rhs: Snapshot) -> Bool {
        if let ld = lhs.date {
            if let rd = rhs.date {
                return ld > rd
            }
            return true
        }
        return false
    }
}

// Extensions to handle the OutlineViewDataSource
extension SnapshotViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if (snapshots.count == 0) {
            let localFileManager = FileManager()
            var isDir: ObjCBool = false
            if localFileManager.fileExists(atPath: siggyApp.snapshotDirectory.path, isDirectory: &isDir) && (isDir.boolValue) {
                let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .producesRelativePathURLs,.skipsSubdirectoryDescendants]
                if let fileEnumerator = localFileManager.enumerator(at: siggyApp.snapshotDirectory, includingPropertiesForKeys: Array(resourceKeys), options: options) {
                    for case let fileURL as URL in fileEnumerator {
                        guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                              let isDirectory = resourceValues.isDirectory, isDirectory
                        else { continue }

                        var date = MSDate(date: resourceValues.contentModificationDate)
                        var path: String = "N/A"
                        let snapDB = SQLDB()
                        
                        
                        if snapDB.open(dbPath: fileURL.appendingPathComponent("siggy.db").path) {
                            let stmt = SQLStatement(snapDB)
                            if stmt.prepare (statement: "SELECT name,value FROM SETTINGS") {
                                while stmt.row() {
                                    if let name = stmt.column_string(0) {
                                        if (name == "SnapshotDate") {
                                            date = MSDate(stmt.column_string(1,defaultValue: ""))
                                        }
                                        else if (name == "SnapshotPath") {
                                            path = stmt.column_string(1, defaultValue: "?")
                                        }
                                    }
                                }
                            }
                            stmt.done()
                            snapDB.close()
                        }
                        snapshots.append(Snapshot(name: fileURL.lastPathComponent, date: date, path: path))
                    }
                    snapshots.sort()
                }
            }
        }
        return snapshots.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return snapshots[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}


extension SnapshotViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        if let view = outlineView.makeView(withIdentifier: SnapshotCellID, owner: self) as? SnapshotView,
           let snapshot  = item as? Snapshot {
            if let title = view.title {
                title.stringValue = snapshot.name
            }
            
            if let date = view.date {
                if let open = snapshot.date {
                    date.stringValue = open.basicDatetimeString("-", ":")
                }
                else {
                    date.stringValue = "Unknown"
                }
            }
            
            if let path = view.path {
                path.stringValue = snapshot.path
            }
            
            view.objectValue = item
            return view
        }
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 100
    }
    
    func outlineShouldChange(in outlineView: NSOutlineView) -> Bool {
        return (true)
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }
        MSLog (level: .debug, "Selected \(outlineView.selectedRow)")
    }
}
