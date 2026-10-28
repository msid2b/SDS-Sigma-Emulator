//
//  MediaInitializeController.swift
//  Siggy
//
//  Created by MS on 2026-09-26.
//
//MARK: NOT CURRENTLY USED.
//MARK: TO INITIALIZE DISKS AND DISK SETS>
//MARK: USE THE CP_V VOLINIT PROCESSOR OR THE MacOS terminal utility volinit
//
// PRIVATE VOLUME SET TABLES
// A private volume set is a collection of disk pack volumes that the user has
// grouped together, containing any number of files with any type of organiza-
// tion. A private volume set is a self-contained entity and contains its own
// account directory and file directories (which contain information about all
// files on the private volume set). The account directory for a private
// volume set is located on granule 1 of the primary volume. The first file
// directory begins on granule 2; each file directory thereafter begins on a
// successive logical cylinder boundary. Because volumes can be mounted
// serially for consecutive files, file directories cannot extend beyond the
// primary volume. The format for the private file directories is the same as
// for the public directories. Every private volume has a Volume Table of
// Contents (VTOC) which is built by the VOLINIT processor and is located on
// granule 0 of the volume. The format of the VToc is shown on the following
// page.
//
//
// VOLUME TABLE OF CONTENTS (VTOC) FORMAT (CP-V TECHNICAL MANUAL SECTION VH.06)
//
//WORD
// 0               : LBL (X'7AD3C2D3')
// 1/2             VSN
// 3               SNTD
// 4               NGC / MAPWL
// 5               NVAT
// 6               MAPWD / First Sector Number
// 7 for MAPWL     BIT MAP (1 bit per cylinder)
// MAPWL+7         NSN
//                 SNT (serial no. table - NSN entries)
//
// VTOC Fields
//    Bit Map contains the cylinder bit map for the volume. If the bit is set, the cylinder is unal-
//        located. If the bit is reset, the cylinder is allocated. For devjces where the
//        number of cyl inders is not an even multiple of 32,   VOLINIT  RESETS the bits in the
//        last word which do not represent cyl inders.
//
//    First Sector contains the sector number for the first sector on the dev i ce (i. e., sector O)
//
//
//    MAPWD  contains the word displacement from the start of an allocation table to the bit map.
//        MAPWD is set to X '07' by the VOLINIT processor.
//
//    MAPWL contains the number of words in the bit map.
//
//    NSN contains the number of serial numbers in the Serial Number Table.
//
//    NGC contains the number of granules per logical cylinder.
//
//    NVAT contains the next volume's cylinder 0 allocation table. Each bit represents
//        a granule. If the bit is set, the granule is unallocated. If the bit is
//        reset, the granule is allocated. The first bit, which represents granule 0
//        is always set allocated. NVAT is only used when a consecutive fi Ie
//        extends beyond volume boundaries.
//
//    SNT contains the serial numbers of a" the volumes in the private vol ume set
//      for the primary volume. The position of a serial number represents its
//      volume number. (The primary volume is always volume 1.) The order
//      of the serial numbers never changes, but new volumes can be added to
//      the set, and will be added at the end. For other volumes, this table
//      contains only the serial number of the primary volume. Only the first
//      four bytes of the serial number are carried in the serial number table.
//
//    SNTD contains the word displacement from the start of the VTOC to the
//      start of the Serial Number Table.
//
//    VSN contains the volume serial number (left-justified and blank-filled to eight bytes.)
//

import Cocoa

class MediaInitializeController: NSViewController, NSWindowDelegate {
    
    @IBOutlet weak var textLabel: NSTextField!

    @IBOutlet weak var radioSingle: NSButton!
    @IBOutlet weak var radioPrimary: NSButton!
    @IBOutlet weak var radioSecondary: NSButton!
    @IBOutlet weak var radioOther: NSButton!

    var labelEBCDIC: UInt32 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        textLabel.stringValue = ""
    }

    func runModal (_ d: DPDevice?, label: UInt32) -> NSApplication.ModalResponse {
        if let w = view.window {
            labelEBCDIC = label
            textLabel.stringValue = ebcdicWordToString(labelEBCDIC)
            
            return NSApp.runModal(for: w)
        }
        return .abort
    }
    
    @IBAction func buttonCancelClick(_ sender: Any) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    @IBAction func buttonDoneClick(_ sender: Any) {
        NSApp.stopModal(withCode: .continue)
    }
    
    @IBAction func textLabelChange(_ sender: Any) {
    }

    
    @IBAction func radioOtherClick(_ sender: Any) {
    }
    @IBAction func textPrimaryClick(_ sender: Any) {
    }
    @IBAction func radioSecondaryClick(_ sender: Any) {
    }
    @IBAction func radioSingleClick(_ sender: Any) {
    }
    @IBAction func radioPrimaryClick(_ sender: Any) {
    }
}
