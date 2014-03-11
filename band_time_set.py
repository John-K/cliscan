#!/usr/bin/env python

import argparse
import logging as log
import sha
import struct
import sys
import time

import hello.pybt as pybt

uuid_alpha0_service = '0000BA5E-1212-EFDE-1523-785FEABCD123'
uuid_control_characteristic = 'DEED'
uuid_control_response_characteristic = 'D00D'
uuid_data_characteristic = 'FEED'
uuid_data_response_characteristic = 'F00D'

log.basicConfig(level=log.DEBUG)

#

PACKET_SIZE = 20

class ControlCodes(object):
    SET_TIME = 1

def uint32_bytearray(value):
    return bytearray(struct.pack('<I', value))

def main(argv):
    arg_parser = argparse.ArgumentParser(description='Set time on the Band.')
    arg_parser.add_argument(
        'band_name',
        help='name of the Band, e.g. Band, Andre')
    args = arg_parser.parse_args(argv[1:])

    pybt.start_scan()

    peripheral = pybt.find_peripheral_by_name(args.band_name)
    print peripheral

    service = peripheral[uuid_alpha0_service]
    print service.UUID()

    control_characteristic = service[uuid_control_characteristic]
    print control_characteristic.UUID()

    data = struct.pack('<BI', ControlCodes.SET_TIME, int(time.time()))
    control_characteristic.write_no_confirm(bytearray(data))


if __name__ == '__main__':
    main(sys.argv)
