///////////////////////////////////////////////////////////////////////
//
// weather module - 2025/2026
//
//    this is simply a shell representing the pad ring
//    which instances weather_core
//
//    this version makes significant use of ifdef macros in order
//    to support different weather_core designs
//    *** no submitted weather module should use these macros since
//    each submitted weather module will be designed to pair with a
//    specific weather_core module ****
//
///////////////////////////////////////////////////////////////////////

`include "options.sv"

module weather(

  output RS, RnW, En,
  inout [7:0] DB,

  `ifdef include_pixel_lcd
    output SCLK, SDIN, DnC, nSCE,
  `endif

  output SPICLK, nVaneCS,
  input MISO,

  `ifdef include_pressure_sensor
    output MOSI, nBaroCS,
  `endif

  input tri1 nMode, nStart,
  input tri1 nRain, nWind,

  input Demo,

  `ifndef no_scan_signals
    output SDO, input Test, SDI,
    `ifdef scan_enable
      ScanEnable,
    `endif
  `endif

  input Clock, nReset

  );

timeunit 1ns;
timeprecision 100ps;

wire [7:0] DB_In, DB_Out;
wire DB_nEnable;

//
// simulation of bidirectional pads
//

assign DB = ( ! DB_nEnable ) ? DB_Out : 'z;
assign DB_In = DB;



//
// optionally synchronise the asynchronous reset in this wrapper
//

`ifdef synchronise_reset_within_wrapper

logic sync_nReset_1,sync_nReset_2;

always @( posedge Clock, negedge nReset )
  if ( ! nReset )
    begin
      sync_nReset_1 <= '0;
      sync_nReset_2 <= '0;
    end
  else
    begin
      sync_nReset_1 <= '1;
      sync_nReset_2 <= sync_nReset_1;
    end

  assign core_nReset = sync_nReset_2;

`else

  assign core_nReset = nReset;

`endif


//
// optionally synchronise the asynchronous inputs in this wrapper
//

`ifdef synchronise_inputs_within_wrapper

logic sync_nMode_1, sync_nMode_2;
logic sync_nStart_1, sync_nStart_2;
logic sync_nRain_1, sync_nRain_2;
logic sync_nWind_1, sync_nWind_2;

always @( posedge Clock, negedge core_nReset )
  if ( ! core_nReset )
    begin
      sync_nMode_1   <= '1;
      sync_nMode_2   <= '1;

      sync_nStart_1   <= '1;
      sync_nStart_2   <= '1;

      sync_nRain_1   <= '1;
      sync_nRain_2   <= '1;

      sync_nWind_1   <= '1;
      sync_nWind_2   <= '1;
    end
  else
    begin
      sync_nMode_1   <= nMode;
      sync_nMode_2   <= sync_nMode_1;

      sync_nStart_1   <= nStart;
      sync_nStart_2   <= sync_nStart_1;

      sync_nRain_1   <= nRain;
      sync_nRain_2   <= sync_nRain_1;

      sync_nWind_1   <= nWind;
      sync_nWind_2   <= sync_nWind_1;
    end

  assign core_nMode   = sync_nMode_2;
  assign core_nStart   = sync_nStart_2;
  assign core_nRain   = sync_nRain_2;
  assign core_nWind   = sync_nWind_2;

`else

  assign core_nMode   = nMode;
  assign core_nStart   = nStart;
  assign core_nRain   = nRain;
  assign core_nWind   = nWind;

`endif



weather_core CORE ( 

    .RS, .RnW, .En,
    .DB_In, .DB_Out, .DB_nEnable,

    `ifdef include_pixel_lcd
      .SCLK, .SDIN, .DnC, .nSCE,
    `endif

    .SPICLK, .MISO, .nVaneCS,

    `ifdef include_pressure_sensor
      .MOSI, .nBaroCS,
    `endif

    .nMode(core_nMode), .nStart(core_nStart),
    .nRain(core_nRain), .nWind(core_nWind),

    .Demo,

    `ifndef no_scan_signals
      .SDO, .Test, .SDI,
      `ifdef scan_enable
        .ScanEnable,
      `endif
    `endif

    .Clock, .nReset(core_nReset)
  );

endmodule
