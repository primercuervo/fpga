#!/usr/bin/python

import optparse
import os
import re

# Parse options
parser = optparse.OptionParser()
parser.add_option("-i", "--include_dir", type="string", dest="include_dir", help="Insert the path of your RFNoC OOT module", default="")
parser.add_option("-t", "--target", type="string", dest="target", help="Target device [X310, X300, E310]", default="")
parser.add_option("-b", "--blocks", type="string", dest="blocks", help="RFNoC blocks to add to the device image", default="")
(options, args) = parser.parse_args()

# Args
if (len(args) < 1):
	print('ERROR: Empty Arguments')
	parser.print_help()
	sys.exit(1)
include_dir = options.include_dir
if (len(include_dir) == 0):
	print('ERROR: Please specify a RFNoC OOT module path')
	parser.print_help()
	sys.exit(1)
else if not os.path.isdir(include_dir):
	print('ERROR: The given directory does not exist or can not be found')
	parser.print_help()
	sys.exit(1)
    os.putenv('OOT_INCLUDE_DIR', include_dir)
target = options.target
if (len(target) == 0):
	print('ERROR: Please specify a device target')
	parser.print_help()
	sys.exit(1)
else if(target) not in ['X310','X300','E300','x310','x300','e300']:
	print('ERROR: Target device not recognized')
	parser.print_help()
	sys.exit(1)
blocks = options.target
if (len(blocks) == 0):
	print('ERROR: Please list the desired RFNoC blocks to include into the device')
	parser.print_help()
	sys.exit(1)




