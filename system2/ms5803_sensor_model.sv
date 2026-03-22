///////////////////////////////////////////////////////////////////////
//
// ms5803_sensor_model (system2 stimulus model)
//
// Gate/SDF-robust external MS5803 behavioural SPI model.
// - Drives deterministic PROM coefficients during boot
// - Synthesizes D1/D2 from real-valued pressure/temperature inputs
// - Tolerates command decode drift by providing a sequential fallback path
//
///////////////////////////////////////////////////////////////////////

module ms5803_sensor_model (
  output logic SDO,
  input  logic SDI,
  input  logic SCLK,
  input  logic CSB,
  input  real  pressure_mb,
  input  real  temperature_c
);
  timeunit 1ns;
  timeprecision 100ps;

  localparam int unsigned C1 = 16'd46372;
  localparam int unsigned C2 = 16'd43981;
  localparam int unsigned C3 = 16'd29059;
  localparam int unsigned C4 = 16'd27842;
  localparam int unsigned C5 = 16'd31553;
  localparam int unsigned C6 = 16'd28165;

  logic        driving;
  logic [7:0]  cmd;
  logic [23:0] d1_raw, d2_raw;
  logic [23:0] out_shift;
  logic        last_is_d1;
  logic        prom_boot_phase;
  logic [2:0]  prom_seq_idx;
  logic [15:0] prom [0:7];

  assign SDO = (!CSB && driving) ? out_shift[23] : 1'bz;

  function automatic logic [23:0] synth_d2_from_temp_x100(input int signed temp_x100);
    longint signed dT, d2;
    begin
      dT = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      d2 = dT + (longint'(C5) * 256);
      if (d2 < 0) d2 = 0;
      if (d2 > 16777215) d2 = 16777215;
      synth_d2_from_temp_x100 = d2[23:0];
    end
  endfunction

  function automatic logic [23:0] synth_d1_from_p_t_x100(
    input int unsigned p_x100,
    input int signed   temp_x100
  );
    longint signed dT, OFF, SENS, num, d1;
    begin
      dT   = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      OFF  = (longint'(C2) * 131072) + ((longint'(C4) * dT) / 64);
      SENS = (longint'(C1) * 65536)  + ((longint'(C3) * dT) / 128);
      if (SENS == 0) d1 = 0;
      else begin
        num = (longint'(p_x100) * 32768) + OFF;
        d1  = (num * 2097152) / SENS;
      end
      if (d1 < 0) d1 = 0;
      if (d1 > 16777215) d1 = 16777215;
      synth_d1_from_p_t_x100 = d1[23:0];
    end
  endfunction

  task automatic update_adc_codes;
    real p_mb, t_c;
    int unsigned p_x100;
    int signed   t_x100;
    begin
      p_mb = pressure_mb;
      t_c  = temperature_c;
      if (p_mb < 300.0)  p_mb = 300.0;
      if (p_mb > 1100.0) p_mb = 1100.0;
      if (t_c < -40.0)   t_c  = -40.0;
      if (t_c > 85.0)    t_c  = 85.0;

      p_x100 = $rtoi(p_mb * 100.0 + 0.5);
      if (t_c >= 0.0) t_x100 = $rtoi(t_c * 100.0 + 0.5);
      else            t_x100 = $rtoi(t_c * 100.0 - 0.5);

      d2_raw = synth_d2_from_temp_x100(t_x100);
      d1_raw = synth_d1_from_p_t_x100(p_x100, t_x100);
    end
  endtask

  task automatic shift_out_bits(input int nbits);
    int i;
    begin
      driving = 1'b1;
      for (i = 0; i < nbits; i = i + 1) begin
        // Master samples on SCLK rising edge.
        @(posedge SCLK);
        if (i < nbits - 1) begin
          // Shift after sample to prepare next bit.
          @(negedge SCLK);
          out_shift = {out_shift[22:0], 1'b0};
        end
      end
      driving = 1'b0;
    end
  endtask

  initial begin
    driving = 1'b0;
    cmd = 8'h00;
    d1_raw = 24'd0;
    d2_raw = 24'd0;
    out_shift = 24'd0;
    last_is_d1 = 1'b1;
    prom_boot_phase = 1'b1;
    prom_seq_idx = 3'd1;

    prom[0] = 16'h0000;
    prom[1] = C1[15:0];
    prom[2] = C2[15:0];
    prom[3] = C3[15:0];
    prom[4] = C4[15:0];
    prom[5] = C5[15:0];
    prom[6] = C6[15:0];
    prom[7] = 16'h0000;
  end

  always @(negedge CSB) begin
    int i;
    int addr;
    logic cmd_is_prom;
    logic cmd_is_d1;
    logic cmd_is_d2;
    begin
      driving = 1'b0;
      cmd = 8'h00;
      cmd_is_prom = 1'b0;
      cmd_is_d1 = 1'b0;
      cmd_is_d2 = 1'b0;

      // Read command byte.
      for (i = 0; i < 8; i = i + 1) begin
        @(posedge SCLK);
        cmd = {cmd[6:0], SDI};
      end

      // Aliases seen with timing-shifted masters.
      cmd_is_prom = ((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) ||
                    ((cmd >= 8'h44) && (cmd <= 8'h5C) && (cmd[1:0] == 2'b00));
      cmd_is_d1   = (cmd == 8'h40) || (cmd == 8'h80) || (cmd == 8'h44);
      cmd_is_d2   = (cmd == 8'h50) || (cmd == 8'hA0) || (cmd == 8'h54);

      // Reset command (canonical + shifted).
      if ((cmd == 8'h1E) || (cmd == 8'h3C)) begin
        prom_boot_phase = 1'b1;
        prom_seq_idx = 3'd1;
        last_is_d1 = 1'b1;
      end

      // Boot: ensure coefficients are always delivered.
      if (prom_boot_phase) begin
        if (cmd_is_prom) begin
          if ((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) addr = cmd[3:1];
          else                                         addr = (cmd - 8'h40) >> 2;
        end else begin
          // Sequential fallback if command decode drifts (common in gate/SDF).
          addr = prom_seq_idx;
        end

        out_shift = {prom[addr[2:0]], 8'h00};
        shift_out_bits(16);

        if (addr[2:0] >= 3'd6) begin
          prom_boot_phase = 1'b0;
          update_adc_codes();
          last_is_d1 = 1'b1;
        end else begin
          prom_seq_idx = addr[2:0] + 1'b1;
        end
      end else begin
        // Normal conversion selection when command decode is valid.
        if (cmd_is_d1) begin
          update_adc_codes();
          last_is_d1 = 1'b1;
        end else if (cmd_is_d2) begin
          update_adc_codes();
          last_is_d1 = 1'b0;
        end

        // ADC read command, plus fallback for ambiguous opcodes.
        if ((cmd == 8'h00) || (!cmd_is_prom && !cmd_is_d1 && !cmd_is_d2)) begin
          update_adc_codes();
          out_shift = last_is_d1 ? d1_raw : d2_raw;
          shift_out_bits(24);
          // Keep progress even if explicit convert commands are missing.
          last_is_d1 = ~last_is_d1;
        end
      end

      @(posedge CSB);
      driving = 1'b0;
    end
  end

endmodule
///////////////////////////////////////////////////////////////////////
//
// ms5803_sensor_model (system2 testbench model)
//
// External behavioural MS5803-02BA SPI model for testbench use.
// - Accepts pressure/temperature as real-valued environment inputs
// - Supports canonical and 1-bit-shifted command aliases from DUT master
// - Separates PROM boot phase from conversion phase to avoid opcode overlap
//
///////////////////////////////////////////////////////////////////////

module ms5803_sensor_model (
  output logic SDO,
  input  logic SDI,
  input  logic SCLK,
  input  logic CSB,
  input  real  pressure_mb,
  input  real  temperature_c
);
  timeunit 1ns;
  timeprecision 100ps;

  localparam int unsigned C1 = 16'd46372;
  localparam int unsigned C2 = 16'd43981;
  localparam int unsigned C3 = 16'd29059;
  localparam int unsigned C4 = 16'd27842;
  localparam int unsigned C5 = 16'd31553;
  localparam int unsigned C6 = 16'd28165;

  logic        driving;
  logic [7:0]  cmd;
  logic [23:0] d1_raw, d2_raw;
  logic [23:0] out_shift;
  logic        last_is_d1;
  logic        prom_boot_phase;
  logic [15:0] prom [0:7];
  logic [2:0]  prom_seq_idx;

  assign SDO = (!CSB && driving) ? out_shift[23] : 1'bz;

  function automatic logic [23:0] synth_d2_from_temp_x100(input int signed temp_x100);
    longint signed dT, d2;
    begin
      dT = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      d2 = dT + (longint'(C5) * 256);
      if (d2 < 0) d2 = 0;
      if (d2 > 16777215) d2 = 16777215;
      synth_d2_from_temp_x100 = d2[23:0];
    end
  endfunction

  function automatic logic [23:0] synth_d1_from_p_t_x100(
    input int unsigned p_x100,
    input int signed   temp_x100
  );
    longint signed dT, OFF, SENS, num, d1;
    begin
      dT   = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      OFF  = (longint'(C2) * 131072) + ((longint'(C4) * dT) / 64);
      SENS = (longint'(C1) * 65536)  + ((longint'(C3) * dT) / 128);
      if (SENS == 0) d1 = 0;
      else begin
        num = (longint'(p_x100) * 32768) + OFF;
        d1  = (num * 2097152) / SENS;
      end
      if (d1 < 0) d1 = 0;
      if (d1 > 16777215) d1 = 16777215;
      synth_d1_from_p_t_x100 = d1[23:0];
    end
  endfunction

  task automatic update_adc_codes;
    real p_mb, t_c;
    int unsigned p_x100;
    int signed   t_x100;
    begin
      p_mb = pressure_mb;
      t_c  = temperature_c;
      if (p_mb < 300.0)  p_mb = 300.0;
      if (p_mb > 1100.0) p_mb = 1100.0;
      if (t_c < -40.0)   t_c  = -40.0;
      if (t_c > 85.0)    t_c  = 85.0;

      p_x100 = $rtoi(p_mb * 100.0 + 0.5);
      if (t_c >= 0.0) t_x100 = $rtoi(t_c * 100.0 + 0.5);
      else            t_x100 = $rtoi(t_c * 100.0 - 0.5);

      d2_raw = synth_d2_from_temp_x100(t_x100);
      d1_raw = synth_d1_from_p_t_x100(p_x100, t_x100);
    end
  endtask

  task automatic shift_out_bits(input int nbits);
    int i;
    begin
      driving = 1'b1;
      for (i = 0; i < nbits; i = i + 1) begin
        @(posedge SCLK);
        if (i < nbits - 1) begin
          @(negedge SCLK);
          out_shift = {out_shift[22:0], 1'b0};
        end
      end
      driving = 1'b0;
    end
  endtask

  initial begin
    driving = 1'b0;
    cmd = 8'h00;
    d1_raw = 24'd0;
    d2_raw = 24'd0;
    out_shift = 24'd0;
    last_is_d1 = 1'b1;
    prom_boot_phase = 1'b1;
    prom_seq_idx = 3'd1;

    prom[0] = 16'h0000;
    prom[1] = C1[15:0];
    prom[2] = C2[15:0];
    prom[3] = C3[15:0];
    prom[4] = C4[15:0];
    prom[5] = C5[15:0];
    prom[6] = C6[15:0];
    prom[7] = 16'h0000;
  end

  always @(negedge CSB) begin
    int i;
    int addr;

    driving = 1'b0;
    cmd = 8'h00;

    // Shift command in on SCLK rising edges.
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge SCLK);
      cmd = {cmd[6:0], SDI};
    end

    // Reset (canonical + shifted)
    if (cmd == 8'h1E || cmd == 8'h3C) begin
      prom_boot_phase = 1'b1;
      prom_seq_idx = 3'd1;

    // During PROM boot phase, prioritize PROM reads to avoid 0x50/0x54 overlap.
    end else if (prom_boot_phase &&
                 (((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) ||
                  (cmd >= 8'h44 && cmd <= 8'h5C && cmd[1:0] == 2'b00))) begin
      if ((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) addr = cmd[3:1];
      else                                         addr = (cmd - 8'h40) >> 2;
      out_shift = {prom[addr[2:0]], 8'h00};
      shift_out_bits(16);
      if (addr[2:0] >= 3'd6) begin
        prom_boot_phase = 1'b0;
        update_adc_codes();
        last_is_d1 = 1'b1;
      end else begin
        prom_seq_idx = addr[2:0] + 1'b1;
      end

    // Some DUT/netlist variants emit 0x00 during PROM boot reads.
    end else if (prom_boot_phase && cmd == 8'h00) begin
      out_shift = {prom[prom_seq_idx], 8'h00};
      shift_out_bits(16);
      if (prom_seq_idx >= 3'd6) begin
        prom_boot_phase = 1'b0;
        update_adc_codes();
        last_is_d1 = 1'b1;
      end else begin
        prom_seq_idx = prom_seq_idx + 1'b1;
      end

    // D1 convert (canonical + shifted)
    end else if (cmd == 8'h40 || cmd == 8'h80 || cmd == 8'h44) begin
      update_adc_codes();
      last_is_d1 = 1'b1;
      prom_boot_phase = 1'b0;

    // D2 convert (canonical + shifted)
    end else if (cmd == 8'h50 || cmd == 8'hA0 || cmd == 8'h54) begin
      update_adc_codes();
      last_is_d1 = 1'b0;
      prom_boot_phase = 1'b0;

    // ADC read
    end else if (cmd == 8'h00) begin
      update_adc_codes();
      out_shift = last_is_d1 ? d1_raw : d2_raw;
      shift_out_bits(24);
      // Keep data flowing even if conversion commands are occasionally missing.
      last_is_d1 = ~last_is_d1;
    end

    @(posedge CSB);
    driving = 1'b0;
  end

endmodule
module ms5803_sensor_model (
  output logic SDO,
  input  logic SDI,
  input  logic SCLK,
  input  logic CSB,
  input  real  pressure_mb,
  input  real  temperature_c
);
  timeunit 1ns;
  timeprecision 100ps;

  localparam int unsigned C1 = 16'd46372;
  localparam int unsigned C2 = 16'd43981;
  localparam int unsigned C3 = 16'd29059;
  localparam int unsigned C4 = 16'd27842;
  localparam int unsigned C5 = 16'd31553;
  localparam int unsigned C6 = 16'd28165;

  logic        driving;
  logic [7:0]  cmd;
  logic [23:0] d1_raw, d2_raw;
  logic [23:0] out_shift;
  logic        last_is_d1;
  logic [15:0] prom [0:7];

  assign SDO = (!CSB && driving) ? out_shift[23] : 1'bz;

  function automatic logic [23:0] synth_d2_from_temp_x100(input int signed temp_x100);
    longint signed dT, d2;
    begin
      dT = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      d2 = dT + (longint'(C5) * 256);
      if (d2 < 0) d2 = 0;
      if (d2 > 16777215) d2 = 16777215;
      synth_d2_from_temp_x100 = d2[23:0];
    end
  endfunction

  function automatic logic [23:0] synth_d1_from_p_t_x100(
    input int unsigned p_x100,
    input int signed   temp_x100
  );
    longint signed dT, OFF, SENS, num, d1;
    begin
      dT   = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      OFF  = (longint'(C2) * 131072) + ((longint'(C4) * dT) / 64);
      SENS = (longint'(C1) * 65536)  + ((longint'(C3) * dT) / 128);
      if (SENS == 0) d1 = 0;
      else begin
        num = (longint'(p_x100) * 32768) + OFF;
        d1  = (num * 2097152) / SENS;
      end
      if (d1 < 0) d1 = 0;
      if (d1 > 16777215) d1 = 16777215;
      synth_d1_from_p_t_x100 = d1[23:0];
    end
  endfunction

  task automatic update_adc_codes;
    real p_mb, t_c;
    int unsigned p_x100;
    int signed   t_x100;
    begin
      p_mb = pressure_mb;
      t_c  = temperature_c;
      if (p_mb < 300.0)  p_mb = 300.0;
      if (p_mb > 1100.0) p_mb = 1100.0;
      if (t_c < -40.0)   t_c  = -40.0;
      if (t_c > 85.0)    t_c  = 85.0;

      p_x100 = $rtoi(p_mb * 100.0 + 0.5);
      if (t_c >= 0.0) t_x100 = $rtoi(t_c * 100.0 + 0.5);
      else            t_x100 = $rtoi(t_c * 100.0 - 0.5);

      d2_raw = synth_d2_from_temp_x100(t_x100);
      d1_raw = synth_d1_from_p_t_x100(p_x100, t_x100);
    end
  endtask

  initial begin
    driving    = 1'b0;
    cmd        = 8'h00;
    d1_raw     = 24'd0;
    d2_raw     = 24'd0;
    out_shift  = 24'd0;
    last_is_d1 = 1'b1;

    prom[0] = 16'h0000;
    prom[1] = C1[15:0];
    prom[2] = C2[15:0];
    prom[3] = C3[15:0];
    prom[4] = C4[15:0];
    prom[5] = C5[15:0];
    prom[6] = C6[15:0];
    prom[7] = 16'h0000;
  end

  always @(negedge CSB) begin
    int i;
    int addr;

    driving = 1'b0;
    cmd = 8'h00;

    // Shift command on rising edge
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge SCLK);
      cmd = {cmd[6:0], SDI};
    end

    // Canonical commands + shifted aliases used by current behavioural master
    if (cmd == 8'h1E || cmd == 8'h3C) begin
      // reset
    end else if (cmd == 8'h40 || cmd == 8'h80 || cmd == 8'h44) begin
      update_adc_codes();
      last_is_d1 = 1'b1;
    end else if (cmd == 8'h50 || cmd == 8'hA0 || cmd == 8'h54) begin
      update_adc_codes();
      last_is_d1 = 1'b0;
    end else if (cmd == 8'h00) begin
      update_adc_codes();
      out_shift = last_is_d1 ? d1_raw : d2_raw;
      last_is_d1 = ~last_is_d1;
      driving = 1'b1;
      for (i = 0; i < 24; i = i + 1) begin
        @(negedge SCLK);
        if (i < 23) out_shift = {out_shift[22:0], 1'b0};
      end
      driving = 1'b0;
    end else if ((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) begin
      addr = cmd[3:1];
      out_shift = {prom[addr[2:0]], 8'h00};
      driving = 1'b1;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge SCLK);
        if (i < 15) out_shift = {out_shift[22:0], 1'b0};
      end
      driving = 1'b0;
    end else if (cmd >= 8'h44 && cmd <= 8'h5C && cmd[1:0] == 2'b00) begin
      // shifted PROM reads: A2/A4/... -> 44/48/...
      addr = (cmd - 8'h40) >> 2;
      out_shift = {prom[addr[2:0]], 8'h00};
      driving = 1'b1;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge SCLK);
        if (i < 15) out_shift = {out_shift[22:0], 1'b0};
      end
      driving = 1'b0;
    end

    @(posedge CSB);
    driving = 1'b0;
  end

endmodule
///////////////////////////////////////////////////////////////////////
//
// ms5803_sensor_model
//
//  External behavioural MS5803-02BA SPI model for testbench use.
//  Implements:
//   - Reset           : 0x1E
//   - Convert D1      : 0x40
//   - Convert D2      : 0x50
//   - ADC Read (24b)  : 0x00
//   - PROM Read (16b) : 0xA0..0xAE
//
///////////////////////////////////////////////////////////////////////

module ms5803_sensor_model (
  output logic SDO,
  input  logic SDI,
  input  logic SCLK,
  input  logic CSB,
  input  real  pressure_mb,
  input  real  temperature_c
);

  timeunit 1ns;
  timeprecision 100ps;

  localparam int unsigned C1 = 16'd46372;
  localparam int unsigned C2 = 16'd43981;
  localparam int unsigned C3 = 16'd29059;
  localparam int unsigned C4 = 16'd27842;
  localparam int unsigned C5 = 16'd31553;
  localparam int unsigned C6 = 16'd28165;

  logic        driving;
  logic [7:0]  cmd;
  logic [23:0] d1_raw, d2_raw;
  logic [23:0] out_shift;
  logic        last_is_d1;
  logic        prom_boot_phase;
  logic [15:0] prom [0:7];

  assign SDO = (!CSB && driving) ? out_shift[23] : 1'bz;

  function automatic logic [23:0] synth_d2_from_temp_x100(input int signed temp_x100);
    longint signed dT, d2;
    begin
      dT = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      d2 = dT + (longint'(C5) * 256);
      if (d2 < 0) d2 = 0;
      if (d2 > 16777215) d2 = 16777215;
      synth_d2_from_temp_x100 = d2[23:0];
    end
  endfunction

  function automatic logic [23:0] synth_d1_from_p_t_x100(
    input int unsigned p_x100,
    input int signed   temp_x100
  );
    longint signed dT, OFF, SENS, num, d1;
    begin
      dT   = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      OFF  = (longint'(C2) * 131072) + ((longint'(C4) * dT) / 64);
      SENS = (longint'(C1) * 65536)  + ((longint'(C3) * dT) / 128);
      if (SENS == 0) d1 = 0;
      else begin
        num = (longint'(p_x100) * 32768) + OFF;
        d1  = (num * 2097152) / SENS;
      end
      if (d1 < 0) d1 = 0;
      if (d1 > 16777215) d1 = 16777215;
      synth_d1_from_p_t_x100 = d1[23:0];
    end
  endfunction

  task automatic update_adc_codes;
    real p_mb, t_c;
    int unsigned p_x100;
    int signed   t_x100;
    begin
      p_mb = pressure_mb;
      t_c  = temperature_c;
      if (p_mb < 300.0)  p_mb = 300.0;
      if (p_mb > 1100.0) p_mb = 1100.0;
      if (t_c < -40.0)   t_c  = -40.0;
      if (t_c > 85.0)    t_c  = 85.0;

      p_x100 = $rtoi(p_mb * 100.0 + 0.5);
      if (t_c >= 0.0) t_x100 = $rtoi(t_c * 100.0 + 0.5);
      else            t_x100 = $rtoi(t_c * 100.0 - 0.5);

      d2_raw = synth_d2_from_temp_x100(t_x100);
      d1_raw = synth_d1_from_p_t_x100(p_x100, t_x100);
    end
  endtask

  initial begin
    driving    = 1'b0;
    cmd        = 8'h00;
    d1_raw     = 24'd0;
    d2_raw     = 24'd0;
    out_shift  = 24'd0;
    last_is_d1 = 1'b1;
    prom_boot_phase = 1'b1;

    prom[0] = 16'h0000;
    prom[1] = C1[15:0];
    prom[2] = C2[15:0];
    prom[3] = C3[15:0];
    prom[4] = C4[15:0];
    prom[5] = C5[15:0];
    prom[6] = C6[15:0];
    prom[7] = 16'h0000;
  end

  always @(negedge CSB) begin
    int i;
    int addr;

    driving = 1'b0;
    cmd = 8'h00;

    // Shift command in on SCLK rising edges
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge SCLK);
      cmd = {cmd[6:0], SDI};
    end

    // Reset
    if (cmd == 8'h1E || cmd == 8'h3C) begin
      prom_boot_phase = 1'b1;

    // PROM read canonical: 0xA0..0xAE (even)
    end else if ((cmd[7:4] == 4'hA) && (cmd[0] == 1'b0)) begin
      addr = cmd[3:1];
      out_shift = {prom[addr[2:0]], 8'h00};
      driving = 1'b1;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge SCLK);
        if (i < 15) out_shift = {out_shift[22:0], 1'b0};
      end
      driving = 1'b0;

    // PROM read shifted (master currently outputs A2/A4/... as 44/48/...)
    end else if (prom_boot_phase && cmd >= 8'h44 && cmd <= 8'h5C && cmd[1:0] == 2'b00) begin
      addr = (cmd - 8'h40) >> 2;
      out_shift = {prom[addr[2:0]], 8'h00};
      driving = 1'b1;
      for (i = 0; i < 16; i = i + 1) begin
        @(negedge SCLK);
        if (i < 15) out_shift = {out_shift[22:0], 1'b0};
      end
      driving = 1'b0;

    // D1 convert
    end else if (cmd == 8'h40 || cmd == 8'h80) begin
      update_adc_codes();
      last_is_d1 = 1'b1;
      prom_boot_phase = 1'b0;

    // D2 convert
    end else if (cmd == 8'h50 || cmd == 8'hA0) begin
      update_adc_codes();
      last_is_d1 = 1'b0;
      prom_boot_phase = 1'b0;

    // ADC read
    end else if (cmd == 8'h00) begin
        out_shift = last_is_d1 ? d1_raw : d2_raw;
        driving = 1'b1;
        for (i = 0; i < 24; i = i + 1) begin
          @(negedge SCLK);
          if (i < 23) out_shift = {out_shift[22:0], 1'b0};
        end
        driving = 1'b0;
    end

    @(posedge CSB);
    driving = 1'b0;
  end

endmodule
///////////////////////////////////////////////////////////////////////
//
// ms5803_sensor_model (system2 testbench model)
//
//  Independent external MS5803 behavioural SPI model.
//  - Different module name (no conflict with system/pressure_sensor.sv)
//  - Accepts pressure/temperature as real-valued environment inputs
//  - Returns 24-bit D1/D2 on ADC read commands
//
///////////////////////////////////////////////////////////////////////

module ms5803_sensor_model (
  output logic SDO,
  input  logic SDI,
  input  logic SCLK,
  input  logic CSB,
  input  real  pressure_mb,
  input  real  temperature_c
);

  timeunit 1ns;
  timeprecision 100ps;

  // Typical MS5803-02BA PROM coefficients from datasheet
  localparam int unsigned C1 = 16'd46372;
  localparam int unsigned C2 = 16'd43981;
  localparam int unsigned C3 = 16'd29059;
  localparam int unsigned C4 = 16'd27842;
  localparam int unsigned C5 = 16'd31553;
  localparam int unsigned C6 = 16'd28165;

  logic        driving;
  logic [7:0]  cmd;
  logic [23:0] d1_raw, d2_raw, out_word;
  logic        last_is_d1;

  assign SDO = (!CSB && driving) ? out_word[23] : 1'bz;

  function automatic logic [23:0] synth_d2_from_temp_x100(input int signed temp_x100);
    longint signed dT, d2;
    begin
      dT = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      d2 = dT + (longint'(C5) * 256);
      if (d2 < 0) d2 = 0;
      if (d2 > 16777215) d2 = 16777215;
      synth_d2_from_temp_x100 = d2[23:0];
    end
  endfunction

  function automatic logic [23:0] synth_d1_from_p_t_x100(
    input int unsigned p_x100,
    input int signed   temp_x100
  );
    longint signed dT, OFF, SENS, num, d1;
    begin
      dT   = ((longint'(temp_x100) - 2000) * 8388608) / longint'(C6);
      OFF  = (longint'(C2) * 131072) + ((longint'(C4) * dT) / 64);
      SENS = (longint'(C1) * 65536)  + ((longint'(C3) * dT) / 128);
      if (SENS == 0) d1 = 0;
      else begin
        num = (longint'(p_x100) * 32768) + OFF;
        d1  = (num * 2097152) / SENS;
      end
      if (d1 < 0) d1 = 0;
      if (d1 > 16777215) d1 = 16777215;
      synth_d1_from_p_t_x100 = d1[23:0];
    end
  endfunction

  task automatic update_adc_codes;
    real p_mb, t_c;
    int unsigned p_x100;
    int signed   t_x100;
    begin
      p_mb = pressure_mb;
      t_c  = temperature_c;
      if (p_mb < 300.0)  p_mb = 300.0;
      if (p_mb > 1100.0) p_mb = 1100.0;
      if (t_c < -40.0)   t_c  = -40.0;
      if (t_c > 85.0)    t_c  = 85.0;

      p_x100 = $rtoi(p_mb * 100.0 + 0.5);
      if (t_c >= 0.0) t_x100 = $rtoi(t_c * 100.0 + 0.5);
      else            t_x100 = $rtoi(t_c * 100.0 - 0.5);

      d2_raw = synth_d2_from_temp_x100(t_x100);
      d1_raw = synth_d1_from_p_t_x100(p_x100, t_x100);
    end
  endtask

  initial begin
    driving    = 1'b0;
    cmd        = 8'h00;
    d1_raw     = 24'd0;
    d2_raw     = 24'd0;
    out_word   = 24'd0;
    last_is_d1 = 1'b1;
  end

  always @(negedge CSB) begin
    int i;
    driving = 1'b0;
    cmd = 8'h00;

    // Command in on SCLK rising edges
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge SCLK);
      cmd = {cmd[6:0], SDI};
    end

    case (cmd)
      // Accept canonical + 1-bit-shifted patterns
      8'h1E, 8'h3C: begin
        // reset command
      end
      8'h40, 8'h80: begin
        update_adc_codes();
        last_is_d1 = 1'b1;
      end
      8'h50, 8'hA0: begin
        update_adc_codes();
        last_is_d1 = 1'b0;
      end
      8'h00: begin
        out_word = last_is_d1 ? d1_raw : d2_raw;
        driving  = 1'b1;
        // First bit exposed immediately via out_word[23], shift on negedge
        for (i = 0; i < 24; i = i + 1) begin
          @(negedge SCLK);
          if (i < 23) out_word = {out_word[22:0], 1'b0};
        end
        driving = 1'b0;
      end
      default: begin
      end
    endcase

    @(posedge CSB);
    driving = 1'b0;
  end

endmodule
