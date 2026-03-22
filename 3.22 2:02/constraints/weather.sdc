###################################################################

# Created by write_sdc on Sun Mar 22 13:41:43 2026

###################################################################
set sdc_version 2.1

set_units -time ns -resistance kOhm -capacitance pF -voltage V -current uA
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
Clock]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports Clock]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
nRain]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports nRain]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
Demo]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports Demo]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
nWind]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports nWind]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[7]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[7]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[6]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[6]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[5]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[5]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[4]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[4]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[3]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[3]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[2]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[2]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[1]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[1]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
{DB[0]}]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports {DB[0]}]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
nReset]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports nReset]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
nStart]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports nStart]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
MISO]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports MISO]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
nMode]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports nMode]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
Test]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports Test]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
SDI]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports SDI]
set_driving_cell -min -lib_cell BU1P -library c35_IOLIB_WC -pin PAD [get_ports \
ScanEnable]
set_driving_cell -max -lib_cell BU24P -library c35_IOLIB_WC -pin PAD           \
[get_ports ScanEnable]
set_load -pin_load 1 [get_ports nVaneCS]
set_load -pin_load 1 [get_ports SPICLK]
set_load -pin_load 1 [get_ports {DB[7]}]
set_load -pin_load 1 [get_ports {DB[6]}]
set_load -pin_load 1 [get_ports {DB[5]}]
set_load -pin_load 1 [get_ports {DB[4]}]
set_load -pin_load 1 [get_ports {DB[3]}]
set_load -pin_load 1 [get_ports {DB[2]}]
set_load -pin_load 1 [get_ports {DB[1]}]
set_load -pin_load 1 [get_ports {DB[0]}]
set_load -pin_load 1 [get_ports RnW]
set_load -pin_load 1 [get_ports nBaroCS]
set_load -pin_load 1 [get_ports En]
set_load -pin_load 1 [get_ports RS]
set_load -pin_load 1 [get_ports MOSI]
set_load -pin_load 1 [get_ports SDO]
set_load -min -pin_load 0.01 [get_ports nVaneCS]
set_load -min -pin_load 0.01 [get_ports SPICLK]
set_load -min -pin_load 0.01 [get_ports {DB[7]}]
set_load -min -pin_load 0.01 [get_ports {DB[6]}]
set_load -min -pin_load 0.01 [get_ports {DB[5]}]
set_load -min -pin_load 0.01 [get_ports {DB[4]}]
set_load -min -pin_load 0.01 [get_ports {DB[3]}]
set_load -min -pin_load 0.01 [get_ports {DB[2]}]
set_load -min -pin_load 0.01 [get_ports {DB[1]}]
set_load -min -pin_load 0.01 [get_ports {DB[0]}]
set_load -min -pin_load 0.01 [get_ports RnW]
set_load -min -pin_load 0.01 [get_ports nBaroCS]
set_load -min -pin_load 0.01 [get_ports En]
set_load -min -pin_load 0.01 [get_ports RS]
set_load -min -pin_load 0.01 [get_ports MOSI]
set_load -min -pin_load 0.01 [get_ports SDO]
create_clock [get_ports Clock]  -name master_clock  -period 30517.6  -waveform {0 15258.8}
set_clock_latency 2.5  [get_clocks master_clock]
set_clock_uncertainty 1  [get_clocks master_clock]
set_clock_transition -max -rise 0.5 [get_clocks master_clock]
set_clock_transition -max -fall 0.5 [get_clocks master_clock]
set_clock_transition -min -rise 0.5 [get_clocks master_clock]
set_clock_transition -min -fall 0.5 [get_clocks master_clock]
set_false_path   -from [get_ports nReset]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports nReset]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nReset]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports nRain]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nRain]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports Demo]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports Demo]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports nWind]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nWind]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[7]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[7]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[6]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[6]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[5]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[5]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[4]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[4]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[3]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[3]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[2]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[2]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[1]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[1]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports {DB[0]}]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[0]}]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports nStart]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nStart]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports MISO]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports MISO]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports nMode]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nMode]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports Test]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports Test]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports SDI]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports SDI]
set_input_delay -clock master_clock  -max 12  -network_latency_included  [get_ports ScanEnable]
set_input_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports ScanEnable]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[7]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[7]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[6]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[6]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[5]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[5]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[4]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[4]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[3]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[3]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[2]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[2]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[1]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[1]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports {DB[0]}]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports {DB[0]}]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports nVaneCS]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nVaneCS]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports SPICLK]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports SPICLK]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports RnW]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports RnW]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports nBaroCS]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports nBaroCS]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports En]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports En]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports RS]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports RS]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports MOSI]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports MOSI]
set_output_delay -clock master_clock  -max 8  -network_latency_included  [get_ports SDO]
set_output_delay -clock master_clock  -min 0.5  -network_latency_included  [get_ports SDO]
