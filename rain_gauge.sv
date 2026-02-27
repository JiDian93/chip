///////////////////////////////////////////////////////////////////////
//
// rain_gauge module
//
//  从 nRain 脉冲统计总降雨量，并输出 ddd.dd mm 形式的 BCD 数码
//
///////////////////////////////////////////////////////////////////////

module rain_gauge(

  input  logic Clock,
  input  logic nReset,

  // Start/Adjust 按键（低有效），用于清零总降雨量
  input  logic nStart,

  // 雨量传感器输入脉冲（低有效）
  input  logic nRain,

  // 累计的脉冲个数
  output logic [15:0] total_rain_pulses,

  // ddd.dd mm 形式的 5 个 BCD 数码：整数部分 3 位 + 小数部分 2 位
  output logic [3:0] rain_hundreds_bcd,
  output logic [3:0] rain_tens_bcd,
  output logic [3:0] rain_units_bcd,
  output logic [3:0] rain_tenths_bcd,
  output logic [3:0] rain_hundredths_bcd

  );

timeunit 1ns;
timeprecision 100ps;

// 记录上一拍的 nRain，用于边沿检测
logic prev_nRain;

// 中间计算用：以 0.01mm 为单位的总雨量 (mm*100)
int unsigned rain_01mm;
int unsigned value_01mm;

// 统计 nRain 脉冲个数；nReset 为异步清零，Start/Adjust (nStart) 为同步清零
always_ff @( posedge Clock, negedge nReset )
  if ( ! nReset )
    begin
      total_rain_pulses <= '0;
      prev_nRain        <= 1'b1;
    end
  else
    begin
      // 同步记录上一拍的 nRain
      prev_nRain <= nRain;

      // Start/Adjust 按键同步清零总降雨量计数
      if ( ! nStart )
        begin
          total_rain_pulses <= '0;
        end
      // 检测 nRain 的下降沿（从 1 变为 0 视为一次脉冲）
      else if ( prev_nRain && ! nRain )
        begin
          total_rain_pulses <= total_rain_pulses + 1'b1;
        end
    end

// 将脉冲数换算成 ddd.dd mm 形式所需的 5 个 BCD 数码
// 1 脉冲 = 0.28mm = 28 × 0.01mm
// rain_01mm 范围限制在 0 ～ 999.99mm 之间，对应 0 ～ 99999 (mm*100)
always_comb
  begin
    // 以 0.01mm 为单位计算雨量
    rain_01mm = total_rain_pulses * 28;

    // 饱和到 999.99mm
    if ( rain_01mm > 99999 )
      rain_01mm = 99999;

    value_01mm = rain_01mm;

    // 小数第二位 (0.01mm)
    rain_hundredths_bcd = value_01mm % 10;
    value_01mm          = value_01mm / 10;

    // 小数第一位 (0.1mm)
    rain_tenths_bcd = value_01mm % 10;
    value_01mm      = value_01mm / 10;

    // 个位
    rain_units_bcd = value_01mm % 10;
    value_01mm     = value_01mm / 10;

    // 十位
    rain_tens_bcd = value_01mm % 10;
    value_01mm    = value_01mm / 10;

    // 百位
    rain_hundreds_bcd = value_01mm % 10;
  end

endmodule

