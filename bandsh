#!/usr/bin/env python

import argparse
import cmd
import datetime
import logging as log
import struct
import sys
import time

import hello.band

log.basicConfig(level=log.DEBUG)

class BandCmd(cmd.Cmd):
    def __init__(self, band):
        self.band = band
        cmd.Cmd.__init__(self)  # can't use super since cmd.Cmd is an old-style class
        self.start_time = datetime.datetime.now()
        self.prompt = '%s> ' % self.band.name

    def do_start_hrs(self, line):
        """usage: start_hrs POWER_LEVEL SAMPLES [LED_ACTIVE] [DELAY].
        
POWER_LEVEL is from [0, 100].
SAMPLES is the number of samples to take. The sampling rate is 100Hz.
LED_ACTIVE is optional: use 1 if you want to keep the LED on all the time. Defaults to 0.
DELAY is optional, and is in milliseconds.

e.g. "start_hrs 10 3000 200" will sample for 2 seconds (200 samples * 100Hz) at power level 10 (0xA), with a 3-second delay (3000 milliseconds).
        """

        fields = line.split()

        power_level = int(fields[0])
        sample_count = int(fields[1])
        led_active = int(fields[2]) if len(fields) > 2 else 0
        delay = int(fields[3]) if len(fields) > 3 else 0

        output_path = '%s.%s.%02u.%03u.%04u.csv' % (
            self.band.name,
            self.start_time.strftime('%Y%m%d.%H%M%S'),
            power_level, 
            sample_count,
            delay)

        method = (self.band.calibrate_hrs_start
                  if led_active
                  else self.band.hrs_start)
        method(power_level, delay, sample_count)
        data = self.band.hrs_read(sample_count)

        file = open(output_path, 'a')
        for i, value in enumerate(data):
            file.write('%u, %u\n' % (i, value))
        file.close()

        for value in data:
            print "%3u" % value,
        print

    def do_test_ag(self, line):
        self.band.test_ag()
        # data = self.band.test_ag()

        # for i in range(0, hello.band.AG_SAMPLES, hello.band.AG_PACKET_SIZE):
        #     s = str(data[i:i+12])
        #     values = list(struct.unpack('<hhhhhh', s))
        #     print ' '.join(['%6hd' % value for value in values])

    def do_DFU(self, line):
        self.band.reset_to_DFU()
        print "Sent DFU command; %s will reset, so I'm disconnecting and exiting." % self.band.name
        return True
        
    def do_EOF(self, line):
        return True

def main(argv):
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        'name',
        help='Name of band (e.g. Band, Andre)'
    )
    args = arg_parser.parse_args(argv[1:])

    band = hello.band.Band(args.name)
    band.connect()
    bandcmd = BandCmd(band)
    bandcmd.cmdloop()

if __name__ == '__main__':
    main(sys.argv)
    sys.exit(0)
