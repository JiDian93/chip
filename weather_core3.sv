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

  // 时间计数器的 BCD 输出 
  logic [3:0] min_tens, min_units;
  logic [3:0] sec_tens, sec_units;

    // 内部连线信号
  logic tick_1kHz, tick_1Hz;
  logic [2:0] display_mode;
  logic nClear_rain; 
  logic nClear_time; 

    // 1. 分频器 (提供 1kHz 和 1Hz 脉冲)
  clock_divider DIV (
    .Clock(Clock),
    .nReset(nReset),
    .Demo(Demo),
    .tick_1kHz(tick_1kHz),
    .tick_1Hz(tick_1Hz)
  );

  // 2. 主状态机 (控制模式与清零)
  main_fsm FSM (
    .Clock(Clock),
    .nReset(nReset),
    .tick_1kHz(tick_1kHz),
    .nMode(nMode),
    .nStart(nStart),
    .display_mode(display_mode),
    .nClear_rain(nClear_rain),
    .nClear_time(nClear_time)
  );

    // 3. 时间计数器 (由 FSM 的 nClear_time 信号控制)
  time_counters TIMER (
    .Clock(Clock),
    .nReset(nReset),
    .tick_1Hz(tick_1Hz),
    .nClear_time(nClear_time),
    .min_tens(min_tens),
    .min_units(min_units),
    .sec_tens(sec_tens),
    .sec_units(sec_units)
  );


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
