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
    prompt = 'Band> '

    def __init__(self, band):
        self.band = band
        cmd.Cmd.__init__(self)  # can't use super since cmd.Cmd is an old-style class
        self.start_time = datetime.datetime.now()

    def do_start_hrs(self, line):
        """usage: start_hrs POWER_LEVEL SAMPLES [DELAY].
        
POWER_LEVEL is from [0, 100].
SAMPLES is the number of samples to take. The sampling rate is 100Hz.
DELAY is optional, and is in milliseconds.

e.g. "start_hrs 10 3000 200" will sample for 2 seconds (200 samples * 100Hz) at power level 10 (0xA), with a 3-second delay (3000 milliseconds).
        """

        fields = line.split()

        power_level = int(fields[0])
        sample_count = int(fields[1])
        delay = int(fields[2]) if len(fields) > 2 else 0

        output_path = '%s.%02u.%03u.%04u.csv' % (
            self.start_time.strftime('%Y%m%d.%H%M%S'),
            power_level, 
            sample_count,
            delay)

        self.band.hrs_start(power_level, delay, sample_count)
        data = self.band.hrs_read(sample_count)

        file = open(output_path, 'a')
        for value in data:
            file.write('%u\n' % value)
        file.close()

        for value in data:
            print "%3u" % value,
        print

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
