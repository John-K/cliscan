//
//  PyBT.m
//  PyBT
//
//  Created by André Pang on 8/16/13.
//  Copyright (c) 2013 Hello Inc. All rights reserved.
//

#import <objc/runtime.h>

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

//

@interface HEBluetoothShellDelegate : NSObject<CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic) CBCentralManager* manager;
@property (nonatomic) NSMutableSet* peripherals;
@property (nonatomic) NSMutableSet* connectedPeripherals;
@property (nonatomic) NSCondition* foundPeripheral;
@property (nonatomic) NSCondition* foundService;
@property (nonatomic) NSCondition* foundCharacteristic;
@property (nonatomic) NSCondition* disconnectedPeripheral;

@end

//

@implementation HEBluetoothShellDelegate

static HEBluetoothShellDelegate* delegate = nil;

+ (void)initialize
{
    static BOOL initialized = NO;
    if(!initialized)
    {
        initialized = YES;
        delegate = [[HEBluetoothShellDelegate alloc] init];
    }
}

#pragma mark CBCentralManagerDelegate methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    NSAssert(central.state == CBCentralManagerStatePoweredOn, @"CBCentralManagerState did not switch to On state");
    
    [central scanForPeripheralsWithServices:nil options:nil];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    if([self.peripherals containsObject:peripheral]) {
        return;
    }
    
    [self.peripherals addObject:peripheral];
    [central connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: @YES}];
    
    [self.foundPeripheral broadcast];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    [self.connectedPeripherals addObject:peripheral];
    
    peripheral.delegate = self;
    
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    if([self.connectedPeripherals containsObject:peripheral]) {
        [self.connectedPeripherals removeObject:peripheral];
        
        [self.disconnectedPeripheral broadcast];
    }
}

#pragma mark CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if(error) {
        NSLog(@"-peripheral:didDiscoverServices: %@", error);
        return;
    }

    for(CBService* service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service];
    }

    [self.foundService broadcast];
}

#pragma mark Methods

- (id)init
{
    self = [super init];
    if(!self) return nil;
    
    self.peripherals = [NSMutableSet set];
    self.connectedPeripherals = [NSMutableSet set];
    self.foundPeripheral = [[NSCondition alloc] init];
    self.foundService = [[NSCondition alloc] init];
    self.disconnectedPeripheral = [[NSCondition alloc] init];
    
    return self;
}

- (void)startScan
{
    dispatch_queue_t bluetoothQueue = dispatch_queue_create("com.hello.HEBluetoothShellCommands.bluetoothQueue", NULL);
    self.manager = [[CBCentralManager alloc] initWithDelegate:self queue:bluetoothQueue];
}

- (void)stopScan
{
    [self.manager stopScan];
}

- (void)disconnectAllPeripherals
{
    for(CBPeripheral* peripheral in self.connectedPeripherals) {
        
        [self.manager cancelPeripheralConnection:peripheral];
    }
    
    [self.disconnectedPeripheral lock];
    
    while([self.connectedPeripherals count] != 0) {
        [self.disconnectedPeripheral wait];
    }
    
    [self.disconnectedPeripheral unlock];
}

+ (void)implementMethodWithSelector:(SEL)selector types:(char*)types block:(id)block
{
    class_replaceMethod(self, selector, imp_implementationWithBlock(block), types);
}

typedef BOOL (^PeripheralPredicateBlock)(CBPeripheral*);
- (CBPeripheral*)findPeripheralWithPredicate:(PeripheralPredicateBlock)predicate
{
    [self.foundPeripheral lock];
    
    for(;;) {
        for(CBPeripheral* peripheral in self.peripherals) {
            if(predicate(peripheral)) {
                [self.foundPeripheral unlock];
                return peripheral;
            }
        }
        
        [self.foundPeripheral wait];
    }
}

typedef BOOL (^ServicePredicateBlock)(CBService*);
- (CBService*)findServiceForPeripheral:(CBPeripheral*)peripheral withPredicate:(ServicePredicateBlock)predicate
{
    [self findPeripheralWithPredicate:^BOOL (CBPeripheral* i) {
        return peripheral == i;
    }];

    [self.foundService lock];
    
    for(;;) {
        for(CBService* service in peripheral.services) {
            if(predicate(service)) {
                [self.foundService unlock];
                return service;
            }
        }
        
        [self.foundService wait];
    }
}

typedef BOOL (^CharacteristicPredicateBlock)(CBCharacteristic*);
- (CBCharacteristic*)findCharacteristicForService:(CBService*)service withPredicate:(CharacteristicPredicateBlock)predicate
{
    [self findServiceForPeripheral:service.peripheral withPredicate:^BOOL(CBService* i) {
        return service == i;
    }];
    
    for(;;) {
        for(CBCharacteristic* characteristic in service.characteristics) {
            if(predicate(characteristic)) {
                return characteristic;
            }
        }
        
        [self.foundCharacteristic lock];
        [self.foundCharacteristic wait];
    }
}

- (NSData*)syncReadCharacteristic:(CBCharacteristic*)characteristic
{
    __block NSData* data = nil;
    
    NSCondition* condition = [[NSCondition alloc] init];
    
    [[self class] implementMethodWithSelector:@selector(peripheral:didUpdateValueForCharacteristic:error:) types:"v@:@@@" block:^(HEBluetoothShellDelegate* delegate, CBPeripheral* peripheral, CBCharacteristic* characteristic, NSError* error) {
        if(error) {
            NSLog(@"-peripheral:didUpdateValueForCharacteristic:error: %@", error);
            return;
        }

        data = characteristic.value;
        
        [condition signal];
    }];
    
    [condition lock];
    
    [characteristic.service.peripheral readValueForCharacteristic:characteristic];
    
    while(!data) {
        [condition wait];
    }
    [condition unlock];
    
    return data;
}

- (BOOL)writeToCharacteristic:(CBCharacteristic*)characteristic wantResponse:(BOOL)needsResponse data:(NSData*)data
{
    const BOOL characteristicCanWriteWithResponse = (characteristic.properties & CBCharacteristicPropertyWrite) != 0;
    
    if(needsResponse && characteristicCanWriteWithResponse) {
        __block BOOL attemptedWrite = NO;
        
        NSCondition* condition = [[NSCondition alloc] init];
        [condition lock];
        
        [[self class] implementMethodWithSelector:@selector(peripheral:didWriteValueForCharacteristic:error:) types:"v@:@@@" block:^(HEBluetoothShellDelegate* delegate, CBPeripheral* peripheral, CBCharacteristic* characteristic, NSError* error) {
            attemptedWrite = YES;
            
            if(error) {
                NSLog(@"-peripheral:didWriteValueForCharacteristic:error: %@", error);
            }
            
            [condition signal];
        }];
        
        [characteristic.service.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
        
        while(!attemptedWrite) {
            [condition wait];
        }
        [condition unlock];
        
        return YES;
    } else {
        [characteristic.service.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
        
        return NO;
    }
}

@end

//

void start_scan()
{
    [HEBluetoothShellDelegate initialize];
    
    [delegate startScan];
}

void stop_scan()
{
    [delegate disconnectAllPeripherals];
    
    [delegate stopScan];
}

CBPeripheral* find_peripheral_by_name(const char* const name)
{
    NSString* wantedName = [NSString stringWithUTF8String:name];
    return [delegate findPeripheralWithPredicate:^BOOL (CBPeripheral* peripheral) {
        return [peripheral.name isEqualToString:wantedName];
    }];
}

CBService* peripheral_get_service_by_uuid(CBPeripheral* peripheral, const char* const UUIDString)
{
    CBUUID* UUID = [CBUUID UUIDWithString:[NSString stringWithUTF8String:UUIDString]];
    
    return [delegate findServiceForPeripheral:peripheral withPredicate:^BOOL(CBService* service) {
        return [service.UUID isEqual:UUID];
    }];
}

CBCharacteristic* service_get_characteristic_by_uuid(CBService* service, const char* const UUIDString)
{
    CBUUID* UUID = [CBUUID UUIDWithString:[NSString stringWithUTF8String:UUIDString]];

    return [delegate findCharacteristicForService:service withPredicate:^BOOL(CBCharacteristic* characteristic) {
        return [characteristic.UUID isEqual:UUID];
    }];
}

NSData* characteristic_sync_read(CBCharacteristic* characteristic)
{
    return [delegate syncReadCharacteristic:characteristic];
}

BOOL characteristic_write(CBCharacteristic* characteristic, NSData* data, int wantConfirmation)
{
    return [delegate writeToCharacteristic:characteristic wantResponse:(wantConfirmation == 0 ? NO : YES) data:data];
}
