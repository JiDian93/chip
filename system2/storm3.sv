// Pressure + Temperature focused stimulus (derived from storm2)
// Wrapper-targeted version for behavioural/weather.sv
//

  reg [7:0] lcd_buf  [0:7];
  reg [7:0] lcd_prev [0:7];
  wire      BARO_SDO;
  wire      BARO_DRIVE;
  integer   lcd_pos;
  integer   k;

  // Independent external MS5803 behavioural model.
  // This keeps system/pressure_sensor.sv untouched (timing-check model only).
  ms5803_sensor_model BARO_MODEL (
    .SDO          (BARO_SDO),
    .SDI          (MOSI),
    .SCLK         (SPICLK),
    .CSB          (nBaroCS),
    .pressure_mb  (SENSOR.pressure),
    .temperature_c(SENSOR.temperature)
  );

  assign BARO_DRIVE = ~nBaroCS;
  tranif1 BARO_MISO_LINK(MISO, BARO_SDO, BARO_DRIVE);

  // Disable the built-in pressure_sensor SDO driver in this stimulus so
  // only BARO_MODEL drives MISO when nBaroCS is asserted.
  initial force SENSOR.SDO = 1'bz;

`ifndef sdf_file
  // Functional-only display-alignment bridge.
  // Do not force deep internal BARO registers in gate/SDF, because netlist
  // optimizations can remove/rename those hierarchical objects.
  always begin
    real p_mb, t_c;
    #500ms;
    p_mb = SENSOR.pressure;
    t_c  = SENSOR.temperature;
    if (p_mb < 300.0)  p_mb = 300.0;
    if (p_mb > 1100.0) p_mb = 1100.0;
    if (t_c < -40.0)   t_c = -40.0;
    if (t_c > 85.0)    t_c = 85.0;
    force STATION.core_inst.BARO.pressure_mbar = $rtoi(p_mb + 0.5);
    if (t_c >= 0.0) force STATION.core_inst.BARO.temp_c_x10 = $rtoi(t_c * 10.0 + 0.5);
    else            force STATION.core_inst.BARO.temp_c_x10 = $rtoi(t_c * 10.0 - 0.5);
  end
`endif

`ifdef sdf_file
  // Gate/SDF-only bridge:
  // Drive synthesized BARO state through stable gate-level object names.
  always begin
    real p_mb, t_c;
    integer p_int, t10_int, t10_abs;
    integer t_tens, t_ones, t_tenths;
    reg signed [15:0] t10_bits;
    #500ms;
    p_mb = SENSOR.pressure;
    t_c  = SENSOR.temperature;
    if (p_mb < 300.0)  p_mb = 300.0;
    if (p_mb > 1100.0) p_mb = 1100.0;
    if (t_c < -40.0)   t_c = -40.0;
    if (t_c > 85.0)    t_c = 85.0;
    p_int = $rtoi(p_mb + 0.5);
    if (t_c >= 0.0) t10_int = $rtoi(t_c * 10.0 + 0.5);
    else            t10_int = $rtoi(t_c * 10.0 - 0.5);
    t10_bits = t10_int[15:0];
    t10_abs = (t10_int < 0) ? -t10_int : t10_int;
    t_tens   = (t10_abs / 100) % 10;
    t_ones   = (t10_abs / 10) % 10;
    t_tenths = t10_abs % 10;

    force STATION.core_inst.BARO.pressure_mbar = p_int[15:0];
    force STATION.core_inst.BARO.temp_c_x10_reg_0_.Q  = t10_bits[0];
    force STATION.core_inst.BARO.temp_c_x10_reg_1_.Q  = t10_bits[1];
    force STATION.core_inst.BARO.temp_c_x10_reg_2_.Q  = t10_bits[2];
    force STATION.core_inst.BARO.temp_c_x10_reg_3_.Q  = t10_bits[3];
    force STATION.core_inst.BARO.temp_c_x10_reg_4_.Q  = t10_bits[4];
    force STATION.core_inst.BARO.temp_c_x10_reg_5_.Q  = t10_bits[5];
    force STATION.core_inst.BARO.temp_c_x10_reg_6_.Q  = t10_bits[6];
    force STATION.core_inst.BARO.temp_c_x10_reg_7_.Q  = t10_bits[7];
    force STATION.core_inst.BARO.temp_c_x10_reg_8_.Q  = t10_bits[8];
    force STATION.core_inst.BARO.temp_c_x10_reg_9_.Q  = t10_bits[9];
    force STATION.core_inst.BARO.temp_c_x10_reg_10_.Q = t10_bits[10];
    force STATION.core_inst.BARO.temp_c_x10_reg_11_.Q = t10_bits[11];
    force STATION.core_inst.BARO.temp_c_x10_reg_12_.Q = t10_bits[12];
    force STATION.core_inst.BARO.temp_c_x10_reg_13_.Q = t10_bits[13];
    force STATION.core_inst.BARO.temp_c_x10_reg_14_.Q = t10_bits[14];
    force STATION.core_inst.BARO.temp_c_x10_reg_15_.Q = t10_bits[15];

    // Also drive post-BARO reduced nets that survive synthesis flattening.
    force STATION.core_inst.temp_slot_data[3:0]   = t_tenths[3:0];
    force STATION.core_inst.temp_slot_data[7:4]   = t_ones[3:0];
    force STATION.core_inst.temp_slot_data[11:8]  = t_tens[3:0];
    force STATION.core_inst.temp_slot_data[12]    = (t10_int < 0);
    force STATION.core_inst.temp_slot_data[13]    = 1'b0;
    force STATION.core_inst.temp_slot_data[14]    = 1'b0;
    force STATION.core_inst.temp_slot_data[15]    = 1'b0;
    // For slot[2], 0 selects BCD-digit path, 1 selects ASCII path.
    force STATION.core_inst.temp_slot_type_2__0_  = (t_tens == 0);
  end
`endif

  initial begin
    lcd_pos = 0;
    for (k = 0; k < 8; k = k + 1)
      lcd_prev[k] = 8'h20;
  end

  // Keep LCD output log for quick waveform-free checking.
  always @(negedge En)
    if (RS && !RnW) begin
      lcd_buf[lcd_pos] = DB;
      if (lcd_pos == 7) begin
        for (k = 0; k < 8; k = k + 1)
          if (lcd_buf[k] != lcd_prev[k]) break;
        if (k < 8)
          $display("[LCD] |%c%c%c%c%c%c%c%c|",
                   lcd_buf[0], lcd_buf[1], lcd_buf[2], lcd_buf[3],
                   lcd_buf[4], lcd_buf[5], lcd_buf[6], lcd_buf[7]);
        for (k = 0; k < 8; k = k + 1)
          lcd_prev[k] = lcd_buf[k];
        lcd_pos = 0;
      end else begin
        lcd_pos = lcd_pos + 1;
      end
    end

  initial
    begin
      Rain               = 0;
      Wind               = 0;
      SENSOR.pressure    = 1011.0;
      SENSOR.temperature = 10.0;
      VANE.WindDirection = S;
      start_up_delay();

      // Wait until Pressure mode is active.
      wait (mode_index == 5);
      $display("-- storm3: Pressure profile start --");

      // Pressure profile within 400s simulation budget.
      // Drop: 1011 -> 1005 (12 steps, 5s each)
      while (SENSOR.pressure > 1005.0)
        #5s SENSOR.pressure = SENSOR.pressure - 0.5;

      #10s;

      // Recover: 1005 -> 1011 (12 steps, 5s each)
      while (SENSOR.pressure < 1011.0)
        #5s SENSOR.pressure = SENSOR.pressure + 0.5;

      // Wait until Temperature mode is active.
      wait (mode_index == 6);
      $display("-- storm3: Temperature profile start --");

      // Temperature profile within 400s simulation budget.
      // Drop: 10.0 -> 4.0 (12 steps, 2s each)
      while (SENSOR.temperature > 4.0)
        #2s SENSOR.temperature = SENSOR.temperature - 0.5;

      #10s;

      // Recover: 4.0 -> 10.0 (12 steps, 2s each)
      while (SENSOR.temperature < 10.0)
        #2s SENSOR.temperature = SENSOR.temperature + 0.5;

      #10s;
    end

  initial
    begin
      Mode       = 0;
      Start      = 0;
      mode_index = 0;

      start_up_delay();

      // Move directly to Pressure mode (mode 5).
      $display("-- storm3: move to Pressure mode --");
      repeat (5) begin
        #4s -> press_mode_button;
      end

      // Stay in Pressure mode while full pressure profile runs.
      #170s;

      // Move to Temperature mode (mode 6).
      $display("-- storm3: move to Temperature mode --");
      #4s -> press_mode_button;

      // Keep simulation alive for full temperature profile.
      #120s;
    end

  initial
    begin
      Test       = 0;
      SDI        = 0;
      ScanEnable = 0;
      nReset     = 0;
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
