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

    allPeripherals = []
    peripherals = []

    # Callbacks. You probably want to override these in a subclass.

    def shouldUsePeripheral(self, peripheral):
        """Return True if you are interested in this peripheral. If you are
        not interested in this peripheral, return False, and you will
        not receive any callbacks for it.
        """

        log.debug('Found peripheral %s, scanning all services...' % (peripheral.name()))

        return True

    def servicesWanted(self, peripheral):
        """Return a list of UUID strings (lowercase hex), e.g. ['180f',
        '180a', '180b'] that you are interested in.  You will receive
        callbacks only for the services that you've speciefied here.
        Return None if you want all services.
        """

        return None

    def characteristicsWanted(self, service):
        """Return a list of UUID strings (lowercase hex) of characteristics
        that you're interested in for the given service, e.g. ['180f',
        '180a', '180b'].  Return None if you want all services.
        """

        log.debug('Found service %s, scanning all characteristics...', UUIDStringForBluetoothObject(service))

        return None

    def characteristicDiscovered(self, characteristic):
        """This method will get called when a characteristic you're interested in gets discovered."""

        log.debug('Found characteristic %s, scanning all descriptors...', UUIDStringForBluetoothObject(characteristic))
        characteristic().service().peripheral().discoverDescriptorsForCharacteristic_(characteristic)

    def characteristicDidRead(self, characteristic):
        """This method will get called when a characteristic gets read."""
        raise NotImplementedError

    def characteristicDidWrite(self, characteristic):
        """This method will get called when a characteristic gets written to."""
        raise NotImplementedError

    def errorHandler(self, error):
        """Any errors that occur will be passed to this callback."""
        log.error(error)

    # NSApplication delegates

    def applicationDidFinishLaunching_(self, notification):
        self.manager = CBCentralManager.alloc().initWithDelegate_queue_(self, None)

    # CBCentralManagerDelegate methods. You shouldn't need to override
    # these. If you do, let me know and I'll add it to the more standard Pythoin callbacks.

    def centralManagerDidUpdateState_(self, central):
        assert central.state() == CBCentralManagerStatePoweredOn
        self.manager.scanForPeripheralsWithServices_options_(None, None)

    def centralManager_didConnectPeripheral_(self, central, peripheral):
        peripheral.setDelegate_(self)
        peripheral.discoverServices_(UUIDStringsToUUIDs(self.servicesWanted(peripheral)))

    def centralManager_didDisconnectPeripheral_error_(self, central, peripheral, error):
        self.manager.scanForPeripheralsWithServices_options_(None, None)

    def centralManager_didDiscoverPeripheral_advertisementData_RSSI_(self, central, peripheral, advertisementData, rssi):
        if peripheral in self.allPeripherals:
            return

        self.allPeripherals.append(peripheral)

        if self.shouldUsePeripheral(peripheral):
            self.peripherals.append(peripheral)
            self.manager.connectPeripheral_options_(peripheral, None)
        else:
            log.debug("Ignoring peripheral %s (%s)" % (peripheral.UUID().description(), peripheral.name()))

    def centralManager_didFailToConnectPeripheral_error_(self, central, peripheral, error):
        log.debug('centralManager_didFailToConnectPeripheral_error_')
        pass

    def centralManager_didRetrieveConnectedPeripherals_(self, central, peripherals):
        log.debug('centralManager_didRetrieveConnectedPeripherals_')
        pass

    def centralManager_didRetrievePeripherals_(self, central, peripherals):
        log.debug('centralManager_didRetrievePeripherals_')
        pass

    # CBPeripheralDelegate

    def peripheral_didDiscoverServices_(self, peripheral, error):
        self.manager.stopScan()

        for service in peripheral.services():
            peripheral.discoverCharacteristics_forService_(
                UUIDStringsToUUIDs(self.characteristicsWanted(service)),
                service)

    def peripheral_didDiscoverCharacteristicsForService_error_(self, peripheral, service, error):
        for characteristic in service.characteristics():
            self.characteristicDiscovered(characteristic)

    def peripheral_didDiscoverDescriptorsForCharacteristic_error_(self, peripheral, characteristic, error):
        log.debug('peripheral_didDiscoverDescriptorsForCharacteristic_error_')
        pass

    def peripheral_didDiscoverIncludedServicesForService_error_(self, peripheral, service, error):
        pass

    def peripheral_didUpdateNotificationStateForCharacteristic_error_(self, peripheral, characteristic, error):
        pass

    def peripheral_didUpdateValueForCharacteristic_error_(self, peripheral, characteristic, error):
        if error is None:
            self.characteristicDidRead(characteristic)
        else:
            self.errorHandler(error)

    def peripheral_didUpdateValueForDescriptor_error_(self, peripheral, descriptor, error):
        pass

    def peripheral_didWriteValueForCharacteristic_error_(self, peripheral, characteristic, error):
        if error is None:
            self.characteristicDidWrite(characteristic)
        else:
            self.errorHandler(error)

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
    """Given a Bluetooth object (e.g. CBCharacteristic, CBService), this
    returns the UUID for that object as a string (as either a 16-bit
    or 128-bit UUID).  e.g. '180f'."""
    return obj.UUID().data().description()[1:-1]

def UUIDStringsToUUIDs(UUIDStrings):
    """Convert a list of 16-bit UUID strings (e.g. ['180f', '2a99']) to a
    list of CBUUID objects.  Returns None if passed in None."""
    if UUIDStrings is None:
        return None
    else:
        return [CBUUID.UUIDWithString_(UUIDString) for UUIDString in UUIDStrings]

def isCharacteristic(characteristic, characteristicUUIDString, serviceUUIDString=None):
    """Returns True if the CBCharacteristic object has a UUID equal to the
    given characteristicUUIDString, and optionally if the object's service
    is equal to the given serviceUUIDString."""
    if UUIDStringForBluetoothObject(characteristic) != characteristicUUIDString:
        return False

    if serviceUUIDString is not None and UUIDStringForBluetoothObject(characteristic.service()) != serviceUUIDString:
        return False

    return True

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

# go

def go(delegateClass, **kwargs):
    delegate = delegateClass.alloc().init()

    global NSApp
    NSApp = NSApplication.sharedApplication()
    NSApp.setDelegate_(delegate)
    NSApp.run()
