
//==============================================================
// lcd_hd44780_ascii_8bit_8x1.v
//  - 8-bit HD44780 LCD
//  - 8 columns, 1 line
//  - Receive external ASCII code and display
//==============================================================

timeunit 1ns;
timeprecision 100ps;

module lcd #(
    parameter integer CLK_HZ = 32768,
    parameter integer COLS   = 8   
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] ascii_in,
    input  wire       ascii_valid,   

    output reg  [7:0] lcd_data,
    output reg        lcd_rs,
    output wire       lcd_rw,
    output reg        lcd_e,

    output wire       lcd_init_done
);

assign lcd_rw = 1'b0;

localparam integer PWRON_WAIT_CYC = (CLK_HZ * 40) / 1000;
localparam integer WAIT_5MS_CYC   = (CLK_HZ * 5)  / 1000;
localparam integer WAIT_1MS_CYC   = (CLK_HZ * 1)  / 1000;
localparam integer WAIT_SHORT_CYC = 3;

//--------------------------------------------------------------
// FSM definition (placed at top to avoid forward reference errors)
//--------------------------------------------------------------
typedef enum logic [4:0] {
    S_RESET       = 5'd0,
    S_PWR_WAIT    = 5'd1,

    S_CMD_30_1    = 5'd2,  S_WAIT_30_1 = 5'd3,
    S_CMD_30_2    = 5'd4,  S_WAIT_30_2 = 5'd5,
    S_CMD_30_3    = 5'd6,  S_WAIT_30_3 = 5'd7,
    S_CMD_38      = 5'd8,  S_WAIT_38   = 5'd9,
    S_CMD_0C      = 5'd10, S_WAIT_0C   = 5'd11,
    S_CMD_06      = 5'd12, S_WAIT_06   = 5'd13,
    S_CMD_01      = 5'd14, S_WAIT_01   = 5'd15,

    S_IDLE        = 5'd16,
    S_SET_ADDR    = 5'd17,
    S_WRITE_CHAR  = 5'd18,

    S_BYTE_SETUP  = 5'd19,
    S_E_HIGH      = 5'd20,
    S_E_WAIT      = 5'd21
} state_t;

state_t state, state_next;

reg [15:0] wait_cnt;
reg [7:0]  byte_to_write;
reg        rs_to_write;

reg [7:0] char_latched;
reg       char_pending;
reg       init_done;

assign lcd_init_done = init_done;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        char_latched <= 8'h20;
        char_pending <= 1'b0;
        init_done    <= 1'b0;
    end else begin
        // Set init_done when LCD initialization is complete (entering S_IDLE for first time)
        if(state == S_WAIT_01 && wait_cnt == 0)
            init_done <= 1'b1;

        // Only latch characters after initialization is complete
        if(init_done && ascii_valid) begin
            char_latched <= ascii_in;
            char_pending <= 1'b1;
        end else if(char_pending && state == S_WRITE_CHAR) begin
            char_pending <= 1'b0;
        end
    end
end

//--------------------------------------------------------------
// Cursor position (0~7)
//--------------------------------------------------------------
reg [2:0] col;

// DDRAM base address (single line)
localparam [7:0] DDRAM_BASE = 8'h80;

//--------------------------------------------------------------
// Write-byte task
//--------------------------------------------------------------
task start_write(input [7:0] b, input rs, input state_t next_state);
begin
    byte_to_write <= b;
    rs_to_write   <= rs;
    state_next    <= next_state;
    state         <= S_BYTE_SETUP;
end
endtask

//--------------------------------------------------------------
// Main state machine
//--------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        lcd_data <= 8'h00;
        lcd_rs   <= 1'b0;
        lcd_e    <= 1'b0;
        state    <= S_RESET;
        wait_cnt <= 16'd0;
        col      <= 3'd0;
    end else begin
        case(state)

        // Power-on wait
        S_RESET: begin
            wait_cnt <= PWRON_WAIT_CYC;
            state    <= S_PWR_WAIT;
        end

        S_PWR_WAIT:
            if(wait_cnt != 0) wait_cnt <= wait_cnt - 1;
            else state <= S_CMD_30_1;

        // Init sequence
        S_CMD_30_1: begin start_write(8'h30,0,S_WAIT_30_1); wait_cnt<=WAIT_5MS_CYC; end
        S_WAIT_30_1: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_30_2;

        S_CMD_30_2: begin start_write(8'h30,0,S_WAIT_30_2); wait_cnt<=WAIT_1MS_CYC; end
        S_WAIT_30_2: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_30_3;

        S_CMD_30_3: begin start_write(8'h30,0,S_WAIT_30_3); wait_cnt<=WAIT_1MS_CYC; end
        S_WAIT_30_3: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_38;

        S_CMD_38: begin start_write(8'h38,0,S_WAIT_38); wait_cnt<=WAIT_SHORT_CYC; end
        S_WAIT_38: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_0C;

        S_CMD_0C: begin start_write(8'h0C,0,S_WAIT_0C); wait_cnt<=WAIT_SHORT_CYC; end
        S_WAIT_0C: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_06;

        S_CMD_06: begin start_write(8'h06,0,S_WAIT_06); wait_cnt<=WAIT_SHORT_CYC; end
        S_WAIT_06: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_CMD_01;

        S_CMD_01: begin start_write(8'h01,0,S_WAIT_01); wait_cnt<=WAIT_5MS_CYC; col<=0; end
        S_WAIT_01: if(wait_cnt!=0) wait_cnt<=wait_cnt-1; else state<=S_IDLE;

        //------------------------------------------------------
        // Wait for new character
        //------------------------------------------------------
        S_IDLE:
            if(char_pending)
                state <= S_SET_ADDR;

        //------------------------------------------------------
        // Set cursor address
        //------------------------------------------------------
        S_SET_ADDR: begin
            start_write(DDRAM_BASE + col, 0, S_WRITE_CHAR);
            wait_cnt <= WAIT_SHORT_CYC;
        end

        //------------------------------------------------------
        // Write character
        //------------------------------------------------------
        S_WRITE_CHAR: begin
            start_write(char_latched, 1, S_IDLE);
            wait_cnt <= WAIT_SHORT_CYC;

            // Cursor advance
            if(col == COLS-1)
                col <= 3'd0;   // wrap
            else
                col <= col + 1;
        end

        //------------------------------------------------------
        // Low-level write timing
        //------------------------------------------------------
        S_BYTE_SETUP: begin
            lcd_data <= byte_to_write;
            lcd_rs   <= rs_to_write;
            lcd_e    <= 1'b1;
            state    <= S_E_HIGH;
        end

        S_E_HIGH: begin
            lcd_e <= 1'b0;
            state <= S_E_WAIT;
        end

        S_E_WAIT:
            if(wait_cnt != 0) wait_cnt <= wait_cnt - 1;
            else state <= state_next;

        default: state <= S_RESET;

        endcase
    end
end

endmodule
