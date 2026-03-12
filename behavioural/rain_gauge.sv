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

  // Start/Adjust key (active low), clears total rainfall
  input  logic nStart,

  // Rain sensor input pulse (active low)
  input  logic nRain,

  // Accumulated pulse count
  output logic [15:0] total_rain_pulses,

  // 4 BCD digits in ddd.d mm format: 3 integer + 1 fractional
  output logic [3:0] rain_hundreds_bcd,
  output logic [3:0] rain_tens_bcd,
  output logic [3:0] rain_units_bcd,
  output logic [3:0] rain_tenths_bcd

  );

timeunit 1ns;
timeprecision 100ps;

// Previous-cycle inputs for edge detection
logic prev_nRain;
logic prev_nStart;

// Monostable debounce counter (25ms @ 32.768kHz = 820 cycles)
// 10-bit counter needed (2^10 = 1024 > 820)
localparam int DEBOUNCE_COUNT = 820;
logic [9:0] debounce_counter;
logic [9:0] start_debounce_counter;

// Intermediate: total rain in 0.1mm units (mm*10)
int unsigned rain_1mm;
int unsigned value_1mm;

// Count nRain pulses; nReset = async clear, Start/Adjust (nStart) = sync clear
// Monostable debounce: start timer on falling edge, ignore input while timer runs
always_ff @( posedge Clock, negedge nReset )
  if ( ! nReset )
    begin
      total_rain_pulses       <= '0;
      prev_nRain              <= 1'b1;
      prev_nStart             <= 1'b1;
      debounce_counter        <= '0;
      start_debounce_counter  <= '0;
    end
  else
    begin
      // Latch previous-cycle inputs
      prev_nRain  <= nRain;
      prev_nStart <= nStart;

      // Start/Adjust key: monostable debounce, clear on falling edge only
      if ( start_debounce_counter != '0 )
        start_debounce_counter <= start_debounce_counter - 1'b1;
      else if ( prev_nStart && ! nStart )
        begin
          total_rain_pulses      <= '0;
          start_debounce_counter <= DEBOUNCE_COUNT;
        end

      // nRain: while debounce counter non-zero, decrement and ignore input
      if ( debounce_counter != '0 )
        debounce_counter <= debounce_counter - 1'b1;
      // When debounce is zero and no Start edge this cycle, detect nRain falling edge
      else if ( prev_nRain && ! nRain && ( prev_nStart || nStart ) )
        begin
          total_rain_pulses <= total_rain_pulses + 1'b1;
          debounce_counter  <= DEBOUNCE_COUNT;
        end
    end

// Convert pulse count to 4 BCD digits for ddd.d mm format
// 1 pulse = 0.28mm = 28 x 0.01mm
// Round to 0.1mm: (pulses * 28 + 5) / 10
// rain_1mm clamped to 0..999.9mm, i.e. 0..9999 (mm*10)
always_comb
  begin
    // Rain in 0.1mm units with rounding
    rain_1mm = (total_rain_pulses * 28 + 5) / 10;

    // Saturate to 999.9mm
    if ( rain_1mm > 9999 )
      rain_1mm = 9999;

    value_1mm = rain_1mm;

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
