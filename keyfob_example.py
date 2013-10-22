#!/usr/bin/env python

"""
Read accelerometer values from a KeyFobSim app, available for your iPhone <http://chipk215.github.io/keyfobsimulation/>.
"""

import sys

import hello.pybt as pybt

i = 1

def main():
    pybt.start_scan()

    # find Keyfobdemo peripheral

    peripheral = pybt.find_peripheral_by_name('Keyfobdemo')
    print "Found peripheral %s" % (peripheral.name())

    # find accelerometer service

    accelerometer = peripheral['ffa0']
    print "Found accelerometer service %s" % (accelerometer.UUID())

    # find accelerometer

    enabler = accelerometer['ffa1']
    print "Found accelerometer/enable enabler %s" % enabler.UUID()

    # say whether accelerometer is enabled

    enabled = enabler.sync_read()
    print "Accelerometer enabled: %r" % enabled

    # turn on accelerometer

    didWrite = enabler.write_confirm(bytearray([1]))
    if didWrite:
        print "Enabled accelerometer"
    else:
        print "Could not turn on accelerometer"
        sys.exit(0)

    # get XYZ accelerometer characteristics

    x_axis = accelerometer['ffa3']
    print "Found X axis characteristic %s" % (x_axis.UUID())
    y_axis = accelerometer['ffa4']
    print "Found Y axis characteristic %s" % (y_axis.UUID())
    z_axis = accelerometer['ffa5']
    print "Found Z axis characteristic %s" % (z_axis.UUID())

    # subscribe with synchronous reads

    print "If you don't get any output here, it's very likely the KeyFobSim app on your phone has crashed. You _need_ to power off your iPhone to fix this :(. Power off phone, power on phone, restart the KeyFobSim app, Ctrl-Z, kill %1 and run again."

    x_subscription = x_axis.subscribe()
    y_subscription = y_axis.subscribe()
    z_subscription = z_axis.subscribe()

    for i in range(1, 50):
        x = x_subscription.read()
        y = y_subscription.read()
        z = z_subscription.read()
        print "Accelerometer: X=%r Y=%r Z=%r"% (x, y, z)

    x_subscription.unsubscribe()
    y_subscription.unsubscribe()
    z_subscription.unsubscribe()

if __name__ == '__main__':
    main()
