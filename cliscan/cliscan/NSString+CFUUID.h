//
//  NSString+CFUUID.h
//
//  Created by Jonathan Dalrymple on 24/01/2013.
//

#import <Foundation/Foundation.h>

@interface NSString (CFUUID)

+(id)stringWithCFUUID:(CFUUIDRef)aUUIDRef;

@end
