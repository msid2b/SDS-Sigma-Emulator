//
//  sql.swift
//
//  Created by MS on 2022-06-17.
//
//MARK: MIT LICENSE
//  Copyright (c) 2022, Michael G. Sidnell
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



import Foundation
import SQLite3
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


func sqlDateString (_ date: Date?) -> String {
    guard (date != nil) else { return "" }
    if #available(macOS 12.0, *) {
        return date!.ISO8601Format()
    } else {
        let dtFormatter = ISO8601DateFormatter()
        dtFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return dtFormatter.string(from: date!)
    }
    
}

func sqlStringDate (_ date: String?) -> Date? {
    if (date == nil) || (date!.trimmingCharacters(in: .whitespaces) == "") {
        return nil
    }
    let dtFormatter = ISO8601DateFormatter();
    dtFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let result = dtFormatter.date (from: date!) {
        return result
    }
    
    let dtFormatter2 = DateFormatter();
    dtFormatter2.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return dtFormatter2.date (from: date!)
}

class SQLDB: NSObject {
    private var dbHandle: OpaquePointer?
    private var handleValid: Bool = false
    private var lastSQLResult: Int32 = SQLITE_OK
    private var statements: [SQLStatement] = []
    private var statementLock = NSLock()
    
    var handle: OpaquePointer? { get { return dbHandle }}
    var isOpen: Bool { get { return handleValid }}
    var message: String { get { return getMessage() }}
    
    private func getMessage() -> String {
        return (String (cString: sqlite3_errmsg(dbHandle)))
    }
    
    func open (dbPath: String?) -> Bool {
        lastSQLResult = sqlite3_open(dbPath, &dbHandle)
        handleValid = (lastSQLResult == SQLITE_OK)
        return (handleValid)
    }
    
    func close () {
        _ = sqlite3_close_v2(dbHandle)
        handleValid = false
    }
    
    func quiesce() {
        NSLog ("Quiescing")

        var count = 0
        for s in statements {
            debugPrint(("Releasing: "+s.statementText))
            s.done()
            count += 1
        }
        debugPrint ("Released \(count) statements")
    }
    
    func execute (_ statement: String) -> Bool {
        lastSQLResult = isOpen ? sqlite3_exec (dbHandle, statement, nil, nil, nil) : SQLITE_MISUSE
        return (lastSQLResult == SQLITE_OK)
    }
    
    func activate (statement: SQLStatement) {
        statementLock.lock()
        statements.append(statement)
        statementLock.unlock()
    }
    
    func deactivate (statement: SQLStatement) {
        statementLock.lock()
        if let x = statements.firstIndex(where: { s in (s == statement)}) {
            statements.remove(at: x)
        }
        statementLock.unlock()
    }
}


class SQLStatement: NSObject {
    var db: SQLDB
    var lastSQLResult: Int32 = SQLITE_OK
    
    var dbStatementHandle: OpaquePointer? = nil
    var statementText: String
    
    required init (_  db: SQLDB) {
        self.db = db
        statementText = ""
        super.init()
        db.activate(statement: self)
    }
    
    func prepare (statement: String) -> Bool {
        statementText = statement
        lastSQLResult = db.isOpen ? sqlite3_prepare (db.handle, statementText, -1, &dbStatementHandle, nil) : SQLITE_MISUSE
        return (lastSQLResult == SQLITE_OK)
    }
    
    func done() {
        sqlite3_finalize(dbStatementHandle)
        db.deactivate(statement: self)
    }
    
    // MARK: Could have just overloaded "bind", but copied SQLite approach
    func bind_int64 (_ n: Int,_ value: Int64?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), v)
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_int64 (_ n: Int,_ value: UInt64?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), Int64(bitPattern: v))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
   func bind_int (_ n: Int,_ value: Int?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), Int64(v))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_int (_ n: Int,_ value: Int32?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), Int64(v))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_int (_ n: Int,_ value: Int16?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), Int64(v))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_int (_ n: Int,_ value: UInt8?) {
        if let v = value {
            sqlite3_bind_int64 (dbStatementHandle, Int32(n), Int64(v))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_double (_ n: Int,_ value: Double?) {
        if let v = value {
            sqlite3_bind_double (dbStatementHandle, Int32(n), v)
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_string (_ n: Int,_ value: String?) {
        if (value != nil) {
            let cString = value!.cString(using: .utf8)
            sqlite3_bind_text (dbStatementHandle, Int32(n), cString, -1, SQLITE_TRANSIENT)
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_bool (_ n: Int,_ value: Bool?) {
        if (value != nil) {
            let cString = (value! ? "Y" : "N").cString(using: .ascii)
            sqlite3_bind_text (dbStatementHandle, Int32(n), cString, -1, SQLITE_TRANSIENT)
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_date (_ n: Int,_ value: Date?) {
        if (value != nil) {
            bind_string (n, sqlDateString(value))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
        
    }
 
    func bind_msdate (_ n: Int,_ value: MSDate?, timeZone tz: TimeZone? = nil) {
        if (value != nil) {
            bind_string (n, value?.ISO8601Format(timeZone: tz))
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
    }
    
    func bind_blob (_ n: Int,_ value: NSData?) {
        if let v = value {
            sqlite3_bind_blob (dbStatementHandle, Int32(n), v.bytes, Int32(v.length), SQLITE_TRANSIENT)
        }
        else {
            sqlite3_bind_null (dbStatementHandle, Int32(n))
        }
        
    }
    
    func row () -> Bool {
        lastSQLResult = sqlite3_step(dbStatementHandle)
        return (lastSQLResult == SQLITE_ROW)
    }
    
    func execute() -> Bool {
        lastSQLResult = sqlite3_step(dbStatementHandle)
        return (lastSQLResult == SQLITE_DONE)
    }
    
    func column_int64 (_ n: Int) -> Int64? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        let v = sqlite3_column_int64(dbStatementHandle, Int32(n))
        return v
    }
    
    func column_int64 (_ n: Int, defaultValue: Int64) -> Int64 {
        if let i = column_int64(n) {
            return i
        }
        return defaultValue
    }
    
    func column_uint64 (_ n: Int) -> UInt64? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        let v = sqlite3_column_int64(dbStatementHandle, Int32(n))
        return UInt64(bitPattern: v)
    }
    
    func column_uint64 (_ n: Int, defaultValue: UInt64) -> UInt64 {
        if let i = column_uint64(n) {
            return i
        }
        return defaultValue
    }
    
    func column_int (_ n: Int) -> Int? {
        if let i = column_int64(n) {
            return (Int(i))
        }
        return nil
    }
    
    func column_int(_ n: Int, defaultValue: Int) -> Int {
        if let i = column_int(n) {
            return i
        }
        return defaultValue
    }
    
    func column_string (_ n: Int) -> String? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        if let v = sqlite3_column_text(dbStatementHandle, Int32(n)) {
            return String(cString: v)
        }
        return nil
    }
    
    func column_string (_ n: Int, defaultValue: String) -> String {
        if let s = column_string (n) {
            return s
        }
        return defaultValue
    }
    
    func column_bool (_ n: Int) -> Bool? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        if let v = sqlite3_column_text(dbStatementHandle, Int32(n)) {
            return (String(cString: v) == "Y")
        }
        return nil
    }
    
    func column_bool (_ n: Int, defaultValue: Bool) -> Bool {
        if let d = column_bool (n) {
            return d
        }
        return defaultValue
    }
    
    func column_date (_ n: Int) -> Date? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        if let v = sqlite3_column_text(dbStatementHandle, Int32(n)) {
            return sqlStringDate(String(cString: v))
        }
        return nil
    }
    
    func column_date(_ n: Int, defaultValue: Date) -> Date {
        if let d = column_date (n) {
            return d
        }
        return defaultValue
    }
    
    func column_msdate (_ n: Int) -> MSDate? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        if let v = sqlite3_column_text(dbStatementHandle, Int32(n)) {
            return MSDate(String(cString: v))
        }
        return nil
    }
    
    func column_msdate(_ n: Int, defaultValue: MSDate) -> MSDate {
        if let d = column_msdate (n) {
            return d
        }
        return defaultValue
    }
    
 
    func column_double (_ n: Int) -> Double? {
        if (SQLITE_NULL == sqlite3_column_type(dbStatementHandle, Int32(n))) {
            return nil
        }
        let v = sqlite3_column_double(dbStatementHandle, Int32(n))
        return v
    }
    
    func column_double (_ n: Int, defaultValue: Double) -> Double {
        if let d = column_double (n) {
            return d
        }
        return defaultValue
    }
    
    func column_blob (_ n: Int) -> NSData? {
        let data = sqlite3_column_blob(dbStatementHandle, Int32(n))
        let size = Int(sqlite3_column_bytes(dbStatementHandle, Int32(n)))
        if (size > 0) { return NSData(bytes: data,length: size) }
        return nil
    }
    
    func insertedRowID() -> Int {
        return Int(sqlite3_last_insert_rowid(db.handle))
    }
    
}
