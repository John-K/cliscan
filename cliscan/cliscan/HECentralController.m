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
@property (nonatomic,strong) NSMutableArray *discoveredPeripherals;
@property (nonatomic,strong) NSDateFormatter *dateFormatter;
@property (nonatomic,assign,getter = isScanning) BOOL scanning;
@property (nonatomic,assign,getter = isInteractive) BOOL interactive;
@property (nonatomic,assign,getter = isPrinting) BOOL printData;
@property (nonatomic,assign,getter = isThroughputTest) BOOL throughputTest;
@property (nonatomic,assign) double timeout;
@property (nonatomic) int packets_rxd;
@property (nonatomic,strong) NSDate *start;

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
    [self writeLine:@"\t-i interactive mode"];
    [self writeLine:@"\t-q print throughput data"];
    [self writeLine:@"\t-p print received data"];
    [self writeLine:@"\t-t timeout"];
    [self writeLine:@"\t-v verbose"];
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
        self.start = [NSDate date];
        self.packets_rxd = 0;
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

- (NSMutableArray *)discoveredPeripherals {
    if (!_discoveredPeripherals) {
        _discoveredPeripherals = [[NSMutableArray alloc] init];
    }
    return _discoveredPeripherals;
}

#pragma mark - helper methods
- (void)parseArguments:(NSArray *)arguments {
  
    self.interactive = NO;
    self.printData = NO;
    int c;
    int argc;
  
    char **argv;
  
    argc = (int)[arguments count];
    
    argv = malloc(sizeof(char*)*[arguments count]);
  
    for (int i=0; i<[arguments count]; i++) {
        argv[i] = (char *)[[arguments objectAtIndex:i] cStringUsingEncoding:NSUTF8StringEncoding];
    }
  
    while ((c= getopt(argc, argv, "t:hivpq")) != -1){
        switch (c) {
            case 'p':
                self.printData = YES;
                break;
                
            case 'q':
                self.throughputTest = YES;
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
                //enable interactive mode
                //overrides all other characteristics
                self.interactive = YES;
                break;
                
            case '?':
                
            default:
                exit(EXIT_FAILURE);
                break;
        }
        optreset = 1;
    }
    
    if (self.interactive) {
        NSLog(@"entering interactive mode");
        [self startScanForDuration:[self timeout]];
    } else {
        [self startScanForDuration:[self timeout]];
    }
    
    free(argv);
}

- (void)scanForDuration:(CGFloat)duration
              withBlock:(dispatch_block_t)aBlock {
  
    __weak id weakSelf = self;
  
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

- (void) presentDevices
{
    __weak id weakSelf = self;

    [self writeLine:[NSString stringWithFormat:@"number of discovered peripherals: %ld", self.discoveredPeripherals.count]];
    
    for (int i = 0; i < self.discoveredPeripherals.count; i++) {
        [self writeLine:[NSString stringWithFormat:@"%d: %@", i, [[self.discoveredPeripherals objectAtIndex:i] name]]];
    }
    
    int userNumInput;
    printf("select which device to explore: ");
    scanf("%d", &userNumInput);
    [self writeLine:[NSString stringWithFormat:@"Connecting to %d: %@", userNumInput, [[self.discoveredPeripherals objectAtIndex:userNumInput] name]]];
    
    [self.centralManager connectPeripheral:self.discoveredPeripherals[userNumInput] options:nil];
    
    [self setDidConnectPeripheralBlock:^(CBPeripheral *peripheral){
        
        [weakSelf setPeripheral:peripheral];
        
        [peripheral setDelegate:weakSelf];
        
        [weakSelf setDidDiscoverServicesBlock:^(CBPeripheral *peripheral){
            for (CBService *service in [peripheral services]) {
                [peripheral discoverCharacteristics:nil forService:service];
            }
        }];
        
        [weakSelf setDidDiscoverCharacteristicsBlock:^(CBService *service){
            for (CBCharacteristic *characteristic in [service characteristics]) {
                if (characteristic.properties & CBCharacteristicPropertyNotify) {
                    DDLogVerbose(@"subscribing to characteristic with indicate property");
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
            }
        }];
        
        [weakSelf setDidUpdateCharacteristicValueBlock:^(CBCharacteristic *characteristic){
            if (self.isPrinting) {
            [weakSelf writeColumns:@[
             [[[characteristic service] peripheral] name],
             [[[[characteristic service] UUID] data] hexString],
             [[[characteristic UUID] data] hexString],
             [[weakSelf dateFormatter] stringFromDate:[NSDate date]],
             [[characteristic value] description],
             ]];
            }
            self.packets_rxd++;
            double timeInterval = -[self.start timeIntervalSinceNow];
            if (self.throughputTest && self.packets_rxd%20==0) {
                NSLog(@"throughput %f, packets: %d, time: %f", ((double)(self.packets_rxd*20*8))/timeInterval, self.packets_rxd, timeInterval);
                self.start = [NSDate date];
                self.packets_rxd = 0;
            }
        }];
        
        [peripheral discoverServices:nil];
        self.start = [NSDate date];
    }];
}

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
                    if ([self isInteractive]) {
                        [self presentDevices];
                    }
                }];
}

- (NSArray *)characteristicUUIDsWithString:(NSString *)aString {
  
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:4];
  
    for (NSString *uuid in [aString componentsSeparatedByString:@","]) {
        [array addObject:[CBUUID UUIDWithString:uuid]];
    }
  
    return [array copy];
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
    NSString *UUID;
  
    UUID = [NSString stringWithCFUUID:[peripheral UUID]];
    if (![[self discoveredPeripherals] containsObject: peripheral]) {
        [self.discoveredPeripherals addObject:peripheral];

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
    printf("%s %d", __FUNCTION__, __LINE__);
    exit(EXIT_FAILURE);
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

@end
