///////////////////////////////////////////////////////////////////////
//
// rain_gauge module
//
//  Counts total rainfall from nRain pulses and outputs BCD in ddd.dd mm format
//
///////////////////////////////////////////////////////////////////////

module rain_gauge(

  input  logic Clock,
  input  logic nReset,

  // Single-cycle clear pulse from main_fsm (already debounced/decoded
  // in MODE_RAIN). Replaces the previous redundant nStart debounce.
  input  logic clear_pulse,

  // Rain sensor input pulse (active low)
  input  logic nRain,

  // Accumulated pulse count
  output logic [15:0] total_rain_pulses,

  // 4 BCD digits in ddd.d mm format: 3 integer + 1 fractional
  output logic [3:0] rain_hundreds_bcd,
  output logic [3:0] rain_tens_bcd,
  output logic [3:0] rain_units_bcd,
  output logic [3:0] rain_tenths_bcd,

  // Calibration multiplier digits for LCD when in calib mode (1000..9999 -> thousands,hundreds,tens,units)
  output logic [3:0] rain_calib_thousands_bcd,
  output logic [3:0] rain_calib_hundreds_bcd,
  output logic [3:0] rain_calib_tens_bcd,
  output logic [3:0] rain_calib_units_bcd,

  // Calibration (from main_fsm when in MODE_RAIN_CALIB)
  input  logic       in_calibration,
  input  logic       is_rain_calib,
  input  logic [1:0] calib_digit_index,
  input  logic       calib_increment_pulse
  );

timeunit 1ns;
timeprecision 100ps;

// Previous-cycle input for nRain edge detection
logic prev_nRain;

// Monostable debounce counter for nRain only
// (nStart debounce handled centrally in main_fsm; this module just receives a pulse)
// 25ms @ 32.768kHz = 820 cycles, 10-bit counter (2^10 = 1024 > 820)
localparam int DEBOUNCE_COUNT = 820;
logic [9:0] debounce_counter;

// Intermediate: total rain in 0.1mm units (mm*10)
int unsigned rain_1mm;
int unsigned value_1mm;

// Calibration: multiplier 1000 = 1.000x, range 100..9999 (0.1x to 9.999x); 9000+1000 wraps to 100
localparam int CALIB_DEFAULT = 1000;
logic [15:0] rain_calib_mult;
logic [15:0] calib_add;
logic [15:0] calib_next;

// Count nRain pulses; nReset = async clear, clear_pulse from main_fsm = sync clear.
// Monostable debounce on nRain only: start timer on falling edge, ignore input while timer runs.
always_ff @( posedge Clock, negedge nReset )
  if ( ! nReset )
    begin
      total_rain_pulses <= '0;
      prev_nRain        <= 1'b1;
      debounce_counter  <= '0;
      rain_calib_mult   <= CALIB_DEFAULT;
    end
  else
    begin
      // Latch previous-cycle nRain
      prev_nRain <= nRain;

      // nRain debounce timer: decrement while running
      if ( debounce_counter != '0 )
        debounce_counter <= debounce_counter - 1'b1;

      // Counter update: clear has priority over rain edge in same cycle
      if ( clear_pulse )
        total_rain_pulses <= '0;
      else if ( debounce_counter == '0 && prev_nRain && ! nRain )
        begin
          total_rain_pulses <= total_rain_pulses + 1'b1;
          debounce_counter  <= DEBOUNCE_COUNT;
        end

      // Calibration: Start increments digit; overflow: thousands (digit 3) -> wrap to 100, else wrap to 1000
      if ( in_calibration && is_rain_calib && calib_increment_pulse )
        begin
          calib_add  = ( calib_digit_index == 2'd0 ) ? 16'd1    :
                       ( calib_digit_index == 2'd1 ) ? 16'd10   :
                       ( calib_digit_index == 2'd2 ) ? 16'd100  : 16'd1000;
          calib_next = rain_calib_mult + calib_add;
          if ( calib_next > 16'd9999 )
            rain_calib_mult <= ( calib_digit_index == 2'd3 ) ? 16'd100 : 16'd1000;
          else
            rain_calib_mult <= calib_next[15:0];
        end
    end

// Calibration multiplier 4 BCD digits (1000..9999) for LCD in calib mode
always_comb begin
  rain_calib_thousands_bcd = 4'(rain_calib_mult / 1000);
  rain_calib_hundreds_bcd  = 4'((rain_calib_mult / 100) % 10);
  rain_calib_tens_bcd      = 4'((rain_calib_mult / 10) % 10);
  rain_calib_units_bcd     = 4'(rain_calib_mult % 10);
end

// Convert pulse count to 4 BCD digits for ddd.d mm format
// 1 pulse = 0.28mm = 28 x 0.01mm -> raw: (pulses * 28 + 5) / 10
// Apply calibration: display = (raw * rain_calib_mult) / 1000, clamp to 9999
always_comb
  begin
    // Raw rain in 0.1mm units with rounding
    rain_1mm = (total_rain_pulses * 28 + 5) / 10;

    // Saturate raw to 9999 then apply calibration multiplier (1000 = 1.0)
    if ( rain_1mm > 9999 )
      rain_1mm = 9999;
    value_1mm = ( rain_1mm * rain_calib_mult ) / 1000;
    if ( value_1mm > 9999 )
      value_1mm = 9999;

    // Tenths (0.1mm)
    rain_tenths_bcd = value_1mm % 10;
    value_1mm       = value_1mm / 10;

    // Units
    rain_units_bcd = value_1mm % 10;
    value_1mm      = value_1mm / 10;

    // Tens
    rain_tens_bcd = value_1mm % 10;
    value_1mm     = value_1mm / 10;

    // Hundreds
    rain_hundreds_bcd = value_1mm % 10;
  end

endmodule
