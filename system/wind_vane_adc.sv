///////////////////////////////////////////////////////////////////////
//
// Wind Vane ADC module
//
//    this model returns a contant 12-bit ADC value, 3,143
//    (which represents an analogue input of around 2.53v)
//
//    a more advanced version would return a value based on the
//    value of the WindDirection variable
//
//    for the purposes of calculating the correct ADC value, you
//    should assume that the supply voltage for the wind vane and
//    for the ADC is 3.3v and that the reference resistor has a value
//    of 10k
//
//    this module might also be the location of assert statements
//    to help with debugging
//
//   Ports:
//	SDATA	(Output)
// 		Serial Data from Slave to Master
//
//	SCLK	(Input)
//		SPI Clock pin
//
//	nCS	(Input - Active Low)
//      	Chip Select
//
//
///////////////////////////////////////////////////////////////////////

module wind_vane_adc (
  output SDATA,
  input SCLK,
  input nCS
  );

timeunit 1ns;
timeprecision 100ps;

// the "WindDirection" variable represent an environmental parameter
//
// the value can be set from the testbench and, in a more a more
// advanced model of the ADC, the WindDirection value would be used
// to calculate a value to be returned during the SPI read operation

compass_t WindDirection;

  //
  // serial bus timing data loosely based on the AD7466
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


    // Serial clock timings
    $period(posedge SCLK, tcy);
    $width(posedge SCLK, tclk1);
    $width(negedge SCLK, tclk0);

    // Chip Select timings relative to the clock
    $setup(nCS, posedge SCLK, tsucs);
    $hold(nCS, posedge SCLK, thcs);
  endspecify


  logic data_out = 1;
  assign SDATA = (!nCS) ? data_out : 'z;

  always @(negedge nCS)
      // note that nCS should remain active for the whole
      // of this begin-end block but this very simple
      // code doesn't check nCS again
      begin
        data_out = 0;
	repeat ( 3) @(negedge SCLK) data_out = 0;

	repeat ( 2) @(negedge SCLK) data_out = 1;
	repeat ( 3) @(negedge SCLK) data_out = 0;
	repeat ( 1) @(negedge SCLK) data_out = 1;
	repeat ( 3) @(negedge SCLK) data_out = 0;
	repeat ( 3) @(negedge SCLK) data_out = 1;

        @(negedge SCLK);
        data_out = 'z;
      end

endmodule
