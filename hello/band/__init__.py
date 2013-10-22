import logging as log
import struct
import time

import hello.pybt as pybt

log.basicConfig(level=log.DEBUG)

CMD_START_HRS = 0x33
CMD_CAL_HRS = 0x35
CMD_SEND_DATA = 0x44
CMD_ENTER_DFU = 0x99
CMD_START_ACCEL_GYRO = 0x55

STATE_HRS_DONE = 0x34
STATE_IDLE = 0x66

IMU_PACKET_SIZE = 12
IMU_SAMPLES = 480

class UUID:
    class SERVICE:
        #DEBUG = '1337'
        DEBUG = '00001337-1212-efde-1523-785feabcd123'

    class CHARACTERISTIC:
        CONTROL = 'beef'
        DATA = 'da1a'
        #CONTROL = '00001531-1212-EFDE-1523-785FEABCD123'
        #DATA = '00001531-1212-EFDE-1523-785FEABCD123'

class Band(object):
    def __init__(self, name):
        self.name = name

    def connect(self):
        pybt.start_scan()
        log.debug('Connecting to %s...' % self.name)
        self.peripheral = pybt.find_peripheral_by_name(self.name)
        log.debug('Found %s' % self.name)
        self.debug_service = self.peripheral[UUID.SERVICE.DEBUG]
        log.debug('Found debug service: %s' % self.debug_service.UUID())
        self.control = self.debug_service[UUID.CHARACTERISTIC.CONTROL]
        log.debug('Found control characteristic: %s' % self.control.UUID())

    # heart rate

    def hrs_start(self, power_level, delay, samples):
        command = bytearray(struct.pack(
            '<BBHH', CMD_START_HRS, power_level, delay, samples))
        log.debug("Sending %s" % repr(command))
        self.control.write_confirm(command)

    def calibrate_hrs_start(self, power_level, delay, samples):
        command = bytearray(struct.pack(
            '<BBHH', CMD_CAL_HRS, power_level, delay, samples))
        log.debug("Sending %s" % repr(command))
        self.control.write_confirm(command)

    def hrs_read(self, samples):
        self.data = self.debug_service[UUID.CHARACTERISTIC.DATA]
        log.debug('Found data characteristic: %s' % self.data.UUID())

        self.data_subscription = self.data.subscribe()
        log.debug('Subscribed to data characteristic')

        data = bytearray()
        self.control.write_confirm(bytearray([CMD_SEND_DATA]))
        log.debug('Wrote CMD_SEND_DATA to control characteristic')

        PACKET_SIZE = 20

        for i in range(0, samples / PACKET_SIZE):
            packet = self.data_subscription.read()
            text = ' '.join([str(value) for value in packet])
            log.debug('<- ' + text)
            data += packet
        return data

    # accelerometer/gyroscope

    def test_imu(self, samples=IMU_SAMPLES):
        self.data = self.debug_service[UUID.CHARACTERISTIC.DATA]
        log.debug('Found data characteristic: %s' % self.data.UUID())

        self.data_subscription = self.data.subscribe()
        log.debug('Subscribed to data characteristic')

        self.control.write_confirm(bytearray([CMD_START_ACCEL_GYRO]))
        log.debug("Wrote CMD_START_ACCEL_GYRO to control characteristic")

        data = bytearray()
        for i in range(0, samples / IMU_PACKET_SIZE):
            packet = self.data_subscription.read()
            data += packet

            text = ' '.join(['%2x' % value for value in packet])
            log.debug('<- ' + text)

            #print len(packet)
            #print type(packet)

            #values = list(struct.unpack('<hhhhh', str(packet)))
            #print ' '.join(['%6hd' % value for value in values])
        return data

    # DFU

    def reset_to_DFU(self):
        self.control.write_confirm(bytearray([CMD_ENTER_DFU]))
