//
//  PasteBufferView.swift
//  Siggy
//
//  Created by MS on 2025-03-17.
//
import Cocoa

private var sharedWindowController: PasteBufferWindowController!
class PasteBufferWindowController: NSWindowController, NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        sharedWindowController = nil
    }
    
    func windowDidResize(_ notification: Notification) {
        if let vc = contentViewController as? PasteBufferViewController,
           let cv = vc.clipView,
           let tv = vc.tableView,
           let tc = vc.columnText {
            var cw: CGFloat = 0
            for c in tv.tableColumns {
                cw += c.width
            }
            tc.width = max(tc.minWidth, cv.frame.width-cw)
        }
    }
    
    
}

func pasteBufferWindow(forMachine: VirtualMachine!,withDelgate: PasteBufferDelegate) -> PasteBufferWindowController? {
    if let swc = sharedWindowController, let vc = swc.contentViewController as? PasteBufferViewController, vc.machine != forMachine {
        swc.close()
        sharedWindowController = nil
    }
    
    if (sharedWindowController == nil),
       let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "PasteBufferWindow") as? PasteBufferWindowController {
        sharedWindowController = wc
    }

    if let wc = sharedWindowController,
       let vc = wc.contentViewController as? PasteBufferViewController {
        vc.loadPasteList(forMachine)
        vc.pasteDelegate = withDelgate
    }

    return sharedWindowController
}

protocol PasteBufferDelegate {
    func pasteText (_ text: String)
}


// Objects used to represent an PasteBuffer ile in the outline view
let PasteBufferCellID = NSUserInterfaceItemIdentifier.init("PasteBuffereCellID")

class PasteBufferView: NSTableCellView {
    @IBOutlet weak var text: NSTextField!
    @IBOutlet weak var buttonDelete: NSButton!
    @IBOutlet weak var buttonEdit: NSButton!
    @IBOutlet weak var buttonPaste: NSButton!
}

class PasteBufferReference: NSObject {
    var text: String
    var id: Int64?
    var group: String?
    
    var view: PasteBufferView!
    
    init(text: String) {
        self.text = text
        self.id = MSDate().gmtTimestamp
        self.group = nil
        super.init()
    }
    
    init (tupple: (id: Int64?, group: String?, text: String?)) {
        self.text = tupple.text ?? ""
        self.id = tupple.id
        self.group = tupple.group
        super.init()
    }
    
}

class PasteBufferViewController: NSViewController, NSWindowDelegate {
    var pasteDelegate: PasteBufferDelegate?

    var machine: VirtualMachine!
    var pbEditor: NSTextField?
    var pasteList: [PasteBufferReference] = []
    
    //MARK: Just one tab for now, maybe later we can split them by command processor?
    @IBOutlet weak var clipView: NSClipView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var columnText: NSTableColumn!
    
    @IBOutlet weak var buttonAdd: NSButton!
    @IBOutlet weak var buttonDelete: NSButton!
    @IBOutlet weak var buttonPaste: NSButton!
    @IBOutlet weak var buttonPasteEnter: NSButton!

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //tableView.delegate = self
        tableView.dataSource = self
    }

    override func viewDidAppear() {
        sharedWindowController.windowDidResize(Notification(name: Notification.Name("viewDidAppear"), object: nil, userInfo: nil))
    }
    
    func loadPasteList(_ m: VirtualMachine!) {
        self.machine = m
        pasteList.removeAll()
        
        while let p = m.getPasteBuffer() {
            pasteList.append(PasteBufferReference(tupple: p))
        }
        
        tableView.reloadData()
    }

    @IBAction func buttonAddClick(_ sender: Any) {
        pasteList.append(PasteBufferReference(tupple: (MSDate().gmtTimestamp, nil, "...")))
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: pasteList.count-1), byExtendingSelection: false)
    }
    
    @IBAction func buttonDeleteClick(_ sender: Any) {
        pasteList.remove(atOffsets: tableView.selectedRowIndexes)
        tableView.reloadData()
    }
    
    @IBAction func buttonPasteClick(_ sender: Any) {
        let row = tableView.selectedRow
        if (row >= 0) && (row < pasteList.count) {
            pasteDelegate?.pasteText(pasteList[row].text)
        }
    }
    
    @IBAction func buttonPasteEnterClick(_ sender: Any) {
        let row = tableView.selectedRow
        if (row >= 0) && (row < pasteList.count) {
            pasteDelegate?.pasteText(pasteList[row].text+"\n")
        }
    }
    
    @IBAction func buttonCloseClick(_ sender: Any) {
        view.window?.close()
    }
    
}

// Extension for TableViewDelegate
extension PasteBufferViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification)  {
        let n = tableView.selectedRowIndexes.count

        buttonAdd.isEnabled = true
        if (n > 1) {
            buttonPaste.isEnabled = false
            buttonDelete.isEnabled = true
        }
        else if (n > 0) {
            buttonPaste.isEnabled = true
            buttonDelete.isEnabled = true
        }
        else {
            buttonPaste.isEnabled = false
            buttonDelete.isEnabled = false
        }
        buttonPasteEnter.isEnabled = buttonPaste.isEnabled
    }
}

// Extensions to handle the TableViewDataSource
extension PasteBufferViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return pasteList.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if (row >= 0) && (row < pasteList.count) {
            if tableColumn?.identifier == NSUserInterfaceItemIdentifier("N"),
               let id = pasteList[row].id {
                return MSDate(gmtTimestamp: id).formatForDisplay(timeZone: nil, options: [.noTimeZone])
            }

            if tableColumn?.identifier == NSUserInterfaceItemIdentifier("GROUP") {
                return pasteList[row].group ?? ""
            }

            if tableColumn?.identifier == NSUserInterfaceItemIdentifier("TEXT") {
                return pasteList[row].text
            }
        }
        return "***"
    }
   
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if let s = object as? String, tableColumn?.identifier == NSUserInterfaceItemIdentifier("TEXT") {
            pasteList[row].text = s
            if (pasteList[row].id == nil) {
                pasteList[row].id = MSDate().gmtTimestamp
            }
            machine.setPasteBuffer(pasteList[row].id!, pasteList[row].group, pasteList[row].text)
        }
    }
}

