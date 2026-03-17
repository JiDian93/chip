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

  `ifdef include_pressure_sensor
  output logic MOSI, nBaroCS,
  `endif

  input Clock, nReset,
  input Demo

  );

timeunit 1ns;
timeprecision 100ps;

//==========================================================
// Clock divider and main FSM control
//==========================================================

logic tick_1kHz;
logic tick_1Hz;

logic [2:0] display_mode;
logic       clear_rain_pulse;
logic       clear_time_pulse;
logic       in_calibration;
logic       is_rain_calib;
logic [1:0] calib_digit_index;
logic       calib_increment_pulse;
logic       in_time_setting;
logic [1:0] time_set_field;
logic       time_increment_pulse;
logic       time_zero_seconds_pulse;

clock_divider u_clock_divider (
  .Clock    (Clock),
  .nReset   (nReset),
  .Demo     (Demo),
  .tick_1kHz(tick_1kHz),
  .tick_1Hz (tick_1Hz)
);

main_fsm u_main_fsm (
  .Clock                (Clock),
  .nReset               (nReset),
  .tick_1kHz            (tick_1kHz),
  .nMode                (nMode),
  .nStart               (nStart),
  .display_mode         (display_mode),
  .clear_rain_pulse     (clear_rain_pulse),
  .clear_time_pulse     (clear_time_pulse),
  .in_calibration       (in_calibration),
  .is_rain_calib        (is_rain_calib),
  .calib_digit_index    (calib_digit_index),
  .calib_increment_pulse(calib_increment_pulse),
  .in_time_setting      (in_time_setting),
  .time_set_field       (time_set_field),
  .time_increment_pulse (time_increment_pulse),
  .time_zero_seconds_pulse(time_zero_seconds_pulse)
);

// Total rainfall (count of nRain pulses) - internal to core
logic [15:0] total_rain_pulses;

// 4 BCD digits in ddd.d mm format: 3 integer + 1 fractional - internal to core
logic [3:0] rain_hundreds_bcd;
logic [3:0] rain_tens_bcd;
logic [3:0] rain_units_bcd;
logic [3:0] rain_tenths_bcd;
logic [3:0] rain_calib_thousands_bcd;
logic [3:0] rain_calib_hundreds_bcd;
logic [3:0] rain_calib_tens_bcd;
logic [3:0] rain_calib_units_bcd;

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
  .rain_tenths_bcd,
  .rain_calib_thousands_bcd,
  .rain_calib_hundreds_bcd,
  .rain_calib_tens_bcd,
  .rain_calib_units_bcd,
  .in_calibration       (in_calibration),
  .is_rain_calib        (is_rain_calib),
  .calib_digit_index    (calib_digit_index),
  .calib_increment_pulse(calib_increment_pulse)
);

//==========================================================
// LCD display: 8x1 character LCD, slot definitions
//==========================================================

localparam int LCD_COLS = 8;

// Per-mode slot arrays
logic [1:0] rain_slot_type    [LCD_COLS];
logic [7:0] rain_slot_data    [LCD_COLS];
logic [1:0] windspd_slot_type [LCD_COLS];
logic [7:0] windspd_slot_data [LCD_COLS];
logic [1:0] winddir_slot_type [LCD_COLS];
logic [7:0] winddir_slot_data [LCD_COLS];
logic [1:0] elapsed_slot_type [LCD_COLS];
logic [7:0] elapsed_slot_data [LCD_COLS];
logic [1:0] time_slot_type    [LCD_COLS];
logic [7:0] time_slot_data    [LCD_COLS];

// Slot type and data fed into formatter (00 = BCD digit, 01 = ASCII)
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
logic       nVaneCS_raw;

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
logic [1:0] wind_n_chars;  // number of non-space wind direction characters (0..3)
logic       SPICLK_vane;
logic       pause_wind_spi;
logic       SPICLK_vane_gated;
logic       nVaneCS_raw_gated;
logic       nVaneCS_mux;

wind_direction VANE(
  .Clock,
  .nReset,
  .pause_spi (pause_wind_spi),
  .MISO,
  .SPICLK   (SPICLK_vane),
  .nVaneCS   (nVaneCS_raw),
  .char0 (wind_char0),
  .char1 (wind_char1),
  .char2 (wind_char2)
);

`ifdef include_pressure_sensor
// Pressure/temperature: MS5803-02BA SPI, shared SPICLK/MISO, adds MOSI and nBaroCS
logic        SPICLK_baro;
logic [1:0]  pressure_slot_type [LCD_COLS];
logic [7:0]  pressure_slot_data [LCD_COLS];
logic [1:0]  temp_slot_type    [LCD_COLS];
logic [7:0]  temp_slot_data    [LCD_COLS];
logic        nBaroCS_clk_sel;
logic        baro_quiet;
logic        mode2_winddir_active;

pressure_temperature_core BARO(
  .Clock,
  .nReset,
  .baro_pause (mode2_winddir_active),
  .MISO,
  .MOSI,
  .SPICLK_out (SPICLK_baro),
  .nBaroCS,
  .baro_quiet,
  .pressure_slot_type,
  .pressure_slot_data,
  .temp_slot_type,
  .temp_slot_data
);

// Delay clock-source switching by one core clock so CS transition and
// shared-SPI source switching are not evaluated at the same timestamp.
always_ff @(posedge Clock or negedge nReset) begin
  if (!nReset) nBaroCS_clk_sel <= 1'b1;
  else         nBaroCS_clk_sel <= nBaroCS;
end

// In wind-direction mode, prioritize vane SPI so each setpoint is observable.
// BARO is paused in this mode, so the shared bus is safe for vane ownership.
assign mode2_winddir_active = (display_mode == 3'd2);
assign pause_wind_spi = (!mode2_winddir_active) && baro_quiet;
assign SPICLK_vane_gated = pause_wind_spi ? 1'b1 : SPICLK_vane;
assign nVaneCS_raw_gated = pause_wind_spi ? 1'b1 : nVaneCS_raw;
assign SPICLK = (!nBaroCS_clk_sel) ? SPICLK_baro : SPICLK_vane_gated;
assign nVaneCS_mux = nBaroCS ? nVaneCS_raw_gated : 1'b1;
`else
assign SPICLK = SPICLK_vane;
assign nVaneCS_mux = nVaneCS_raw;
`endif

// Keep vane CS transitions away from SCLK edges for external timing checks.
assign #(123ns) nVaneCS = nVaneCS_mux;

//==========================================================
// Instantaneous wind speed (anemometer)
//==========================================================

logic [15:0] wind_tenths;

anemometer #(
  .CLK_HZ(32768),
  .COLS  (LCD_COLS)
) U_ANEMO (
  .clk                  (Clock),
  .rst_n                (nReset),
  .anemo_sw             (nWind),
  .slot_type            (windspd_slot_type),
  .slot_data            (windspd_slot_data),
  .wind_tenths          (wind_tenths),
  .in_calibration       (in_calibration),
  .is_rain_calib        (is_rain_calib),
  .calib_digit_index    (calib_digit_index),
  .calib_increment_pulse(calib_increment_pulse)
);

//==========================================================
// Elapsed time and time-of-day counters
//==========================================================

logic [3:0] et_hour_tens, et_hour_units;
logic [3:0] et_min_tens,  et_min_units;
logic [3:0] et_sec_tens, et_sec_units;

elapsed_time_counter U_ELAPSED (
  .Clock          (Clock),
  .nReset         (nReset),
  .tick_1Hz       (tick_1Hz),
  .start_adjust_hit(clear_time_pulse),
  .hour_tens      (et_hour_tens),
  .hour_units     (et_hour_units),
  .min_tens       (et_min_tens),
  .min_units      (et_min_units),
  .sec_tens       (et_sec_tens),
  .sec_units      (et_sec_units)
);

logic [3:0] tod_hour_tens, tod_hour_units;
logic [3:0] tod_min_tens,  tod_min_units;
logic [3:0] tod_sec_tens,  tod_sec_units;
logic [3:0] tod_sixtieths_tens, tod_sixtieths_units;

time_counters U_TIME (
  .Clock                (Clock),
  .nReset               (nReset),
  .tick_1Hz             (tick_1Hz),
  .nClear_time          (1'b1),
  .Demo                 (Demo),
  .time_set_field       (time_set_field),
  .time_increment_pulse (time_increment_pulse),
  .time_zero_seconds_pulse(time_zero_seconds_pulse),
  .hour_tens            (tod_hour_tens),
  .hour_units           (tod_hour_units),
  .min_tens             (tod_min_tens),
  .min_units            (tod_min_units),
  .sec_tens             (tod_sec_tens),
  .sec_units            (tod_sec_units),
  .sixtieths_tens       (tod_sixtieths_tens),
  .sixtieths_units      (tod_sixtieths_units)
);

//==========================================================
// Rain slots: normal (ddd.d mm) or calib mode ( ddd.d  = multiplier e.g.  1.035 )
//==========================================================

always_comb begin
  for (int i = 0; i < LCD_COLS; i++) begin
    rain_slot_type[i] = 2'b01;
    rain_slot_data[i] = 8'h20;
  end
  if (in_calibration && is_rain_calib) begin
    // Show calibration multiplier as " ddd.d " (e.g. " 1.035 ")
    rain_slot_type[0] = 2'b01; rain_slot_data[0] = 8'h20;
    rain_slot_type[1] = 2'b00; rain_slot_data[1] = {4'b0000, rain_calib_thousands_bcd};
    rain_slot_type[2] = 2'b01; rain_slot_data[2] = 8'h2E;
    rain_slot_type[3] = 2'b00; rain_slot_data[3] = {4'b0000, rain_calib_hundreds_bcd};
    rain_slot_type[4] = 2'b00; rain_slot_data[4] = {4'b0000, rain_calib_tens_bcd};
    rain_slot_type[5] = 2'b00; rain_slot_data[5] = {4'b0000, rain_calib_units_bcd};
    rain_slot_type[6] = 2'b01; rain_slot_data[6] = 8'h20;
    rain_slot_type[7] = 2'b01; rain_slot_data[7] = 8'h20;
  end else begin
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
end

//==========================================================
// Wind direction slots (right-aligned in last columns)
//  - If 1 non-space letter  -> at last column
//  - If 2 non-space letters -> at last 2 columns
//  - If 3 non-space letters -> at last 3 columns
//==========================================================

always_comb begin
  // Default all 8 columns to space ASCII
  for (int i = 0; i < LCD_COLS; i++) begin
    winddir_slot_type[i] = 2'b01;   // direct ASCII
    winddir_slot_data[i] = 8'h20;   // space
  end

  // Count how many non-space chars we have
  wind_n_chars = 2'd0;
  if (wind_char0 != 8'h20) wind_n_chars++;
  if (wind_char1 != 8'h20) wind_n_chars++;
  if (wind_char2 != 8'h20) wind_n_chars++;

  case (wind_n_chars)
    0: begin
      // keep all spaces
    end

    1: begin
      // Exactly one letter: put that single letter in the last column
      if (wind_char0 != 8'h20 &&
          wind_char1 == 8'h20 &&
          wind_char2 == 8'h20) begin
        winddir_slot_data[7] = wind_char0;
      end else if (wind_char1 != 8'h20 &&
                   wind_char0 == 8'h20 &&
                   wind_char2 == 8'h20) begin
        winddir_slot_data[7] = wind_char1;
      end else begin
        winddir_slot_data[7] = wind_char2;
      end
    end

    2: begin
      // Two letters: right-align into last two columns
      if (wind_char0 == 8'h20) begin
        // chars are [1],[2]
        winddir_slot_data[6] = wind_char1;
        winddir_slot_data[7] = wind_char2;
      end else if (wind_char1 == 8'h20) begin
        // chars are [0],[2]
        winddir_slot_data[6] = wind_char0;
        winddir_slot_data[7] = wind_char2;
      end else begin
        // chars are [0],[1]
        winddir_slot_data[6] = wind_char0;
        winddir_slot_data[7] = wind_char1;
      end
    end

    default: begin
      // 3 or more (we only have 3), right-align all 3
      winddir_slot_data[5] = wind_char0;
      winddir_slot_data[6] = wind_char1;
      winddir_slot_data[7] = wind_char2;
    end
  endcase
end

//==========================================================
// Elapsed time slots: normal "HH:MM", Demo "MM:SS" (spec)
//==========================================================

always_comb begin
  for (int i = 0; i < LCD_COLS; i++) begin
    elapsed_slot_type[i] = 2'b01;
    elapsed_slot_data[i] = 8'h20;
  end

  if (Demo) begin
    // Demo: minutes and seconds (last 5 cols "MM:SS")
    elapsed_slot_type[3] = 2'b00; elapsed_slot_data[3] = {4'b0000, et_min_tens};
    elapsed_slot_type[4] = 2'b00; elapsed_slot_data[4] = {4'b0000, et_min_units};
    elapsed_slot_type[5] = 2'b01; elapsed_slot_data[5] = ":";
    elapsed_slot_type[6] = 2'b00; elapsed_slot_data[6] = {4'b0000, et_sec_tens};
    elapsed_slot_type[7] = 2'b00; elapsed_slot_data[7] = {4'b0000, et_sec_units};
  end else begin
    // Normal: hours and minutes "HH:MM"
    elapsed_slot_type[3] = 2'b00; elapsed_slot_data[3] = {4'b0000, et_hour_tens};
    elapsed_slot_type[4] = 2'b00; elapsed_slot_data[4] = {4'b0000, et_hour_units};
    elapsed_slot_type[5] = 2'b01; elapsed_slot_data[5] = ":";
    elapsed_slot_type[6] = 2'b00; elapsed_slot_data[6] = {4'b0000, et_min_tens};
    elapsed_slot_type[7] = 2'b00; elapsed_slot_data[7] = {4'b0000, et_min_units};
  end
end

//==========================================================
// Time-of-day slots: normal "HH:MM:SS", Demo "MM:SS:xx" (sixtieths), roll 24 min
//==========================================================

always_comb begin
  for (int i = 0; i < LCD_COLS; i++) begin
    time_slot_type[i] = 2'b01;
    time_slot_data[i] = 8'h20;
  end

  if (Demo) begin
    // Demo: minutes, seconds, sixtieths "MM:SS:xx"
    time_slot_type[0] = 2'b00; time_slot_data[0] = {4'b0000, tod_min_tens};
    time_slot_type[1] = 2'b00; time_slot_data[1] = {4'b0000, tod_min_units};
    time_slot_type[2] = 2'b01; time_slot_data[2] = ":";
    time_slot_type[3] = 2'b00; time_slot_data[3] = {4'b0000, tod_sec_tens};
    time_slot_type[4] = 2'b00; time_slot_data[4] = {4'b0000, tod_sec_units};
    time_slot_type[5] = 2'b01; time_slot_data[5] = ":";
    time_slot_type[6] = 2'b00; time_slot_data[6] = {4'b0000, tod_sixtieths_tens};
    time_slot_type[7] = 2'b00; time_slot_data[7] = {4'b0000, tod_sixtieths_units};
  end else begin
    // Normal: "HH:MM:SS"
    time_slot_type[0] = 2'b00; time_slot_data[0] = {4'b0000, tod_hour_tens};
    time_slot_type[1] = 2'b00; time_slot_data[1] = {4'b0000, tod_hour_units};
    time_slot_type[2] = 2'b01; time_slot_data[2] = ":";
    time_slot_type[3] = 2'b00; time_slot_data[3] = {4'b0000, tod_min_tens};
    time_slot_type[4] = 2'b00; time_slot_data[4] = {4'b0000, tod_min_units};
    time_slot_type[5] = 2'b01; time_slot_data[5] = ":";
    time_slot_type[6] = 2'b00; time_slot_data[6] = {4'b0000, tod_sec_tens};
    time_slot_type[7] = 2'b00; time_slot_data[7] = {4'b0000, tod_sec_units};
  end
end

//==========================================================
// Mode-based LCD slot MUX
//==========================================================

always_comb begin
  for (int j = 0; j < LCD_COLS; j++) begin
    unique case (display_mode)
      3'd0: begin // TotalRainfall
        lcd_slot_type[j] = rain_slot_type[j];
        lcd_slot_data[j] = rain_slot_data[j];
      end
      3'd1: begin // InstantaneousWindSpeed
        lcd_slot_type[j] = windspd_slot_type[j];
        lcd_slot_data[j] = windspd_slot_data[j];
      end
      3'd2: begin // WindDirection
        lcd_slot_type[j] = winddir_slot_type[j];
        lcd_slot_data[j] = winddir_slot_data[j];
      end
      3'd3: begin // ElapsedTime
        lcd_slot_type[j] = elapsed_slot_type[j];
        lcd_slot_data[j] = elapsed_slot_data[j];
      end
      3'd4: begin // TimeOfDay
        lcd_slot_type[j] = time_slot_type[j];
        lcd_slot_data[j] = time_slot_data[j];
      end
      `ifdef include_pressure_sensor
      3'd5: begin // pressure
        lcd_slot_type[j] = pressure_slot_type[j];
        lcd_slot_data[j] = pressure_slot_data[j];
      end
      3'd6: begin // Temperature
        lcd_slot_type[j] = temp_slot_type[j];
        lcd_slot_data[j] = temp_slot_data[j];
      end
      `endif
      default: begin
        lcd_slot_type[j] = 2'b01;
        lcd_slot_data[j] = 8'h20;
      end
    endcase
  end
end

//==========================================================
// Simulation-only: print LCD line on mode change
//==========================================================
`ifndef SYNTHESIS
function automatic [7:0] slot_to_ascii(input logic [1:0] t, input logic [7:0] d);
  begin
    case (t)
      2'b00: begin
        // BCD digit 0-9
        if (d[3:0] <= 4'd9) slot_to_ascii = 8'd48 + d[3:0];
        else                slot_to_ascii = 8'h3F; // '?'
      end
      2'b01: slot_to_ascii = d;          // direct ASCII
      default: slot_to_ascii = 8'h20;    // space
    endcase
  end
endfunction

logic [2:0] dbg_prev_mode;
logic [7:0] dbg_line [0:LCD_COLS-1];
integer     dbg_i;

always_ff @(posedge Clock or negedge nReset) begin
  if (!nReset) begin
    dbg_prev_mode <= 3'd7; // force first print after reset
  end else begin
    if (display_mode != dbg_prev_mode) begin
      // Build current LCD line from selected slots
      for (dbg_i = 0; dbg_i < LCD_COLS; dbg_i = dbg_i + 1) begin
        dbg_line[dbg_i] = slot_to_ascii(lcd_slot_type[dbg_i], lcd_slot_data[dbg_i]);
      end
      // Print one line per mode change
      $write("MODE%0d LCD: ", display_mode);
      for (dbg_i = 0; dbg_i < LCD_COLS; dbg_i = dbg_i + 1) begin
        $write("%c", dbg_line[dbg_i]);
      end
      $write("\n");
      dbg_prev_mode <= display_mode;
    end
  end
end
`endif

// this module makes no attempt to communicate with the LCD

assign RS  = lcd_rs;
assign RnW = lcd_rw;      // This design is write-only (lcd_rw is always 0)
assign En  = lcd_en;

assign DB_Out     = lcd_data;
assign DB_nEnable = 1'b0; // Always drive data bus

endmodule
