///////////////////////////////////////////////////////////////////////
//
// MS5803-02BA Sensor module
//
//    this model is dummy version ready for customisation
//
//   Ports:
//	SDO	(Output)
// 		Serial Data from Slave to Master
//
//	SDI	(Input)
//		Serial Data from Master to Slave
//
//	SCLK	(Input)
//		SPI Clock pin
//
//	CSB	(Input - Active Low)
//      	Chip Select
//
//
///////////////////////////////////////////////////////////////////////

module pressure_sensor (
  output SDO,
  input SDI,
  input SCLK,
  input CSB
  );

timeunit 1ns;
timeprecision 100ps;

// This model represents an MS5803-02BA sensor module which can
// be used for both pressure and temerature measurement
//
// the model here includes timing checks on the inputs but
// will never return any useful data (note that the model does
// support a tri-state output to ensure that the operation of the
// SPI bus is not hampered by this non-functioning SPI slave)
//
// the variables "pressure" and "temperature" represent values
// for environmental parameters
//
// the values can be set from the testbench and, in a more a more
// advanced model of the sensor, the values would be consulted
// and would be suitably encoded for return to the user

real pressure; // pressure in millibars
real temperature; // temperature in Celcius

  //
  // serial bus timing data loosely based on the MS5803-02BA
  // datasheet
  //
  // the values specified here should be both conservative and
  // easy to achieve in practice
  //
  specify
    specparam tcy   = 60ns;     // clock cycle SPI clock
    // this value is intenionally longer than implied
    // by the 20 MHz maximum clock frequency quoted
    // on the datasheet

    specparam tclk1  = 25ns;    // SPI clock pulse width HIGH
    specparam tclk0  = 25ns;    // SPI clock pulse width LOW

    specparam tsucs = 25ns;    // chip select setup time
    specparam thcs  = 25ns;    // chip select hold time

    specparam tsud  = 25ns;    // SDI data setup time
    specparam thd   = 25ns;    // SDI data hold time


    // Serial clock timings
    $period(posedge SCLK, tcy);
    $width(posedge SCLK, tclk1);
    $width(negedge SCLK, tclk0);

    // Chip Select timings relative to the clock
    $setup(CSB, posedge SCLK, tsucs);
    $hold(CSB, posedge SCLK, thcs);

    // Serial Data timings relative to the clock
    $setup(SDI, posedge SCLK, tsud);
    $hold(SDI, posedge SCLK, thd);
  endspecify



endmodule
