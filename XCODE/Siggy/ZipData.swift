//
//  ZipData.swift
//  Siggy
//
//  Created by MS on 2025-05-18.
//
//  Capable of unzipping zip-archives which contain either stored or deflated files (original algorithm).
//

import Cocoa

class ZipData: NSObject {
    // LittleEndian, of course
    let CDFHSignature = 0x02014b50
    let LFHSignature = 0x04034b50

    // Needs to be Data to search for
    let EOCDSignature = Data([0x50,0x4b,0x05,0x06])

    struct EOCD {
        var signature: UInt32                   // 0x06054b50
        var thisDisk: UInt16
        var cdStartDisk: UInt16
        var cdRecordsThisDisk: UInt16
        var cdRecordsTotal: UInt16
        var cdSize: UInt32
        var cdOffset: UInt32
        var commentLength: UInt16
        var comment: String
    }
    let eocdSize = 22                           // Size in ZIP data
    
    struct CDFH {
        var signature: UInt32                   // 0x02014b50 - Here's to you Phil
        var madeByVersion: UInt16
        var neededVersion: UInt16
        var flags: UInt16
        var compressionMethod: UInt16
        //var FileLastModificationTime: UInt16
        //var FileLastModificationDate: UInt16
        var fileModification: MSDate
        var CRC: UInt32
        var compressedDataSize: UInt32
        var uncompressedDataSize: UInt32
        var filenameLength: UInt16
        var extraFieldLength: UInt16
        var fileCommentLength: UInt16
        var diskNumberFileStart: UInt16
        var internalFileAttributes: UInt16
        var externalFileAttributes: UInt32
        var localFileHeaderOffset: UInt32
        var filename: String
        var extraField: Data?
        var comment: String
    }
    let cdfhSize = 46                           // Size in ZIP data
    
    struct LFH {
        var signature: UInt32                   // 0x04034b50
        var neededVersion: UInt16
        var flags: UInt16
        var compressionMethod: UInt16
        //var FileLastModificationTime: UInt16
        //var FileLastModificationDate: UInt16
        var fileModification: MSDate
        var CRC: UInt32
        var compressedDataSize: UInt32
        var uncompressedDataSize: UInt32
        var filenameLength: UInt16
        var extraFieldLength: UInt16
        var filename: String
        var extraField: Data?
    }
    let lfhSize = 30                            // Size in ZIP data
    
    var zip: NSData
    var cd: [CDFH] = []
    
    init?(_ data: Data) {
        zip = NSData (data: data)
        if (zip.count < eocdSize+cdfhSize+lfhSize) {
            return nil
        }
        super.init()
        headers()
    }
    
    init?(url: URL) {
        do {
            zip = try NSData(contentsOf: url)
            if (zip.count < eocdSize+cdfhSize+lfhSize) {
                return nil
            }
            super.init()
            headers()
        }
        catch {
            return nil
        }
    }
    
    func headers() {
        // Find start of EOCD record
        let r = zip.range(of: EOCDSignature, options: .backwards, in: NSRange(location: 0, length: zip.count-18))
        MSLog (level: .debug, "Zipfile EOCD record start: \(r.location)")
        
        var cdOffset = Int(zip.bytes.loadUnaligned(fromByteOffset: r.location+16, as: UInt32.self))
        let cdCount = Int(zip.bytes.loadUnaligned(fromByteOffset: r.location+10, as: UInt16.self))
        MSLog (level: .debug, "Zipfile Central Directory Offset: \(cdOffset), count: \(cdCount)")

        // Make a list of central directory file headers, so that it is easy to process.
        cd.append(getCDFH(at: cdOffset)!)
        var n = 1
        while n < cdCount {
            cdOffset += cdfhSize + Int((cd[n-1].filenameLength + cd[n-1].extraFieldLength + cd[n-1].fileCommentLength))
            cd.append(getCDFH(at: cdOffset)!)
            n += 1
        }
    }
    
    // Get and convert date and time
    func getDate(dateOffset: Int, timeOffset: Int) -> MSDate? {
        let date16 = Int(zip.bytes.loadUnaligned(fromByteOffset: dateOffset, as: UInt16.self))
        let time16 = Int(zip.bytes.loadUnaligned(fromByteOffset: timeOffset, as: UInt16.self))
        
        let s = (time16 & 0x1f) << 1
        let m = (time16 >> 5) & 0x3f
        let h = time16 >> 11
        
        let d = (date16 & 0x1f)
        let n = (date16 >> 5) & 0xf
        let y = (date16 >> 9) + 1980
        
        return MSDate(components: MSDateComponents(year: y, month: n, day: d, hour: h, minute: m, second: s, tick: 0))
    }
    
    func getString(at offset: Int, length: Int) -> String {
        var s: String = ""
        
        if (length > 0) {
            for i in 0 ... length-1 {
                s += String(Character(Unicode.Scalar(zip[offset+i])))
            }
        }
        return s
    }
    
    func getCDFH (at offset: Int) -> CDFH? {
        let signature = zip.bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        guard (signature == CDFHSignature) else { return nil }
                                                
        let filenameLength = Int(zip.bytes.loadUnaligned(fromByteOffset: offset+28, as: UInt16.self))
        let fileCommentLength = Int(zip.bytes.loadUnaligned(fromByteOffset: offset+32, as: UInt16.self))
        
        let cdfh = CDFH(signature: signature,
                        madeByVersion: zip.bytes.loadUnaligned(fromByteOffset: offset+4, as: UInt16.self),
                        neededVersion: zip.bytes.loadUnaligned(fromByteOffset: offset+6, as: UInt16.self),
                        flags: zip.bytes.loadUnaligned(fromByteOffset: offset+8, as: UInt16.self),
                        compressionMethod: zip.bytes.loadUnaligned(fromByteOffset: offset+10, as: UInt16.self),
                        fileModification: getDate(dateOffset: offset+14, timeOffset: offset+12) ?? MSDate(),
                        CRC: zip.bytes.loadUnaligned(fromByteOffset: offset+16, as: UInt32.self),
                        compressedDataSize: zip.bytes.loadUnaligned(fromByteOffset: offset+20, as: UInt32.self),
                        uncompressedDataSize: zip.bytes.loadUnaligned(fromByteOffset: offset+24, as: UInt32.self),
                        filenameLength: UInt16(filenameLength),
                        extraFieldLength: zip.bytes.loadUnaligned(fromByteOffset: offset+30, as: UInt16.self),
                        fileCommentLength: UInt16(fileCommentLength),
                        diskNumberFileStart: zip.bytes.loadUnaligned(fromByteOffset: offset+34, as: UInt16.self),
                        internalFileAttributes: zip.bytes.loadUnaligned(fromByteOffset: offset+36, as: UInt16.self),
                        externalFileAttributes: zip.bytes.loadUnaligned(fromByteOffset: offset+38, as: UInt32.self),
                        localFileHeaderOffset: zip.bytes.loadUnaligned(fromByteOffset: offset+42, as: UInt32.self),
                        filename: getString(at: offset+46, length: filenameLength),
                        comment: getString(at: offset+46+filenameLength, length: fileCommentLength))
        return cdfh
    }
    
    func getLFH (at offset: Int) -> LFH? {
        let signature = zip.bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        guard (signature == LFHSignature) else { return nil }
        
        let filenameLength = Int(zip.bytes.loadUnaligned(fromByteOffset: offset+26, as: UInt16.self))
        
        let lfh = LFH(signature: signature,
                        neededVersion: zip.bytes.loadUnaligned(fromByteOffset: offset+4, as: UInt16.self),
                        flags: zip.bytes.loadUnaligned(fromByteOffset: offset+6, as: UInt16.self),
                        compressionMethod: zip.bytes.loadUnaligned(fromByteOffset: offset+8, as: UInt16.self),
                        fileModification: getDate(dateOffset: offset+12, timeOffset: offset+10) ?? MSDate(),
                        CRC: zip.bytes.loadUnaligned(fromByteOffset: offset+14, as: UInt32.self),
                        compressedDataSize: zip.bytes.loadUnaligned(fromByteOffset: offset+18, as: UInt32.self),
                        uncompressedDataSize: zip.bytes.loadUnaligned(fromByteOffset: offset+22, as: UInt32.self),
                        filenameLength: UInt16(filenameLength),
                        extraFieldLength: zip.bytes.loadUnaligned(fromByteOffset: offset+28, as: UInt16.self),
                        filename: getString(at: offset+30, length: filenameLength))
        return lfh
    }
    
    func forEachFile (call: (CDFH?, Data?)->Bool ) {
        for cdfh in cd {
            if let lfh = getLFH(at: Int(cdfh.localFileHeaderOffset)) {
                let offset = Int(cdfh.localFileHeaderOffset) + lfhSize + Int(lfh.filenameLength) + Int(lfh.extraFieldLength)
                
                let compressedData = NSData(data: zip.subdata(with: NSRange(location: offset, length: Int(cdfh.compressedDataSize))))
                var fileData: Data?
                
                switch (cdfh.compressionMethod) {
                case 0:
                    fileData = Data(compressedData)
                case 8:
                    do {
                        fileData = try Data(compressedData.decompressed(using: .zlib))
                    }
                    catch {
                        MSLog(level: .error, "Failed to inflate \(cdfh.filename)")
                    }
                    
                default:
                    MSLog(level: .error, "Cannot handle compression method \(lfh.compressionMethod) for \(cdfh.filename)")
                }
                
                if !call(cdfh, fileData) {
                    break
                }
            }
            else {
                MSLog(level: .error, "Failed to get local file header for \(cdfh.filename)")
            }
        }
    }
}


// Intended to move a single file for installation purposes.
// If the source file exists, and is not a zip file, it is copied.
// If the zip file contains a file of the same name (less the zip extension), it is unzipped to the expected destination.
// Returns the resulting filename or nil
//
func copyOrUnzip (_ source: URL, toDirectory: URL, toFile: String, useSourceExtension: Bool = false) -> String? {
    guard FileManager.default.fileExists(atPath: source.path) else { return nil }
    
    let ext = source.pathExtension.lowercased()
    if (ext != "zip") {
        let tf = useSourceExtension ? toFile + "." + ext : toFile
        let destination = toDirectory.appendingPathComponent(tf)
        let destPath = destination.path
        
        do {
            if (FileManager.default.fileExists(atPath: destPath)) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.copyItem(atPath: source.path, toPath: destPath)
            return (tf)
        } catch {
            siggyApp.FileManagerThrew(error, message: "Cannot copy to \(destPath)")
        }
    }
    else {
        let nz = source.deletingPathExtension()
        let ext = nz.pathExtension
        let fileOfInterest = nz.lastPathComponent
        
        let tf = useSourceExtension ? toFile + "." + ext : toFile
        var result: String?
        
        func uz (cdfh: ZipData.CDFH?, fileData: Data?) -> Bool {
            if let fh = cdfh, let d = fileData {
                if fh.filename == fileOfInterest {
                    
                    let fileURL = toDirectory.appendingPathComponent(tf)
                    do {
                        try d.write(to: fileURL)
                        result = tf
                    }
                    catch {
                        MSLog(level: .warning, "Cannot write to temporary file: \(fileURL.path)")
                        return false // Abort
                    }
                    // Got the file we want, terminate.
                    return false
                }
            }
            return false
        }
        
        
        if let zd = ZipData(url: source) {
            zd.forEachFile(call: uz)
        }
        return result
    }
    return nil
}
