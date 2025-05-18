//
//  pdf.swift
//  burst
//
//  Created by ms on 2024-09-12.
//


//
//  PDF.swift
//  Simple PDF Writer
//
//  Created by MGS on 2024-09-09.
//


import Foundation
import AppKit


//MARK: MIT LICENSE
//  Copyright (c) 2024, Michael G. Sidnell
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



class PDFOutputFile: NSObject {
    enum Paper: String {
        case custom
        case executive
        case letter
        case legal
        case ledger
        case a4
        case a3
        case printer
    }
    
    static func paperSize(_ p: Paper) -> NSSize {
        var size: NSSize!
        
        switch (p) {
        case .executive:
            size = NSSize(width: 522.0, height: 756.0)
            
        case .letter:
            size = NSSize(width: 612.0, height: 792.0)
            
        case .legal:
            size = NSSize(width: 612.0, height: 1008.0)
            
        case .ledger:
            size = NSSize(width: 792.0, height: 1224.0)
            
        case .a4:
            size = NSSize(width: 595.2, height: 841.8)
            
        case .a3:
            size = NSSize(width: 841.8, height: 1190.6)
            
        case .printer:
            size = NSSize(width: 630.0, height: 1224.0)

            
        default:
            size = NSSize(width: 612.0, height: 792.0)
        }
        return size
    }
    
    enum Orientation {
        case landscape
        case portrait
    }
    
    struct ObjectReference {
        var fileOffset: Int
        
        init() {
            self.fileOffset = -1
        }
        
        init(_ fileOffset: Int) {
            self.fileOffset = fileOffset
        }
    }
    
    struct Font {
        var objectNumber: Int
        var typeFace: String
        var subType: String
    }
    
    let type1Fonts: [String] = ["Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic",
                                "Courier", "Courier-Italic", "Courier-Bold", "Courier-Oblique",
                                "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique",
                                "Symbol", "ZapfDingbats"]
    
    // Page tree
    static let pageTreeLevels = 3
    static let pageTreeBreadth = 32                     // Implies max 32768 pages
    struct PageNode {
        var objectNumber: Int
        var pageCount: Int                              // Total pages (including lower levels)
        var pageObject: [Int]
    }
    
    
    private var pageSize = NSSize()                     // Points
    private var orientation: Orientation = .portrait
    private var pageIsClean: Bool = true
    private var pageRotation: CGFloat = 0
    private var xMargin: CGFloat = 0
    private var yMargin: CGFloat = 0
    private var currentPosition = NSPoint()             // Current "pen" position
    
    private var fontList: [Font] = []
    private var currentFontSize: CGFloat = -1
    private var currentScale: CGFloat = 0
    private var currentFont: Int = -1
    private var currentShading: CGFloat = 0
    private var currentColor = NSColor.white
    
    private var pageTree: [PageNode] = []
    private var procSetObject: Int = 0
    
    private var catalog: Int = 0
    private var infoObject: Int = 0
    private var streamStart: Int = 0
    private var objectList: [ObjectReference] = []
    
    
    private var fPath: String = "<Unassigned>"
    private var fh: FileHandle?
    
    var currentPageSize: NSSize { get { return pageSize }}
    
    init (_ path: String) {
        fPath = path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        fh = FileHandle(forWritingAtPath: path)
        if (fh == nil) {
            MSLog(level: .warning, "PDF open failed: " + fPath)
        }
    }
    
    private func write (_ s: String) {
        do {
            let d = Data(s.utf8)
            try fh?.write(contentsOf: d)
        }
        catch {
            MSLog(level: .warning, "Failed to write PDF data to " + fPath)
        }
    }
    
    private func write (data: Data) {
        do {
            try fh?.write(contentsOf: data)
        }
        catch {
            MSLog(level: .warning, "Failed to write PDF data to " + fPath)
        }
    }
    
    private func offset() -> Int {
        if let fh = fh {
            do {
                let o = try Int(fh.offset())
                return o
            }
            catch {}
        }
        return (-1)
    }
    
    
    private func allocateObject(_ offset: Int = -1) -> Int {
        let objectIndex = objectList.count
        objectList.append(ObjectReference(offset))
        return objectIndex
    }
    
    private func startObject() -> Int {
        let off = offset()
        let objectIndex = allocateObject(off)
        write("\(objectIndex) 0 obj\n")
        return objectIndex
    }
    
    private func endObject() {
        write("endobj\n")
    }
    
    private func startPage() {
        if (pageTree[Self.pageTreeLevels-1].pageObject.count >= Self.pageTreeBreadth) {
            flushPage(Self.pageTreeLevels-1);
        }
        
        let onum = startObject()
        write("<</Length \(onum+1) 0 R>>\n")
        write("stream\n");
        
        streamStart = offset()
    }
    
    private func endPage() {
        let streamLength = offset() - streamStart;
        
        write("endstream\n")
        endObject()
        
        // Emit an object containing the length of the page data stream
        _ = startObject()
        write("\(streamLength)\n")
        endObject()
        
        // Define the page object
        let pob = startObject()
        write("<< /Type /Page /Parent \(pageTree[Self.pageTreeLevels-1].objectNumber) 0 R /MediaBox [0 0 \(pageSize.width) \(pageSize.height)]\n")
        write("/Rotate 0 /Contents \(pob-2) 0 R /Resources <</ProcSet \(procSetObject) 0 R\n")
        
        write("/Font <<\n")
        for x in 0 ... fontList.count-1 {
            if (fontList[x].objectNumber < 0) {
                fontList[x].objectNumber = allocateObject()
            }
            write("/F\(x) \(fontList[x].objectNumber) 0 R\n")
        }
        write(">>\n")
        write(">> >>\n")
        endObject()
        
        currentFont = -1
        
        // Add the page to the index
        let level = Self.pageTreeLevels-1
        if (pageTree[level].pageObject.count >= Self.pageTreeBreadth) {
            flushPage(level)
        }
        pageTree[level].pageObject.append(pob)
        
        // Count the pages
        for x in 0 ... Self.pageTreeLevels-1 {
            pageTree[x].pageCount += 1
        }
    }
    
    private func flushPage(_ level: Int) {
        if (pageTree[level].pageObject.count > 0) {
            if (level > 0) {
                if (pageTree[level-1].pageObject.count >= Self.pageTreeBreadth) {
                    flushPage(level-1)
                }
                pageTree[level-1].pageObject.append(pageTree[level].objectNumber)
            }
            
            objectList[pageTree[level].objectNumber].fileOffset = offset()
            write("\(pageTree[level].objectNumber) 0 obj\n")
            write("<</Type /Pages ")
            if (level > 0) {
                write("/Parent \(pageTree[level-1].objectNumber) 0 R ")
            }
            write("/Kids [\n")
            for p in pageTree[level].pageObject {
                write("\(p) 0 R\n")
            }
            write("] /Count \(pageTree[level].pageCount) >>\n")
            write("endobj\n")
            
            pageTree[level].pageObject = []
            pageTree[level].pageCount = 0
            pageTree[level].objectNumber = allocateObject()
        }
    }
    
    private func setFill (color: NSColor, shading: CGFloat = 0) {
        if (color != currentColor) {
            if let color = color.usingColorSpace(.sRGB) {
                write("\(color.redComponent) \(color.greenComponent) \(color.blueComponent) rg\n")
                currentColor = color
            }
        }
    }
    
    private func characterOut(_ c: UInt8) {
        let punct = "$,()[]{}/\\".utf8
        if punct.contains(c) {
            write("\\\(String(cString: [c,0]))")
        }
        else if ((c & 0x80) != 0) {
            write (String(format:"\\%03o", c))
        }
        else {
            write(String(cString: [c,0]))
        }
    }
    
    
    //MARK: Interface methods follow..
    
    func beginOutput(producer: String, author: String, paper: Paper, pageHeight: Int = 0, pageWidth: Int = 0, orientation: Orientation, margins: NSSize?) {
        try! fh?.truncate(atOffset: 0)
        write ("%%PDF-1.3\n");
        
        // Start with an empty object.
        _ = allocateObject()
        
        catalog = startObject()
        write("<< /Type /Catalog /Outlines \(catalog+1) 0 R /Pages \(catalog+2) 0 R >>\n")
        endObject()
        
        // Outline
        _ = startObject()
        write("<< /Type /Outlines /Count 0 >>\n")
        endObject()
        
        // Root page node
        pageTree.append(PageNode(objectNumber: allocateObject(), pageCount: 0, pageObject: []))
        
        // Information object
        infoObject = startObject()
        write("<</Producer(\(producer))\n")
        write("/Creator(\(producer) 1.0)\n")
        write("/CreationDate(D:\(MSDate().basicDateString("")))\n")
        write("/Author(\(author))\n")
        write(">>\n")
        endObject()
                
        // Also need a ProcSet object and one for each page level
        procSetObject = allocateObject()
        for _ in 1 ... Self.pageTreeLevels-1 {
            pageTree.append(PageNode(objectNumber: allocateObject(), pageCount: 0, pageObject: []))
        }
        
        pageSize = Self.paperSize(paper)
        if (orientation == .landscape) {
            pageSize = NSSize(width: pageSize.height, height: pageSize.width)
        }
        
        if let m = margins {
            xMargin = m.width
            yMargin = m.height
        }
        
        pageIsClean = true
        pageRotation = 0;
        fontList = []
        startPage()
    }
    
    
    func finalizeOutput() {
        if !pageIsClean {
            endPage()
        }

        //Embedded Fonts?
        
        
        var fx = 0
        for f in fontList {
            objectList[f.objectNumber].fileOffset = offset()
            write("\(f.objectNumber) 0 obj\n")
            write("<< /Type /Font /Subtype /\(f.subType) /Name /F\(fx)\n");
            write("/BaseFont /\(f.typeFace) /Encoding /MacRomanEncoding >>\n")
            write("endobj\n")
            fx += 1
        }
        
        objectList[procSetObject].fileOffset = offset()
        write("\(procSetObject) 0 obj\n")
        write("[/PDF /Text]\n")
        write("endobj\n")
        
        // Flush the page nodes
        var px = pageTree.count-1
        while (px >= 0) {
            flushPage(px)
            px -= 1
        }
        
        
        // Do the crossref table
        let startXRef = offset()
        write ("xref\n0 \(objectList.count)\n")
        for o in objectList {
            if (o.fileOffset >= 0) {
                write(String(format:"%10d", o.fileOffset)+" 00000 n\n")
            }
            else {
                write("0000000000 65535 f\n")
            }
        }
        
        
        //Trailer
        write("trailer\n")
        write("<< /Size \(objectList.count) /Root \(catalog) 0 R /Info \(infoObject) 0 R >>\n")
        write("startxref\n\(startXRef)\n%%EOF\n")
        
        try! fh?.close()
        fh = nil
    }
    
    func newPage() {
        if !pageIsClean {
            endPage()
            startPage()
        }
        pageIsClean = true
        currentPosition = NSPoint(x: xMargin, y: yMargin)
    }
    
    func textOut (_ text: String, at: NSPoint,typeFace: String? = nil,_ fontSize: CGFloat = 0, horizontalScale: CGFloat = 100, color: NSColor, shading: CGFloat = 1.0,  angle: CGFloat = 0) {
        
        currentPosition = at

        // Add font if necessary
        var thisFont = -1
        let tf = typeFace ?? "Courier"
        let st = type1Fonts.contains(tf) ? "Type1" : "TrueType"
        if let x = fontList.firstIndex(where: {(f) -> Bool in f.typeFace == tf }) {
            thisFont = x
        }
        else {
            thisFont = fontList.count
            fontList.append(Font(objectNumber: -1, typeFace: tf, subType: st))
        }
        
        
        if (angle != 0) {
            let a = CGFloat.pi * angle / 180.0
            var cosa = cos(a)
            var sina = sin(a)
            
            let verySmall = 0.0001
            if ((cosa > -verySmall) && (cosa < verySmall)) { cosa = 0 }
            if ((sina > -verySmall) && (sina < verySmall)) { sina = 0 }
            write("q \(cosa) \(sina) \(-sina) \(cosa) \(currentPosition.x) \(pageSize.height-currentPosition.y) cm\n")
            
            
            // MARK: Force the font and fill to be redefined...
            currentFont = -1
            //currentFill = -1
        }
        
        write("BT\n")
        
        if (thisFont != currentFont) || (fontSize != currentFontSize) {
            currentFont = thisFont
            currentFontSize = (fontSize > 0) ? fontSize : 10.0
            write("/F\(currentFont) \(currentFontSize) Tf\n")
            
            // Force Horizontal Scale to be redefined.
            currentScale = -1
        }

        if (currentScale != horizontalScale) {
            currentScale = horizontalScale
            write("\(horizontalScale) Tz\n")
        }

        setFill (color: color);
        
        if (angle == 0) {
            write("\(currentPosition.x) \(pageSize.height-yMargin-currentPosition.y) Td\n")
        }
        
        write("(")
        for c in text.utf8 {
            characterOut(c)
        }
        write(")Tj ET\n")
        
        if (angle != 0) {
            write("Q\n")
            currentFont = -1
        }
        
        pageIsClean = false
    }
    
    func textOut (_ text: String,_ xRelative: CGFloat,_ yRelative: CGFloat, _ typeFace: String? = nil,_ fontSize: CGFloat = 0,_ color: NSColor, _ shading: CGFloat = 1.0,  _ angle: CGFloat = 0) {
        textOut(text, at: NSPoint(x: currentPosition.x + xRelative, y: currentPosition.y + yRelative), typeFace: typeFace, fontSize, horizontalScale: 100, color: color, shading: shading, angle: angle)
    }
    
    // For simple line by line output, with margins, and automatic new page.
    func lineOut (_ text: String, _ font: NSFont,_ color: NSColor, skip: Int = 0, pageThresh: CGFloat = 100) {
        let yDelta = font.pointSize * 1.1 * CGFloat(skip + 1)
        currentPosition.y += yDelta
        if (currentPosition.y > pageSize.height - yMargin) || (((currentPosition.y-yMargin) / (pageSize.height-2*yMargin)) > pageThresh) {
            newPage()
        }
        textOut (text, 0, 0, font.familyName, font.pointSize, color)
    }
    
    func moveTo (_ position: NSPoint) {
        currentPosition = position
    }
    
    func moveRelative (_ x: CGFloat,_ y: CGFloat) {
        moveTo(NSPoint(x: currentPosition.x + x, y: currentPosition.y + y))
        
    }
    
    func lineTo (_ position: NSPoint,_ color: NSColor,_ penwidth: CGFloat) {
        write("\(currentPosition.x) \(pageSize.width-currentPosition.y) m\n")
        currentPosition = position
        write("\(currentPosition.x) \(pageSize.width-currentPosition.y) l\nS\n")
        pageIsClean = false
    }
    
    func shadedRectangle (at: NSPoint, size: NSSize,_ shading: CGFloat,_ color: NSColor) {
        if (shading > 0) {
            let hwadjustment = 0.0 // (clinewidth / 10.0);
            let tladjustment = hwadjustment * 2;
            setFill (color: color);
            write("\(at.x+tladjustment) \(at.y-tladjustment) \(size.width-hwadjustment) \(hwadjustment-size.height) re\nf\n")
            pageIsClean = false
        }
    }

}
