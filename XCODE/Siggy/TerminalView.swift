//
//  TerminalView.swift
//  Siggy
//
//  Created by MS on 2023-05-01.
//

import Cocoa


protocol TerminalViewDelegate {
    func keyboardInput (_ characters: String)

}

class TerminalView: NSView {
    var delegate: TerminalViewDelegate!

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    

    override func keyUp(with event: NSEvent) {
        if let c = event.characters {
            delegate?.keyboardInput(c)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // ignore
    }
}
