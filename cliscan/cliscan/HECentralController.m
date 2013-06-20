//
//  HECentralController.m
//  Desktop Scanner
//
//  Created by Jonathan Dalrymple on 18/01/2013.
//  Copyright (c) 2013 Hello Inc. All rights reserved.
//

#import "HECentralController.h"

#import "NSString+CFUUID.h"
#import "NSData+hex.h"

#include <unistd.h>

typedef void(^HEPeripheralBlock)(CBPeripheral *peripheral);
typedef void(^HEServiceBlock)(CBService *service);
typedef void(^HECharacteristicBlock)(CBCharacteristic *characteristic);

typedef void(^HEArrayBlock)(NSArray *array);

@interface HECentralController ()

@property (nonatomic,strong,readwrite) CBCentralManager *centralManager;

@property (nonatomic,copy) HEPeripheralBlock didDiscoverServicesBlock;
@property (nonatomic,copy) HEPeripheralBlock didConnectPeripheralBlock;
@property (nonatomic,copy) HEPeripheralBlock didDiscoverPeripheralBlock;
@property (nonatomic,copy) HEServiceBlock didDiscoverCharacteristicsBlock;
@property (nonatomic,copy) HECharacteristicBlock didUpdateCharacteristicValueBlock;

@property (nonatomic,copy) HEArrayBlock didRetrievePeripheralsBlock;

@property (nonatomic,strong) CBPeripheral *peripheral;

@property (nonatomic,strong) NSDateFormatter *dateFormatter;

@property (nonatomic,copy) NSSet *discoveredPeripheralUUIDs;

@property (nonatomic,assign,getter = isScanning) BOOL scanning;

@property (nonatomic,assign) double timeout;

@end

@implementation HECentralController

#pragma mark - STDOUT
/**
 *  Write string to stdout
 */
+ (void)writeLine:(NSString *)aString {
    printf("%s\n",[aString cStringUsingEncoding:NSUTF8StringEncoding]);
}

/**
 *  Write string to stdout
 */
- (void)writeLine:(NSString *)aString {
    [HECentralController writeLine:aString];
}

- (void)writeColumns:(NSArray *)arr {
    [HECentralController writeLine:[arr componentsJoinedByString:@","]];
}

/**
 *  Write Help to stdout
 */
+ (void)writeHelp {

    [self writeLine:@"BLE Scanner v1.3"];
    [self writeLine:@"Usage:"];
    [self writeLine:@"\t-t timeout"];
    [self writeLine:@"\t-c characteristic UUID(s) to subscribe to, Comma separated list"];
    [self writeLine:@"\t-r characteristic UUID to read"];
    [self writeLine:@"\t-d device name"];
    [self writeLine:@"\t-v Become verbose"];
    [self writeLine:@"\t-s service UUID"];

}

#pragma mark - Object life cycle
- (id)init {
    self = [super init];
    if (self) {
        [self setScanning:NO];
        [self setTimeout:15.0f];
    }
    return self;
}

- (id)initWithCentralManager:(CBCentralManager*)aCentralManager {
    self = [self init];
    if (self) {
        [self setCentralManager:aCentralManager];
        [aCentralManager setDelegate:self];
    }
    return self;
}

#pragma mark - Lazy Accessors
/**
 *  Lazily create a central manager if needed
 */
- (CBCentralManager *)centralManager {
    if (!_centralManager) {
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self
                                                               queue:nil];
    }
    return _centralManager;
}

- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
    
        [_dateFormatter setDateFormat:kISO8601DateFormat];
    }
    return _dateFormatter;
}

#pragma mark - helper methods
- (void)parseArguments:(NSArray *)arguments {
  
    NSString *characteristic;
    NSString *deviceName;
    NSString *service;
  
    BOOL subscribe = NO;
  
    int c;
    int argc;
  
    char **argv;
  
    argc = (int)[arguments count];
    
    argv = malloc(sizeof(char*)*[arguments count]);
  
    for (int i=0; i<[arguments count]; i++) {
        argv[i] = (char *)[[arguments objectAtIndex:i] cStringUsingEncoding:NSUTF8StringEncoding];
    }
  
    while ((c= getopt(argc, argv, "c:d:s:t:r:hiv")) != -1){
        switch (c) {
            case 'c':
                subscribe = YES;
            case 'r':
                characteristic = [NSString stringWithCString:optarg
                                            encoding:NSUTF8StringEncoding];
                break;
            case 'd':
                deviceName = [NSString stringWithCString:optarg
                                        encoding:NSUTF8StringEncoding];
                break;
            case 's':
                service = [NSString stringWithCString:optarg
                                     encoding:NSUTF8StringEncoding];
        
                if ([service isEqualToString:@"hello"]) {
                    service = kHelloServiceUUID; //Aliased UUID string
                }
                break;
            case 't':
                self.timeout = [[NSString stringWithCString:optarg
                                           encoding:NSUTF8StringEncoding] doubleValue];

                break;
            case 'h':
        
                [HECentralController writeHelp];
                exit(EXIT_SUCCESS);
            case 'v':
                ddLogLevel = 1;
                break;
            case 'i':
                break;
            default:
                exit(EXIT_FAILURE);
                break;
        }
        optreset = 1;
    }
  
    if ((deviceName || service || characteristic) && [self timeout] != 15.0f ) {
    [self writeLine:@"You cannot use the timeout param if you are not performing a scan"];
    exit(EXIT_FAILURE);
    }

    if ( deviceName && service && characteristic && subscribe ){
        self.timeout = UINT16_MAX;
        [self subscribeToCharacteristics:characteristic
                                 service:service
                             deviceNamed:deviceName];
    } else if ( deviceName && service && characteristic ) {
        [self readValueForCharacteristic:characteristic
                                 service:service
                             deviceNamed:deviceName];
    } else if ( deviceName && service ) {
        [self listCharacteristicsForService:service
                                deviceNamed:deviceName];
    } else if (deviceName) {
        [self listServicesForDeviceNamed:deviceName];
    } else {
        [self startScanForDuration:[self timeout]];
    }
  
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self timeout] * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        exit(EXIT_FAILURE);
    });

    free(argv);
}

- (void)scanForDuration:(CGFloat)duration
              withBlock:(dispatch_block_t)aBlock {
  
    __unsafe_unretained id weakSelf = self;
  
    [[self centralManager] scanForPeripheralsWithServices:nil
                                                  options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@NO}];
  
    [self setScanning:YES];
  
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [weakSelf setScanning:NO];
        [[weakSelf centralManager] stopScan];
        aBlock();
    });
}

/**
 *  Connect to a peripheral and execute the block when connected
 */
- (void)connectToPeripheralNamed:(NSString *)aDeviceName
                       withBlock:(HEPeripheralBlock)aBlock {

    __weak id weakSelf = self;
  
    [self setDidConnectPeripheralBlock:aBlock];
  
  
    [self setDidDiscoverPeripheralBlock:^(CBPeripheral *peripheral){
        //Find a peripheral with that name
        if ([[peripheral name] isEqualToString:aDeviceName] && ![weakSelf peripheral]) {
      
            [weakSelf setPeripheral:peripheral];
      
            [peripheral setDelegate:weakSelf];
      
            DDLogVerbose(@"Connecting to %@",[peripheral name]);
      
            [[weakSelf centralManager] connectPeripheral:peripheral
                                                 options:nil];
        }
    }];
}

#pragma mark -
- (void)startScanForDuration:(CGFloat)duration {
  
    __weak id weakSelf = self;
  
    [self setDidDiscoverPeripheralBlock:^(CBPeripheral *peripheral){
    
        [weakSelf writeColumns:@[
            [peripheral name],
            [NSString stringWithCFUUID:[peripheral UUID]]
         ]];
    
    }];
  
    DDLogVerbose(@"Started %.0fs Scan",duration);
    [self scanForDuration:duration
                withBlock:^{
                    DDLogVerbose(@"Stopped Scan");
                }];
}

- (void)listServicesForDeviceNamed:(NSString *)aDevice {
  
    __weak id weakSelf = self;

    [self connectToPeripheralNamed:aDevice
                         withBlock:^(CBPeripheral *peripheral){
                             [peripheral discoverServices:nil];
                         }];
  
    //Print the services
    [self setDidDiscoverServicesBlock:^(CBPeripheral *peripheral){
    
        for (CBService *service in [peripheral services]) {
            [weakSelf writeLine:[[[service UUID] data] hexString]];
        }
    
        exit(EXIT_SUCCESS);
    }];
  
    [self scanForDuration:[self timeout]
                withBlock:^{
                    DDLogVerbose(@"Stopped list");
                }];
}

- (void)listCharacteristicsForService:(NSString *)aService
                          deviceNamed:(NSString *)aDevice {
  
    CBUUID *serviceUUID;
  
    serviceUUID = [CBUUID UUIDWithString:aService];
  
    __weak id weakSelf = self;
  
    [self connectToPeripheralNamed:aDevice
                       withBlock:^(CBPeripheral *peripheral){
                           [peripheral discoverServices:nil];
                       }];
  
    [self setDidDiscoverServicesBlock:^(CBPeripheral *peripheral){
    
        for (CBService *service in [peripheral services]) {
            if ( [[service UUID] isEqual:serviceUUID]) {
                [[service peripheral] discoverCharacteristics:nil
                                                   forService:service];
                break;
            }
        }

    }];
  
    [self setDidDiscoverCharacteristicsBlock:^(CBService *service){
    
        for (CBCharacteristic *characteristic in [service characteristics]) {
            [weakSelf writeLine:[[[characteristic UUID] data] hexString]];
        }
    
        exit(EXIT_SUCCESS);
    }];
  
    [self scanForDuration:[self timeout]
                withBlock:^{
                    DDLogVerbose(@"listCharacteristicsForService");
                }];
}

- (void)readValueForCharacteristic:(NSString *)aCharacteristic
                           service:(NSString *)aService
                       deviceNamed:(NSString*)aDevice {
 
    CBUUID *serviceUUID;
    CBUUID *characteristicUUID;
  
    serviceUUID = [CBUUID UUIDWithString:aService];
    characteristicUUID = [CBUUID UUIDWithString:aCharacteristic];
  
    __weak id weakSelf = self;
  
    [self connectToPeripheralNamed:aDevice
                       withBlock:^(CBPeripheral *peripheral){
                           [peripheral discoverServices:nil];
                       }];
  
    [self setDidDiscoverServicesBlock:^(CBPeripheral *peripheral){
        for (CBService *service in [peripheral services]) {
            if ( [[service UUID] isEqual:serviceUUID]) {
                [[service peripheral] discoverCharacteristics:nil
                                                   forService:service];
                break;
            }
        }
    }];
  
    [self setDidDiscoverCharacteristicsBlock:^(CBService *service){
    
        for (CBCharacteristic *characteristic in [service characteristics]) {

            if ([[characteristic UUID] isEqual:characteristicUUID]) {
                [[service peripheral] readValueForCharacteristic:characteristic];
                break;
            }
        }
  }];
  
    [self setDidUpdateCharacteristicValueBlock:^(CBCharacteristic *characteristic){
    
        [weakSelf writeColumns:@[
         [[[characteristic service] peripheral] name],
         [[[[characteristic service] UUID] data] hexString],
         [[[characteristic UUID] data] hexString],
         [[weakSelf dateFormatter] stringFromDate:[NSDate date]],
         [[characteristic value] hexString],
         ]];
        exit(EXIT_SUCCESS);
    }];
  
    [self scanForDuration:[self timeout]
                withBlock:^{
                    DDLogVerbose(@"listCharacteristicsForService");
                }];
}

- (void)subscribeToCharacteristics:(NSString *)aCharacteristic
                           service:(NSString *)aService
                       deviceNamed:(NSString*)aDevice {
  
    CBUUID *serviceUUID;
    NSArray *characteristics;
    __weak id weakSelf;
  
    serviceUUID = [CBUUID UUIDWithString:aService];
  
    characteristics = [self characteristicUUIDsWithString:aCharacteristic];
  
    weakSelf = self;
  
    [self connectToPeripheralNamed:aDevice
                         withBlock:^(CBPeripheral *peripheral){
                             [peripheral discoverServices:nil];
                         }];
  
    [self setDidDiscoverServicesBlock:^(CBPeripheral *peripheral){
    
        for (CBService *service in [peripheral services]) {
            if ( [[service UUID] isEqual:serviceUUID]) {
                [[service peripheral] discoverCharacteristics:nil
                                                   forService:service];
                break;
            }
        }
  }];
  
    [self setDidDiscoverCharacteristicsBlock:^(CBService *service){
        for (CBCharacteristic *characteristic in [service characteristics]) {
      
            if ([characteristics containsObject:[characteristic UUID]]) {
                [[service peripheral] setNotifyValue:YES
                                   forCharacteristic:characteristic];
            }
        }
    }];
  
    [self setDidUpdateCharacteristicValueBlock:^(CBCharacteristic *characteristic){
        [weakSelf writeColumns:@[
         [[[characteristic service] peripheral] name],
         [[[[characteristic service] UUID] data] hexString],
         [[[characteristic UUID] data] hexString],
         [[weakSelf dateFormatter] stringFromDate:[NSDate date]],
         [[characteristic value] hexString],
         ]];
    }];
  
    [self scanForDuration:[self timeout]
                withBlock:^{
                    DDLogVerbose(@"subscribeToCharacteristic");
                }];
}

- (NSArray *)characteristicUUIDsWithString:(NSString *)aString {
  
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:4];
  
    for (NSString *uuid in [aString componentsSeparatedByString:@","]) {
        [array addObject:[CBUUID UUIDWithString:uuid]];
    }
  
    return [array copy];
}


#pragma mark - CBPeripheralDelegate
- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error {
    DDLogVerbose(@"didDiscoverServices");
    if (error){
        DDLogError(@"didDiscoverServices %@",error);
    }
  
    if ([self didDiscoverServicesBlock] && !error) {
        [self didDiscoverServicesBlock](peripheral);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
             error:(NSError *)error {
    DDLogVerbose(@"didDiscoverCharacteristicsForService");
    if (error){
        DDLogError(@"didDiscoverCharacteristicsForService %@",error);
    }
  
    if ([self didDiscoverCharacteristicsBlock] && !error) {
        [self didDiscoverCharacteristicsBlock](service);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    DDLogVerbose(@"didUpdateValueForCharacteristic");
    if (error){
        DDLogError(@"didUpdateValueForCharacteristic %@",error);
    }
  
    if ([self didUpdateCharacteristicValueBlock] && !error) {
        [self didUpdateCharacteristicValueBlock](characteristic);
    }
}

#pragma mark - CBCentralManagerDelegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  
    switch ([central state]) {
        case CBCentralManagerStatePoweredOn:
            DDLogVerbose(@"BT ON");
      
            if (![self isScanning]) {
                DDLogVerbose(@"Attempting scan again");
                [self startScanForDuration:[self timeout]];
            }
      
            break;
        case CBCentralManagerStateResetting:
            DDLogVerbose(@"BT Resetting");
            break;
        case CBCentralManagerStatePoweredOff:
            DDLogVerbose(@"BT Off");
            break;
        default:
            break;
  }
  
}

-(void)centralManager:(CBCentralManager *)central
didDiscoverPeripheral:(CBPeripheral *)peripheral
    advertisementData:(NSDictionary *)advertisementData
                 RSSI:(NSNumber *)RSSI {
  
    DDLogVerbose(@"didDiscoverPeripheral %@\n with RSSI %@\nand data %@\n\n",[peripheral UUID], RSSI, advertisementData);

    NSSet *set;
    NSString *UUID;
  
    UUID = [NSString stringWithCFUUID:[peripheral UUID]];
  
    if (!(set=[self discoveredPeripheralUUIDs])) {
        set = [NSSet set];
    }
  
    if (![set member:UUID]) {
        set = [set setByAddingObject:UUID];

        //update the cache
        [self setDiscoveredPeripheralUUIDs:set];
    
        if ([self didDiscoverPeripheralBlock]) {
            [self didDiscoverPeripheralBlock](peripheral);
        }
    
    }
  
}

- (void)centralManager:(CBCentralManager *)central
didRetrievePeripherals:(NSArray *)peripherals {
    DDLogVerbose(@"Peripherals %@",peripherals);
  
    if ([self didRetrievePeripheralsBlock]) {
        [self didRetrievePeripheralsBlock](peripherals);
    }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {

    DDLogVerbose(@"didConnectPeripheral %@",[[peripheral name] copy]);
  
    if ([self didConnectPeripheralBlock]) {
        [self didConnectPeripheralBlock](peripheral);
    }
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    DDLogError(@"didFailToConnectPeripheral %@",error);
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    DDLogVerbose(@"didDisconnectPeripheral %@ %@",[peripheral name],error);
    exit(EXIT_FAILURE);
}

@end
