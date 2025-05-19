# SDS-Sigma-Emulator
SDS Sigma 7 Emulator for MacOS.

## Introduction
This repository contains an XCode project that can be used to compile and run a Xerox Sigma 7 emulator.  
The emulator is capable of booting and running CP-V.  
On a Mac M1 system it is considerably faster than a real Sigma.

## Getting Started
Download and compile the XCode project.  For speed, it is best to build a runnable app with the Project > Archive function.  
I find it easiest to install the resulting app in the Applications directory and run it from there.   
The file MacSiggy.pdf describes the initial set up and some of the program features.

## PO Tape
There is a F00 PO Tape in the Tapes directory of this respository.  

## Installer
The Installer directory contains a zip file of the compiled application.  This can be installed directly on a Mac by copying the application package to the Applications directory.

## SIMH Compatibility
The emulator can read and write both .tap and .mt format tape images: .tap files can be used for interchange with SIMH emulated Sigmas. 
Disk and RAD images are not compatible with SIMH, although it should be possible to convert them. (At a minimum the bytes in each word  would have to be swapped. It might also be necessary to change the order of the disk sectors in the image).

## CP-V Resources
There are many many CP-V related resources including PO Tapes; Sysgen related binaries and source; SST and X accounts, etc.  in Ken Rector's excellent sigma-cpv-kit (https://github.com/kenrector/sigma-cpv-kit)

## Manuals
Manuals for various hardware and for CP-V can be found at http://bitsavers.org/pdf/sds/sigma

