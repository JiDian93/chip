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

//==========================================================
// LCD 显示：8x1 字符 LCD，显示格式 ddd.ddmm
//==========================================================

localparam int LCD_COLS = 8;

// 槽位类型与数据
//  slot_type: 00 = BCD digit, 01 = ASCII
logic [1:0] lcd_slot_type [LCD_COLS];
logic [7:0] lcd_slot_data [LCD_COLS];

// formatter → HD44780 LCD 的 ASCII 流
logic [7:0] lcd_ascii;
logic       lcd_ascii_valid;

// lcd 内部信号
logic [7:0] lcd_data;
logic       lcd_rs;
logic       lcd_rw;
logic       lcd_en;

// 组合逻辑：把雨量 BCD 数码映射到 8 个槽位
// 第 1 位: rain_hundreds_bcd
// 第 2 位: rain_tens_bcd
// 第 3 位: rain_units_bcd
// 第 4 位: 小数点 '.'
// 第 5 位: rain_tenths_bcd
// 第 6 位: rain_hundredths_bcd
// 第 7 位: 'm'
// 第 8 位: 'm'
integer i;

always_comb begin
  // 默认：空格 ASCII
  for(i = 0; i < LCD_COLS; i++) begin
    lcd_slot_type[i] = 2'b01;
    lcd_slot_data[i] = 8'h20;
  end

  // BCD 数字槽位
  lcd_slot_type[0] = 2'b00;
  lcd_slot_data[0] = {4'b0000, rain_hundreds_bcd};

  lcd_slot_type[1] = 2'b00;
  lcd_slot_data[1] = {4'b0000, rain_tens_bcd};

  lcd_slot_type[2] = 2'b00;
  lcd_slot_data[2] = {4'b0000, rain_units_bcd};

  lcd_slot_type[4] = 2'b00;
  lcd_slot_data[4] = {4'b0000, rain_tenths_bcd};

  lcd_slot_type[5] = 2'b00;
  lcd_slot_data[5] = {4'b0000, rain_hundredths_bcd};

  // 小数点 '.'
  lcd_slot_type[3] = 2'b01;
  lcd_slot_data[3] = 8'h2E;

  // 单位 "mm"
  lcd_slot_type[6] = 2'b01;
  lcd_slot_data[6] = "m";

  lcd_slot_type[7] = 2'b01;
  lcd_slot_data[7] = "m";
end

// 槽位 → ASCII 流
lcd_formatter_8x1 #(
  .CLK_HZ(32768),
  .COLS(LCD_COLS),
  .CHAR_PERIOD_MS(2)
) u_lcd_formatter_8x1 (
  .clk        (Clock),
  .rst_n      (nReset),
  .slot_type  (lcd_slot_type),
  .slot_data  (lcd_slot_data),
  .ascii_out  (lcd_ascii),
  .ascii_valid(lcd_ascii_valid)
);

// ASCII 流 → HD44780 LCD 时序
lcd #(
  .CLK_HZ(32768),
  .COLS  (LCD_COLS)
) u_lcd (
  .clk        (Clock),
  .rst_n      (nReset),
  .ascii_in   (lcd_ascii),
  .ascii_valid(lcd_ascii_valid),
  .lcd_data   (lcd_data),
  .lcd_rs     (lcd_rs),
  .lcd_rw     (lcd_rw),
  .lcd_e      (lcd_en)
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

assign RS  = lcd_rs;
assign RnW = lcd_rw;      // 当前设计只写入（lcd_rw 恒为 0）
assign En  = lcd_en;

assign DB_Out     = lcd_data;
assign DB_nEnable = 1'b0; // 始终驱动数据总线




endmodule
