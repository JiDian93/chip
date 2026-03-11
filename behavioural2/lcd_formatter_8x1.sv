//==============================================================
// lcd_formatter_8x1.sv
//  Generic "digit/char slot -> ASCII stream -> LCD module" formatter and pusher
//
//  - Fits existing LCD interface: ascii_in + ascii_valid
//  - 8 display slots (8x1 LCD)
//  - Each slot: BCD digit (0~9) or direct ASCII
//
//  Usage (e.g. rain ddd.ddmm) see weather_rain_lcd_top at end of file
//==============================================================

timeunit 1ns;
timeprecision 100ps;

module lcd_formatter_8x1 #(
    parameter int CLK_HZ = 32768,
    parameter int COLS   = 8,
    parameter int CHAR_PERIOD_MS = 2   // Inter-character send interval (ms), suggest 1~5ms
)(
    input  logic clk,
    input  logic rst_n,

    // LCD ready signal: formatter waits until LCD initialization is complete
    input  logic lcd_ready,

    // Per-slot 2bit type: 00=BCD_DIGIT, 01=ASCII
    input  logic [1:0] slot_type [COLS],
    // Per-slot 8bit data: BCD uses low 4 bits only; ASCII uses full 8 bits
    input  logic [7:0] slot_data [COLS],

    output logic [7:0] ascii_out,
    output logic       ascii_valid
);

    // Character send tick: once every CHAR_PERIOD_MS ms
    localparam int CHAR_PERIOD_CYC = (CLK_HZ * CHAR_PERIOD_MS) / 1000;
    localparam int TICK_W = (CHAR_PERIOD_CYC <= 1) ? 1 : $clog2(CHAR_PERIOD_CYC + 1);

    logic [TICK_W-1:0] tick_cnt;
    logic tick;

    assign tick = (tick_cnt == '0);

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tick_cnt <= (CHAR_PERIOD_CYC[TICK_W-1:0] == '0) ? '0 : CHAR_PERIOD_CYC[TICK_W-1:0];
        end else begin
            if(CHAR_PERIOD_CYC <= 1) begin
                tick_cnt <= '0; // Tick every clock (not recommended; avoids div-by-zero/width issues)
            end else begin
                if(tick_cnt != 0) tick_cnt <= tick_cnt - 1'b1;
                else              tick_cnt <= CHAR_PERIOD_CYC[TICK_W-1:0];
            end
        end
    end

    // Current output column index
    localparam int IDX_W = (COLS <= 2) ? 1 : $clog2(COLS);
    logic [IDX_W-1:0] idx;

    // BCD to ASCII
    function automatic logic [7:0] bcd_to_ascii(input logic [3:0] bcd);
        if(bcd <= 4'd9) bcd_to_ascii = 8'd48 + bcd; // '0' + bcd
        else            bcd_to_ascii = 8'h3F;       // '?'
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            idx         <= '0;
            ascii_out   <= 8'h20; // space
            ascii_valid <= 1'b0;
        end else begin
            ascii_valid <= 1'b0;

            // Only start sending when LCD is ready (initialization complete)
            if(lcd_ready && tick) begin
                unique case(slot_type[idx])
                    2'b00: ascii_out <= bcd_to_ascii(slot_data[idx][3:0]); // BCD digit
                    2'b01: ascii_out <= slot_data[idx];                    // direct ASCII
                    default: ascii_out <= 8'h20;                           // space
                endcase
                ascii_valid <= 1'b1;

                if(idx == COLS-1) idx <= '0;
                else              idx <= idx + 1'b1;
            end
        end
    end

endmodule
