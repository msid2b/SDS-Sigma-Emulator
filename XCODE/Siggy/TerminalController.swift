//
//  TerminalController.swift
//  Siggy
//
//  Created by MS on 2023-07-04.
//
/**
import Cocoa
import Foundation

class TerminalWindowController: NSWindowController {

    func setTitle (_ title: String) {
        self.window?.title = title
    }

}

class TerminalViewController: NSViewController {
    @IBOutlet weak var boxHeader: NSBox!
    @IBOutlet weak var boxFooter: NSBox!
    
    @IBOutlet weak var labelDisplaySize: NSTextField!
    @IBOutlet weak var labelStatus: NSTextField!
    @IBOutlet weak var buttonInterrupt: NSButton!
    @IBOutlet weak var buttonExit: NSButton!
    
    
    var machine: VirtualMachine!
    var outputView: OutputView!
    
    struct Style {
        enum DeviceSubtype {
            case none
            case console
            case terminal
        }
        var deviceSubtype: DeviceSubtype = .none
        var interruptButtonTitle: String = ""
        var exitButtonTitle: String = ""
        
        var font: NSFont!
        var backgroundColor: NSColor = .white
        var foregroundColor: NSColor = .black
        
        var forceUppercase: Bool = false
    }

    
    func configure (machine: VirtualMachine?, title: String, headingSize: CGFloat, style: Style, height: Int, width: Int, maxBufferedLines: Int = 0) -> OutputView {
        outputView?.removeFromSuperview()

        let leftMargin: CGFloat = 5
        let f = NSRect(x: leftMargin, y: boxFooter.frame.height, width: view.frame.width - leftMargin, height: view.frame.height - (boxHeader.frame.height+boxFooter.frame.height))
        switch (style.deviceSubtype) {
        case .none:
            outputView = OutputView(frame: f)
            
        case .console:
            outputView = ConsoleView(frame: f)
            
        case .terminal:
            outputView = TerminalView (frame: f)
        }
        
        view.addSubview(outputView)
        outputView.configure(machine, headingSize, height, width, fgColor: style.foregroundColor, bgColor: style.backgroundColor, font: style.font, maxBufferedLines: maxBufferedLines, labelDisplaySize: labelDisplaySize)

        if let w = view.window {
            w.title = title
            w.initialFirstResponder = outputView
            w.makeFirstResponder(outputView)
        }

        buttonInterrupt.title = style.interruptButtonTitle
        //buttonExit.title = style.exitButtonTitle
        
        return outputView
    }
    
 @IBAction func buttonDateClick(_ sender: Any) {
     if let ov = outputView {
         let c = MSDate().components()
         // Find a year (1971-1998) that matches days of the week and leap.
         var year = c.year - 28
         while (year >= 1999) {
             year -= 28
         }
         ov.insertInput(String(format:"%02d/%02d/%02d", c.month, c.day, year-1900))
     }
 }
     
 @IBAction func buttonTimeClick(_ sender: Any) {
     if let ov = outputView {
         let c = MSDate().roundedToMinute.components()
         ov.insertInput(String(format:"%02d:%02d", c.hour, c.minute))
     }
 }
 
 @IBAction func buttonInterruptClick(_ sender: Any) {
     if let ov = outputView {
         ov.buttonInterruptClick(sender)
     }
 }
}


class xTTYViewController: TerminalViewController {
    var coc: COCDevice?
    var cocLine: Int = -1
    var buffer: String = ""
    
    
    func write (_ s: String) {
        if let ov = outputView {
            ov.write(s)
        }
    }
    
    func outputCharacter(_ c: UInt8) {
        switch (c) {
        case 0x07:
            write (">BEL<")
            
        default:
            write (String(cString: [c & 0x7f, 0]))
        }
    }
}

//class TerminalMainView: NSView {
//}

// A classic terminal type device.
// MARK: SIZING NEEDS WORK, and get rid of FUDGE
let scrollerWidth: CGFloat = 20             // Width of the scroller

let fudgeWidth = 2
let fudgeHeight = 2

//MARK: Intended to be an ABSTRACT class, but could be used as an output only terminal.
class OutputView: NSView, NSWindowDelegate {
    var machine: VirtualMachine!
    var access = SimpleMutex()

    var labelDS: NSTextField!
    
    var headingSize: CGFloat = 0
    var textView: NSText!
    var vScroller: NSSlider!
    let scrollerWidth: CGFloat = 20         // Width of the scroller

    var buffer: [String] =  []
    var output: String = ""
    
    var input: String = ""                  // Pending input. Only used for line mode
    
    var forceUppercase: Bool = false

    var displayWidth: Int = 80              // Number of characters in each line.
    var displayHeight: Int = 50             // Number of lines displayed

    var characterFont: NSFont! = siggyApp.standardFont
    var foregroundColor: NSColor!
    var backgroundColor: NSColor!
    
    
    // The following funnctions should be overridden to allow for input
    func interruptClick() {}
    func characterInput(_ c: Character) {}
    func insertInput(_ s: String) {
        for c in s {
            characterInput(c)
        }
        characterInput("\n")
    }
 
    func configure (_ machine: VirtualMachine?,_ headSize: CGFloat,_ height: Int,_ width: Int, fgColor: NSColor, bgColor: NSColor, font: NSFont? = nil, maxBufferedLines: Int = 0, labelDisplaySize: NSTextField? = nil) {
        self.machine = machine
        
        labelDS = labelDisplaySize
        headingSize = headSize
        if let f = font {
            characterFont = f
        }
        foregroundColor = fgColor
        backgroundColor = bgColor
        
        displayWidth = width
        displayHeight = height
        
        let cWidth = characterFont.maximumAdvancement.width
        let cHeight = characterFont.ascender - characterFont.descender
        
        let tWidth = cWidth * CGFloat(displayWidth+fudgeWidth)
        let tHeight = cHeight * CGFloat(displayHeight+fudgeHeight)
        
        if let w = self.window {
            let frame = NSRect(x: w.frame.minX, y: w.frame.minY,
                               width: self.frame.minX + tWidth  + scrollerWidth,
                               height: self.frame.minY + tHeight + headingSize)
            w.setFrame(frame, display: true)
            w.layoutIfNeeded()
            w.makeFirstResponder(self)
            w.delegate = self
        }
        
        layoutText(tWidth, tHeight)
        //access.trace = true
    }
    

    //MARK: Window delegate...
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        siggyApp.alert (.warning, message: "Console cannot be closed", detail: "Close the Processor Window to abort the machine")
        return false
    }
    
    func windowDidResize(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            let tWidth = max(0, w.frame.width - (self.frame.minX + scrollerWidth))
            let tHeight = max(0, w.frame.height - (self.frame.minY + headingSize))
            
            let cWidth = characterFont.maximumAdvancement.width
            let cHeight = characterFont.ascender - characterFont.descender
            
            displayWidth = Int(tWidth / cWidth) - fudgeWidth
            displayHeight = Int(tHeight / cHeight) - fudgeHeight
            
            layoutText (tWidth, tHeight)
        }
    }

    // Rebuild the textView and associated scroller(NSSlider)
    func layoutText(_ tWidth: CGFloat,_ tHeight: CGFloat) {
        if (textView != nil) {
            textView.removeFromSuperview()
        }
        textView = NSText(frame: NSRect(x:0, y: 0, width: tWidth , height: tHeight))
        textView.isRichText = false
        textView.font = characterFont
        textView.backgroundColor = backgroundColor
        textView.textColor = foregroundColor
        textView.isFieldEditor = false
        textView.isEditable = false
        textView.isSelectable = true
        addSubview(textView)
        
        if (vScroller != nil) {
            vScroller.removeFromSuperview()
        }
        vScroller = NSSlider(frame: NSRect(x: tWidth, y:0, width: scrollerWidth, height: tHeight))
        vScroller.isVertical = true
        vScroller.target = self
        vScroller.action = #selector(scrollerChanged)
        setScrollerRange()
        addSubview(vScroller)

        generateTextString()
        if let lds = labelDS {
            lds.stringValue = String(displayHeight)+" lines by "+String(displayWidth)+" characters"
        }
    }
    
    func setScrollerRange() {
        if (buffer.count > displayHeight) {
            vScroller.maxValue = 0
            vScroller.minValue = -Double(buffer.count-displayHeight)
            vScroller.doubleValue = vScroller.minValue
        }
    }
    
    func generateTextString() {
        // Regenerate screen
        var last = buffer.count-1
        var first = max(0, last-displayHeight+1)
        if (vScroller.minValue < 0) {
            let x = vScroller.doubleValue / vScroller.minValue
            first = Int((Double(first) * x).rounded())
            last = first + displayHeight-1
        }

        var s = ""
        if (last > first) {
            for x in first...last-1 {
                s = s.appending(buffer[x]+"\n")
            }
            s = s.appending(buffer[last]+input)
        }
        textView.string = s
        textView.needsDisplay = true
    }
    
    @objc func scrollerChanged (sender: Any) {
        generateTextString()
    }
    
    
    @IBAction func buttonInterruptClick(_ sender: Any) {
        interruptClick()
    }
    
    override func keyUp(with event: NSEvent) {
        if let s = event.characters {
            for c in s {
                characterInput(c)
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
    }
    
    override func resignFirstResponder() -> Bool {
        return false
    }

    
    // MARK: Buffer management.
    @objc private func writeToBuffer () {
        let lines = output.components(separatedBy: ["\n"])
        guard (lines.count > 0) else { return }
        
        if (buffer.count <= 0) {
            buffer.append("")
        }
        
        let last = buffer.count-1
        buffer[last] = buffer[last].appending(lines.first!)

        for line in lines.dropFirst(1) {
            buffer.append(line)
        }
        output = ""
        setScrollerRange()
    }
    
    func writeInternal () {
        if (access.acquire(waitFor: 5000000)) {
            writeToBuffer()
            generateTextString()
            access.release()
        }
        else {
            MSLog("WriteInternal, access timeout")
        }
    }
        

    func write (_ s: String) {
        if (access.acquire(waitFor: 5000000)) {
            output = output.appending(s)
            access.release()
            RunLoop.main.perform(writeInternal)
        }
        else {
            MSLog("Write, access timeout")
        }
    }
        
}

// MARK: Terminal View
// This is a primitive CRT type terminal for COCs.
// MARK: *** NOT CURRENTLY USED ***  TTY WINDOW USES TTYViewController instead
class TerminalView: OutputView {

    var coc: COCDevice?
    var cocLine: Int = -1
    
    override func characterInput(_ c: Character) {
        coc?.characterIn (c, cocLine, isBreak: false)
    }
    
    override func interruptClick() {
        coc?.characterIn (Character(Unicode.Scalar(0)), cocLine, isBreak: true)
    }
    
    func characterOutput(_ c: UInt8) {
        switch (c) {
        case 0x07:
            write (">BEL<")
            
        default:
            write (String(cString: [c, 0]))
        }
    }
}


// MARK: Console View
// This is a half duplex line oriented console type device
// Input is blocking.

 protocol ConsoleDelegate {
     func readComplete(_ input: String)
 }


class ConsoleView: OutputView {
    var delegate: ConsoleDelegate?
    var readInProgress: Bool = false
    var myTurn = DispatchSemaphore(value: 1)
    var readMutex = DispatchSemaphore(value: 0)
    
    override func characterInput(_ c: Character) {
        if readInProgress {
            switch (c.asciiValue) {
            case 0x0A, 0x0D:
                write (input + "\n")
                delegate?.readComplete(input)
                input = ""
                readMutex.signal()
                
            case 0x7F:
                if (input.count > 0) {
                    input = String(input.dropLast(1))
                }
                
            default:
                input = input.appending(c.uppercased())
            }
            generateTextString()
        }
    }

    override func interruptClick() {
        write(">!<\n")
        perform (#selector(postPanelInterrupt), with: nil, afterDelay:0.001)
    }


    @objc func postPanelInterrupt() {
        if let iss = machine.cpu?.interrupts {
            _ = iss.post(iss.levelControlPanel, priority: 3)
        }
    }

    @objc func updateState(s: Any?) {
        if let s = s as? String,
           let c = self.window?.contentViewController as? TerminalViewController {
            c.labelStatus.stringValue = s
        }
    }
    
    func readWaited (bufferLength: Int) {
        myTurn.wait()                               // Wait for my turn
        access.acquire()
        readInProgress = true
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
}
*/
