///////////////////////////////////////////////////////////////////////
//
// MS5803-02BA behavioural sensor (system2)
//
//  Returns 24-bit D1/D2 from real pressure (mbar) and temperature (°C)
//  set by testbench (SENSOR.pressure, SENSOR.temperature). Same ports
//  as system/pressure_sensor.sv for drop-in use with
//  +define+use_ms5803_behavioural (compile with -y system2 -y system).
//
//  Protocol: 8-bit command (0x1E reset, 0x40 D1 conv, 0x50 D2 conv,
//  0x00 read ADC) then for 0x00 output 24 bits MSB first on SDO.
//
///////////////////////////////////////////////////////////////////////

module ms5803_sensor (
  output SDO,
  input  SDI,
  input  SCLK,
  input  CSB
  );

  timeunit 1ns;
  timeprecision 100ps;

  // Set by testbench like SENSOR.pressure / SENSOR.temperature
  real pressure;   // millibars, 300..1100
  real temperature; // Celsius, -40..85

  initial begin
    pressure   = 1013.0;
    temperature = 25.0;
  end

  logic       driving;
  logic       data_out;
  logic [7:0] cmd;
  int         bit_cnt;
  logic [23:0] D1_raw, D2_raw;  // last conversion results
  logic [23:0] out_val;
  logic        last_was_D1;     // last convert was D1 (pressure) else D2 (temp)

  assign      SDO = (!CSB && driving) ? data_out : 1'bz;

  initial begin
    D1_raw     = pressure_to_D1(1013.0);
    D2_raw     = temperature_to_D2(25.0);
    last_was_D1 = 1'b1;
  end

  // Map pressure (mbar) -> D1, temperature (°C) -> D2 (simplified linear)
  function automatic logic [23:0] pressure_to_D1(input real p);
    real r;
    r = (p - 300.0) / 800.0;
    if (r < 0.0) r = 0.0;
    if (r > 1.0) r = 1.0;
    pressure_to_D1 = 24'($rtoi(r * 0.6 * 16777216.0 + 0.4 * 16777216.0));
  endfunction
  function automatic logic [23:0] temperature_to_D2(input real t);
    real r;
    r = (t + 40.0) / 125.0;
    if (r < 0.0) r = 0.0;
    if (r > 1.0) r = 1.0;
    temperature_to_D2 = 24'(24'sh400000 + $rtoi(r * 3014656.0));
  endfunction

  always @(negedge CSB) begin
    driving = 1'b0;
    data_out = 1'b0;
    cmd = 8'b0;
    bit_cnt = 0;

    // Shift in 8-bit command on posedge SCLK
    repeat (8) begin
      @(posedge SCLK) cmd = { cmd[6:0], SDI };
    end

    case (cmd)
      8'h1E: ; // Reset – no data out
      8'h40: begin
        D1_raw = pressure_to_D1(pressure);
        last_was_D1 = 1'b1;
      end
      8'h50: begin
        D2_raw = temperature_to_D2(temperature);
        last_was_D1 = 1'b0;
      end
      8'h00: begin
        out_val = last_was_D1 ? D1_raw : D2_raw;
        driving = 1'b1;
        // Drive MSB-first so that the pressure_temperature SPI
        // driver, which shifts MISO MSB-first into adc_shift,
        // reconstructs D1/D2 correctly.
        begin
          int b;
          for (b = 23; b >= 0; b = b - 1) begin
            data_out = out_val[b];
            @(negedge SCLK);
          end
        end
      end
      default: ;
    endcase

    driving = 1'b0;
    @(posedge CSB);
  end

endmodule
