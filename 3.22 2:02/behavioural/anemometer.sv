//==============================================================
// anemometer.sv
//  - Cup anemometer switch -> instantaneous wind speed (m/s)
//  - 1.492 mph produces 1 closure per second (1 Hz)
//  - Output to lcd_formatter_8x1 as 8 slots:
//      " DD.Dm/s" (8 chars)
//==============================================================

`timescale 1ns/100ps

module anemometer #(
    parameter int unsigned CLK_HZ     = 32768,
    parameter int unsigned COLS       = 8,

    // If no pulse for TIMEOUT_S seconds -> show 0.0
    parameter int unsigned TIMEOUT_S  = 2,
    // Monostable debounce window after each accepted edge
    parameter int unsigned DEBOUNCE_MS = 25
)(
    input  logic clk,
    input  logic rst_n,

    // raw anemometer switch/contact closure
    input  logic anemo_sw,

    // to lcd_formatter_8x1
    output logic [1:0] slot_type [COLS], // 00=BCD_DIGIT, 01=ASCII
    output logic [7:0] slot_data [COLS], // BCD uses low 4 bits; ASCII uses full 8 bits

    // optional numeric output for other logic/debug (calibrated value)
    output logic [15:0] wind_tenths,     // 0.1 m/s units (e.g. 53 => 5.3 m/s)

    // Calibration (from main_fsm when in MODE_WIND_CALIB: in_calibration=1, is_rain_calib=0)
    input  logic       in_calibration,
    input  logic       is_rain_calib,
    input  logic [1:0] calib_digit_index,
    input  logic       calib_increment_pulse
);

    // ----------------------------------------------------------
    // 1) Sync + edge detect
    // ----------------------------------------------------------
    logic sw_ff1, sw_ff2;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sw_ff1 <= 1'b0;
            sw_ff2 <= 1'b0;
        end else begin
            sw_ff1 <= anemo_sw;
            sw_ff2 <= sw_ff1;
        end
    end

    // nWind/anemo switch is active-low: count falling edges (high -> low)
    wire sw_fall_raw = ~sw_ff1 & sw_ff2;

    // ----------------------------------------------------------
    // 1b) Monostable debounce (rain_gauge style)
    // ----------------------------------------------------------
    localparam int unsigned DEBOUNCE_CYC = (CLK_HZ * DEBOUNCE_MS) / 1000;
    logic [31:0] debounce_counter;
    logic        sw_fall;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            debounce_counter <= 32'd0;
            sw_fall          <= 1'b0;
        end else begin
            sw_fall <= 1'b0;
            if (debounce_counter != 32'd0)
                debounce_counter <= debounce_counter - 1'b1;
            else if (sw_fall_raw) begin
                sw_fall <= 1'b1;
                debounce_counter <= (DEBOUNCE_CYC == 0) ? 32'd1 : DEBOUNCE_CYC;
            end
        end
    end

    // ----------------------------------------------------------
    // 2) Measure period between pulses (in clk cycles)
    // ----------------------------------------------------------
    localparam int unsigned TIMEOUT_CYC = TIMEOUT_S * CLK_HZ;

    logic [31:0] cyc_since_last;
    logic [31:0] last_period_cyc;
    logic        have_period;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cyc_since_last  <= 32'd0;
            last_period_cyc <= 32'd0;
            have_period     <= 1'b0;
        end else begin
            if(cyc_since_last != 32'hFFFF_FFFF)
                cyc_since_last <= cyc_since_last + 1;

            if(sw_fall) begin
                last_period_cyc <= (cyc_since_last == 0) ? 32'd1 : cyc_since_last;
                cyc_since_last  <= 32'd0;
                have_period     <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------
    // 3) Convert to wind speed (m/s) in tenths (raw, before calibration)
    //
    // Given: 1 Hz => 1.492 mph => ~0.667 m/s
    // wind_tenths_raw ~= (667*CLK_HZ) / (100*period), clamp to 999
    // ----------------------------------------------------------
    logic [15:0] wind_tenths_raw;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wind_tenths_raw <= 16'd0;
        end else begin
            if(cyc_since_last >= TIMEOUT_CYC) begin
                wind_tenths_raw <= 16'd0;
            end else if(have_period) begin
                logic [63:0] num, den, q;

                num = 64'(667) * 64'(CLK_HZ);
                den = 64'(100) * 64'(last_period_cyc);

                if(den == 0) begin
                    wind_tenths_raw <= 16'd0;
                end else begin
                    q = (num + (den >> 1)) / den; // rounded
                    if(q > 64'd999) wind_tenths_raw <= 16'd999;
                    else            wind_tenths_raw <= q[15:0];
                end
            end
        end
    end

    // Calibration: multiplier 1000 = 1.0x, range 100..9999 (0.1x to 9.999x)
    // Edit is per-digit (9 -> 0) without carry into neighbouring digits; no lower-bound clamp.
    logic [15:0] wind_calib_mult;
    logic        wind_calib_active;
    assign wind_calib_active = in_calibration && !is_rain_calib;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wind_calib_mult <= 16'd1000;
        end else if(wind_calib_active && calib_increment_pulse) begin
            logic [3:0] d3, d2, d1, d0;
            logic [15:0] next_val;
            d3 = 4'(wind_calib_mult / 1000);
            d2 = 4'((wind_calib_mult / 100) % 10);
            d1 = 4'((wind_calib_mult / 10) % 10);
            d0 = 4'(wind_calib_mult % 10);
            unique case (calib_digit_index)
                2'd0: d0 = (d0 == 4'd9) ? 4'd0 : (d0 + 4'd1);
                2'd1: d1 = (d1 == 4'd9) ? 4'd0 : (d1 + 4'd1);
                2'd2: d2 = (d2 == 4'd9) ? 4'd0 : (d2 + 4'd1);
                default: d3 = (d3 == 4'd9) ? 4'd0 : (d3 + 4'd1);
            endcase
            next_val = d3 * 16'd1000 + d2 * 16'd100 + d1 * 16'd10 + d0;
            wind_calib_mult <= next_val;
        end
    end

    // Calibrated output: display = (raw * mult) / 1000, saturate to 999
    logic [15:0] wind_tenths_calib;
    always_comb begin
        logic [31:0] prod;
        prod = wind_tenths_raw * wind_calib_mult;
        wind_tenths_calib = (prod / 1000 > 32'd999) ? 16'd999 : 16'(prod / 1000);
    end
    assign wind_tenths = wind_tenths_calib;

    // ----------------------------------------------------------
    // 4) Split into BCD digits for " DD.D"
    //    wind_tenths: 0..999
    // ----------------------------------------------------------
    logic [3:0] d_tens, d_ones, d_tenths;
    always_comb begin
        int unsigned v;
        v = wind_tenths;
        d_tens   = (v / 100) % 10;
        d_ones   = (v / 10)  % 10;
        d_tenths = (v % 10);
    end

    // Calibration multiplier 4 BCD digits for LCD when in wind calib mode
    logic [3:0] wcalib_thousands, wcalib_hundreds, wcalib_tens, wcalib_units;
    always_comb begin
        wcalib_thousands = 4'(wind_calib_mult / 1000);
        wcalib_hundreds  = 4'((wind_calib_mult / 100) % 10);
        wcalib_tens      = 4'((wind_calib_mult / 10) % 10);
        wcalib_units     = 4'(wind_calib_mult % 10);
    end

    // ----------------------------------------------------------
    // 5) Build 8 slots: normal "DD.D m/s" or calib " ddd.d " (multiplier)
    // ----------------------------------------------------------
    always_comb begin
        for (int i=0; i<COLS; i++) begin
            slot_type[i] = 2'b01;
            slot_data[i] = 8'h20;
        end
        if (wind_calib_active) begin
            // Show calibration multiplier as " ddd.d " (e.g. " 1.035 ")
            slot_type[0] = 2'b01; slot_data[0] = 8'h20;
            slot_type[1] = 2'b00; slot_data[1] = {4'h0, wcalib_thousands};
            slot_type[2] = 2'b01; slot_data[2] = 8'h2E;
            slot_type[3] = 2'b00; slot_data[3] = {4'h0, wcalib_hundreds};
            slot_type[4] = 2'b00; slot_data[4] = {4'h0, wcalib_tens};
            slot_type[5] = 2'b00; slot_data[5] = {4'h0, wcalib_units};
            slot_type[6] = 2'b01; slot_data[6] = 8'h20;
            slot_type[7] = 2'b01; slot_data[7] = 8'h20;
        end else begin
            if (d_tens == 4'd0) begin
                slot_type[0] = 2'b01; slot_data[0] = 8'h20;
            end else begin
                slot_type[0] = 2'b00; slot_data[0] = {4'h0, d_tens};
            end
            slot_type[1] = 2'b00; slot_data[1] = {4'h0, d_ones};
            slot_type[2] = 2'b01; slot_data[2] = 8'h2E;
            slot_type[3] = 2'b00; slot_data[3] = {4'h0, d_tenths};
            slot_type[4] = 2'b01; slot_data[4] = 8'h20;
            slot_type[5] = 2'b01; slot_data[5] = "m";
            slot_type[6] = 2'b01; slot_data[6] = "/";
            slot_type[7] = 2'b01; slot_data[7] = "s";
        end
    end

endmodule