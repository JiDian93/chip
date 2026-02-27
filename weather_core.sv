///////////////////////////////////////////////////////////////////////
//
// weather_core module
//
//    this is the behavioural model of the weather station without pads
//
///////////////////////////////////////////////////////////////////////

`include "options.sv"

module weather_core(

  output logic RS,
  output logic RnW,
  output logic En,

  input [7:0] DB_In,
  output logic [7:0] DB_Out,
  output logic DB_nEnable,

  input nMode, nStart,
  input nRain, nWind,

  output logic SPICLK, nVaneCS,
  input MISO,

  input Clock, nReset,
  input Demo,

  // 总降雨量（按 nRain 脉冲个数计）
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

// 雨量功能子模块：统计总降雨量，并给出 ddd.dd mm 形式的 BCD 数码
rain_gauge RAIN(
  .Clock,
  .nReset,
  .nStart,
  .nRain,
  .total_rain_pulses,
  .rain_hundreds_bcd,
  .rain_tens_bcd,
  .rain_units_bcd,
  .rain_tenths_bcd,
  .rain_hundredths_bcd
);

// this model sends a clock to the wind vane ADC
// but makes no attempt to interpret the data
// returned

always
  begin
    SPICLK = '1;
    nVaneCS = '1;
    
    #2s nVaneCS = '0;
    repeat(16)
      begin
             SPICLK = '1;
        #9ms SPICLK = '0;
        #9ms SPICLK = '1;
      end
    #9ms nVaneCS = '1;
  end

// this module makes no attempt to communicate with the LCD

assign RS = '0;
assign RnW = '1;
assign En = '0;

assign DB_Out = '0;
assign DB_nEnable = '1;




endmodule
