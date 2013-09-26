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

// An NSTimer category to to add blocks support: <https://github.com/jivadevoe/NSTimer-Blocks/blob/master/NSTimer%2BBlocks.m>

@interface NSTimer (Blocks)

+(id)scheduledTimerWithTimeInterval:(NSTimeInterval)inTimeInterval block:(void (^)())inBlock repeats:(BOOL)inRepeats;
+(id)timerWithTimeInterval:(NSTimeInterval)inTimeInterval block:(void (^)())inBlock repeats:(BOOL)inRepeats;

@end

@implementation NSTimer (Blocks)

+(id)scheduledTimerWithTimeInterval:(NSTimeInterval)inTimeInterval block:(void (^)())inBlock repeats:(BOOL)inRepeats
{
    void (^block)() = [inBlock copy];
    id ret = [self scheduledTimerWithTimeInterval:inTimeInterval target:self selector:@selector(jdExecuteSimpleBlock:) userInfo:block repeats:inRepeats];
    return ret;
}

+(id)timerWithTimeInterval:(NSTimeInterval)inTimeInterval block:(void (^)())inBlock repeats:(BOOL)inRepeats
{
    void (^block)() = [inBlock copy];
    id ret = [self timerWithTimeInterval:inTimeInterval target:self selector:@selector(jdExecuteSimpleBlock:) userInfo:block repeats:inRepeats];
    return ret;
}

+(void)jdExecuteSimpleBlock:(NSTimer *)inTimer;
{
    if([inTimer userInfo])
    {
        void (^block)() = (void (^)())[inTimer userInfo];
        block();
    }
}

@end

//

typedef int (*SubscriberCallback)(CBCharacteristic*, NSData*);

@interface HEBluetoothShellDelegateSubscription : NSObject

@property (nonatomic) CBCharacteristic* characteristic;
@property (nonatomic) NSCondition* condition;
@property (nonatomic) id observer;
@property (nonatomic) NSMutableArray* dataQueue;
@property (nonatomic) SubscriberCallback callback;

@end

//

@implementation HEBluetoothShellDelegateSubscription

- (id)initWithCharacteristic:(CBCharacteristic*)characteristic callback:(SubscriberCallback)callback
{
    self = [super init];
    if(!self) {
        return nil;
    }
    
    self.dataQueue = [NSMutableArray array];
    
    self.callback = callback;
    
    self.condition = [[NSCondition alloc] init];
    [self.condition setName:[NSString stringWithFormat:@"%@", characteristic.UUID]];
    [self.condition lock];
    
    self.observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidReadCharacteristic" object:characteristic queue:nil usingBlock:^(NSNotification* note) {
        NSData* data = note.userInfo[@"data"];
        
        if(callback) {
            callback(characteristic, data);
        } else {
            [self.dataQueue addObject:data];
        }
        
        [self broadcast];
    }];
    
    NSCondition* condition = [[NSCondition alloc] init];

    __block BOOL receivedNotification = NO;
    __block id observer = [[NSNotificationCenter defaultCenter]addObserverForName:@"HEBluetoothShellDelegateDidUpdateNotificationStateForCharacteristic" object:characteristic queue:Nil usingBlock:^(NSNotification* note) {
        receivedNotification = YES;
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
    
    [condition lock];
    [[[characteristic service] peripheral] setNotifyValue:YES forCharacteristic:characteristic];
    while(!receivedNotification) {
        [condition wait];
    }
    [condition unlock];
    
    return self;
}

- (void)unsubscribe
{
    [[[self.characteristic service] peripheral] setNotifyValue:NO forCharacteristic:self.characteristic];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self.observer];
}

- (void)broadcast
{
    [self.condition broadcast];
}

- (NSData*)read
{
    if(self.callback) {
        @throw [NSException exceptionWithName:@"HEBluetoothShellDelegateSubscriptionWaitCalledForAsynchronousCallback" reason:[NSString stringWithFormat:@"You have called %s, but have also specified a callback. Either (1) do not specify a callback (synchronous behaviour), and call %s to retrieve the next value, or (2) specify a callback and do not use %s.", __func__, __func__, __func__] userInfo:nil];
    }
    
    if([self.dataQueue count] > 0) {
        NSData* data = [self.dataQueue objectAtIndex:0];
        [self.dataQueue removeObjectAtIndex:0];
        
        return data;
    }
    
    while([self.dataQueue count] == 0) {
        [self.condition wait];
    }
    
    NSData* data = [self.dataQueue objectAtIndex:0];
    [self.dataQueue removeObjectAtIndex:0];
    
    return data;
}

@end

//

@interface HEBluetoothShellDelegate : NSObject<CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic) CBCentralManager* central;
@property (nonatomic) NSMutableSet* peripherals;
@property (nonatomic) NSMutableSet* connectedPeripherals;
@property (nonatomic) dispatch_queue_t bluetoothQueue;
@property (nonatomic) NSMapTable* subscriptions; /* CBCharacteristic -> HEBluetoothShellDelegateSubscription */

@end

//

@implementation HEBluetoothShellDelegate

static HEBluetoothShellDelegate* delegate = nil;

#pragma mark Lifecycle

+ (void)initialize
{
    static BOOL initialized = NO;
    if(!initialized)
    {
        initialized = YES;
        delegate = [[HEBluetoothShellDelegate alloc] init];
    }
}

- (id)init
{
    self = [super init];
    if(!self) return nil;
    
    self.peripherals = [NSMutableSet set];
    self.connectedPeripherals = [NSMutableSet set];
    self.bluetoothQueue = dispatch_queue_create("com.hello.HEBluetoothShellCommands.bluetoothQueue", NULL);
    self.subscriptions = [NSMapTable strongToStrongObjectsMapTable];
    
    return self;
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
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidDiscoverPeripheral" object:central userInfo:@{@"peripheral": peripheral, @"advertisementData": advertisementData, @"RSSI": RSSI}];
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
    }

    if([self.peripherals containsObject:peripheral]) {
        [self.peripherals removeObject:peripheral];
    }

    if(error) {
        NSLog(@"%s: %@", __func__, error);
        return;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidDisconnectPeripheral" object:central userInfo:@{@"peripheral": peripheral, @"error": error ? error : [NSNull null]}];
    
    [central connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: @YES}];
}

#pragma mark CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if(error) {
        NSLog(@"%s: %@", __func__, error);
    }

    for(CBService* service in peripheral.services) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidDiscoverService" object:peripheral userInfo:@{@"service": service, @"error": error ? error : [NSNull null]}];
        [peripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if(error) {
        NSLog(@"%s: %@", __func__, error);
    }
    
    for(CBCharacteristic* characteristic in service.characteristics) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidDiscoverCharacteristic" object:service userInfo:@{@"characteristic": characteristic, @"error": error ? error : [NSNull null]}];
        [peripheral discoverDescriptorsForCharacteristic:characteristic];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(error) {
        NSLog(@"%s Error changing notification state: %@", __func__, error);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(error) {
        NSLog(@"%s: %@", __func__, error);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidReadCharacteristic" object:characteristic userInfo:@{@"data": characteristic.value ? characteristic.value : [NSNull null], @"error": error ? error : [NSNull null]}];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(error) {
        NSLog(@"%s: %@", __func__, error);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidWriteCharacteristic" object:characteristic userInfo:@{@"error": error ? error : [NSNull null]}];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(error) {
        NSLog(@"%s: %@", __func__, error);
    }
    
    for(CBDescriptor* descriptor in characteristic.descriptors) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"HEBluetoothShellDelegateDidDiscoverDescriptor" object:characteristic userInfo:@{@"descriptor": descriptor, @"error": error ? error : [NSNull null]}];
    }
}

#pragma mark Methods

- (void)startScan
{
    self.central = [[CBCentralManager alloc] initWithDelegate:self queue:self.bluetoothQueue];
}

@end

//

void start_scan(NSArray* UUIDStrings)
{
    [HEBluetoothShellDelegate initialize];
    
    [delegate startScan];
}

void disconnect_all_peripherals()
{
    for(CBCharacteristic* characteristic in delegate.subscriptions) {
        [[delegate.subscriptions objectForKey:characteristic] unsubscribe];
    }
    
    for(CBPeripheral* peripheral in delegate.connectedPeripherals) {
        [delegate.central cancelPeripheralConnection:peripheral];
    }
    
    if([delegate.connectedPeripherals count] == 0) {
        return;
    }
    
    NSCondition* condition = [[NSCondition alloc] init];

    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDisconnectPeripheral" object:delegate.central queue:nil usingBlock:^(NSNotification* note) {
        [condition broadcast];
    }];
    
    [condition lock];
    while([delegate.connectedPeripherals count] > 0) {
        [condition wait];
    }
    [condition unlock];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

void stop_scan()
{
    [delegate.central stopScan];
    
    disconnect_all_peripherals();
}

CBPeripheral* find_peripheral_by_name(const char* const name)
{
    NSString* wantedName = [NSString stringWithUTF8String:name];
    
    BOOL (^predicate)(CBPeripheral*) = ^BOOL(CBPeripheral* peripheral) {
        return [peripheral.name isEqualToString:wantedName] ? YES : NO;
    };
    
    NSCondition* condition = [[NSCondition alloc] init];
       
    __block CBPeripheral* peripheral = nil;
    
    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDiscoverPeripheral" object:delegate.central queue:nil usingBlock:^(NSNotification* note) {
        CBPeripheral* newPeripheral = note.userInfo[@"peripheral"];
        if(!predicate(newPeripheral)) {
            return;
        }
        
        peripheral = newPeripheral;
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
    
    for(CBPeripheral* peripheral in delegate.peripherals) {
        if(predicate(peripheral)) {
            return peripheral;
        }
    }
    
    [condition lock];
    while(!peripheral) {
        [condition wait];
    }
    [condition unlock];

    return peripheral;
}

NSArray* find_all_peripherals(unsigned timeout)
{
    NSCondition* condition = [[NSCondition alloc] init];

    NSMutableArray* peripherals = [NSMutableArray array];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDiscoverPeripheral" object:delegate.central queue:nil usingBlock:^(NSNotification* note) {
        CBPeripheral* peripheral = note.userInfo[@"peripheral"];
        
        if(![peripherals containsObject:peripheral]) {
            [peripherals addObject:peripheral];
        }
    }];
    
    [NSTimer scheduledTimerWithTimeInterval:timeout block:^() {
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    } repeats:NO];

    NSDate* timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [condition lock];
    [condition waitUntilDate:timeoutDate];
    [condition unlock];
    
    return peripherals;
}

CBService* peripheral_get_service_by_uuid(CBPeripheral* peripheral, const char* const UUIDString)
{
    CBUUID* wantedUUID = [CBUUID UUIDWithString:[NSString stringWithUTF8String:UUIDString]];
    
    NSCondition* condition = [[NSCondition alloc] init];
    
    __block CBService* service = nil;
    
    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDiscoverService" object:peripheral queue:nil usingBlock:^(NSNotification* note) {
        CBService* newService = note.userInfo[@"service"];
        if(![newService.UUID isEqual:wantedUUID]) {
            return;
        }
        
        service = newService;
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];

    for(CBService* service in peripheral.services) {
        if([service.UUID isEqual:wantedUUID]) {
            return service;
        }
    }
    
    [condition lock];
    while(!service) {
        [condition wait];
    }
    [condition unlock];
    
    return service;
}

CBCharacteristic* service_get_characteristic_by_uuid(CBService* service, const char* const UUIDString)
{
    CBUUID* wantedUUID = [CBUUID UUIDWithString:[NSString stringWithUTF8String:UUIDString]];
    
    NSCondition* condition = [[NSCondition alloc] init];
    
    __block CBCharacteristic* characteristic = nil;
    
    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDiscoverCharacteristic" object:service queue:nil usingBlock:^(NSNotification* note) {
        CBCharacteristic* newCharacteristic = note.userInfo[@"characteristic"];
        
        if(![newCharacteristic.UUID isEqual:wantedUUID]) {
            return;
        }
        
        characteristic = newCharacteristic;
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
    
    for(CBCharacteristic* characteristic in service.characteristics) {
        if([characteristic.UUID isEqual:wantedUUID]) {
            return characteristic;
        }
    }
    
    [condition lock];
    while(!characteristic) {
        [condition wait];
    }
    [condition unlock];
    
    return characteristic;
}

NSData* characteristic_sync_read(CBCharacteristic* characteristic)
{
    if((characteristic.properties & CBCharacteristicPropertyRead) == 0) {
        NSLog(@"characteristic.sync_read(): You attempted to read from a non-readable characteristic %@; an error will follow. (Perhaps you need to subscribe to the characeristic instead?", characteristic);
    }
    
    NSCondition* condition = [[NSCondition alloc] init];
    
    __block NSData* data = nil;
    
    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidReadCharacteristic" object:characteristic queue:nil usingBlock:^(NSNotification* note) {
        data = note.userInfo[@"data"];
        
        [condition broadcast];
        
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
    
    [condition lock];
    
    [characteristic.service.peripheral readValueForCharacteristic:characteristic];
    
    while(!data) {
        [condition wait];
    }
    [condition unlock];
    
    return data;
}

BOOL characteristic_write(CBCharacteristic* characteristic, NSData* data, int wantConfirmation)
{
    __block BOOL success = YES;
    
    if(wantConfirmation) {
        if((characteristic.properties & CBCharacteristicPropertyWrite) == 0) {
            NSLog(@"characteristic.write_confirm(): You attempted to write to a characteristic %@ that does not support writing with confirmation; an error will follow.", characteristic);
        }
        
        NSCondition* condition = [[NSCondition alloc] init];
        
        __block BOOL finished = NO;
        
        __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidWriteCharacteristic" object:characteristic queue:nil usingBlock:^(NSNotification* note) {
            finished = YES;
            if(![note.userInfo[@"error"] isEqual:[NSNull null]]) {
                success = NO;
            }
            
            [condition broadcast];
            
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
        }];
        
        [condition lock];
        
        [characteristic.service.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
        
        while(!finished) {
            [condition wait];
        }
        [condition unlock];
    } else {
        if((characteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) == 0) {
            NSLog(@"characteristic.write_no_confirm(): You attempted to write to a characteristic %@ that does not support writing without confirmation; an error will follow.", characteristic);
        }
        
        [characteristic.service.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
    }
    
    return success;
}

HEBluetoothShellDelegateSubscription* characteristic_subscribe(CBCharacteristic* characteristic, SubscriberCallback callback)
{
    if((characteristic.properties & CBCharacteristicPropertyNotify) == 0) {
        NSLog(@"characteristic.subscribe(): You attempted to subscribe to a characteristic %@ that does not support notifications; an error will follow.", characteristic);
    }

    HEBluetoothShellDelegateSubscription* subscription = [[HEBluetoothShellDelegateSubscription alloc] initWithCharacteristic:characteristic callback:callback];
    [delegate.subscriptions setObject:subscription forKey:characteristic];
    
    return subscription;
}

void characteristic_unsubscribe(CBCharacteristic* characteristic, id observer)
{
    [[[characteristic service] peripheral] setNotifyValue:NO forCharacteristic:characteristic];

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    [delegate.subscriptions removeObjectForKey:characteristic];
}

NSData* subscription_sync_read(CBCharacteristic* characteristic)
{
    return [[delegate.subscriptions objectForKey:characteristic] read];
}

#pragma mark Descriptors

CBDescriptor* characteristic_get_descriptor_by_uuid(CBCharacteristic* characteristic, const char* const UUIDString)
{
    CBUUID* wantedUUID = [CBUUID UUIDWithString:[NSString stringWithUTF8String:UUIDString]];
    
    NSCondition* condition = [[NSCondition alloc] init];
    
    __block CBDescriptor* descriptor = nil;
    
    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HEBluetoothShellDelegateDidDiscoverDescriptor" object:characteristic queue:nil usingBlock:^(NSNotification* note) {
        CBDescriptor* newDescriptor = note.userInfo[@"descriptor"];
        
        if(![newDescriptor.UUID isEqual:wantedUUID]) {
            return;
        }
        
        descriptor = newDescriptor;
        [condition broadcast];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
    
    for(CBDescriptor* descriptor in characteristic.descriptors) {
        if([descriptor.UUID isEqual:wantedUUID]) {
            return descriptor;
        }
    }
    
    [condition lock];
    while(!characteristic) {
        [condition wait];
    }
    [condition unlock];
    
    return descriptor;
}

