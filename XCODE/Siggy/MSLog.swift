//
//  MSLog.swift
//  Generic log file management
//
//  Created by MS on 2023-12-21.
//

import Foundation
import AppKit

//MARK: MIT LICENSE
//  Copyright 2023, Michael G. Sidnell
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

func MSLog (level: MSLogManager.LogLevel = .always,_ message: String, function: String = #function, line: Int = #line) {
    MSLogManager.shared.log (level: level, "\(function):\(line): "+message)
}


class MSLogManager {
    static let shared = MSLogManager()
    
    public enum LogLevel: Int, CaseIterable, Comparable {
        case always = 0
        case error = 1
        case warning = 2
        case info = 3
        case detail = 4
        case trace = 5
        case debug = 6
        
        var name: String { get { return myName() }}
        func myName () -> String {
            switch (rawValue) {
            case 0: return "always"
            case 1: return "error"
            case 2: return "warning"
            case 3: return "info"
            case 4: return "detail"
            case 5: return "trace"
            case 6: return "debug"
            default: return "unknown"
            }
        }
        
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
    }
    var logPrefix: String = "LOG"
    var logDirectory: String = "logs"
    var logFailed: Bool = false
    var logLevel: LogLevel = .always
    var logURL: URL?
    var logDebug: Bool { get { return (logLevel >= .debug) }}

    init () {
    }
    
    func setLogDirectory (_ dir: String) {
        logDirectory = dir
    }
    
    func setLogPrefix (_ prefix: String) {
        logPrefix = prefix
    }
    
    func setLogLevel (level: LogLevel) {
        self.logLevel = level
        //applicationDB.setGlobalSetting ("LogLevel", String(level.rawValue))
    }
    
    func log(level: LogLevel, _ message: String) {
        guard !logFailed else { return }
        guard (level.rawValue <= logLevel.rawValue) else {return }
        NSLog (message)

        let formatter = DateFormatter()
        
        if (logURL == nil) {
            formatter.dateFormat = "yyyyMMdd"
            let dateString = formatter.string(from: Date())
            let filename = logPrefix+"."+dateString+".log"
            let applicationLibraryDirectory = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            logURL = applicationLibraryDirectory.appendingPathComponent(logDirectory)
            if (logURL == nil) {
                logFailed = true
                return
            }
            try? FileManager.default.createDirectory(at: logURL!, withIntermediateDirectories: true, attributes: nil)
            logURL = logURL!.appendingPathComponent(filename)
            
        }
        
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        guard let data = (timestamp + ": " + message + "\n").data(using: String.Encoding.utf8) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: logURL!.path) {
                let fileHandle = try FileHandle(forWritingTo: logURL!)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
            else {
                try data.write(to: logURL!, options: .atomicWrite)
            }
        }
        catch {
            logFailed = true
        }
    }
    
}


