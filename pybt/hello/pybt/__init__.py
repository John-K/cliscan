import atexit
import ctypes
import os

import IOBluetooth.CoreBluetooth as CoreBluetooth
import Cocoa

#

dylib = ctypes.cdll.LoadLibrary(os.path.join(os.path.dirname(__file__), 'build/Release/PyBT.dylib'))

#

dylib.find_peripheral_by_name.restype = ctypes.c_void_p
dylib.peripheral_get_service_by_uuid.restype = ctypes.c_void_p
dylib.service_get_characteristic_by_uuid.restype = ctypes.c_void_p
dylib.characteristic_sync_read.restype = ctypes.c_void_p

#

def peripheral_getitem(self, item):
    pointer = dylib.peripheral_get_service_by_uuid(self.__c_void_p__(), item)
    return CoreBluetooth.CBService(c_void_p=pointer)
CoreBluetooth.CBPeripheral.__getitem__ = peripheral_getitem

#

def service_getitem(self, item):
    pointer = dylib.service_get_characteristic_by_uuid(self.__c_void_p__(), item)
    return CoreBluetooth.CBCharacteristic(c_void_p=pointer)
CoreBluetooth.CBService.__getitem__ = service_getitem

#

def characteristic_sync_read(self):
    """Returns a bytearray object."""
    pointer = dylib.characteristic_sync_read(self.__c_void_p__())
    data = Cocoa.NSData(c_void_p=pointer)
    return bytearray(data.bytes().tobytes())
CoreBluetooth.CBCharacteristic.sync_read = characteristic_sync_read

def characteristic_write(self, value, confirm):
    if isinstance(value, bytearray):
        pass
    elif isinstance(value, str):
        value = bytearray(value)
    else:
        raise TypeError("characteristic_write_confirm requires a bytearray or str as its first parameter")

    data = Cocoa.NSData.alloc().initWithBytes_length_(value, len(value))
    result = dylib.characteristic_write(self.__c_void_p__(), data.__c_void_p__(), 1 if confirm else 0)
    return result != 0
def characteristic_write_confirm(self, value):
    return characteristic_write(self, value, True)
def characteristic_write_no_confirm(self, value):
    return characteristic_write(self, value, False)
CoreBluetooth.CBCharacteristic.write_confirm = characteristic_write_confirm
CoreBluetooth.CBCharacteristic.write_no_confirm = characteristic_write_no_confirm

#

def start_scan():
    """Starts the scan for Bluetooth LE peripherals.  You need to call
    this before you do anything else.
    """

    atexit.register(stop_scan)
    dylib.start_scan()

def stop_scan():
    dylib.stop_scan()

def find_peripheral_by_name(name):
    """Finds a peripheral by a given name, e.g. "LightBlue" or "Band (DFU
    Mode)."""

    pointer = dylib.find_peripheral_by_name(name)
    peripheral = CoreBluetooth.CBPeripheral(c_void_p=pointer)
    return peripheral
