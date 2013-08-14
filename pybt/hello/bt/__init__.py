import objc

from CoreFoundation import *

from IOBluetooth.CoreBluetooth import *

import logging as log
log.basicConfig(level=log.DEBUG)

Cocoa = objc.initFrameworkWrapper(
    "Cocoa",
    frameworkIdentifier="com.apple.Cocoa",
    frameworkPath=objc.pathForFramework("/System/Library/Frameworks/Cocoa.framework"),
    globals=globals())

NSApp = None

class AppDelegate(NSObject):
    peripherals = []

    # NSApplicationDelegate

    def applicationDidFinishLaunching_(self, notification):
        self.manager = CBCentralManager.alloc().initWithDelegate_queue_(self, None)

    # CBCentralManagerDelegate

    def centralManagerDidUpdateState_(self, central):
        assert central.state() == CBCentralManagerStatePoweredOn
        self.manager.scanForPeripheralsWithServices_options_(None, None)

    def centralManager_didConnectPeripheral_(self, central, peripheral):
        peripheral.setDelegate_(self)
        peripheral.discoverServices_(None)

    def centralManager_didDisconnectPeripheral_error_(self, central, peripheral, error): #
        pass

    def centralManager_didDiscoverPeripheral_advertisementData_RSSI_(self, central, peripheral, advertisementData, rssi):
        self.peripherals.append(peripheral)

        if peripheral.name() == self.peripheralName:
            log.debug("Found %s" % peripheral.name())
            #self.manager.stopScan()
            self.manager.connectPeripheral_options_(peripheral, None)
        elif peripheral.name is not None:
            log.debug("Found %s (%s), will keep scanning..." % (peripheral.UUID(), peripheral.name()))

    def centralManager_didFailToConnectPeripheral_error_(self, central, peripheral, error):
        pass

    def centralManager_didRetrieveConnectedPeripherals_(self, central, peripherals):
        pass

    def centralManager_didRetrievePeripherals_(self, central, peripherals):
        pass

    # CBPeripheralDelegate

    def peripheral_didDiscoverServices_(self, peripheral, error):
        for service in peripheral.services():
            peripheral.discoverCharacteristics_forService_(None, service)

    def peripheral_didDiscoverCharacteristicsForService_error_(self, peripheral, service, error):
        for characteristic in service.characteristics():
            peripheral.discoverDescriptorsForCharacteristic_(characteristic)
            self.readyCallback(peripheral)

    def peripheral_didDiscoverDescriptorsForCharacteristic_error_(self, peripheral, characteristic, error):
        log.debug('peripheral_didDiscoverDescriptorsForCharacteristic_error_')
        pass

    def peripheral_didDiscoverIncludedServicesForService_error_(self, peripheral, service, error):
        pass

    def peripheral_didUpdateNotificationStateForCharacteristic_error_(self, peripheral, characteristic, error):
        pass

    def peripheral_didUpdateValueForCharacteristic_error_(self, peripheral, characteristic, error):
        pass

    def peripheral_didUpdateValueForDescriptor_error_(self, peripheral, descriptor, error):
        pass

    def peripheral_didWriteValueForCharacteristic_error_(self, peripheral, characteristic, error):
        pass

    def peripheral_didWriteValueForDescriptor_error_(self, peripheral, descriptor, error):
        pass

    def peripheralDidInvalidateServices(self, peripheral):
        pass

    def peripheralDidUpdateName(self, peripheral):
        pass

    def peripheralDidUpdateRSSI_error_(self, periphral, error):
        pass

    def peripheral_didReliablyWriteValuesForCharacteristics_error_(self, peripheral, characteristics, error):
        pass

    def peripheral_didUpdateBroadcastStateForCharacteristic_error_(self, peripheral, characteristic, error):
        pass

# Utility functions

def UUIDStringForBluetoothObject(obj):
    return obj.UUID().data().description()[1:5]

# CBPeripheral additions

def peripheralGetItem(self, key):
    """Pass in a 16-byte UUID string, e.g. peripheral['180f']"""
    if self.services() is None:
        raise KeyError

    for service in self.services():
        if UUIDStringForBluetoothObject(service) == key:
            return service

    raise KeyError
CBPeripheral.__getitem__ = peripheralGetItem

# CBService additions

def serviceGetItem(self, key):
    """Pass in a 16-byte UUID string, e.g. service['180f']"""
    if self.characteristics() is None:
        raise KeyError

    for characteristic in self.characteristics():
        if UUIDStringForBluetoothObject(characteristic) == key:
            return characteristic

    raise KeyError

CBService.__getitem__ = serviceGetItem

def find_peripheral(peripheralName, readyCallback):
    try:
        appDelegate = AppDelegate.alloc().init()
        appDelegate.peripheralName = peripheralName
        appDelegate.readyCallback = readyCallback

        global NSApp
        NSApp = NSApplication.sharedApplication()
        NSApp.setDelegate_(appDelegate)
        NSApp.run()
        #NSRunLoop.mainRunLoop().run()
    except KeyboardInterrupt:
        sys.exit(1)
