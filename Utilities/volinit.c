//MARK: volinit: create and initialize a siggy private pack (set)
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
// WORD
// 0               :LBL (X'7AD3C2D3')
// 1/2             VSN
// 3               SNTD
// 4               NGC / MAPWL
// 5               NVAT
// 6               MAPWD / First Sector Number
// 7 for MAPWL     BIT MAP (1 bit per cylinder)
// MAPWL+7         NSN
// MAPWL+8 for NSN SNT (serial no. table - NSN entries)
//
// VTOC Fields
//    Bit Map contains the cylinder bit map for the volume. If the bit is set, the cylinder is unal-
//        located. If the bit is reset, the cylinder is allocated. For devjces where the
//        number of cyl inders is not an even multiple of 32,   VOLINIT  RESETS the bits in the
//        last word which do not represent cyl inders.
//
//    First Sector contains the sector number for the first sector on the device (i. e., sector O)
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
#define clen(x) ((x+2)&0x7ffe)

#define FALSE 0
#define TRUE  1

#include <ctype.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <stdint.h>
#include <unistd.h>

#define WPS     0x100
#define WPG     0x200
#define BPG     0x800
uint32_t granule[WPG];
uint32_t zgranule[WPG];

// For allocating file directories.
int nextfdgranule = 2;

struct MODEL {
    int number;
    int granpercyl;
    
    int cylinders;
    int heads;
    int sectors;
};

struct MODEL modtable[] = {
    {7242,0x1e, 200,20,6},
    {7261,0x37, 200,20,11},
    {7271,0x1e, 400,20,6},
    {7275,0x34, 404,19,11},
    {3275,0x39, 404,19,12},
    {9210,0x7a, 822,28,8},
    {0,0,0,0}};

unsigned char a2e[] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x09, 0x06, 0x07, 0x08, 0x05, 0x15, 0x0B, 0x0C, 0x15, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    0x40, 0x5A, 0x7F, 0x7B, 0x5B, 0x6C, 0x50, 0x7D, 0x4D, 0x5D, 0x5C, 0x4E, 0x6B, 0x60, 0x4B, 0x61,
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0x7A, 0x5E, 0x4C, 0x7E, 0x6E, 0x6F,
    0x7C, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
    0xD7, 0xD8, 0xD9, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xB4, 0xB1, 0xB5, 0x6A, 0x6D,
    0x4A, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xB2, 0x4F, 0xB3, 0x5F, 0xFF };


int fexists (const char *filename) {
  struct stat   buffer;
  return (stat (filename, &buffer) == 0);
}

void clencpy (char *d, const char *s, int l, int upshift) {
    if (l > 0) {
        int i;
        for (i=0; i<l; i++) {
            d[i] = upshift ? toupper(s[i]) : s[i];
            if (d[i] == 0) break;
        }
        
        int k = clen(l);
        while (i < k) {
            d[i] = 0;
            i++;
        }
    }
}

uint64_t atoe64(const char *s, int maxc) {
    int n;
    uint64_t e;
    
    e = 0;
    n = 0;
    while (s[n] && (n < maxc)) {
        e = (e << 8) | ((uint64_t)a2e[s[n]&0x7f]);
        n ++;
    }
    while (n < maxc) {
        e = (e << 8) | 0x40;
        n ++;
    }
    return e;
}


uint32_t atoe32(const char *s) {
    return ((uint32_t)atoe64(s,4));
}


void swapbytes (void *d, const void *s, size_t len) {
    uint8_t *db = (unsigned char *)d;
    uint8_t *sb = (unsigned char *)s;
    int i = 0;
    int m = len-1;
    for (; i<len; i++,m--)
        db[i] = sb[m];
}


uint32_t bswap32 (uint32_t x) {
    uint32_t r;
    swapbytes (&r, &x, sizeof(uint32_t));
    return r;
}

uint64_t bswap64 (uint64_t x) {
    uint64_t r;
    swapbytes (&r, &x, sizeof(uint64_t));
    //printf ("swap64: %llx -> %llx\n", x, r);
    return r;
}


int addacc (uint32_t *granule, uint64_t account, int islast, int gpc) {
    int nav = (int)(bswap32(granule[2]) >> 16);
    unsigned char *gb = (unsigned char *)granule;
    unsigned char *ab = (unsigned char *)&account;
    int i;
    
    printf("Adding account: X'%llx', NAV=0x%x\n", account, nav);
    if ((BPG-nav) < 21) {
        fprintf (stderr, "ACCOUNT DIRECTORY full: %llx\n", account);
        return (1);
    }
    
    gb[nav++] = 0x0b;
    for (i=0; i<3; i++) { gb[nav++] = 0x40; }
    for (i=0; i<8; i++) { gb[nav++] = ab[7-i]; }
    
    //MARK: NOW DISK ADDRESS OF FILE DIRECTORY
    // TWO BYTES VOLUME NUMBER
    gb[nav++] = 0;
    gb[nav++] = 1;
    // TWO BYTES FILE DIRECTORY SECTOR (SWAPPED)
    int nextfdsector = nextfdgranule << 1;
    gb[nav++] = (uint8_t)(nextfdsector >> 8);
    gb[nav++] = (uint8_t)(nextfdsector & 0xff);
    
    for (i=0; i<2; i++) { gb[nav++] = 0; }
    
    //MARK: FAK BYTE = 4 FOR ALL BUT LAST ENTRY WHICH IS 6.
    gb[nav++] = islast ? 0x6 : 0x4;
    
    for (i=0; i<2; i++) { gb[nav++] = 0; }
    
    //MARK: UPDATE NAV
    granule[2] = bswap32((uint32_t)(nav << 16) | 0x400C);
    
    //MARK: UPDATE NEXT FD GRANULE
    nextfdgranule = (nextfdgranule < gpc) ? gpc : (nextfdgranule + gpc);
    printf ("Next FD gran: 0x%x\n", nextfdgranule);
    return 0;
}

int initialize (const char *outfile, int volume, int overwrite, int modx, int nac, const char acc[][clen(8)], int nvs, const char volset[][clen(4)]) {
    
    FILE *of;
    uint64_t *ea;
    int s;
    int x;

    printf ("Initializing \"%s\", file: %s\n", volset[volume], outfile);
    if (fexists(outfile) && !overwrite)  {
        fprintf (stderr, "File already exists: %s\n", outfile);
        exit (0);
    }
    
    of = fopen (outfile, "wb");
    if (of == NULL) {
        fprintf (stderr, "Error opening file: %s\n", outfile);
        exit (0);
    }
    
    //MARK: BUILD AND WRITE THE VTOC
    memset(zgranule, 0x0, BPG);
    memset(granule, 0xff, BPG);
    granule[0] = bswap32(0x7AD3C2D3);
    granule[1] = bswap32(atoe32(volset[volume]));
    granule[2] = 0x40404040;
    granule[3] = bswap32(0x21);
    
    int gplc = modtable[modx].granpercyl;
    int sppc = modtable[modx].heads * modtable[modx].sectors;
    int gppc = sppc >> 1;
    int tgran = (modtable[modx].cylinders * gppc);
    int logicalc = tgran / gplc;
    int mapbits = (logicalc + 31) & 0x7fffe0;
    int resetbits = mapbits - logicalc;     // # non existent cylinders in last mapword
    int mapwl = mapbits >> 5;
    
    printf ("Model: %d\n", modtable[modx].number);
    printf ("Cylinders: %d, Heads: %d, Sectors/Track: %d\n", modtable[modx].cylinders, modtable[modx].heads, modtable[modx].sectors);
    printf ("Sectors, granules per Physical Cylinder: %d, %d\n", sppc, gppc);
    printf ("Total usable granules: %d, gplc: %d, cyl: %d, mapbits: %d, mapwl: %d\n", tgran, gplc, logicalc, mapbits, mapwl);
    
    granule[4] =  bswap32((uint32_t)((modtable[modx].granpercyl << 16) | mapwl));
    
    granule[5] = bswap32(0x7FFFFFFC);       // NVAT
    granule[6] = bswap32(0x00070000);       // MAPWD / First Sector Number

    //MARK: EACH ACCOUNT BEYOND 1 REQUIRES ANOTHER CYL: THIS CODE HANDLES MAX 32 ACCOUNTS
    if (nac > 1) {
        granule[7] = bswap32(0x7FFFFFFF >> (nac-1));
    }
    else {
        granule[7] = bswap32(0x7FFFFFFF);   // JUST First cylinder is allocated..
    }
    
    x = 6 + (int)mapwl;                     // last map word
    if (resetbits > 0) {
        granule[x] = bswap32((uint32_t)((0x7FFFFFFFu << resetbits) & 0xFFFFFFFF));
    }
    
    x++;
    granule[x] = bswap32((uint32_t)nvs);
    
    x++;
    for (s = 0; s < nvs; s ++) {
        granule[x+s] = bswap32(atoe32(volset[s]));
    }
    
    printf ("Writing VTOC.\n");
    if (WPG != fwrite (granule, sizeof(uint32_t), WPG, of)) {
        fprintf (stderr, "VTOC write failed: %s\n", outfile);
        exit (0);
    }
    
    //MARK: THE REST IS ONLY FOR THE PRIMARY VOLUME
    if (volume == 0) {
        
        //MARK: CONVERT THE ACCOUNT LIST TO EBCDIC AND SORT IT.
        if (nac > 0) {
            ea = malloc(sizeof(uint64_t)*nac);
            
            for (x = 0; x < nac; x++) {
                ea[x] = (uint64_t)atoe64(acc[x], 8);
                printf("Account \"%s\" -> X'%llx'.\n", acc[x], ea[x]);
            }
            
            int i,j;
            uint64_t z;
            for (i=0; i<nac; i++) {
                for (j=i+1; j<nac; j++) {
                    if (ea[j] < ea[i]) {
                        z = ea[j];
                        ea[j] = ea[i];
                        ea[i] = z;
                    }
                }
            }
            
        }
        //MARK: BUILD THE ACCOUNT DIRECTORY
        memset (granule, 0, BPG);
        granule[2] = bswap32(0x000C400C);       // BASE NAV, FULL GRAN, PRIVATE
        if (nac > 0) {
            int lac = nac-1;
            for (s = 0; s <= lac; s++ ) {
                addacc (granule, ea[s], (s == lac), gplc);
            }}
        else {
            addacc (granule, 0, TRUE, gplc);
        }
        
        printf ("Writing account directory.\n");
        if (WPG != fwrite (granule, sizeof(uint32_t), WPG, of)) {
            fprintf (stderr, "ACCOUNT DIRECTORY write failed: %s\n", outfile);
            exit (0);
        }
        
        //MARK: WRITE AN EMPTY FILE DIRECTORY FOR EACH ACCOUNT
        printf("Next available file directory granule: %x\n", nextfdgranule);
        
        memset (granule, 0, BPG);
        granule[2] = bswap32(0x000C4020);
        granule[0x1fc] = bswap32(0x80000000);   // TODO: What is this?
        int ngav = gplc - 3;                     // Grans avail this file dir.
        int g;
        for (g = 2; g < nextfdgranule; g++) {
            int s = g << 1;
            
            // Write a filler sector at end of physical cylinder if sppc is odd.
            if ((sppc & 1) && ((g % gppc) == 0)) {
                printf("Writing fill sector at sector %x\n", s);
                if (WPS != fwrite (zgranule, sizeof(uint32_t), WPS, of)) {
                    fprintf (stderr, "Fill (sector %d) write failed: %s\n", s, outfile);
                    exit (0);
                }
            }
            
            
            granule[0x1fd] = bswap32((uint32_t)((ngav << 24) | 0x010000 | s+2));
            
            printf("Writing file directory at sector %x\n", s);
            if (WPG != fwrite (granule, sizeof(uint32_t), WPG, of)) {
                fprintf (stderr, "FILE DIRECTORY (sector %d) write failed: %s\n", s, outfile);
                exit (0);
            }
            
            // FILL THE REST OF THE CYL
            while (ngav > 0) {
                s += 2;
                printf("Writing available file directory granule at sector %x\n", s);
                if (WPG != fwrite (zgranule, sizeof(uint32_t), WPG, of)) {
                    fprintf (stderr, "FILE DIRECTORY zero sector write failed: %s\n", outfile);
                    exit (0);
                }
                ngav --;
                g++;
            }
            ngav = gplc - 1;
        }
    }
    else {
        //MARK: PAD SECONDARY 
        
        for (x=7; x>0; x--) {
            if (WPG != fwrite (zgranule, sizeof(uint32_t), WPG, of)) {
                fprintf (stderr, "Zero sector write failed: %s\n", outfile);
                exit (0);
            }
        }

    }
    fclose (of);
    return 0;
}


int main (int argc, char *argv[])
{
    char *progname = argv[0];
    short i;
    short x;
    short overwrite = FALSE;
    short model = 7275;

    int nacc = 0;
    char accounts[32][clen(8)];

    int nvol = 0;
    char volumes[10][clen(4)];
    
    char oname[clen(254)];

    
    if (argc < 3) {
        fprintf (stderr, "Initialize a Sigma private disk pack (set).\n\n");
        fprintf (stderr, "Usage:  %s file volname [options]\n", progname);
        fprintf (stderr, "Options:\n");
        fprintf (stderr, "    -a accounts   specifies the accounts to be created on the pack\n");
        fprintf (stderr, "    -m model#     specifies the disk drive model number\n");
        fprintf (stderr, "    -o            overwrite file if it exists\n");
        fprintf (stderr, "    -s volnames   specifies the secondary volume names for the set\n");
        fprintf (stderr, "\n");
        fprintf (stderr, "This program creates private disk pack image(s) that can be mounted and\n");
        fprintf (stderr, "used on a virtual Sigma.\n\n");
        fprintf (stderr, "If secondary volumes are specified, the entire set is created using the\n");
        fprintf (stderr, "root filename and pack number.\n");
        fprintf (stderr, "I.E. file0 will be the primary, and file1 .. filen will be the secondaries.\n\n");
        fprintf (stderr, "If no secondary volumes are supplied, a single disk pack is created on the\n");
        fprintf (stderr, "filename specified.\n\n");
        exit (0);
    }
    
    
    strcpy (oname, argv[1]);
    clencpy (volumes[0], argv[2], 4, TRUE);
    
    i = 3;
    while (i < argc) {
        if (argv[i][0] != '-') {
            fprintf (stderr, "Unexpected command data: \"%s\"\n", argv[i]);
            exit(0);
        }
        
        switch (argv[i][1]) {
            case 'a':
                i++;
                x = 0;
                while ((i < argc) && (x < 32) && (argv[i][0] != '-')) {
                    clencpy (accounts[x], argv[i], 8, TRUE);
                    x ++;
                    i ++;
                }
                nacc = x;
                break;
              
            case 'm':
                if (argv[i][2]) {
                    model = atoi(&argv[i][2]);
                }
                else {
                    i++;
                    model = atoi(argv[i]);
                }
                i++;
                break;
                
            case 'o':
                overwrite = TRUE;
                i++;
                break;
                
            case 's':
                i++;
                x = 1;
                while ((i < argc) && (x < 10) && (argv[i][0] != '-')) {
                    clencpy (volumes[x], argv[i], 4, TRUE);
                    x ++;
                    i ++;
                }
                nvol = x;
                break;
                

            default:
                fprintf (stderr, "Unexpected command data: \"%s\"\n", argv[i]);
                exit(0);
        }
    }
    
    
    
    int modx = 0;
    while (modtable[modx].number != model) {
        if (modtable[modx].number <= 0) {
            fprintf (stderr, "Unknown model number: \"%04d\"\n", model);
            exit(0);
        }
        modx ++;
    }
    
    char *vs = strrchr (oname, '.');
    if (vs <= 0) vs = oname + strlen(oname);
    if (nvol > 1) {
        int v = 0;
        strcpy (vs, "x.dp");

        while (v < nvol) {
            *vs = v + '0';
            initialize (oname, v, overwrite, modx, nacc, accounts, nvol, volumes);
            v ++;
        }
    }
    else {
        strcpy (vs, ".dp");
        initialize (oname, 0, overwrite, modx, nacc, accounts, 1, volumes);
    }
    
    
    return 0;
}
