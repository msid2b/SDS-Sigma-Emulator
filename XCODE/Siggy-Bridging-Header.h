//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//


#import <Foundation/Foundation.h>

NSString *applicationCompileDate(void);
NSString *applicationCompileTime(void);
void sqlSetThreading (void);

NSString *hexDumpLineC (const uint8 *buffer, int start, int count, uint32 apparentAddress, uint32 addressWidth, uint32 addressShift);
