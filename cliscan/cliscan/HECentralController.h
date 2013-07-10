//
//  HECentralController.h
//  Desktop Scanner
//
//  Created by Jonathan Dalrymple on 18/01/2013.
//  Copyright (c) 2013 Hello Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>


#define kHelloServiceUUID   @"00001e3f-1212-efde-1523-785feabcd123"
#define kHelloDevUUID       @"2fe3a7e4-8355-40a6-89d5-4e7b3f29c73e"

@interface HECentralController : NSObject <CBCentralManagerDelegate,CBPeripheralDelegate>

@property (nonatomic,strong,readonly) CBCentralManager *centralManager;

- (id)initWithCentralManager:(CBCentralManager*)aCentralManager;

- (void)parseArguments:(NSArray *)args;

- (void)startScanForDuration:(CGFloat)duration;

@end