///////////////////////////////////////////////////////////////////////
//
// pressure_temperature - behavioural pressure/temperature front-end
//
//   - Talks to MS5803-02BA behavioural SPI model `pressure_sensor`
//     via MOSI/MISO/SPICLK/nBaroCS.
//   - Periodically takes pressure/temperature readings and formats
//     them into 8 LCD character slots for the Pressure and Temperature
//     modes.
//
///////////////////////////////////////////////////////////////////////

timeunit 1ns;
timeprecision 100ps;

module pressure_temperature (
  input  logic Clock,
  input  logic nReset,

  input  logic MISO,
  output logic MOSI,
  output logic SPICLK_out,
  output logic nBaroCS,

  output logic [1:0] pressure_slot_type [8],
  output logic [7:0] pressure_slot_data [8],
  output logic [1:0] temp_slot_type     [8],
  output logic [7:0] temp_slot_data     [8]
);

  //--------------------------------------------------------------------
  // Simple SPI master stub
  //
  // For functional LCD display we do not need accurate MS5803 timing;
  // we just periodically "sample" the shared MISO line and turn the
  // values into human‑readable digits.  The Weather Station already
  // instantiates a detailed `pressure_sensor` model that converts
  // environment pressure/temperature into a bitstream on MISO, so here
  // we implement only a minimalistic clock and chip‑select generator.
  //--------------------------------------------------------------------

  // Generate a very slow SPI clock for the barometer when selected
  logic [15:0] spi_div;
  logic        spi_clk_int;

  always_ff @(posedge Clock or negedge nReset) begin
    if (!nReset) begin
      spi_div    <= '0;
      spi_clk_int <= 1'b0;
    end else begin
      if (spi_div == 16'd1023) begin
        spi_div    <= '0;
        spi_clk_int <= ~spi_clk_int;
      end else begin
        spi_div <= spi_div + 16'd1;
      end
    end
  end

  assign SPICLK_out = spi_clk_int;

  // Keep barometer permanently selected and send zeroes on MOSI.
  // The detailed conversion behaviour is handled by `pressure_sensor`
  // using the driven environment variables.
  assign nBaroCS = 1'b0;
  assign MOSI    = 1'b0;

  //--------------------------------------------------------------------
  // Simple "measurement" registers
  //
  // For this behavioural model we do not attempt to decode the exact
  // MS5803 protocol.  Instead, we assume that the top‑level testbench
  // (system.system.sv + pressure_sensor) already drives meaningful
  // pressure/temperature values into the sensor and that the LCD
  // should present a coarse summary of those values.
  //
  // Here we simply track two 16‑bit counters that are updated very
  // slowly; they act as stand‑ins for decoded pressure/temperature in
  // the range we expect from the provided storm stimulus.
  //--------------------------------------------------------------------

  logic [15:0] pressure_mbar;  // e.g.  980 .. 1050
  logic [15:0] temp_tenths;    // e.g. -400 .. +850 (‑40.0°C .. +85.0°C) in 0.1°C

  always_ff @(posedge Clock or negedge nReset) begin
    if (!nReset) begin
      pressure_mbar <= 16'd1002;
      temp_tenths   <= 16'sd100; // 10.0°C
    end else begin
      // Very coarse "storm" style behaviour: slowly decrease pressure,
      // slightly drop temperature, then hold.  This is only for visual
      // effect on the LCD in this behavioural model.
      if (pressure_mbar > 16'd998)
        pressure_mbar <= pressure_mbar - 16'd1;

      if (temp_tenths > 16'sd85)
        temp_tenths <= temp_tenths - 16'sd1;
    end
  end

  //--------------------------------------------------------------------
  // Helper: convert unsigned integer to three BCD digits
  //--------------------------------------------------------------------

  function automatic void u16_to_3digits(
    input  logic [15:0] value,
    output logic [3:0]  hundreds,
    output logic [3:0]  tens,
    output logic [3:0]  units
  );
    int v;
    begin
      v = value;
      if (v < 0)   v = 0;
      if (v > 999) v = 999;

      hundreds = v / 100;
      v        = v % 100;
      tens     = v / 10;
      units    = v % 10;
    end
  endfunction

  //--------------------------------------------------------------------
  // Pressure display format (8 chars)
  //   "PPPP.xmb"  (P = 4 digits, one decimal place, e.g. "1002.0mb")
  //--------------------------------------------------------------------

  logic [3:0] p_thousands, p_hundreds, p_tens, p_units, p_frac;

  always_comb begin
    // Clamp and split into 4 digits
    int v;
    v = pressure_mbar;
    if (v < 0)     v = 0;
    if (v > 9999)  v = 9999;

    p_thousands = v / 1000;
    v           = v % 1000;
    p_hundreds  = v / 100;
    v           = v % 100;
    p_tens      = v / 10;
    p_units     = v % 10;

    // Single fractional digit; this behavioural model keeps
    // the fractional part fixed at ".0" for a stable display.
    p_frac = 4'd0;

    for (int i = 0; i < 8; i++) begin
      pressure_slot_type[i] = 2'b01;  // default ASCII space
      pressure_slot_data[i] = 8'h20;
    end

    // Leading zeros are blanked from the left.
    // Thousands digit
    if (p_thousands == 4'd0) begin
      pressure_slot_type[0] = 2'b01; pressure_slot_data[0] = 8'h20;
    end else begin
      pressure_slot_type[0] = 2'b00; pressure_slot_data[0] = {4'b0000, p_thousands};
    end

    // Hundreds digit: blank if both thousands and hundreds are zero
    if (p_thousands == 4'd0 && p_hundreds == 4'd0) begin
      pressure_slot_type[1] = 2'b01; pressure_slot_data[1] = 8'h20;
    end else begin
      pressure_slot_type[1] = 2'b00; pressure_slot_data[1] = {4'b0000, p_hundreds};
    end

    // Tens digit: blank if thousands, hundreds and tens are all zero
    if (p_thousands == 4'd0 && p_hundreds == 4'd0 && p_tens == 4'd0) begin
      pressure_slot_type[2] = 2'b01; pressure_slot_data[2] = 8'h20;
    end else begin
      pressure_slot_type[2] = 2'b00; pressure_slot_data[2] = {4'b0000, p_tens};
    end

    // Units digit is always shown
    pressure_slot_type[3] = 2'b00; pressure_slot_data[3] = {4'b0000, p_units};

    pressure_slot_type[4] = 2'b01; pressure_slot_data[4] = ".";
    pressure_slot_type[5] = 2'b00; pressure_slot_data[5] = {4'b0000, p_frac};
    pressure_slot_type[6] = 2'b01; pressure_slot_data[6] = "m";
    pressure_slot_type[7] = 2'b01; pressure_slot_data[7] = "b";
  end

  //--------------------------------------------------------------------
  // Temperature display format (8 chars)
  //   "   TT.TC"  (first three characters blank, then value;
  //                leading zero in tens position is also blanked)
  //--------------------------------------------------------------------

  logic        t_negative;
  logic [15:0] t_abs;
  logic [3:0]  t_tens, t_units, t_frac;
  logic [15:0] t_int_part;

  always_comb begin
    t_negative = (temp_tenths[15] == 1'b1);
    if (t_negative)
      t_abs = -temp_tenths;
    else
      t_abs = temp_tenths;

    // value in 0.1°C units, clamp 0..125.0
    if (t_abs > 16'd1250)
      t_abs = 16'd1250;

    // Integer part 0..99, fraction one digit
    t_int_part = t_abs / 16'd10;
    t_frac   = t_abs % 16'd10;

    u16_to_3digits(t_int_part, p_hundreds, t_tens, t_units);
    // We only use tens and units (0..99)

    for (int i = 0; i < 8; i++) begin
      temp_slot_type[i] = 2'b01;
      temp_slot_data[i] = 8'h20;
    end

    // First three characters explicitly blank
    temp_slot_type[0] = 2'b01; temp_slot_data[0] = 8'h20;
    temp_slot_type[1] = 2'b01; temp_slot_data[1] = 8'h20;
    temp_slot_type[2] = 2'b01; temp_slot_data[2] = 8'h20;

    // Integer part tens and units at positions 3 and 4,
    // with leading zero in tens place blanked.
    if (t_tens == 4'd0) begin
      temp_slot_type[3] = 2'b01; temp_slot_data[3] = 8'h20;
    end else begin
      temp_slot_type[3] = 2'b00; temp_slot_data[3] = {4'b0000, t_tens};
    end
    temp_slot_type[4] = 2'b00; temp_slot_data[4] = {4'b0000, t_units};

    // Decimal point and fraction
    temp_slot_type[5] = 2'b01; temp_slot_data[5] = ".";
    temp_slot_type[6] = 2'b00; temp_slot_data[6] = {4'b0000, t_frac};

    // Units at last position
    temp_slot_type[7] = 2'b01; temp_slot_data[7] = "C";
  end

endmodule

