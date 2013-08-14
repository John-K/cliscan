#!/usr/bin/env python

import hello.bt

BT_SERVICE_BATTERY = '180f'
BT_CHARACTERISTIC_BATTERY_LEVEL = '2a19'

"""The intention is to make a slightly nicer Python API for people to
use. The Objective-C madness of delegates and callbacks don't
translate very well to Python, and using big fat objects for the
simple tasks that we need is kinda overkill.  So the idea's to expose
just a few functions in the hello.bt module that are a little more
Pythonic.

"""

def peripheral_ready(peripheral):
    # This function gets called when a new peripheral is detected. The
    # idea for this is to return immediately if you don't detect the
    # peripheral that you're interested in; if the peripheral _is_ the
    # one you're interested in, well, do something with it here :).

    try:
        # Here, service & characteristic are full-blown CoreBluetooth
        # CBService and CBPeripheral PyObjC objects. You can call any
        # methods on them, so see the docs at
        # <http://developer.apple.com/library/ios/documentation/CoreBluetooth/Reference/CoreBluetooth_Framework/_index.html>
        # for the methods that you can use on them. If you're not
        # familiar with PyObjC, the introduction document at
        # <http://pythonhosted.org/pyobjc/core/intro.html#first-steps>
        # shows you how to call methods.

        # You can call methods to read/write/notify to
        # characteristics, but there's no feedback that you get from
        # that yet, so it's probably not useful yet.

        service = peripheral[BT_SERVICE_BATTERY]
        characteristic = service[BT_CHARACTERISTIC_BATTERY_LEVEL]

        print "Found characteristic %s" % characteristic.UUID().description()

    except KeyError:
        # service/characteristic hasn't been scanned on the device yet, so do nothing
        return

hello.bt.find_peripheral('LightBlue', peripheral_ready)
