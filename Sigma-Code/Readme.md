This directory contains various source code for programs that run on CP-V.


LA is a program that lists files which match a pattern and which have specific attributes:
 
LA: List all files with name and account matching pattern
Version date: AUGUST, 2026
LA filepattern[.accountpattern][,selection-options]
 
One file is listed one per line in a manner similar to the 
output of the PCL L(A) command.  If the DETAIL option is 
supplied, then the information for each file is split into 
multiple lines.
 
File and account patterns can contain wildcard characters:
   *   matches any sequence of characters
   ?   matches any single character
   +   matches any single digit
   \   naturalizes the following character
 
   !pattern matches if pattern does not
 
e.g.
 LA * lists all files in the current account
 LA *.* lists all files on the system
 LA J:*+ lists all files beginning with J:, and ending with a digit
 LA ABC.9* lists files named ABC in accounts beginning with 9
 LA \* lists the file "*"
 LA !A* lists files that do not begin with A
 
 Selection options are separated by commas. Except for simple
 boolean options and arguments can be specified as a list, 
 e.g:
   (ORG,'K','C')
 Dates and integers can use comparators rather than the comma:
   ACCESSED<29FEB96
   (CREATED>01JAN97<31DEC97)
   (GRAN<5>10)
 
 Dates can take various forms including: DDMMMYY, YYYY-MM-DD.
   The form JD-n or JD+n express dates relative to the current
   day, e.g. ACCESSED>JD-7 selects files accessed in the last
   week.
 
 Using a list of values constructs a condition which is
 satisifed if any of the terms match,  e.g.
   GRAN<5>10 selects files of less than 5 granules OR more
   than 10
 Using multiple entries implies an AND, e.g.
   GRAN>5,GRAN<10 selects files with greater than 5 AND less
   than 10 granules
 
Selection Options:
 At least 3 characters of the option name are required.  When
 the option ends in ! (e.g. DELETE!), abbreviation is not
 allowed.
 
ACCESSED
    Select files with a specific last open date range
CREATED
    Select files with a specific creation date range
DELETE!
    ANY MATCHED FILES WILL BE DELETED
DETAIL
    Print more file information (RECORDS, R, W, E, etc)
EXPIRED!
    Files that are expired
EXPIRES
    Select files with a specific expiry date range
GRANULES
    Select files with the specified size range
IGNORE
    Ignore any access errors
KEYLENGTH
    Select files with the specified key size
MODIFIED
    Select files with a specific modification date range
ORG
    Select files with one of the specified ORGs (C,K, or R)
RECORDS
    Select files with the specified number of records
SAVED
    Select files with a specific saved date range
UNSAVED
    Files that have not been saved
VERBOSE
    Print debugging information
