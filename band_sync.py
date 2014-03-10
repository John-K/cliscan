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
    SEND_SENSOR_DATA = 2

class OpCodes(object):
    START_DFU = 1
    INITIALIZE_DFU = 2
    RECEIVE_FIRMWARE_IMAGE = 3
    VALIDATE_FIRMWARE_IMAGE = 4
    ACTIVATE_FIRMWARE_AND_RESET = 5
    SYSTEM_RESET = 6
    REQ_PKT_RCPT_NOTIF = 8
    RESPONSE = 16
    PKT_RCPT_NOTIF = 17

op_codes = dict(zip(OpCodes.__dict__.values(), OpCodes.__dict__.keys()))

status_code_lookup = {
    1: "SUCCESS",
    2: "Invalid State",
    3: "Not Supported",
    4: "Data Size Exceeds Limit",
    5: "CRC Error",
    6: "Operation Failed"
}

def uint32_bytearray(value):
    return bytearray(struct.pack('<I', value))

def uint16_bytearray(value):
    return bytearray(struct.pack('<H', value))

def validate_dfu_response(data):
    op_code = data[0]

    if op_code == OpCodes.PKT_RCPT_NOTIF:
        print('Received PKT_RCPT_NOTIF for %d bytes' % struct.unpack('<H', str(data[0:2])))
    elif op_code == OpCodes.RESPONSE:
        request_op_code = int(data[1])
        request_op_code_text = op_codes.get(request_op_code, '(unknown op code)')

        response_value = int(data[2])
        response_text = status_code_lookup.get(response_value, '(unknown response value)')

        print('Received response OpCode %s (%d): %s (%d)' % (
            request_op_code_text,
            request_op_code,
            response_text,
            response_value))
    else:
        dataText = ''
        for c in data:
            dataText += '%x' % ord(c)
        print('Received unknown response (%s): %s' % (type(data), dataText))

def main(argv):
    arg_parser = argparse.ArgumentParser(description='Read sensor data from Band and upload it to Ingress server.')
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

    # control_response_characteristic = peripheral[uuid_control_response_characteristic]
    # print control_response_characteristic.UUID()

    data_characteristic = service[uuid_data_characteristic]
    print data_characteristic.UUID()

    # data_response_characteristic = peripheral[uuid_data_response_characteristic]
    # print data_response_characteristic.UUID()

    data_subscription = data_characteristic.subscribe()

    control_characteristic.write_no_confirm(bytearray([ControlCodes.SEND_SENSOR_DATA]))
    print "Wrote 0x02 to 0xDEED"

    packets = [bytearray()] * 15
    expected_size = None

    while True:
        data = data_subscription.read()
        print "Received %d bytes: %r" % (len(data), data)

        sequence_number = data[0]
        if sequence_number == 0:
            print "Got header packet"
            (expected_size, ) = struct.unpack('<H', data[1:3])
            packet = data[3:]
        else:
            packet = data[1:]

        packets[sequence_number] = packet

        received_size = sum(len(b) for b in packets)
        print "Received %d of %d bytes" % (received_size, expected_size)
        if received_size == expected_size:
            # last packet received; now remove SHA-1 from data packets and compute it
            # packets[-1] = bytearray()

            final_packets = reduce(lambda lhs, rhs: lhs+rhs, packets)
            print "Final: %r" % final_packets

            break

if __name__ == '__main__':
    main(sys.argv)
