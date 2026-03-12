///////////////////////////////////////////////////////////////////////
//
// lcd_char_display module - 2025/2026
//
//    this version of the module is empty
//
//    a more advanced version might attempt to decode the inputs
//    to produce a value representing the number on the display
//
//    this module might also be the location of assert statements
//    to help with debugging
//
// Display module information:
//   Type: NHD-0108BZ-RN-YBW 1 Line x 8 Characters LCD Module
//   Driver chip: ST7066U Controller
//
//   Ports:
//	RS	(Input)
//		Register Select
//
//	RnW	(Input)
//		Read/Write
//
//	E	(Input)
//		Operation Enable
//
//	DB	(Inout)
//      	8-bit Data Bus
//
//
///////////////////////////////////////////////////////////////////////

`include "options.sv"

module lcd_char_display (
  input RS,
  input RnW,
  input E,
  inout [7:0] DB
  );

timeunit 1ns;
timeprecision 100ps;

  //
  // timings taken from the NHD-0108BZ-RN-YBW datasheet
  //

  logic Write;

  initial
    begin
      Write = 0;
      #(`clock_period / 4) assign Write = !RnW;
    end

  specify
    specparam tC=1200ns;     // Enable Cycle Time
    specparam tPW=140ns;     // Enable Pulse Width
    specparam tAS=0ns;       // Address Setup Time
    specparam tAH=10ns;      // Address Hold Time
    specparam tDSW=40ns;     // Data Setup Time
    specparam tH=10ns;       // Data Hold Time
    
    $period(posedge E, tC);
    $width(posedge E, tPW);
    
    $nochange(posedge E, RS, -tAS, tAH);
    $nochange(posedge E, RnW, -tAS, tAH);

    $setuphold(negedge E &&& Write, DB, tDSW, tH);
  endspecify

endmodule

