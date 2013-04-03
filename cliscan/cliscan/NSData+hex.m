//
//  NSData+hex.m
//
//  Created by Jonathan Dalrymple on 24/01/2013.
//

#import "NSData+hex.h"

@implementation NSData (hex)

- (NSString *)hexString {
    
    NSCharacterSet *charSet;
    
    charSet = [NSCharacterSet characterSetWithCharactersInString:@"<>"];
    
    return [[self description] stringByTrimmingCharactersInSet:charSet];
}

@end