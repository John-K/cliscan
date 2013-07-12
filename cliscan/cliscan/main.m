//
//  main.m
//  CScanner
//
//  Created by Jonathan Dalrymple on 31/01/2013.
//  Copyright (c) 2013 Hello. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#import "HECentralController.h"

//Convert a C array of string pointers to an NSArray of NSStrings
NSArray* arrayWithStrings(const char *arr[],int len) {
  
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:len];
  
    NSString *str;
  
    for (int i =0; i < len; i++) {

      str = [NSString stringWithCString:arr[i]
                               encoding:NSUTF8StringEncoding];
    
      [array addObject:str];
    
    }
  
    return [[array copy] autorelease];
}

@interface HEAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic,strong) HECentralController *controller;
@property (nonatomic,copy) NSArray *arguments;
@end

@implementation HEAppDelegate

- (HECentralController *)controller {
    if (!_controller) {
      _controller = [[HECentralController alloc] init];
    }
    return _controller;
}

- (void)dealloc {
  
    [_arguments release];
    [_controller release];
  
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *arguments;
  
    arguments = [self arguments];
    /*
    arguments = @[
                @"/Desktop Scanner",
                @"-i",
                @"-t",
                @"3",
                @"-p"];
    */ 
    [[self controller] parseArguments:arguments];
  
}

@end

int main(int argc, const char * argv[])
{

    @autoreleasepool {
    
        HEAppDelegate *delegate;
    
        delegate = [[HEAppDelegate alloc] init];
    
        [delegate setArguments:arrayWithStrings(argv, argc)];
    
        [[NSApplication sharedApplication] setDelegate:delegate];
        
        [NSApp run];
    
        [delegate release];
    }
  
    return 0;
}
