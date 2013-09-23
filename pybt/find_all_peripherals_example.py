#!/usr/bin/env python

import hello.pybt as pybt

"""
Read the battery from a LightBlue peripheral.
"""

def main():
    pybt.start_scan()

    peripherals = pybt.find_all_peripherals(timeout=3)
    for peripheral in peripherals:
        print "Found peripheral with name=%s" % peripheral.name()

if __name__ == '__main__':
    main()
