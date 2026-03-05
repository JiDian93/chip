//==============================================================
// anemometer.sv
//  - Cup anemometer switch -> instantaneous wind speed
//  - 1.492 mph produces 1 closure per second (1 Hz)
//  - Output as 8 ASCII chars to your lcd module:
//      " DD.Dm/s"  (8 chars)
//      Example: 5.3 m/s -> " 05.3m/s"
//==============================================================
module anemometer #(
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
