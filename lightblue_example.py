#!/usr/bin/env python

import hello.pybt as pybt

"""
Read the battery from a LightBlue peripheral.
"""

def main():
    pybt.start_scan()

    peripheral = pybt.find_peripheral_by_name('LightBlue')
    battery_service = peripheral['180f']
    battery_level_characteristic = battery_service['2a19']
    value = battery_level_characteristic.sync_read()
    print "Battery level: %r" % value

if __name__ == '__main__':
    main()
