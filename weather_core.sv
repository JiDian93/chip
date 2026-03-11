///////////////////////////////////////////////////////////////////////
//
// weather_core module
//
//    this is the behavioural model of the weather station without pads
//
///////////////////////////////////////////////////////////////////////

`include "options.sv"

module weather_core(

  output logic RS,
  output logic RnW,
  output logic En,

  input [7:0] DB_In,
  output logic [7:0] DB_Out,
  output logic DB_nEnable,

  input nMode, nStart,
  input nRain, nWind,

  output logic SPICLK, nVaneCS,
  input MISO,

  input Clock, nReset,
  input Demo

  );

timeunit 1ns;
timeprecision 100ps;

// Total rainfall (count of nRain pulses) – internal to core
logic [15:0] total_rain_pulses;

// 4 BCD digits in ddd.d mm format: 3 integer + 1 fractional – internal to core
logic [3:0] rain_hundreds_bcd;
logic [3:0] rain_tens_bcd;
logic [3:0] rain_units_bcd;
logic [3:0] rain_tenths_bcd;

// Rain submodule: total rainfall and ddd.d mm BCD digits
rain_gauge RAIN(
  .Clock,
  .nReset,
  .nStart,
  .nRain,
  .total_rain_pulses,
  .rain_hundreds_bcd,
  .rain_tens_bcd,
  .rain_units_bcd,
  .rain_tenths_bcd
);

//==========================================================
// LCD display: 8x1 character LCD, format ddd.d mm
//==========================================================

localparam int LCD_COLS = 8;

// Slot type and data
//  slot_type: 00 = BCD digit, 01 = ASCII
logic [1:0] lcd_slot_type [LCD_COLS];
logic [7:0] lcd_slot_data [LCD_COLS];

// Formatter -> HD44780 LCD ASCII stream
logic [7:0] lcd_ascii;
logic       lcd_ascii_valid;

// LCD internal signals
logic [7:0] lcd_data;
logic       lcd_rs;
logic       lcd_rw;
logic       lcd_en;
logic       lcd_init_done;

// Slots -> ASCII stream
lcd_formatter_8x1 #(
  .CLK_HZ(32768),
  .COLS(LCD_COLS),
  .CHAR_PERIOD_MS(2)
) u_lcd_formatter_8x1 (
  .clk        (Clock),
  .rst_n      (nReset),
  .lcd_ready  (lcd_init_done),
  .slot_type  (lcd_slot_type),
  .slot_data  (lcd_slot_data),
  .ascii_out  (lcd_ascii),
  .ascii_valid(lcd_ascii_valid)
);

// ASCII stream -> HD44780 LCD timing
lcd #(
  .CLK_HZ(32768),
  .COLS  (LCD_COLS)
) u_lcd (
  .clk          (Clock),
  .rst_n        (nReset),
  .ascii_in     (lcd_ascii),
  .ascii_valid  (lcd_ascii_valid),
  .lcd_data     (lcd_data),
  .lcd_rs       (lcd_rs),
  .lcd_rw       (lcd_rw),
  .lcd_e        (lcd_en),
  .lcd_init_done(lcd_init_done)
);

// Wind direction: SPI to vane ADC (AD7466) + nearest-neighbour decode + 3 LCD chars
logic [7:0] wind_char0, wind_char1, wind_char2;

wind_direction VANE(
  .Clock,
  .nReset,
  .MISO,
  .SPICLK,
  .nVaneCS,
  .char0 (wind_char0),
  .char1 (wind_char1),
  .char2 (wind_char2)
);

//==========================================================
// Mode: sync nMode, edge detect, mode_reg (default 2 = WindDirection)
//==========================================================
logic sync_nMode_1, sync_nMode_2;
logic nMode_fall;
logic [1:0] mode_reg;

always_ff @(posedge Clock or negedge nReset) begin
  if (!nReset) begin
    sync_nMode_1 <= 1'b1;
    sync_nMode_2 <= 1'b1;
    mode_reg     <= 2'd2;   // Default Mode 2 = WindDirection
  end else begin
    sync_nMode_1 <= nMode;
    sync_nMode_2 <= sync_nMode_1;
    if (nMode_fall)
      mode_reg   <= (mode_reg + 2'd1);  // 0,1,2,3 wrap
  end
end
assign nMode_fall = sync_nMode_2 && !sync_nMode_1;

//==========================================================
// LCD slot mux: mode_reg==2 -> wind (3 chars + 5 spaces); else rain
//==========================================================
logic [1:0] rain_slot_type [LCD_COLS];
logic [7:0] rain_slot_data [LCD_COLS];
logic [1:0] wind_slot_type [LCD_COLS];
logic [7:0] wind_slot_data [LCD_COLS];

always_comb begin
  for (int i = 0; i < LCD_COLS; i++) begin
    wind_slot_type[i] = 2'b01;
    wind_slot_data[i] = 8'h20;
  end
  // Right-align direction in last 3 slots (5,6,7): last position never empty
  if (wind_char2 != 8'h20) begin
    wind_slot_data[5] = wind_char0; wind_slot_data[6] = wind_char1; wind_slot_data[7] = wind_char2;  // 3 chars
  end else if (wind_char1 != 8'h20) begin
    wind_slot_data[5] = 8'h20;      wind_slot_data[6] = wind_char0; wind_slot_data[7] = wind_char1;  // 2 chars
  end else begin
    wind_slot_data[5] = 8'h20;      wind_slot_data[6] = 8'h20;      wind_slot_data[7] = wind_char0;  // 1 char
  end
end

// Rain slots (existing logic, now as separate arrays)
always_comb begin
  for (int i = 0; i < LCD_COLS; i++) begin
    rain_slot_type[i] = 2'b01;
    rain_slot_data[i] = 8'h20;
  end
  if (rain_hundreds_bcd == 4'd0) begin
    rain_slot_type[0] = 2'b01; rain_slot_data[0] = 8'h20;
  end else begin
    rain_slot_type[0] = 2'b00; rain_slot_data[0] = {4'b0000, rain_hundreds_bcd};
  end
  if (rain_hundreds_bcd == 4'd0 && rain_tens_bcd == 4'd0) begin
    rain_slot_type[1] = 2'b01; rain_slot_data[1] = 8'h20;
  end else begin
    rain_slot_type[1] = 2'b00; rain_slot_data[1] = {4'b0000, rain_tens_bcd};
  end
  rain_slot_type[2] = 2'b00; rain_slot_data[2] = {4'b0000, rain_units_bcd};
  rain_slot_type[3] = 2'b01; rain_slot_data[3] = 8'h2E;
  rain_slot_type[4] = 2'b00; rain_slot_data[4] = {4'b0000, rain_tenths_bcd};
  rain_slot_type[5] = 2'b01; rain_slot_data[5] = 8'h20;
  rain_slot_type[6] = 2'b01; rain_slot_data[6] = "m";
  rain_slot_type[7] = 2'b01; rain_slot_data[7] = "m";
end

// Select slots by mode
always_comb begin
  if (mode_reg == 2'd2)
    for (int i = 0; i < LCD_COLS; i++) begin
      lcd_slot_type[i] = wind_slot_type[i];
      lcd_slot_data[i] = wind_slot_data[i];
    end
  else
    for (int i = 0; i < LCD_COLS; i++) begin
      lcd_slot_type[i] = rain_slot_type[i];
      lcd_slot_data[i] = rain_slot_data[i];
    end
end

// this module makes no attempt to communicate with the LCD

assign RS  = lcd_rs;
assign RnW = lcd_rw;      // This design is write-only (lcd_rw is always 0)
assign En  = lcd_en;

assign DB_Out     = lcd_data;
assign DB_nEnable = 1'b0; // Always drive data bus




endmodule

