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

