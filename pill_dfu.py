#!/usr/bin/env python

# vi:noet:sw=4 ts=4

import argparse
import logging as log
import sha
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

def uint32_t(num):
    return num % 2**32

def uint16_t(num):
    return num % 2**16

def uint8_t(num):
    return num % 2**8

def crc16(data):
    crc = 0xffff
    for i in range(0, len(data)):
        crc = uint16_t(uint8_t(crc >> 8) | (crc << 8))
        crc ^= uint16_t(data[i])
        crc ^= uint16_t(uint8_t(crc & 0xff) >> 4)
        crc ^= uint16_t(uint32_t(crc << 8) << 4)
        crc ^= uint16_t(((crc & 0xff) << 4) << 1)

    return crc

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
    arg_parser = argparse.ArgumentParser(description='Send firmware to Band.')
    arg_parser.add_argument(
        'band_name',
        help='name of the Band, e.g. Band, Andre')
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

    firmware_crc = crc16(firmware_data)
    print "crc16 is %x" % firmware_crc

    sha_object = sha.new(firmware_data)
    firmware_sha1 = sha_object.digest()
    print "firmware SHA1 is %s" % sha_object.hexdigest()

    pybt.start_scan()

    packet_notification_count = args.packet_notification_count

    # need to implement data_received_handler

    peripheral = pybt.find_peripheral_by_name(args.band_name)
    print peripheral

    dfu = peripheral[uuid_dfu_service]
    print dfu.UUID()
    dfu_control_point = dfu[uuid_dfu_control_state_characteristic]
    print dfu_control_point.UUID()
    dfu_packet = dfu[uuid_dfu_packet_characteristic]
    print dfu_packet.UUID()

    control_point_subscription = dfu_control_point.subscribe()

    did_write = dfu_control_point.write_confirm(bytearray([OpCodes.START_DFU]))
    print "wrote START_DFU: %d" % did_write
    dfu_packet.write_no_confirm(uint32_bytearray(firmware_size))
    print "wrote firmware_size=%d" % firmware_size
    validate_dfu_response(control_point_subscription.read())

    did_write = dfu_control_point.write_confirm(bytearray([OpCodes.INITIALIZE_DFU]))
    print "wrote INITIALIZE_DFU: %d" % did_write
    dfu_packet.write_no_confirm(bytearray(struct.pack('<H', firmware_crc)))
    print "wrote firmware_crc=%r" % firmware_crc
    validate_dfu_response(control_point_subscription.read())
    # dfu_packet.write_no_confirm(bytearray(firmware_sha1))
    # print "wrote firmware_sha1=%r" % firmware_sha1

    if packet_notification_count > 0:
        did_write = dfu_control_point.write_confirm(
            bytearray([OpCodes.REQ_PKT_RCPT_NOTIF])
            + uint16_bytearray(packet_notification_count))
        print "wrote REQ_PKT_RCPT_NOTIF: %d" % did_write

    did_write = dfu_control_point.write_confirm(bytearray([OpCodes.RECEIVE_FIRMWARE_IMAGE]))
    print "wrote RECEIVE_FIRMWARE_IMAGE: %d" % did_write

    for packet_count, i in enumerate(range(0, firmware_size, PACKET_SIZE)):
        data = firmware_data[i:i+PACKET_SIZE]
        dfu_packet.write_no_confirm(data)
        sys.stdout.write('.')

        if packet_notification_count > 0 and packet_count % packet_notification_count == 0:
            validate_dfu_response(control_point_subscription.read())

    print '\nwrote %d bytes (%d packets)' % (firmware_size, packet_count)
    if packet_notification_count == 0:
        validate_dfu_response(control_point_subscription.read())

    did_write = dfu_control_point.write_confirm(bytearray([OpCodes.VALIDATE_FIRMWARE_IMAGE]))
    print "wrote VALIDATE_FIRMWARE_IMAGE: %d" % did_write
    validate_dfu_response(control_point_subscription.read())

    time.sleep(1)

    did_write = dfu_control_point.write_confirm(bytearray([OpCodes.ACTIVATE_FIRMWARE_AND_RESET]))
    print "wrote ACTIVATE_FIRMWARE_AND_RESET: %d" % did_write

if __name__ == '__main__':
    main(sys.argv)
