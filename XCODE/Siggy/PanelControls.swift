//
//  PanelControls.swift
//  Siggy
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

//

import Foundation
import AppKit

func PColor(_ red: UInt8,_ green: UInt8,_ blue: UInt8) -> NSColor {
    return NSColor(red: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: 1.0)
}

let PPanelColor = PColor(0xdd, 0xdd, 0xee)
let PLightOnColor = PColor(0xff, 0xf9, 0xd2)
let PlightOffColor = PColor(0xc0,0xc0, 0xc0)



// A Hex selector chooses a single hex digit. Three or four of them are used to select the load address on the panel.
// On the actual machine thumbwheels were used.
class PHexSelector: NSComboBox {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.removeAllItems()
        for i in 0...15 {
            self.addItem(withObjectValue: String(format: "%1X",i))
        }
        self.selectItem(at: 0)
        self.refusesFirstResponder = true
    }
}

class PHexBox: NSBox {
    var isEnabled: Bool { get { return false} set { setEnable(newValue)}}
    
    func setEnable (_ e: Bool) {
        for v in self.subviews {
            for v2 in v.subviews {
                if let c = v2 as? NSControl {
                    c.isEnabled = e
                }
            }
        }
    }
    
    func setHexValue (_ intValue: Int) {
        var i = intValue
        
        for v in self.subviews {
            for v2 in v.subviews {
                if let c = v2 as? PHexSelector {
                    c.selectItem(at: i & 0xf)
                    i = i >> 4
                }
            }
        }
    }
    
    func getHexValue () -> Int {
        var i = 0
        var s = 0
        
        for v in self.subviews {
            for v2 in v.subviews {
                if let c = v2 as? PHexSelector {
                    i |= (c.indexOfSelectedItem << s)
                    s += 4
                }
            }
        }
        return i
    }

}

// MARK: A vertically oriented panel switch has two or three states
// MARK: THIS NEEDS REWORK.  The control should be descended from a box and should add it's own components:
// MARK: 2 or 3 labels (left or right)
// MARK: 2 or 3 positions
// MARK: title above or below
// MARK: momentary up/down/both/none
//
class PSwitch: NSSlider {
    var bar: PBar? = nil
    var value: Int = 0
    var threeWay: Bool = false

    var pTarget: AnyObject?
    var pAction: Selector?

    
    func commonInit (_ isThreeWay: Bool = false) {
        self.threeWay = isThreeWay
        
        self.sliderType = .linear
        self.controlSize = .small
        self.isVertical = true
        
        minValue = threeWay ? -1 : 0
        maxValue = 1
        
        self.numberOfTickMarks = threeWay ? 3 : 2
        self.allowsTickMarkValuesOnly = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(minValue < 0)
    }
    
    init(frame frameRect: NSRect, isThreeWay: Bool, bar: PBar?) {
        self.bar = bar
        super.init(frame: frameRect)
        commonInit(isThreeWay)
        
        if (bar != nil) {
            pTarget = target
            pAction = action
        
            target = self
            action = #selector(valueChanged)
        }
    }
    
    @objc func valueChanged (sender: Any?) {
        value = integerValue
        _ = pTarget?.perform(pAction, with: sender)
    }
    
    
}

class PSwitch3Way: PSwitch {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(true)
    }
}

class PSwitchBox: NSBox {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func configure () {
        // Set up switch, labels, etc.
    }
        
}

class PLight: NSBox {
    func commonInit() {
        self.boxType = .custom
        self.titlePosition = .noTitle
        self.borderWidth = 1
        self.cornerRadius = self.frame.width/2
        self.fillColor = PLightOnColor
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    var isLit: Bool { get { return (fillColor == PLightOnColor) } set { fillColor = newValue ? PLightOnColor : PlightOffColor }}
}

// Common object for a row of switches or a row of lights
// Each light or switch represents a bit.  They are arranged in groups of four (for a hex digit)
class PBar: NSBox {
    public enum NumberOption {
        case from0
        case from1
        case fromHigh
        case bitValue
        case custom
    }
    
    var bits: Int = 0
    var mask: Int = 0
    var bitLights: [PLight?] = Array(repeating: nil, count: 32)
    var bitSwitches: [PSwitch?] = Array(repeating: nil, count: 32)
    
    func numberingText (_ option: NumberOption,_ bits: Int,_ n: Int) -> String {
        guard (n >= 0) && (n < 32) else { return "" }
        switch (option) {
        case .from0: return (String(format: "%d", bits-(n+1)))
        case .from1: return (String(format: "%d", bits-n))
        case .fromHigh: return (String(format: "%d", n))
        case .bitValue: return (String(format: "%d", 1 << n))
        case .custom: return ""
        }
    }
    
    
    func configure (bits: Int, mask: Int, isLight: Bool, numberingPosition: Int = 0, numberingOption: NumberOption = .from0, bitNames: [String]? = nil) {
        self.bits = bits
        self.mask = mask
        
        let sv = self.superview
        let ny = self.frame.minY-CGFloat(numberingPosition)
        let nf = NSFont(name: "Arial", size: 8)
        
        let h = self.frame.height/2
        let hb = h * 1.2
        
        let w = self.frame.width
        let py = h/2
        var px = w - hb
        var n: Int = 0
        while (px >= 0) && (n < bits) {
            if ((mask & (1 << n)) != 0) {
                if (isLight) {
                    let r = NSRect(x:px, y:py, width: h, height: h)
                    let light = PLight.init(frame: r)
                    self.addSubview(light)
                    bitLights[n] = light
                }
                else {
                    let r = NSRect(x:px, y:0, width: h, height: h*2)
                    let swtch = PSwitch.init(frame: r, isThreeWay: false, bar: self)
                    self.addSubview(swtch)
                    bitSwitches[n] = swtch
                }
                
                if (numberingPosition != 0) {
                    let r = NSRect(x: self.frame.minX+px, y: ny, width: h, height: h)
                    let labelNum = NSTextField(labelWithString: (numberingOption == .custom) ? bitNames![n] : numberingText(numberingOption, bits, n))
                    labelNum.frame = r
                    labelNum.font = nf
                    labelNum.alignment = .center
                    sv?.addSubview(labelNum)
                }
            }
            
            px -= hb
            if ((n & 3) == 3) {
                // Add a divider every 4 lights
                let r = NSRect(x: px+h/2, y: 0, width: h/4, height: h*2)
                let bar = NSBox.init(frame: r)
                bar.boxType = .custom
                bar.titlePosition = .noTitle
                bar.borderWidth = 0
                bar.cornerRadius = 0
                bar.fillColor = PPanelColor
                self.addSubview(bar)
                
                px -= h
            }
            n += 1
        }
        
        self.fillColor = NSColor.darkGray
    }
    
    func setLights (v: Int) {
        var n: Int = 0
        var m: Int = 1
        
        while (n < bits) {
            if let light = bitLights[n] {
                light.fillColor = ((v & m) == 0) ? PlightOffColor : PLightOnColor
            }
            n += 1
            m <<= 1
        }
        
    }
    

}

// This object is used to display a set of lights representing a binary integer.
class PLightBar: PBar {
    func configure (bits: Int, mask: Int, numberingPosition: Int = 0) {
        super.configure(bits: bits, mask: mask, isLight: true, numberingPosition: numberingPosition)
    }
}

// A corresponding set of switches is used to provide various binary input values.
class PSwitchBar: PBar {
    func configure (bits: Int, mask: Int) {
        super.configure(bits: bits, mask: mask, isLight: false)
    }
    
    func read () -> Int {
        var v: Int = 0
        var n: Int = 0
        var m: Int = 1
                
        while (n < bits) {
            if let s = bitSwitches[n] {
                if (s.value != 0) {
                    v |= m
                }
            }
            n += 1
            m <<= 1
        }
        return v
        
    }
}

