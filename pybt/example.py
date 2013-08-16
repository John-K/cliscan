#!/usr/bin/env python

import logging as log
import sys

from Cocoa import *
from IOBluetooth.CoreBluetooth import *

import hello.bt as bt

BATTERY_SERVICE = '180f'
BATTERY_LEVEL_CHARACTERISTIC = '2a19'

# CoreBluetooth programming guide (Performing Common Central Role Tasks):
# http://developer.apple.com/library/ios/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks/PerformingCommonCentralRoleTasks.html
#
# CoreBluetooth framework reference:
# http://developer.apple.com/library/ios/documentation/CoreBluetooth/Reference/CoreBluetooth_Framework/_index.html
#
# CBPeripheral:
# http://developer.apple.com/library/ios/documentation/CoreBluetooth/Reference/CBPeripheral_Class/translated_content/CBPeripheral.html
#
# CBPeripheralDelegate:
# https://developer.apple.com/library/mac/documentation/CoreBluetooth/Reference/CBPeripheralDelegate_Protocol/translated_content/CBPeripheralDelegate.html
#
# CBService:
# http://developer.apple.com/library/ios/documentation/CoreBluetooth/Reference/CBService_Class/translated_content/CBService.html
#
# CBCharacteristic:
# http://developer.apple.com/library/ios/documentation/CoreBluetooth/Reference/CBCharacteristic_Class/translated_content/CBCharacteristic.html

class BandReadBatteryDelegate(bt.AppDelegate):
    # This is an example delegate class that you should implement.  See the docstrings for the method definitios in the AppDelegate class for their specification.

    def shouldUsePeripheral(self, peripheral):
        return peripheral.name() == 'Band (DFU Mode)'

    def servicesWanted(self, peripheral):
        if self.shouldUsePeripheral(peripheral):
            return [BATTERY_SERVICE]
        else:
            return None

    def characteristicsWanted(self, service):
        if bt.UUIDStringForBluetoothObject(service) == BATTERY_SERVICE:
            return [BATTERY_LEVEL_CHARACTERISTIC]
        else:
            return None

    def characteristicDiscovered(self, characteristic):
        log.debug('Found characteristic %s for service %s' % (
            bt.UUIDStringForBluetoothObject(characteristic),
            bt.UUIDStringForBluetoothObject(characteristic.service())))

        if bt.isCharacteristic(characteristic, BATTERY_LEVEL_CHARACTERISTIC, BATTERY_SERVICE):
            print 'Starting read from %s%s' % (BATTERY_SERVICE, BATTERY_LEVEL_CHARACTERISTIC)
            characteristic.service().peripheral().readValueForCharacteristic_(characteristic)

    def characteristicDidRead(self, characteristic):
        if bt.isCharacteristic(characteristic, BATTERY_LEVEL_CHARACTERISTIC, BATTERY_SERVICE):
            print "[%s%s]: %s" % (BATTERY_SERVICE, BATTERY_LEVEL_CHARACTERISTIC, characteristic.value())
            print "Done. Press Ctrl-Z then 'kill %1' to kill this thing."

class CyclingSpeedAndCadenceWriteDelegate(bt.AppDelegate):
    # An example delegate class for how to write to a characteristic.

    SERVICE = '1816'
    CHARACTERISTIC = '2a55'

    def shouldUsePeripheral(self, peripheral):
        return peripheral.name() == 'LightBlue'

    def servicesWanted(self, peripheral):
        if self.shouldUsePeripheral(peripheral):
            return [self.SERVICE]
        else:
            return None

    def characteristicsWanted(self, service):
        if bt.UUIDStringForBluetoothObject(service) == self.SERVICE:
            return [self.CHARACTERISTIC]
        else:
            return None

    def characteristicDiscovered(self, characteristic):
        if bt.isCharacteristic(characteristic, self.CHARACTERISTIC, self.SERVICE):
            print 'Starting write to %s%s' % (self.SERVICE, self.CHARACTERISTIC)
            characteristic.service().peripheral().writeValue_forCharacteristic_type_(
                NSString.stringWithString_('Awesomesauce').dataUsingEncoding_(NSUTF8StringEncoding),
                characteristic,
                CBCharacteristicWriteWithoutResponse)

    def characteristicDidWrite(self, characteristic):
        if bt.isCharacteristic(characteristic, self.CHARACTERISTIC, self.SERVICE):
            print "Updated %s%s to %s" % (self.SERVICE, self.CHARACTERISTIC, characteristic.value())

if __name__ == '__main__':
    bt.go(BandReadBatteryDelegate)
    # bt.go(CyclingSpeedAndCadenceWriteDelegate)
