# ===================================================
# weather_pad.txt
# ===================================================
#
# Pad-ring definition for weather design.
# Based on weather.sv ports and provided pad arrangement/pinout.
#
# Notes:
# - This version includes scan and optional LCD/pressure sensor pads.
# - External labels are mapped to internal weather.sv signal names where needed.
#

WRAPPER   weather
CORE      weather_core
INSTANCE  CORE

# TOP side (left -> right)
TOP     OUTPUT       MOSI
TOP     OUTPUT       VaneCS          nVaneCS
TOP     INPUT        MISO
TOP     OUTPUT       SPICLK
TOP     PADS_VDD
TOP     INPUT_PULLUP Mode            nMode
TOP     INPUT_PULLUP Start           nStart
TOP     INPUT_PULLUP Rain            nRain
TOP     OUTPUT       SCLK

# LEFT side (top -> bottom)
LEFT    OUTPUT       BaroCS          nBaroCS
LEFT    INPUT        Demo
LEFT    OUTPUT       SDO
LEFT    INPUT        SDI
LEFT    CORE_GND
LEFT    INPUT_CLOCK  Clock
LEFT    INPUT        Reset           nReset
LEFT    INPUT        Test
LEFT    INPUT        ScanEnable

# BOTTOM side (left -> right)
BOTTOM  INOUT        DB[7]
BOTTOM  INOUT        DB[6]
BOTTOM  INOUT        DB[5]
BOTTOM  PADS_GND
BOTTOM  INOUT        DB[4]
BOTTOM  INOUT        DB[3]
BOTTOM  INOUT        DB[2]
BOTTOM  OUTPUT       SCE             nSCE

# RIGHT side (top -> bottom)
RIGHT   OUTPUT       SDIN
RIGHT   INPUT_PULLUP Wind            nWind
RIGHT   OUTPUT       RS
RIGHT   OUTPUT       R/W             RnW
RIGHT   CORE_VDD
RIGHT   OUTPUT       En
RIGHT   INOUT        DB[0]
RIGHT   INOUT        DB[1]
RIGHT   OUTPUT       D/C             DnC

