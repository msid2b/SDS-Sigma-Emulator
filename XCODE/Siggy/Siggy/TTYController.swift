//
//  TTYViewController.swift
//  Siggy
//
//  Created by MS on 2023-07-23.
//

import Cocoa
import Foundation

class TTYWindowController: SiggyWindowController {
}


class TTYTextView: NSTextView {
    var foregroundColor: NSColor!
    var viewController: TTYViewController!
    
    var editMode: Bool = false
    var editPosition: Int = 0
    var editColor: NSColor?
    
    var insertMode: Bool = false
    var inputLine: String = ""
    var inputPosition: Int = 0
    
    var previousLine: [String] = []
    var previousIndex: Int = 0
    
    
    func configure (controller: TTYViewController?, foreground: NSColor?) {
        self.viewController = controller!
        self.foregroundColor = foreground!
    }
    
    
    override func keyDown(with event: NSEvent) {
    }
    

    override func keyUp(with event: NSEvent) {
        
        func updateEditLine() {
            if let length = textStorage?.length, (editPosition < length) { textStorage?.deleteCharacters(in: NSRange(editPosition...(length-1))) }
            let aLine = NSMutableAttributedString(string: inputLine, attributes: [.font: font!, .foregroundColor: editColor!])
            //if (inputPosition < inputLine.count) {
            //    aLine.addAttributes([.underlineStyle: NSUnderlineStyle.single], range: NSRange(inputPosition...inputPosition))
            //}
            textStorage?.append(aLine)

            let cursorPosition = editPosition + inputPosition
            setSelectedRange(NSRange(cursorPosition...cursorPosition))
            selectedTextAttributes = insertMode ? [.foregroundColor : foregroundColor!] : [.backgroundColor : editColor!, .foregroundColor : backgroundColor ]
        }

        var eventChars = event.characters
        if let vc = window?.contentViewController as? TTYViewController {
            var handled = false
            if let key = event.specialKey {
                if editMode {
                    handled = true
 
                    switch (key) {
                    case .carriageReturn:           // EXIT edit mode and send the input
                        if let length = textStorage?.length, (editPosition < length) {
                            textStorage?.deleteCharacters(in: NSRange(editPosition...length-1))
                        }
                        vc.pasteText(inputLine.appending(event.characters!))
                        previousLine.append(inputLine)
                        inputLine = ""
                        editMode = false
                        
                    case .upArrow, .downArrow:
                        if (previousLine.count > 0) {
                            if (key == .downArrow) {
                                previousIndex += 1
                                if (previousIndex >= previousLine.count) {
                                    inputLine = ""
                                    editMode = false
                                }
                            }
                            else {
                                previousIndex -= 1
                                if (previousIndex < 0) {
                                    previousIndex = 0
                                }
                            }
                            
                            if (previousIndex >= 0) && (previousIndex < previousLine.count) {
                                inputLine = previousLine[previousIndex]
                                inputPosition = inputLine.count
                            }
                        }
                        
                    case .end:
                        inputLine = ""
                        editMode = false

                        
                    case .leftArrow:
                        if (inputPosition > 0) {
                            inputPosition -= 1
                        }
                        
                    case .rightArrow:
                        inputPosition = min(inputPosition+1, inputLine.count)
                        super.keyUp(with: event)
                        
                    case .delete:
                        if (inputPosition > 0) && (inputLine.count > 0) {
                            inputPosition -= 1
                            inputLine = inputLine.substr(0, inputPosition) + inputLine.substr(inputPosition+1)
                        }

                    case .deleteForward:
                        if (inputLine.count > 0) && (inputPosition < inputLine.count) {
                            inputLine = inputLine.substr(0, inputPosition) + inputLine.substr(inputPosition+1)
                        }
                        
                    case .insert, .tab:
                        insertMode = !insertMode
                        
                    default: break                  // IGNORE
                    }
                    
                    updateEditLine()

                }
                else {
                    // MARK: Not edit mode
                    handled = true
                    
                    switch (key) {
                    case .upArrow:
                        if (inputLine == "") && (!previousLine.isEmpty) {
                            //MARK: Enter edit mode
                            editColor = (foregroundColor == .black) ? NSColor.orange :  foregroundColor.shadow(withLevel: 0.5)
                            editPosition = textStorage!.length
                            editMode = true
                            insertMode = true
                            previousIndex = previousLine.count-1
                            inputLine = previousLine[previousIndex]
                            inputPosition = inputLine.count
                            updateEditLine()
                        }

                    case .delete, .tab, .carriageReturn:
                        handled = false             // ALLOW THESE
                        
                    case .downArrow:
                        eventChars = String(Character(UnicodeScalar(0x0a)))
                        handled = false
                    
                    case .pageUp:
                        self.scrollPageUp(self)

                    case .pageDown:
                        self.scrollPageDown(self)

                    case .home:
                        self.scrollToBeginningOfDocument(self)

                    case .end:
                        self.scrollToEndOfDocument(self)

                    default:                        // IGNORE EVERYTHING ELSE
                        break
                    }
                }
            }
            

            //MARK: Deal with regular keys and unhandled special ones
            if !handled, var s = eventChars {
                if (editMode) {
                    if (vc.checkCapsLock.state == .on) { s = s.uppercased() }
                    
                    if (s.contains(Character(UnicodeScalar(0x1b)))) {
                        //MARK: IGNORE ESCAPE IN EDIT MODE
                    }
                    else if (inputPosition >= inputLine.count) {
                        inputLine.append(String(s))
                        textStorage?.append(NSAttributedString(string: s, attributes: [.font: font!, .foregroundColor: editColor!]))
                        inputPosition += 1
                    }
                    else {
                        if (insertMode) {
                            inputLine = inputLine.substr(0, inputPosition) + s + inputLine.substr(inputPosition)
                        }
                        else {
                            inputLine = inputLine.substr(0, inputPosition) + s + inputLine.substr(inputPosition+1)
                        }
                        inputPosition += 1
                        updateEditLine()
                    }
                }
                else {
                    for c in s {
                        let c = vc.characterInput(c)
                        
                        switch c.asciiValue {
                        case 0x0d:
                            previousLine.append(inputLine)
                            inputLine = ""
                            
                        case 0x18, 0x19:
                            inputLine = ""
                            
                        case 0x7f:
                            if (inputLine.count > 0) {
                                inputLine = inputLine.substr(0, inputLine.count-1)
                            }
                            
                        default:
                            inputLine.append(String(c))
                        }
                    }
                }
            }
        }
    }

    @objc override func paste(_ sender: Any?) {
        viewController?.pasteFromClipBoard(self)
    }
    
    @objc  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch (menuItem.action) {
        case #selector(copy(_:)):
            return (selectedRange().length > 0)
            
        case #selector(paste(_:)):
            return true
            
        case #selector(selectAll):
            return true
            
        default:
            return false
        }
    }

    
    override func resignFirstResponder() -> Bool {
        return false
    }
}

protocol TTYDelegate {
    func machineYear(_ y: Int) -> Int
    func autoSettingChanged(_ id: Int,_ enabled: Bool)
    func characterIn (_ id: Int, _ c: Character, isBreak: Bool)
    func windowShouldClose(_ id: Int) -> Bool
    func windowDidResize(_ id: Int, width: Int, height: Int)
    func windowDidMove(_ id: Int,_ origin: CGPoint)
    func fontDidChange(_ id: Int, fontName: String, fontSize: Double, fgColor:NSColor, bgColor: NSColor)
    func startPasteWindow(_ id: Int)
}

enum TTYOption {
    case auto
    case capsLock
    case interrupt
    case isbreak
}


// MARK: TTY Controller for COC connected terminal.
// MARK: Each character output operation initiated by WD is asyncronous and independent.
// MARK: They are independent threads started from the OutputOperation queue

class TTYViewController: NSViewController, NSWindowDelegate, NSTextViewDelegate, PasteBufferDelegate {
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var clipView: NSClipView!
    @IBOutlet weak var scrollerVertical: NSScroller!
    @IBOutlet weak var textView: TTYTextView!
    @IBOutlet weak var buttonInterrupt: NSButton!
    @IBOutlet weak var labelDisplaySize: NSTextField!
    @IBOutlet weak var boxHeader: NSBox!
    @IBOutlet weak var boxFooter: NSBox!
    @IBOutlet weak var checkCapsLock: NSButton!
    @IBOutlet weak var checkAuto: NSButton!
    @IBOutlet weak var buttonLog: NSButton!
    @IBOutlet weak var buttonPaste: NSButton!
    @IBOutlet weak var labelStatus: NSTextField!
    
    @IBOutlet weak var boxFont: NSBox!
    @IBOutlet weak var comboFont: NSComboBox!
    @IBOutlet weak var textFontSize: NSTextField!
    @IBOutlet weak var sliderFontSize: NSSlider!
    @IBOutlet weak var stepperFontSize: NSStepper!
    @IBOutlet weak var colorBackground: NSColorWell!
    @IBOutlet weak var colorForeground: NSColorWell!

    //MARK: COC for tereminals, ConsoleWindow for Console.
    private var id: Int = -1
    var delegateID: Int { get { return id } set { id = newValue }}
    var delegate: TTYDelegate?
    var name: String?
    let defaultFont = NSFont(name: "Courier", size: 12.0)!
    
    var windowController: TTYWindowController?
    
    let intraCharacterInterval = MSDate.ticksPerMillisecond64
    var lastInputTime: MSTimestamp = 0
    var inputQueue: String = ""
    var isResizing: Bool = false
    
    //MARK: screenWidth and screenHeight refer to the size of the terminal window in CG units
    //MARK: characterWidth and characterHeight refer to the size of each character in CG units
    //MARK: width and height refer to the size of the terminal in characters
    let minScreenHeight: CGFloat = 400
    let minScreenWidth: CGFloat = 800
    
    var logFileHandle: FileHandle?
    var buffer: String = ""
    var access = SimpleMutex()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if (delegate?.windowShouldClose(delegateID) ?? true) {
            return true
        }
        return false
    }

    func setOrigin (_ origin: CGPoint) {
        if let w = view.window {
            w.setFrame (NSRect(origin: origin, size: w.frame.size), display: true)
            w.windowController?.showWindow(self)
        }
    }
    
    
    func updateDisplaySize (_ width: Int,_ height: Int) {
        labelDisplaySize.stringValue = "\(height) Lines X \(width) Characters"
    }
    
    //MARK: Determine the terminal size in number of displayable characters
    func calculateDisplayCharacterSize () -> (Int, Int) {
        if let w = view.window, let f = textView.font {
            let sWidth = max(minScreenWidth, w.frame.width) - scrollView.scrollerInsets.right
            let sHeight = max(minScreenHeight, w.frame.height) - (boxFooter.frame.height + boxHeader.frame.height)
            let cWidth = f.maximumAdvancement.width * 1.02
            let cHeight = (f.ascender - f.descender) * 1.02
            let width =  Int(sWidth/cWidth)
            let height = Int(sHeight/cHeight)
            return (width, height)
        }
        
        //MARK: ** IMPOSSIBLE **
        return (80,25)
    }
    
    //MARK: Determine terminal window size from number of characters
    func calculateDisplaySize (_ width: Int,_ height: Int) -> CGSize {
        if let f = textView.font {
            let cWidth = f.maximumAdvancement.width * 1.02
            let cHeight = (f.ascender - f.descender) * 1.02
            let sWidth = max(minScreenWidth, CGFloat(width)*cWidth)
            let sHeight = max(minScreenHeight, CGFloat(height)*cHeight + (boxFooter.frame.height + boxHeader.frame.height))
            return CGSize(width: sWidth, height: sHeight)
        }
        
        //MARK: ** IMPOSSIBLE **
        return (CGSize(width: CGFloat(width*500),height: CGFloat(height*700)))
    }
    

    func configure (name: String, font: NSFont?, foreground: NSColor?, background: NSColor?, height: Int, width: Int, options: [TTYOption]?) -> Bool {
        self.name = name
        textView.configure(controller: self, foreground: foreground)

        labelStatus.stringValue = ""
        if let options = options {
            buttonInterrupt.isEnabled = options.contains(.interrupt)
            buttonInterrupt.title = options.contains(.isbreak) ? "BREAK" : "INTERRUPT"
            checkCapsLock.state = controlState(options.contains(.capsLock))
            checkAuto.isHidden = !options.contains(.auto)
        }
        
        let f = font ?? defaultFont
        sliderFontSize.doubleValue = Double(f.pointSize)
        textFontSize.doubleValue = sliderFontSize.doubleValue
        stepperFontSize.doubleValue = sliderFontSize.doubleValue
        colorBackground.color = background ?? .white
        colorForeground.color = foreground ?? .black
        updateDisplaySize(width, height)

    
        //MARK: Determine available Fonts
        comboFont.removeAllItems()
        comboFont.addItem(withObjectValue: "Courier")
        let allFonts = NSFontManager.shared.availableFonts
        for f in allFonts {
            if (NSFontManager.shared.fontNamed(f, hasTraits: .fixedPitchFontMask)) {
                comboFont.addItem(withObjectValue: f)
            }
        }
        comboFont.selectItem(withObjectValue: f.fontName)
        
        //MARK: Controls are initialized, now set up textView
        textView.font = f
        textView.textColor = colorForeground.color
        textView.backgroundColor = colorBackground.color
        textView.delegate = self
        
        //MARK: Finally, show the window.
        if let w = view.window {
            let frame = CGRect(origin: w.frame.origin, size: calculateDisplaySize(width, height))
            w.setFrame(frame, display: false)
            w.makeFirstResponder(textView)
            w.delegate = self
            w.title = self.name ?? "TTY"
            if let wc = w.windowController as? TTYWindowController {
                wc.showWindow(self)
                windowController = wc
            }
            return true
        }
        return false
    }
    
    func windowDidResize(_ notification: Notification) {
        if (isResizing) { return }
        if let w = notification.object as? NSWindow, let f = textView.font {
            let sWidth = max(minScreenWidth,w.frame.width) - scrollView.scrollerInsets.right
            let sHeight = max(minScreenHeight,w.frame.height) - (boxFooter.frame.height + boxHeader.frame.height)
            if (w.frame.width < minScreenWidth) || (w.frame.height < minScreenHeight) {
                isResizing = true
                w.setFrame(CGRect(origin: w.frame.origin,
                                  size: CGSize(width: sWidth+scrollView.scrollerInsets.right,
                                               height: sHeight+(boxFooter.frame.height + boxHeader.frame.height))),
                           display: true)
                isResizing = false
            }
            let cWidth = f.maximumAdvancement.width * 1.02
            let cHeight = (f.ascender - f.descender) * 1.02
            let width =  Int(sWidth/cWidth)
            let height = Int(sHeight/cHeight)
            delegate?.windowDidResize(delegateID, width: width, height: height)
            updateDisplaySize(width, height)
        }
    }
    
    func windowDidMove(_ notification: Notification) {
        if let origin = view.window?.frame.origin {
            delegate?.windowDidMove(delegateID, origin)
        }
    }
    
    @IBAction func stepperClick(_ sender: Any) {
        textFontSize.doubleValue = stepperFontSize.doubleValue
        sliderFontSize.doubleValue = stepperFontSize.doubleValue
        fontSizeChanged(sender)
    }
    
    @IBAction func fontSizeChanged(_ sender: Any) {
        if (sender is NSSlider) {
            let s = sliderFontSize.doubleValue
            let r = Double(Int(s*10))/10
            textFontSize.doubleValue = r
        }
        else {
            var fontSize = textFontSize.doubleValue
            fontSize = Double(Int(fontSize*10))/10
            if (fontSize < sliderFontSize.minValue) {
                fontSize = sliderFontSize.minValue
            }
            if (fontSize > sliderFontSize.maxValue) {
                fontSize = sliderFontSize.maxValue
            }
            textFontSize.doubleValue = fontSize
        }
        sliderFontSize.doubleValue = textFontSize.doubleValue
        stepperFontSize.doubleValue = textFontSize.doubleValue
        fontChanged(sender)
    }
    
    @IBAction func fontChanged(_ sender: Any) {
        let fontSize = sliderFontSize.doubleValue
        if let s = comboFont.objectValueOfSelectedItem as? String,
           let f = NSFont(name: s, size: fontSize) {
            textView.font = f
            
            let fg = colorForeground.color
            let bg = colorBackground.color
            textView.textColor = fg
            textView.backgroundColor = bg
            textView.needsDisplay = true
            
            delegate?.fontDidChange(delegateID, fontName: s, fontSize: fontSize, fgColor: fg, bgColor: bg)
            let (w, h) = calculateDisplayCharacterSize()
            updateDisplaySize(w, h)
        }
    }

    
    @IBAction func buttonInterruptClick(_ sender: Any) {
        if !inputQueue.isEmpty {
            inputQueue = ""
        }
        delegate?.characterIn (delegateID, Character(Unicode.Scalar(0)), isBreak: true)
    }
    
    
    @IBAction func checkAutoChange(_ sender: Any) {
        delegate?.autoSettingChanged(delegateID, checkAuto.state == .on)
    }

    @IBAction func buttonPasteClick(_ sender: Any) {
        delegate?.startPasteWindow(delegateID)
    }

    @IBAction func buttonLogClick(_ sender: Any) {
        if let fh = logFileHandle {
            try! fh.close()
            logFileHandle = nil
            return
        }
        
        // Choose
        let savePanel = NSSavePanel();
        savePanel.title                   = "Log to..."
        savePanel.treatsFilePackagesAsDirectories = true
        savePanel.showsResizeIndicator    = true
        savePanel.showsHiddenFiles        = false
        savePanel.canCreateDirectories    = true;
        savePanel.allowedFileTypes        = ["txt"]
        
        let result = savePanel.runModal()
        if (result == NSApplication.ModalResponse.OK),
           let url = savePanel.url {
            
            if FileManager.default.createFile(atPath: url.path, contents: nil)
                || siggyApp.alertYesNo(message: "Overwrite?", detail: url.path + " already exisits") {
                logFileHandle = FileHandle(forUpdatingAtPath: url.path)
            }
        }
        
    }
    
    @IBAction func buttonDateClick(_ sender: Any) {
        let c = MSDate().components()
        if let year = delegate?.machineYear(c.year) {
            pasteText(String(format:"%02d/%02d/%02d", c.month, c.day, year%100))
        }
    }
    
    @IBAction func buttonTimeClick(_ sender: Any) {
        let c = MSDate().roundedToMinute.components()
        pasteText(String(format:"%02d:%02d", c.hour, c.minute))
    }
    
    
    // Cutting and Pasting..
    func pasteFromClipBoard(_ sender: Any) {
        // MARK: Get clipboard string data)
        let pb = NSPasteboard.general
        if let d = pb.data(forType: .string) {
            var s = ""
            d.forEach({(x) in s.append(String(Unicode.Scalar(x)))})
            pasteText (s)
        }
    }
    
    func pasteText(_ s: String) {
        if !inputQueue.isEmpty {
            inputQueue += s
        }
        else {
            let c = s.first
            inputQueue += s.dropFirst(1)
            pendingInput(c)
        }
    }
    

    
    func characterInput(_ c: Character) -> Character {
        switch (c.asciiValue) {
        case 0x18, 0x19:
            inputQueue = ""
            
        default:
            let c = (checkCapsLock.state == .on) ? c.uppercased().first! : c
            let ts = MSClock.shared.gmtTimestamp()
            let elapsed = ts - lastInputTime
            if (elapsed > intraCharacterInterval) {
                delegate?.characterIn (delegateID, c, isBreak: false)
                lastInputTime = ts
            }
            else {
                // Do it later.
                if !inputQueue.isEmpty {
                    inputQueue += String(c)
                }
                else {
                    perform (#selector(pendingInput), with: c, afterDelay: 0.01)
                }
            }
            return c
        }
        return c
    }
    
    @objc func pendingInput (_ a: Any?) {
        if let c = a as? Character {
            delegate?.characterIn(delegateID, c, isBreak: false)
            lastInputTime = MSClock.shared.gmtTimestamp()
            if !inputQueue.isEmpty {
                let c = inputQueue.removeFirst()
                perform (#selector(pendingInput), with: c, afterDelay: 0.02)
            }
        }
    }
    
    func update() {
        if access.acquire(waitFor: MSDate.ticksPerMillisecond) {
            textView.textStorage?.append(NSAttributedString(string: buffer, attributes: [.font: textView.font!, .foregroundColor: textView.textColor!]))
            buffer = ""
            access.release()
            textView.moveToEndOfDocument(self)
        }
    }
    
    func delete() {
        if access.acquire(waitFor: MSDate.ticksPerMillisecond) {
            if (buffer.isEmpty) {
                if let length = textView.textStorage?.string.count, (length > 0) {
                    textView.textStorage?.deleteCharacters(in: NSRange(location: length-1, length: 1))
                }
            }
            else {
                _ = buffer.removeLast()
            }
            access.release()
            textView.moveToEndOfDocument(self)
            view.needsDisplay = true
        }
    }
    
    
    func write (_ s: String) {
        if access.acquire(waitFor: MSDate.ticksPerMillisecond) {
            buffer += s
            RunLoop.main.perform(update)
            access.release()
            
            if let fh = logFileHandle {
                if let d = s.data(using: String.Encoding.utf8) {
                    do { try fh.write(contentsOf: d) } catch { MSLog(level: .error, "Unable to write to log for \(name ?? "Unknown"):\(delegateID)") }
                }
            }
        }
        else {
            MSLog(level: .error, "Unable to write to TTY \(name ?? "Unknown"):\(delegateID)")
        }
    }
    
    func outputCharacter(_ c: UInt8) {
        let a = c & 0x7F
        switch (a) {
        case 0x00, 0x0D:
            break
            
        case 0x07:
            NSSound.beep()
        
        case 008:
            //RunLoop.main.perform(delete)
            break
            
        case 0x7F:
            RunLoop.main.perform(delete)
            
        default:
            write (String(cString: [a, 0]))
        }
    }
    
    // NSTextViewDelegate Functions:
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange, toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
        return newSelectedCharRange
    }
}

//MARK: CONSOLE
//MARK: This is a wrapper object for a TTY Window
//MARK: It could be integrated with the TTYDevice in IO.swift, however it is clearer here I think.
protocol ConsoleDelegate {
    func readComplete(_ input: String)
}


class ConsoleController: NSObject, TTYDelegate {
    
    var delegate: ConsoleDelegate?
    var tty: TTYViewController?
    var windowController: SiggyWindowController?

    var machine: VirtualMachine!
    var autoAnswerEnabled: Bool = true
    var input: String = ""                  // Pending input.
    var readInProgress: Bool = false
    var maxLength: Int = 0
    var myTurn = DispatchSemaphore(value: 1)
    var readMutex = DispatchSemaphore(value: 0)
    
    var access = SimpleMutex()

    init? (_ machine: VirtualMachine,_ title: String) {
        if let wc = siggyApp.storyboard?.instantiateController(withIdentifier: "TTYWindow") as? SiggyWindowController,
           let vc = wc.contentViewController as? TTYViewController {
            self.machine = machine
            self.tty = vc
            self.windowController = wc
            
            super.init()
            tty!.delegate = self
            
            let ch = machine.getIntegerSetting("ConsoleHeight",25)
            let cw = machine.getIntegerSetting("ConsoleWidth", 80)
            let cx = machine.getDoubleSetting("ConsoleX", 0)
            let cy = machine.getDoubleSetting("ConsoleY", 0)
            
            let fontName = machine.getSetting("ConsoleFont", "Courier")
            let fontSize = machine.getDoubleSetting("ConsoleFontSize", 11.0)
            let fg = hexIn(hex: machine.getSetting("ConsoleFGColor"), defaultValue: 0xFF000000)
            let bg = hexIn(hex: machine.getSetting("ConsoleBGColor"), defaultValue: 0xFFFFFFFF)
            if tty!.configure(name: title,
                              font: NSFont(name: fontName, size: fontSize),
                              foreground: NSColor(rgb32: fg),
                              background: NSColor(rgb32: bg),
                              height: max(ch,10), width: max(cw,60),
                              options: [.auto, .interrupt, .capsLock]) {
                 tty!.setOrigin (CGPoint(x: cx, y: cy))
                return
            }
        }
        return nil
    }
    
    func autoSettingChanged(_ id: Int,_ enabled: Bool) {
        autoAnswerEnabled = enabled
    }
    
    func machineYear(_ y: Int) -> Int {
        return machine.getVirtualYear(y)
    }

    func windowShouldClose(_ id: Int) -> Bool {
        siggyApp.alert (.warning, message: "Console cannot be closed", detail: "Close the Processor Window to abort the machine")
        return false
    }
    
    func windowDidMove(_ id: Int,_ origin: CGPoint) {
        machine.set("ConsoleX", String(Double(origin.x)))
        machine.set("ConsoleY", String(Double(origin.y)))
    }

    func windowDidResize(_ id: Int, width: Int, height: Int) {
        machine.set("ConsoleHeight",String(height))
        machine.set("ConsoleWidth", String(width))
    }
    
    func fontDidChange(_ id: Int, fontName: String, fontSize: Double, fgColor: NSColor, bgColor: NSColor) {
        machine.set ("ConsoleFont", fontName)
        machine.set ("ConsoleFontSize", String(format:"%4.1f",fontSize))
        machine.set ("ConsoleFGColor", String(format:"%08X",fgColor.rgb32))
        machine.set ("ConsoleBGColor", String(format:"%08X",bgColor.rgb32))
    }
    
    func startPasteWindow(_ id: Int) {
        let pb = pasteBufferWindow(forMachine: machine, withDelgate: tty!)
        pb?.showWindow(self)
    }
    

    @objc func postPanelInterrupt() {
        if let iss = machine.cpu?.interrupts {
            _ = iss.post(iss.levelControlPanel, priority: 3)
        }
    }

    func characterIn (_ l: Int,_ c: Character, isBreak: Bool) {
        
        func activate() {
            delegate?.readComplete(input)
            input = ""
            readMutex.signal()
        }
        
        
        if (isBreak) {
            tty?.write(">!<\n")
            perform (#selector(postPanelInterrupt), with: nil, afterDelay:0.001)
            return
        }

        
        if readInProgress, let a = c.asciiValue {
            switch (a) {
            case 0x0A, 0x0D:
                activate()
                tty?.outputCharacter(0x0A)
                
            case 0x7F:
                if (input.count > 0) {
                    input = String(input.dropLast(1))
                }
                
            default:
                input = input.appending(c.uppercased())
                if (input.count >= maxLength) {
                    activate()
                }
            }
            
            //MARK: Echo the character
            tty?.outputCharacter(a)
            
        }
    }
    
    func write (_ s:String) {
        tty?.write(s)
    }

    func close() {
        tty?.view.window?.close()
    }
    
    @objc func updateState(_ s: String) {
        tty?.labelStatus.stringValue = s
    }
    
    
    func readWaited (bufferLength: Int) {
        myTurn.wait()                               // Wait for my turn
        access.acquire()
        readInProgress = true
        maxLength = bufferLength
        access.release()
        performSelector(onMainThread: #selector(self.updateState), with: "READ", waitUntilDone: false)
        readMutex.wait()                            // Wait for completion
        access.acquire()
        readInProgress = false
        access.release()
        performSelector(onMainThread: #selector(self.updateState), with: "IDLE", waitUntilDone: false)
        myTurn.signal()                             // Done my turn
    }
    
    func readAbort () {
        if access.acquire(waitFor: 2*MSDate.ticksPerMillisecond) {
            if readInProgress {
                readMutex.signal()                  // Terminate it
                readInProgress = false
            }
            access.release()
        }
    }

    func autoAnswer(_ s: String) -> String? {
        if autoAnswerEnabled {
            if (s == "\nDATE(MM/DD/YY)=") && (machine.getSetting(VirtualMachine.kAutoDate,"N") == "Y") {
                let c = MSDate().components()
                let year = machine.getVirtualYear(c.year)
                return String(format:"%02d/%02d/%02d", c.month, c.day, year%100)
            }
            else if (s == "\nTIME(HH:MM)=") && (machine.getSetting(VirtualMachine.kAutoDate,"N") == "Y") {
                let c = MSDate().roundedToMinute.components()
                return String(format:"%02d:%02d", c.hour, c.minute)
            }
            else if (s == "\nDO YOU WANT DELTA (Y/N)") {
                if let aa = machine.getSetting(VirtualMachine.kAutoDelta) {
                    if (aa != "*") {
                        return aa
                    }
                }
            }
            else if (s == "\nDO YOU WANT HGP RECONSTRUCTION(Y/N)?") {
                if let aa = machine.getSetting(VirtualMachine.kAutoHGP) {
                    if (aa != "*") {
                        return aa
                    }
                }
            }
            else if (s == "\nATTEMPT BATCH QUEUE RECOVERY(Y/N)?") {
                if let aa = machine.getSetting(VirtualMachine.kAutoBatch) {
                    if (aa != "*") {
                        return aa
                    }
                }
            }
        }
        return nil
    }

}
