// This special stimulus simulates a short lived storm
//

  reg [7:0] expected_wind [0:2];
  reg [7:0] lcd_buf  [0:7];
  reg [7:0] lcd_prev [0:7];
  wire      BARO_SDO;
  wire      BARO_DRIVE;
  integer   lcd_pos;
  integer   k;
  integer   wind_wait_i;
  reg       wind_seen;

  task automatic set_wind_and_expect(
    input compass_t dir,
    input [7:0] exp0,
    input [7:0] exp1,
    input [7:0] exp2,
    input [8*4-1:0] tag
  );
    begin
      expected_wind[0] = exp0;
      expected_wind[1] = exp1;
      expected_wind[2] = exp2;
      VANE.WindDirection = dir;
      $display("  [set] %0s", tag);

      wind_seen = 1'b0;
      for (wind_wait_i = 0; wind_wait_i < 30; wind_wait_i = wind_wait_i + 1) begin
        #100ms;
        if (STATION.CORE.winddir_slot_data[5] == expected_wind[0] &&
            STATION.CORE.winddir_slot_data[6] == expected_wind[1] &&
            STATION.CORE.winddir_slot_data[7] == expected_wind[2]) begin
          wind_seen = 1'b1;
          wind_wait_i = 30;
        end
      end

      if (wind_seen) begin
        $display("  [ok ] %0s -> %c%c%c",
                 tag,
                 STATION.CORE.winddir_slot_data[5],
                 STATION.CORE.winddir_slot_data[6],
                 STATION.CORE.winddir_slot_data[7]);
      end else begin
        $error("WindDirection LCD mismatch for %0s: got %c%c%c expected %c%c%c",
               tag,
               STATION.CORE.winddir_slot_data[5], STATION.CORE.winddir_slot_data[6], STATION.CORE.winddir_slot_data[7],
               expected_wind[0], expected_wind[1], expected_wind[2]);
      end
    end
  endtask

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

  initial begin
    lcd_pos = 0;
    for (k = 0; k < 8; k = k + 1)
      lcd_prev[k] = 8'h20;
  end

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
      Wind = 0;
      start_up_delay();

      repeat (5)
        #4s -> trigger_wind_sensor;

      // wind gets stronger
      repeat (250)
        #0.3s -> trigger_wind_sensor;

      // gust
      repeat (40)
        #0.1s -> trigger_wind_sensor;

      // wind continues strong
      repeat (100)
        #0.3s -> trigger_wind_sensor;

      // lull
      repeat (4)
        #8s -> trigger_wind_sensor;

      // wind continues strong
      repeat (400)
        #0.3s -> trigger_wind_sensor;

      // wind returns to pre-storm speed
      forever
        #4s -> trigger_wind_sensor;

    end


  initial
    begin
      Rain              = 0;
      SENSOR.pressure   = 1011;
      SENSOR.temperature= 10.0;
      VANE.WindDirection= S; // wind is from the South
      start_up_delay();

      // temperature drops
      while (SENSOR.temperature > 8.5)
        #1.5s SENSOR.temperature = SENSOR.temperature - 0.25;

      // wind changes direction 
      #0.8s VANE.WindDirection = SSW;
      #0.8s VANE.WindDirection = SW;
      #0.8s VANE.WindDirection = W;
      #0.8s VANE.WindDirection = NW;

      wait (mode_index == 2);
      set_wind_and_expect(N,   8'h20, 8'h20, "N",   "N");
      set_wind_and_expect(NNE, "N",   "N",   "E",   "NNE");
      set_wind_and_expect(NE,  8'h20, "N",   "E",   "NE");
      set_wind_and_expect(ENE, "E",   "N",   "E",   "ENE");
      set_wind_and_expect(E,   8'h20, 8'h20, "E",   "E");
      set_wind_and_expect(ESE, "E",   "S",   "E",   "ESE");
      set_wind_and_expect(SE,  8'h20, "S",   "E",   "SE");
      set_wind_and_expect(SSE, "S",   "S",   "E",   "SSE");
      set_wind_and_expect(S,   8'h20, 8'h20, "S",   "S");
      set_wind_and_expect(SSW, "S",   "S",   "W",   "SSW");
      set_wind_and_expect(SW,  8'h20, "S",   "W",   "SW");
      set_wind_and_expect(WSW, "W",   "S",   "W",   "WSW");
      set_wind_and_expect(W,   8'h20, 8'h20, "W",   "W");
      set_wind_and_expect(WNW, "W",   "N",   "W",   "WNW");
      set_wind_and_expect(NW,  8'h20, "N",   "W",   "NW");
      set_wind_and_expect(NNW, "N",   "N",   "W",   "NNW");

      // very rapid drop in pressure: 1011 -> 998
      while (SENSOR.pressure > 998.0)
        #5s SENSOR.pressure = SENSOR.pressure - 0.25;

      repeat (20)
        #5s -> trigger_rain_sensor;

      // pressure returns to previous (high) value: 998 -> 1011
      while (SENSOR.pressure < 1011.0)
        #10s SENSOR.pressure = SENSOR.pressure + 0.25;

      // allow time for display to catch up
      #1s;
    end


  initial
    begin
      start_up_delay();
      repeat (10)
        #4s -> trigger_rain_sensor;

      repeat (20)
        #1s -> trigger_rain_sensor;
    end


  initial
    begin
      Mode       = 0;
      Start      = 0;
      mode_index = 0;

      start_up_delay();

      // Mode 0: Total Rainfall
      $display("-- Mode 0: Total Rainfall --");
      #10s;
      $display("-- Clear rainfall via Start/Adjust --");
      -> press_trip_button;
      #10s;

      // Mode 1: Instantaneous Wind Speed
      $display("-- Mode 1: Instantaneous Wind Speed --");
      -> press_mode_button;
      #15s;

      // Mode 2: Wind Direction
      $display("-- Mode 2: Wind Direction --");
      -> press_mode_button;
      // Wind-direction sweep applies 16 setpoints with 2.5s spacing (~37.5s total),
      // so keep mode 2 active long enough for LCD to show each one.
      #45s;

      // Mode 3: Elapsed Time
      $display("-- Mode 3: Elapsed Time --");
      -> press_mode_button;
      #10s;
      $display("-- Clear elapsed time via Start/Adjust --");
      -> press_trip_button;
      #5s;

      // Mode 4: Time of Day
      $display("-- Mode 4: Time of Day --");
      -> press_mode_button;
      #10s;

      // Mode 5: Pressure
      $display("-- Mode 5: Pressure --");
      -> press_mode_button;
      #10s;

      // Mode 6: Temperature
      $display("-- Mode 6: Temperature --");
      -> press_mode_button;
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
