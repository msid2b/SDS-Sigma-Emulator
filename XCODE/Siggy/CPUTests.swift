//
//  CPUTests.swift
//  Siggy
//
//  Created by ms on 2024-11-17.
//

func floatTest(_ mode: CPU.PSD.FloatMode) {
    let n1: [UInt32] =
    [0x7FFFFFFF, 0x43500000, 0x3DD10000, 0x017FF000,  0x00100000, 0x00000000, 0xFFF00000, 0xFE801000,
     0xC22F0000, 0xBDD10000, 0xBCB00000, 0x80000001,  0x40100000, 0x40200000, 0x40400000, 0x40800000,
     0x41100000, 0x41200000, 0x41400000, 0x41800000]
    
    MSLog("BEGIN FLOAT TEST 1")
    for u in n1 {
        var line = hexOut(u, width: 8)+": "
        let d = ie3Float(u)
        line += String(d)+"(\(hexOut(d.bitPattern,width:16))), "
        let (v,o,c) = sigmaDouble(d, mode)
        line += hexOut(v, width:16)+", CC=\(c)"
        if (o) { line += "  *OVERFLOW*"}
        MSLog(line)
    }
    
    let n2: [Double] = [1.0, -1.0, -47.0, 1280.0]
    
    MSLog("BEGIN FLOAT TEST 2")
    for d in n2 {
        var line = String(d)+"(\(hexOut(d.bitPattern,width:16))), "
        let (v,o,c) = sigmaDouble(d, mode)
        line += hexOut(v, width:16)+", CC=\(c)"
        if (o) { line += "  *OVERFLOW*"}
        MSLog(line)
    }
}
    
func decimalTest() {
    let max = Int128.max
    MSLog("Max: \(max)")
    
    var a = Int128(0)
    var n = 31
    while (n >= 0) {
        a = a * 10 + 9
        n -= 1
    }
    MSLog("9's: \(a); /9: \(a/9)")
}
