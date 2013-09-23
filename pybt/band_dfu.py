#!/usr/bin/env python

import struct
import sys
import time

import hello.pybt as pybt

uuid_dfu_service = '000015301212efde1523785feabcd123'
uuid_dfu_control_state_characteristic = '000015311212efde1523785feabcd123'
uuid_dfu_packet_characteristic = '000015321212efde1523785feabcd123'
uuid_client_characteristic_configuration_descriptor = '2902'

class OpCodes:
    START_DFU = 1
    INITIALIZE_DFU = 2
    RECEIVE_FIRMWARE_IMAGE = 3
    VALIDATE_FIRMWARE_IMAGE = 4
    ACTIVATE_FIRMWARE_AND_RESET = 5
    SYSTEM_RESET = 6
    REQ_PKT_RCPT_NOTIF = 8
    RESPONSE = 16
    PKT_RCPT_NOTIF = 17

# Textual description lookup table for status codes received from peer.
status_code_lookup = {
    1: "SUCCESS",
     2: "Invalid State",
     3: "Not Supported",
     4: "Data Size Exceeds Limit",
     5: "CRC Error",
     6: "Operation Failed"
}

def uint32_bytearray(value):
    return struct.pack('<I', value)

def uint16_bytearray(value):
    return struct.pack('<H', value)

def main():
    print "This is not working yet."
    sys.exit(1)

    pybt.start_scan()

    # need to implement data_received_handler

    peripherals = pybt.find_all_peripherals(timeout=3)
    for peripheral in peripherals:
        print "Found peripheral with name=%s" % peripheral.name()

    firmware_path = sys.argv[1]
    firmware_data = bytearray(open(firmware_path, 'rb'))
    firmware_size = len(firmware_data)

    peripheral = peripherals[0]
    dfu = peripheral[uuid_dfu_service]
    dfu_cccd = dfu[uuid_client_characteristic_configuration_descriptor]
    dfu_control_point = dfu[uuid_dfu_control_state_characteristic]
    dfu_packet = dfu[uuid_dfu_packet_characteristic]

    dfu_cccd.write_confirm(uint16_bytearray(1)))
    # should turn on packet notifications here, if we want to
    dfu_control_point.write_confirm(bytearray([OpCodes.START_DFU]))
    dfu_packet.write_confirm(bytearray(uint16_bytearray(firmware_size)))
    dfu_control_point.write_confirm(bytearray(OpCodes.RECEIVE_FIRMWARE_IMAGE))

    # why 20 bytes?
    for i in range(0, firmware_size, 20):
        data = firmware_data[i:i+20]
        dfu_packet.write_confirm(data)

    dfu_control_point.write_confirm(bytearray(OpCodes.VALIDATE_FIRMWARE_IMAGE))
    time.sleep(1)
    dfu_control_point.write_confirm(bytearray(OpCodes.ACTIVATE_FIRMWARE_AND_RESET))

if __name__ == '__main__':
    main()
