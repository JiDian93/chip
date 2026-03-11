///////////////////////////////////////////////////////////////////////
//
// MS5803-02BA Sensor module (behavioural library copy)
//
//   Simplified SPI model that converts real-valued pressure /
//   temperature into 24‑bit D1/D2 results, compatible with a
//   subset of the MS5803‑02BA command set.
//
//   Ports:
//     SDO  (Output, tri‑state when CSB=1)
//     SDI  (Input, serial data from master)
//     SCLK (Input, SPI clock)
//     CSB  (Input, active‑low chip select)
//
///////////////////////////////////////////////////////////////////////

module pressure_sensor (
  output      SDO,   // tri-stated when CSB=1
  input  wire SDI,
  input  wire SCLK,
  input  wire CSB
  );

timeunit 1ns;
timeprecision 100ps;

// This model represents an MS5803-02BA sensor module which can
// be used for both pressure and temperature measurement.
//
// The variables "pressure" and "temperature" represent environment
// values and may be driven from the testbench.  This SPI slave model
// exposes them to the DUT as simple 24‑bit conversion results on
// D1 (pressure) and D2 (temperature), using a subset of the commands
// described in the MS5803‑02BA datasheet.

real pressure;    // pressure in millibars
real temperature; // temperature in Celsius

// -------------------------------------------------------------------
// Simple SPI protocol / data model
// -------------------------------------------------------------------

// Encoded conversion results for pressure (D1) and temperature (D2)
logic [23:0] d1_code, d2_code;

always_comb begin
  int p_i, t_i;

  // Scale pressure (mbar) and temperature (°C) into 24‑bit codes
  p_i = int'(pressure * 100.0);              // 0.01 mbar units
  if (p_i < 0)          p_i = 0;
  if (p_i > 24'hFFFFFF) p_i = 24'hFFFFFF;

  t_i = int'((temperature + 40.0) * 100.0);  // offset negatives
  if (t_i < 0)          t_i = 0;
  if (t_i > 24'hFFFFFF) t_i = 24'hFFFFFF;

  d1_code = p_i[23:0];
  d2_code = t_i[23:0];
end

// Command opcodes (subset)
localparam logic [7:0] CMD_RESET    = 8'h1E;
localparam logic [7:0] CMD_ADC_READ = 8'h00;
localparam logic [7:0] CMD_CONV_D1  = 8'h40; // D1 conversion (any OSR)
localparam logic [7:0] CMD_CONV_D2  = 8'h50; // D2 conversion (any OSR)

// Incoming command and bit counter
logic [7:0] cmd_shift;
logic [4:0] bit_count;      // 0..7
logic       last_is_d1;     // remembers last conversion type

// Outgoing shift register and SDO driver
logic [23:0] shift_out;
logic [4:0]  shift_count;   // 0..23
logic        sdo_bit;

assign SDO = (CSB == 1'b0) ? sdo_bit : 1'bz;

// Simple SPI state machine on SCLK rising edge
always_ff @(posedge SCLK) begin
  if (CSB) begin
    // When CSB is high, interface is idle
    cmd_shift   <= 8'd0;
    bit_count   <= 5'd0;
    shift_out   <= 24'd0;
    shift_count <= 5'd0;
    sdo_bit     <= 1'b0;
    last_is_d1  <= 1'b1;
  end else begin
    // Shift in command bits (MSB-first)
    cmd_shift <= {cmd_shift[6:0], SDI};

    // Shift out data if a conversion value has been loaded
    if (shift_count < 5'd24) begin
      sdo_bit   <= shift_out[23];
      shift_out <= {shift_out[22:0], 1'b0};
      shift_count <= shift_count + 5'd1;
    end

    // On every 8th bit, decode the command byte
    if (bit_count == 5'd7) begin
      bit_count <= 5'd0;

      unique case ({cmd_shift[6:0], SDI})
        CMD_RESET: begin
          shift_out   <= 24'd0;
          shift_count <= 5'd0;
          last_is_d1  <= 1'b1;
        end

        CMD_CONV_D1: begin
          last_is_d1 <= 1'b1;
        end

        CMD_CONV_D2: begin
          last_is_d1 <= 1'b0;
        end

        CMD_ADC_READ: begin
          shift_out   <= last_is_d1 ? d1_code : d2_code;
          shift_count <= 5'd0;
        end

        default: begin
          shift_out   <= 24'd0;
          shift_count <= 5'd0;
        end
      endcase
    end else begin
      bit_count <= bit_count + 5'd1;
    end
  end
end

// -------------------------------------------------------------------
// Timing checks (copied from datasheet‑based system model)
// -------------------------------------------------------------------

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

