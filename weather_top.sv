//==============================================================
// weather_top.sv
//  目标：让 weather_core 只负责“采集/计算并输出 BCD”，
//       显示链路由 top 统一完成：
//          weather_core (BCD) -> lcd_formatter_8x1 -> lcd -> LCD引脚
//
//  说明：
//  - 这个 top 不使用 weather_core 里那套 RS/RnW/En/DB_* LCD总线接口
//    （因为 weather_core 目前把它们固定为常量，且它本来就是“core”）
//  - 你需要工程中同时包含：weather_core.sv、rain_gauge.sv、lcd.sv、lcd_formatter_8x1.sv
//==============================================================

module weather_top #(
    parameter int CLK_HZ = 32768
)(
    // -------- 时钟复位 --------
    input  logic Clock,
    input  logic nReset,

    // -------- 用户输入/传感器输入 --------
    input  logic nMode,
    input  logic nStart,
    input  logic nRain,
    input  logic nWind,
    input  logic Demo,

    // -------- 风向ADC SPI（来自 weather_core 的行为模型/未来可替换为可综合SPI）--------
    output logic SPICLK,
    output logic nVaneCS,
    input  logic MISO,

    // -------- LCD 物理引脚（推荐用这一套简洁接口）--------
    output logic [7:0] lcd_data,
    output logic       lcd_rs,
    output logic       lcd_rw,
    output logic       lcd_e,

    // -------- 调试/观测输出（可选）--------
    output logic [15:0] total_rain_pulses
);

    //==========================================================
    // 1) 实例化 weather_core：只用它的“计算输出”（BCD 等）
    //==========================================================

    // weather_core 原本的 LCD 总线端口（本 top 不使用）
    logic core_RS, core_RnW, core_En;
    logic [7:0] core_DB_Out;
    logic core_DB_nEnable;
    logic [7:0] core_DB_In;

    // DB_In 在这个 top 里没有用途（因为不走 core 的 LCD 总线接口）
    assign core_DB_In = 8'h00;

    // weather_core 输出的雨量 BCD
    logic [3:0] rain_hundreds_bcd;
    logic [3:0] rain_tens_bcd;
    logic [3:0] rain_units_bcd;
    logic [3:0] rain_tenths_bcd;
    logic [3:0] rain_hundredths_bcd;

    weather_core u_core (
        // LCD（不使用，但必须连线以满足端口）
        .RS(core_RS),
        .RnW(core_RnW),
        .En(core_En),

        .DB_In(core_DB_In),
        .DB_Out(core_DB_Out),
        .DB_nEnable(core_DB_nEnable),

        // 输入
        .nMode(nMode),
        .nStart(nStart),
        .nRain(nRain),
        .nWind(nWind),

        // SPI
        .SPICLK(SPICLK),
        .nVaneCS(nVaneCS),
        .MISO(MISO),

        // 时钟复位/演示
        .Clock(Clock),
        .nReset(nReset),
        .Demo(Demo),

        // 雨量输出
        .total_rain_pulses(total_rain_pulses),
        .rain_hundreds_bcd(rain_hundreds_bcd),
        .rain_tens_bcd(rain_tens_bcd),
        .rain_units_bcd(rain_units_bcd),
        .rain_tenths_bcd(rain_tenths_bcd),
        .rain_hundredths_bcd(rain_hundredths_bcd)
    );

    //==========================================================
    // 2) 组织 8x1 LCD 的 8 个字符槽位：显示 "ddd.ddmm"
    //==========================================================
    localparam int COLS = 8;

    logic [1:0] slot_type [COLS];
    logic [7:0] slot_data [COLS];

    // slot_type: 00=BCD 数字, 01=直接 ASCII
    always_comb begin
        // 默认填空格
        for (int i = 0; i < COLS; i++) begin
            slot_type[i] = 2'b01;
            slot_data[i] = 8'h20; // ' '
        end

        // H T U . d1 d2 m m
        slot_type[0] = 2'b00; slot_data[0] = {4'b0, rain_hundreds_bcd};
        slot_type[1] = 2'b00; slot_data[1] = {4'b0, rain_tens_bcd};
        slot_type[2] = 2'b00; slot_data[2] = {4'b0, rain_units_bcd};

        slot_type[3] = 2'b01; slot_data[3] = 8'h2E; // '.'

        slot_type[4] = 2'b00; slot_data[4] = {4'b0, rain_tenths_bcd};
        slot_type[5] = 2'b00; slot_data[5] = {4'b0, rain_hundredths_bcd};

        slot_type[6] = 2'b01; slot_data[6] = 8'h6D; // 'm'
        slot_type[7] = 2'b01; slot_data[7] = 8'h6D; // 'm'
    end

    //==========================================================
    // 3) lcd_formatter_8x1：槽位 -> ASCII 流
    //==========================================================
    logic [7:0] ascii_out;
    logic       ascii_valid;

    lcd_formatter_8x1 #(
        .CLK_HZ(CLK_HZ),
        .COLS(COLS),
        .CHAR_PERIOD_MS(2)   // 每 2ms 推一个字符（可按需要改 1~5ms）
    ) u_fmt (
        .clk(Clock),
        .rst_n(nReset),
        .slot_type(slot_type),
        .slot_data(slot_data),
        .ascii_out(ascii_out),
        .ascii_valid(ascii_valid)
    );

    //==========================================================
    // 4) lcd：ASCII 流 -> LCD 时序与引脚
    //==========================================================
    lcd #(
        .CLK_HZ(CLK_HZ),
        .COLS(COLS)
    ) u_lcd (
        .clk(Clock),
        .rst_n(nReset),
        .ascii_in(ascii_out),
        .ascii_valid(ascii_valid),
        .lcd_data(lcd_data),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_e(lcd_e)
    );

endmodule
