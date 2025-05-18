//
//  ConsoleViewController.swift
//  Siggy
//
//  Created by MS on 2023-03-06.
//
//MARK: *** DEPRICATED ***

import Cocoa

/**
 class ConsoleViewController: NSViewController, NSTextViewDelegate {
    @IBOutlet weak var input: NSTextField!
    @IBOutlet var outputView: NSTextView!

    var terminal: TerminalView!
    var command: DispatchSemaphore!
    
    var outputAccess: Resource!
    var outputPending: String = ""

    var inputAccess: Resource!
    var inputPending: String = ""
    var inputAbort: Bool = false
    var inputSize: Int = 0

    let nl: UInt8 = 0x15

    let fontBody = NSFont(name: "Menlo", size: 13)
    let fontHead = NSFont(name: "Menlo", size: 16)
    

    
    override func viewDidLoad() {
        super.viewDidLoad()
        outputView.delegate = self
        
        inputAccess = Resource("CONSOLE-INPUT")
        outputAccess = Resource("CONSOLE-OUTPUT")
        command = DispatchSemaphore(value: 0)
        output(siggyApp.applicationName+"\nCONSOLE STARTED\n")
    }
    

    // MARK: Functions to be called by main thread only.
    @objc func inputStart() {
        inputPending = ""
    }

    func output (_ s: String,_ font: NSFont? = nil) {
        let f = (font == nil) ? fontBody : font
        let sa = NSAttributedString(string: s, attributes: [.font : f!])
        outputView.textStorage?.append(sa)
    }

    @objc func updateOutput() {
        outputAccess.acquire()
        output(outputPending)
        outputPending = ""
        outputAccess.release()
    }
    
    // Called by IO Thread
    func write (data: Data) {
        let s = asciiBytes(data, unprintable: " ")
        outputAccess.acquire()
        outputPending.append(s)
        outputAccess.release()
        RunLoop.main.perform(updateOutput)
    }
    
    
    // Called by IO Thread
    func read(bufferLength: Int) -> Data {
        var r = Data()
        inputAccess.acquire()
        inputAbort = false
        inputSize = bufferLength

        if (inputSize > 0) {
            RunLoop.main.perform(inputStart)
            
            inputAccess.release()
            command.wait()
            inputAccess.acquire()
            
            if inputAbort {
                inputPending = ""
                inputAbort = false
                inputSize = 0
                return r
            }
            
            for c in inputPending.uppercased() {
                if let a = c.asciiValue {
                    var e = ebcdicFromAscii(a)
                    r.append(&e, count: 1)
                }
            }
            
            var vnl = nl
            r.append(&vnl, count: 1)
        }
        
        inputSize = 0
        inputAccess.release()
        return r
    }
    
    // Called by IO Thread
    func abortInput() {
        if (inputSize > 0) {
            inputAbort = true
            command.signal()
        }
    }
    
    @IBAction func buttonInterruptClick(_ sender: Any) {
        abortInput()
        output("\n")
        perform (#selector(postPanelInterrupt), with: nil, afterDelay:0.001)
    }
    
    @objc func postPanelInterrupt() {
        if let iss = siggyApp.mainViewController.cpu?.interruptSubsystem {
            _ = iss.post(iss.levelControlPanel, priority: 3)
        }
    }
    
    
    func keyboardInput(_ characters: String) {
        if (inputSize > 0) {
            //output (characters.uppercased())
            inputPending.append(characters)
        }
    }
    
    
    //MARK: Intercept the Key events
    override func keyUp(with event: NSEvent) {
        if let c = event.characters {
            keyboardInput(c)
        }
    }
    
    
    
    //MARK: TextView Actions
    
    
    //MARK: TextViewDelegate
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        NSLog(commandSelector.description)
        
        switch (commandSelector) {
        case #selector(insertNewline):
            siggyApp.log(level: .info, "CONSOLE INPUT: \""+inputPending+"\"")
            output("\n")
            command.signal()
            return true
            
        case #selector(deleteBackward), #selector(deleteForward):
            return true
            
        default:
            break
        }

        return false
    }
    
    func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        outputView.moveToEndOfDocument(self)
        return true
    }
    
    
    
}
*/
