#!/usr/bin/env python

import argparse
import logging as log
import struct
import sys
import time

import hello.pybt as pybt

uuid_dfu_service = '00001530-1212-EFDE-1523-785FEABCD123'
uuid_dfu_control_state_characteristic = '00001531-1212-EFDE-1523-785FEABCD123'
uuid_dfu_packet_characteristic = '00001532-1212-EFDE-1523-785FEABCD123'

log.basicConfig(level=log.DEBUG)

#

PACKET_SIZE = 20

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

    print "Validating..."

    if op_code == OpCodes.PKT_RCPT_NOTIF:
        log.debug('Received PKT_RCPT_NOTIF for %d bytes' % struct.unpack('<H', data[1:2]))
    elif op_code == OpCodes.RESPONSE:
        request_op_code = int(data[1])
        request_op_code_text = op_codes.get(request_op_code, '(unknown op code)')

        response_value = int(data[2])
        response_text = status_code_lookup.get(response_value, '(unknown response value)')

        log.debug('Received response OpCode %s (%d): %s (%d)' % (
            request_op_code_text,
            request_op_code,
            response_text,
            response_value))
    else:
        dataText = ''
        for c in data:
            dataText += '%x' % ord(c)
        log.debug('Received unknown response (%s): %s' % (type(data), dataText))

def main(argv):
    arg_parser = argparse.ArgumentParser(description='Send firmware to Band.')
    arg_parser.add_argument(
        'firmware_path',
        help='path to firmware .bin file')
    arg_parser.add_argument(
        '-w', '--wait',
        dest='packet_notification_count',
        help='wait for acknowledgement from Band when sending data after PACKET_NOTIFICATION_COUNT packets (where one packet is %d bytes)' % PACKET_SIZE,
        type=int,
        default=0)
    args = arg_parser.parse_args(argv[1:])

    firmware_data = bytearray(open(args.firmware_path, 'rb').read())
    firmware_size = len(firmware_data)

    print "firmware is %d bytes" % firmware_size

    pybt.start_scan()

    packet_notification_count = args.packet_notification_count

    # need to implement data_received_handler

    peripheral = pybt.find_peripheral_by_name('Andre')
    print peripheral

    dfu = peripheral[uuid_dfu_service]
    print dfu.UUID()
    dfu_control_point = dfu[uuid_dfu_control_state_characteristic]
    print dfu_control_point.UUID()
    dfu_packet = dfu[uuid_dfu_packet_characteristic]
    print dfu_packet.UUID()
    
    if packet_notification_count > 0:
        dfu_control_point.write_confirm(
            bytearray([OpCodes.REQ_PKT_RCPT_NOTIF])
            + uint16_bytearray(packet_notification_count))
        validate_dfu_response(dfu_control_point.sync_read())

    control_point_subscription = dfu_control_point.subscribe()

    didWrite = dfu_control_point.write_confirm(bytearray([OpCodes.START_DFU]))
    print "wrote START_DFU: %d" % didWrite
    dfu_packet.write_no_confirm(uint32_bytearray(firmware_size))
    print "wrote firmware_size=%d" % firmware_size
    #validate_dfu_response(control_point- -p_subscription.read())

    didWrite = dfu_control_point.write_confirm(bytearray([OpCodes.RECEIVE_FIRMWARE_IMAGE]))
    print "wrote RECEIVE_FIRMWARE_IMAGE: %d" % didWrite

    #validate_dfu_response(control_point_subscription.read())

    for packet_count, i in enumerate(range(0, firmware_size, PACKET_SIZE)):
        data = firmware_data[i:i+PACKET_SIZE]
        dfu_packet.write_no_confirm(data)
        print "wrote data: %d-%d" % (i, i+PACKET_SIZE)
        #validate_dfu_response(control_point_subscription.read())

        if packet_notification_count > 0 and packet_count % packet_notification_count == 0:
            # what do we do here?
            pass

    didWrite = dfu_control_point.write_confirm(bytearray([OpCodes.VALIDATE_FIRMWARE_IMAGE]))
    print "wrote VALIDATE_FIRMWARE_IMAGE: %d" % didWrite
    validate_dfu_response(control_point_subscription.read())

    time.sleep(1)

    didWrite = dfu_control_point.write_confirm(bytearray([OpCodes.ACTIVATE_FIRMWARE_AND_RESET]))
    print "wrote ACTIVATE_FIRMWARE_AND_RESET: %d" % didWrite
    validate_dfu_response(control_point_subscription.read())

if __name__ == '__main__':
    main(sys.argv)
