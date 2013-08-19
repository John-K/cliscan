#!/usr/bin/env python

import hello.pybt as pybt

def main():
    pybt.start_scan()
    peripheral = pybt.find_peripheral_by_name('Band (DFU Mode)')
    print "Found peripheral %s" % (peripheral.name())
    service = peripheral['1800']
    print "Found service %s" % (service.UUID())
    characteristic = service['2a00']
    print "Found characteristic %s" % (characteristic.UUID())
    print "18002a00 says: %s" % characteristic.sync_read()

if __name__ == '__main__':
    main()
