#!/usr/bin/env python

import cmd
import logging as log
import sys
import time

import hello.band

def main(argv):
    band = hello.band.Band('TEST')
    band.connect()

    band.hrs_start(6, 3000, 200)
    values = band.hrs_read(200)

    print >> sys.stderr, "Got values! %d" % len(values)
    for value in values:
        print "%d" % value

if __name__ == '__main__':
    main(sys.argv)
    sys.exit(0)
