# XDS-Sigma-Emulator
Xerox Sigma 7 Emulator for MacOS.

## Introduction
This repository contains an XCode project that can be used to compile and run a Xerox Sigma 7 emulator.  The emulator is capable of running CP-V.  On a Mac M1 system it is considerably faster than a real Sigma.

The emulator can read either .mt or .tap format tapes.  The .tap format can be used for interchange with a SIMH system. 
 
Disk and RAD images are not compatible with SIMH.


## Getting Started
Download and compile the XCode project.  For speed, it is best to build a runnable app with the Project > Archive function.  Install this app in the applications directory and run it from there.   The file MacSiggy.pdf describes the initial set up and some of the program features.

## PO Tape
There is a F00 PO Tape in the Tapes directory of this respository.

## CP-V Resources
There are many many CP-V related resources including F00 sysgen tapes in Ken Rector's excellent sigma-cpv-kit (https://github.com/kenrector/sigma-cpv-kit)

## Manuals
Manuals for various hardware and for CP-V can be found at http://bitsavers.org/pdf/sds/sigma

