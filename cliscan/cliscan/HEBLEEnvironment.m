//
//  HEBLEEnvironment.m
//  cliscan
//
//  Created by Roy Blankman on 6/20/13.
//  Copyright (c) 2013 Roy Blankman. All rights reserved.
//

#import "HEBLEEnvironment.h"

@implementation HEBLEEnvironment

- (id)init
{
    self = [super init];
    
    if (self) {
        NSLog(@"created");
    }
    
    return self;
}

- (void)addDiscoveredPeripheralUUID:(NSString *)UUID{
    return;
}

@end
