// This special stimulus simulates a short lived storm
//
// 覆盖所有模式：总雨量、瞬时风速、风向、累计时间、当前时间。
// 在 handin 版本基础上扩展雨量与模式切换，同时保持原有风速 / 气压 / 温度波形。

  reg [7:0] expected_wind [0:2];
  reg [7:0] lcd_buf  [0:7];
  reg [7:0] lcd_prev [0:7];
  integer   lcd_pos;
  integer   k;

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


  // ================================================================
  // 风速刺激（沿用 handin 行为）
  // ================================================================

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


  // ================================================================
  // 其他气象刺激（扩展 handin：加上 16 方位扫描）
  // ================================================================

  initial
    begin
      Rain              = 0;
      SENSOR.pressure   = 1002;
      SENSOR.temperature= 10.0;
      VANE.WindDirection= S; // wind is from the South
      start_up_delay();

      // temperature drops
      while (SENSOR.temperature > 8.5)
        #1.5s SENSOR.temperature = SENSOR.temperature - 0.25;

      // wind changes direction (粗粒度)
      #0.8s VANE.WindDirection = SSW;
      #0.8s VANE.WindDirection = SW;
      #0.8s VANE.WindDirection = W;
      #0.8s VANE.WindDirection = NW;

      // 细粒度：16 个方向扫描并驱动 expected_wind，用于 LCD 校验
      expected_wind[0]=8'h20; expected_wind[1]=8'h20; expected_wind[2]="N";
      $display("  [set] N");
      VANE.WindDirection = N;
      #2500ms expected_wind[0]="N"; expected_wind[1]="N"; expected_wind[2]="E"; VANE.WindDirection = NNE; $display("  [set] NNE");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]="N"; expected_wind[2]="E"; VANE.WindDirection = NE;  $display("  [set] NE");
      #2500ms expected_wind[0]="E"; expected_wind[1]="N"; expected_wind[2]="E"; VANE.WindDirection = ENE; $display("  [set] ENE");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]=8'h20; expected_wind[2]="E"; VANE.WindDirection = E;   $display("  [set] E");
      #2500ms expected_wind[0]="E"; expected_wind[1]="S"; expected_wind[2]="E"; VANE.WindDirection = ESE; $display("  [set] ESE");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]="S"; expected_wind[2]="E"; VANE.WindDirection = SE;  $display("  [set] SE");
      #2500ms expected_wind[0]="S"; expected_wind[1]="S"; expected_wind[2]="E"; VANE.WindDirection = SSE; $display("  [set] SSE");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]=8'h20; expected_wind[2]="S"; VANE.WindDirection = S;   $display("  [set] S");
      #2500ms expected_wind[0]="S"; expected_wind[1]="S"; expected_wind[2]="W"; VANE.WindDirection = SSW; $display("  [set] SSW");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]="S"; expected_wind[2]="W"; VANE.WindDirection = SW;  $display("  [set] SW");
      #2500ms expected_wind[0]="W"; expected_wind[1]="S"; expected_wind[2]="W"; VANE.WindDirection = WSW; $display("  [set] WSW");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]=8'h20; expected_wind[2]="W"; VANE.WindDirection = W;   $display("  [set] W");
      #2500ms expected_wind[0]="W"; expected_wind[1]="N"; expected_wind[2]="W"; VANE.WindDirection = WNW; $display("  [set] WNW");
      #2500ms expected_wind[0]=8'h20; expected_wind[1]="N"; expected_wind[2]="W"; VANE.WindDirection = NW;  $display("  [set] NW");
      #2500ms expected_wind[0]="N"; expected_wind[1]="N"; expected_wind[2]="W"; VANE.WindDirection = NNW; $display("  [set] NNW");

      // very rapid drop in pressure
      while (SENSOR.pressure > 998.0)
        #5s SENSOR.pressure = SENSOR.pressure - 0.25;

      // rain storm (用作总雨量测试的一部分)
      repeat (20)
        #5s -> trigger_rain_sensor;

      // pressure returns to previous value
      while (SENSOR.pressure < 1002)
        #10s SENSOR.pressure = SENSOR.pressure + 0.25;

      // allow time for display to catch up
      #1s;
    end


  // ================================================================
  // 额外雨量刺激：更长时间的轻 / 中雨，用于 TotalRainfall 覆盖
  // ================================================================

  initial
    begin
      start_up_delay();
      // 轻雨：每 4s 一次
      repeat (10)
        #4s -> trigger_rain_sensor;

      // 中雨：每 1s 一次
      repeat (20)
        #1s -> trigger_rain_sensor;
    end


  // ================================================================
  // 按键刺激：遍历所有 5 个模式，并在雨量 / 时间模式下使用 Start/Adjust 清零
  // ================================================================

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
      #15s;

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
      // 保持在当前时间模式，直到 sim_time 结束
    end


  // ================================================================
  // 时钟 / 复位 / 扫描链：与 handin 一致
  // ================================================================

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

