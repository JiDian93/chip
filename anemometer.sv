​//==============================================================
// anemometer.sv
//  - Cup anemometer switch -> instantaneous wind speed (m/s)
//  - 1.492 mph produces 1 closure per second (1 Hz)
//  - Output to lcd_formatter_8x1 as 8 slots:
//      " DD.Dm/s" (8 chars)
//==============================================================

module anemometer #(
    parameter int unsigned CLK_HZ     = 32768,
    parameter int unsigned COLS       = 8,

    // If no pulse for TIMEOUT_S seconds -> show 0.0
    parameter int unsigned TIMEOUT_S  = 2
)(
    input  logic clk,
    input  logic rst_n,

    // raw anemometer switch/contact closure
    input  logic anemo_sw,

    // to lcd_formatter_8x1
    output logic [1:0] slot_type [COLS], // 00=BCD_DIGIT, 01=ASCII
    output logic [7:0] slot_data [COLS], // BCD uses low 4 bits; ASCII uses full 8 bits

    // optional numeric output for other logic/debug
    output logic [15:0] wind_tenths       // 0.1 m/s units (e.g. 53 => 5.3 m/s)
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

    // rising edge counts one closure event
    wire sw_rise = sw_ff1 & ~sw_ff2;

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

            if(sw_rise) begin
                last_period_cyc <= (cyc_since_last == 0) ? 32'd1 : cyc_since_last;
                cyc_since_last  <= 32'd0;
                have_period     <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------
    // 3) Convert to wind speed (m/s) in tenths
    //
    // Given: 1 Hz => 1.492 mph
    // mph -> m/s: 1 mph = 0.44704 m/s
    // => 1 Hz => 1.492*0.44704 ≈ 0.666... m/s
    //
    // tenths(m/s) = (m/s)*10 ≈ 6.67 * Hz
    // Hz = CLK_HZ / period_cycles
    // wind_tenths ≈ (667*CLK_HZ) / (100*period)
    // (with rounding, clamp to 99.9 => 999 tenths)
    // ----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wind_tenths <= 16'd0;
        end else begin
            if(cyc_since_last >= TIMEOUT_CYC) begin
                wind_tenths <= 16'd0;
            end else if(have_period) begin
                logic [63:0] num, den, q;

                num = 64'(667) * 64'(CLK_HZ);
                den = 64'(100) * 64'(last_period_cyc);

                if(den == 0) begin
                    wind_tenths <= 16'd0;
                end else begin
                    q = (num + (den >> 1)) / den; // rounded
                    if(q > 64'd999) wind_tenths <= 16'd999;
                    else            wind_tenths <= q[15:0];
                end
            end
        end
    end

    // ----------------------------------------------------------
    // 4) Split into BCD digits for " DD.D"
    //    wind_tenths: 0..999
    //      tens  = floor(v/100)
    //      ones  = floor(v/10) % 10
    //      tenths= v % 10
    // ----------------------------------------------------------
    logic [3:0] d_tens, d_ones, d_tenths;
    always_comb begin
        int unsigned v;
        v = wind_tenths;

        d_tens   = (v / 100) % 10;  // 0..9
        d_ones   = (v / 10)  % 10;  // 0..9
        d_tenths = (v % 10);        // 0..9
    end

    // ----------------------------------------------------------
    // 5) Build 8 slots: " DD.Dm/s"
    //    slot_type: 00=BCD, 01=ASCII
    // ----------------------------------------------------------
    always_comb begin
        // default all blanks
        for (int i=0; i<COLS; i++) begin
            slot_type[i] = 2'b01;
            slot_data[i] = 8'h20; // ' '
        end

        // " DD.Dm/s"
        slot_type[0] = 2'b01; slot_data[0] = 8'h20;       // leading blank
        slot_type[1] = 2'b00; slot_data[1] = {4'h0, d_tens};
        slot_type[2] = 2'b00; slot_data[2] = {4'h0, d_ones};
        slot_type[3] = 2'b01; slot_data[3] = 8'h2E;       // '.'
        slot_type[4] = 2'b00; slot_data[4] = {4'h0, d_tenths};
        slot_type[5] = 2'b01; slot_data[5] = "m";
        slot_type[6] = 2'b01; slot_data[6] = "/";
        slot_type[7] = 2'b01; slot_data[7] = "s";
    end

endmodule

Get Outlook for iOS
From: Jie Yin (jy1u25) <jy1u25@soton.ac.uk>
Sent: Thursday, March 5, 2026 2:50:06 PM
To: Jie Yin (jy1u25) <jy1u25@soton.ac.uk>
Subject: Re: Re:
 

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
From: Jie Yin (jy1u25) <jy1u25@soton.ac.uk>
Sent: Thursday, March 5, 2026 14:36
To: Jie Yin (jy1u25) <jy1u25@soton.ac.uk>
Subject: Re:
 
//==============================================================
// anemometer_to_lcd.sv
//  - Cup anemometer switch -> instantaneous wind speed
//  - 1.492 mph produces 1 closure per second (1 Hz)
//  - Output as 8 ASCII chars to your lcd module:
//      " DD.Dm/s"  (8 chars)
//      Example: 5.3 m/s -> " 05.3m/s"
//==============================================================
module anemometer_to_lcd #(
    parameter int unsigned CLK_HZ          = 32768,

    // If no pulse for this many seconds, wind speed -> 0.0
    parameter int unsigned TIMEOUT_S       = 2,

    // How often to refresh the display (Hz)
    parameter int unsigned REFRESH_HZ       = 2,

    // Gap between each character sent to lcd (cycles).
    // Must be safely larger than lcd's internal per-byte time.
    parameter int unsigned CHAR_GAP_CYC     = 200
)(
    input  wire       clk,
    input  wire       rst_n,

    // raw anemometer switch (contact closure)
    input  wire       anemo_sw,

    // connect to your lcd module
    output reg  [7:0] ascii_out,
    output reg        ascii_valid
);

    // ----------------------------------------------------------
    // 1) Sync + edge detect
    // ----------------------------------------------------------
    reg sw_ff1, sw_ff2;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sw_ff1 <= 1'b0;
            sw_ff2 <= 1'b0;
        end else begin
            sw_ff1 <= anemo_sw;
            sw_ff2 <= sw_ff1;
        end
    end

    wire sw_rise = (sw_ff1 & ~sw_ff2); // rising edge = one "closure event"

    // ----------------------------------------------------------
    // 2) Measure period between pulses (cycles)
    // ----------------------------------------------------------
    localparam int unsigned TIMEOUT_CYC = TIMEOUT_S * CLK_HZ;

    reg [31:0] cyc_since_last;   // running counter
    reg [31:0] last_period_cyc;  // captured period between pulses
    reg        have_period;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cyc_since_last <= 32'd0;
            last_period_cyc<= 32'd0;
            have_period    <= 1'b0;
        end else begin
            // free run with saturation
            if(cyc_since_last < 32'hFFFF_FFFF)
                cyc_since_last <= cyc_since_last + 1;

            if(sw_rise) begin
                // capture period (avoid zero)
                last_period_cyc <= (cyc_since_last == 0) ? 32'd1 : cyc_since_last;
                cyc_since_last  <= 32'd0;
                have_period     <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------
    // 3) Convert to wind speed (m/s) with 0.1 resolution
    //
    // Given: 1 Hz -> 1.492 mph
    // mph -> m/s: 1 mph = 0.44704 m/s
    // so 1 Hz -> 1.492 * 0.44704 = 0.666... m/s  (≈0.667)
    //
    // freq = CLK_HZ / period_cycles
    // mps  = 0.667 * freq
    // tenths(m/s) = mps * 10 = 6.67 * freq
    //            = (667/100) * (CLK_HZ / period)
    //            = (667 * CLK_HZ) / (100 * period)
    // ----------------------------------------------------------
    reg [15:0] wind_tenths;  // e.g. 53 means 5.3 m/s

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wind_tenths <= 16'd0;
        end else begin
            // timeout -> 0.0
            if(cyc_since_last >= TIMEOUT_CYC) begin
                wind_tenths <= 16'd0;
            end else if(have_period) begin
                // compute with rounding:
                // wind_tenths = (667*CLK_HZ) / (100*period)
                // rounding add denom/2
                logic [63:0] num;
                logic [63:0] den;
                logic [63:0] q;

                num = 64'(667) * 64'(CLK_HZ);
                den = 64'(100) * 64'(last_period_cyc);

                // avoid div by 0
                if(den == 0) begin
                    wind_tenths <= 16'd0;
                end else begin
                    q = (num + (den >> 1)) / den; // rounded
                    // clamp to 0..99.9 m/s -> 0..999 tenths (fits in 10 bits)
                    if(q > 64'd999) wind_tenths <= 16'd999;
                    else            wind_tenths <= q[15:0];
                end
            end
        end
    end

    // ----------------------------------------------------------
    // 4) Format into 8 ASCII chars: " DD.Dm/s"
    //    index: 0 1 2 3 4 5 6 7
    //           ' ' tens ones '.' tenths 'm' '/' 's'
    // ----------------------------------------------------------
    function automatic [7:0] to_ascii_digit(input int unsigned d);
        to_ascii_digit = 8'h30 + d[7:0];
    endfunction

    reg [7:0] disp [0:7];

    always_comb begin
        int unsigned tens, ones, tenths;
        int unsigned v;

        v      = wind_tenths;          // 0..999
        tens   = (v / 10) / 10;        // floor(v/100)
        ones   = (v / 10) % 10;        // floor(v/10)%10
        tenths = v % 10;

        disp[0] = 8'h20;               // leading blank
        disp[1] = to_ascii_digit(tens);
        disp[2] = to_ascii_digit(ones);
        disp[3] = 8'h2E;               // '.'
        disp[4] = to_ascii_digit(tenths);
        disp[5] = "m";
        disp[6] = "/";
        disp[7] = "s";
    end

    // ----------------------------------------------------------
    // 5) Send 8 chars to lcd safely (no FIFO/ready in lcd module)
    //    - Refresh at REFRESH_HZ
    //    - Between characters wait CHAR_GAP_CYC cycles
    // ----------------------------------------------------------
    localparam int unsigned REFRESH_CYC = (REFRESH_HZ == 0) ? CLK_HZ : (CLK_HZ / REFRESH_HZ);

    typedef enum logic [1:0] {TX_IDLE, TX_SEND, TX_GAP} tx_state_t;
    tx_state_t tx_state;

    reg [31:0] refresh_cnt;
    reg [31:0] gap_cnt;
    reg [2:0]  idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ascii_out   <= 8'h20;
            ascii_valid <= 1'b0;

            tx_state    <= TX_IDLE;
            refresh_cnt <= 32'd0;
            gap_cnt     <= 32'd0;
            idx         <= 3'd0;
        end else begin
            ascii_valid <= 1'b0; // default pulse low

            case(tx_state)
                TX_IDLE: begin
                    // count to next refresh
                    if(refresh_cnt >= (REFRESH_CYC-1)) begin
                        refresh_cnt <= 32'd0;
                        idx         <= 3'd0;
                        tx_state    <= TX_SEND;
                    end else begin
                        refresh_cnt <= refresh_cnt + 1;
                    end
                end

                TX_SEND: begin
                    ascii_out   <= disp[idx];
                    ascii_valid <= 1'b1;      // 1-cycle strobe
                    gap_cnt     <= 32'd0;
                    tx_state    <= TX_GAP;
                end

                TX_GAP: begin
                    if(gap_cnt >= (CHAR_GAP_CYC-1)) begin
                        if(idx == 3'd7) begin
                            tx_state <= TX_IDLE;
                        end else begin
                            idx      <= idx + 1;
                            tx_state <= TX_SEND;
                        end
                    end else begin
                        gap_cnt <= gap_cnt + 1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
