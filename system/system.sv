///////////////////////////////////////////////////////////////////////
//
// system module - 2025/2026
//
//    this is the top-level module which describes the complete system
//
///////////////////////////////////////////////////////////////////////

`include "options.sv"

`ifdef clock_period
  // already defined - do nothing
`else
  // this is a default frequency of 32.768kHz
  `define clock_period 30517.6ns
  // note that the calculation of the period is not perfectly accurate
  //  - the inaccuracy here will most likely be less than that specified for the clock source itself
`endif

`ifdef num_modes
  // already defined - do nothing
`else
  // default specification has 5 modes
  `define num_modes 5
`endif

`define STRINGIFY(x) `"x`"

typedef enum logic [3:0] { N=0,  NNE=1, NE=2,  ENE=3,  E=4,  ESE=5,  SE=6,  SSE=7,
                           S=8,  SSW=9, SW=10, WSW=11, W=12, WNW=13, NW=14, NNW=15 } compass_t;


module system;

timeunit 1ns;
// this precision allows for clock_period/2 and clock_period/4
timeprecision 10ps;

wire SPICLK, MOSI, MISO, nVaneCS, nBaroCS;

wire RS, RnW, En;
wire [7:0] DB;

wire SCLK, SDIN, DnC, nSCE;

logic Mode, Start, Rain, Wind, Demo;
wire nMode, nStart, nRain, nWind;
event press_mode_button, press_trip_button, trigger_rain_sensor, trigger_wind_sensor;

logic Button3;
wire nButton3;
event press_third_button;

wire SDO;
logic Clock, nReset, Test, SDI, ScanEnable;

int mode_index;


weather STATION (

    .RS, .RnW, .En,
    .DB,

    `ifdef include_pixel_lcd
      .SCLK, .SDIN, .DnC, .nSCE,
    `endif

    .SPICLK, .MISO, .nVaneCS,

    `ifdef include_pressure_sensor
      .MOSI, .nBaroCS,
    `endif

    .nMode, .nStart,
    .nRain, .nWind,

    `ifdef third_button
      .`third_button(nButton3),
    `endif
    
    .Demo,

    `ifndef no_scan_signals
      .SDO, .Test, .SDI,
      `ifdef scan_enable
        .ScanEnable,
      `endif
    `endif

    .Clock, .nReset
  );

`ifdef sdf_file
  initial
    $sdf_annotate( `STRINGIFY(`sdf_file), STATION );
`endif

// the weather station is supported by simulation models for the LCD and OLED displays and for the sensor

lcd_char_display CHAR_LCD ( .RS, .RnW, .E(En), .DB );

`ifdef include_pixel_lcd
  lcd_pixel_display PIXEL_LCD ( .SCLK, .SDIN, .DnC, .nSCE, .nRES(nReset) );
`endif

wind_vane_adc VANE ( .SCLK(SPICLK), .SDATA(MISO), .nCS(nVaneCS) );

pressure_sensor SENSOR ( .SCLK(SPICLK), .SDI(MOSI), .SDO(MISO), .CSB(nBaroCS) );

// this pullup ensures that the pressure/temperature sensor doesn't drive the
// MISO signal if the weather station chip doesn't drive nBaroCS

pullup( weak0, weak1 )(nBaroCS);

// these inputs all pull down when active and are high impedance at other times

assign nMode    = ( Mode )    ? '0 : 'z;
assign nStart    = ( Start )    ? '0 : 'z;
assign nButton3 = ( Button3 ) ? '0 : 'z;
assign nRain    = ( Rain )    ? '0 : 'z;
assign nWind   = ( Wind )   ? '0 : 'z;

`ifdef external_pullup
  pullup( weak0, weak1 )(nMode);
  pullup( weak0, weak1 )(nStart);
  pullup( weak0, weak1 )(nButton3);
  pullup( weak0, weak1 )(nRain);
  pullup( weak0, weak1 )(nWind);
`endif

`ifdef demo_mode
  assign Demo = 1;
`else
  assign Demo = 0;
`endif

// display information about the design

initial
  begin
    $display( "COMPILATION OK" );
    $display( "CLOCK PERIOD IS ", `STRINGIFY(`clock_period) );
    `ifdef include_pixel_lcd
      $display( "DISPLAY IS CHARACTER LCD + PIXEL LCD" );
    `else
      $display( "DISPLAY IS CHARACTER LCD ONLY" );
    `endif
    `ifdef include_pressure_sensor
      $display( "MODEL SUPPORTS PRESSURE/TEMPERATURE SENSOR" );
    `endif
    $display( "This Weather Station supports ", `STRINGIFY(`num_modes ), " modes:" );
    `ifdef Mode0
      $display( "  Mode 0: ", `STRINGIFY(`Mode0) );
    `endif
    `ifdef Mode1
      $display( "  Mode 1: ", `STRINGIFY(`Mode1) );
    `endif
    `ifdef Mode2
      $display( "  Mode 2: ", `STRINGIFY(`Mode2) );
    `endif
    `ifdef Mode3
      $display( "  Mode 3: ", `STRINGIFY(`Mode3) );
    `endif
    `ifdef Mode4
      $display( "  Mode 4: ", `STRINGIFY(`Mode4) );
    `endif
    `ifdef Mode5
      $display( "  Mode 5: ", `STRINGIFY(`Mode5) );
    `endif
    `ifdef Mode6
      $display( "  Mode 6: ", `STRINGIFY(`Mode6) );
    `endif
    `ifdef Mode7
      $display( "  Mode 7: ", `STRINGIFY(`Mode7) );
    `endif
    `ifdef Mode8
      $display( "  Mode 8: ", `STRINGIFY(`Mode8) );
    `endif
    `ifdef Mode9
      $display( "  Mode 9: ", `STRINGIFY(`Mode9) );
    `endif
    $display( " (the weather station will enter mode 0 on reset)");
  end


// define tasks to help with a simple stimulus

task start_up_delay( );
  begin
    `ifdef start_up_time
      #`start_up_time ;
    `endif
  end

endtask

always @(trigger_rain_sensor)
  begin

    `ifdef sanitise_input
      // delay until 1/4 of a clock period after a clock edge
      // - this should ensure that the clock delay to the
      //   synchronisation D-types doesn't cause setup/hold violations
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Rain = 1;
    
    #2ms

    `ifdef sanitise_input
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Rain = 0;
    
  end

always @(trigger_wind_sensor)
  begin

    `ifdef sanitise_input
      // delay until 1/4 of a clock period after a clock edge
      // - this should ensure that the clock delay to the
      //   synchronisation D-types doesn't cause setup/hold violations
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Wind = 1;
    
    #4ms

    `ifdef sanitise_input
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Wind = 0;
    
  end

always @(press_mode_button)
  begin

    `ifdef sanitise_input
      // delay until 1/4 of a clock period after a clock edge
      // - this should ensure that the clock delay to the
      //   synchronisation D-types doesn't cause setup/hold violations
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Mode = 1;
    
    #0.1s

    `ifdef sanitise_input
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Mode = 0;
    mode_index = ( mode_index + 1 ) % `num_modes;
    
  end

always @(press_trip_button)
  begin

    `ifdef sanitise_input
      // delay until 1/4 of a clock period after a clock edge
      // - this should ensure that the clock delay to the
      //   synchronisation D-types doesn't cause setup/hold violations
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Start = 1;
    
    #0.1s

    `ifdef sanitise_input
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Start = 0;
    
  end

always @(press_third_button)
  begin

    $display( "Press Third button" );

    `ifdef sanitise_input
      // delay until 1/4 of a clock period after a clock edge
      // - this should ensure that the clock delay to the
      //   synchronisation D-types doesn't cause setup/hold violations
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Button3 = 1;
    
    #0.1s

    `ifdef sanitise_input
      @(posedge Clock );
      #(`clock_period / 4)
    `endif

    Button3 = 0;
    
  end

`ifdef stimulus

  `include `STRINGIFY(`stimulus)

`else

  initial
    begin
      Test = 0;
      SDI = 0;
      ScanEnable = 0;
      nReset = 0;
      #(`clock_period / 4) nReset = 1;
    end

  initial
    begin
      Clock = 0;
      #`clock_period
      forever
        begin
          Clock = 1;
          #(`clock_period / 2) Clock = 0;
          #(`clock_period / 2) Clock = 0;
        end
    end


  // Button stimulus
  //
  //  This default stimulus represents a change in
  //  mode once per second 

  initial
    begin
      Mode = 0;
      Start = 0;
      mode_index = 0;
      start_up_delay();
      `ifdef basic_mode_change
        forever
          #1s -> press_mode_button;
      `endif
    end
  
  // Weather stimulus
  //
  //  This default stimulus represents initial inactivity
  //  followed by strong wind and heavy rain at a constant rate 

  initial
    begin
      SENSOR.pressure=1013.25;
      SENSOR.temperature=15.0;
      VANE.WindDirection=WSW;
      Wind = 0;
      start_up_delay();
      #0.55s
      forever
        #100ms -> trigger_wind_sensor;
    end
  
  initial
    begin
      Rain = 0;
      start_up_delay();
      #1s
      forever
        #2s -> trigger_rain_sensor;
    end
  
  

`endif

`ifdef special_monitor

  `include "monitor.sv"

`endif

`ifdef sim_time

  initial
    begin
      #`sim_time
      $stop;
      $finish;
    end

`endif

endmodule
