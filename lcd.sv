
//==============================================================
// lcd_hd44780_ascii_8bit_8x1.v
//  - 8-bit HD44780 LCD
//  - 8 columns, 1 line
//  - Receive external ASCII code and display
//==============================================================
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
    output reg        lcd_e
);

assign lcd_rw = 1'b0;   

localparam integer PWRON_WAIT_CYC = (CLK_HZ * 40) / 1000;
localparam integer WAIT_5MS_CYC   = (CLK_HZ * 5)  / 1000;
localparam integer WAIT_1MS_CYC   = (CLK_HZ * 1)  / 1000;
localparam integer WAIT_SHORT_CYC = 3;

reg [7:0] char_latched;
reg       char_pending;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        char_latched <= 8'h20;
        char_pending <= 1'b0;
    end else begin
        if(ascii_valid) begin
            char_latched <= ascii_in;
            char_pending <= 1'b1;
        end else if(char_pending && state == S_WRITE_CHAR) begin
            char_pending <= 1'b0;
        end
    end
end

//--------------------------------------------------------------
// 光标位置（0~7）
//--------------------------------------------------------------
reg [2:0] col;

// DDRAM 起始地址（单行）
localparam [7:0] DDRAM_BASE = 8'h80;

//--------------------------------------------------------------
// FSM 定义
//--------------------------------------------------------------
typedef enum logic [4:0] {
    S_RESET       = 0,
    S_PWR_WAIT    = 1,

    S_CMD_30_1    = 2,  S_WAIT_30_1 = 3,
    S_CMD_30_2    = 4,  S_WAIT_30_2 = 5,
    S_CMD_30_3    = 6,  S_WAIT_30_3 = 7,
    S_CMD_38      = 8,  S_WAIT_38   = 9,
    S_CMD_0C      = 10, S_WAIT_0C   = 11,
    S_CMD_06      = 12, S_WAIT_06   = 13,
    S_CMD_01      = 14, S_WAIT_01   = 15,

    S_IDLE        = 16,
    S_SET_ADDR    = 17,
    S_WRITE_CHAR  = 18,

    S_BYTE_SETUP  = 19,
    S_E_HIGH      = 20,
    S_E_WAIT      = 21
} state_t;

state_t state, state_next;

reg [15:0] wait_cnt;
reg [7:0]  byte_to_write;
reg        rs_to_write;

//--------------------------------------------------------------
// 写字节任务
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
// 主状态机
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

        // 上电等待
        S_RESET: begin
            wait_cnt <= PWRON_WAIT_CYC;
            state    <= S_PWR_WAIT;
        end

        S_PWR_WAIT:
            if(wait_cnt != 0) wait_cnt <= wait_cnt - 1;
            else state <= S_CMD_30_1;

        // 初始化流程
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
        // 等待新字符
        //------------------------------------------------------
        S_IDLE:
            if(char_pending)
                state <= S_SET_ADDR;

        //------------------------------------------------------
        // 设置光标地址
        //------------------------------------------------------
        S_SET_ADDR: begin
            start_write(DDRAM_BASE + col, 0, S_WRITE_CHAR);
            wait_cnt <= WAIT_SHORT_CYC;
        end

        //------------------------------------------------------
        // 写字符
        //------------------------------------------------------
        S_WRITE_CHAR: begin
            start_write(char_latched, 1, S_IDLE);
            wait_cnt <= WAIT_SHORT_CYC;

            // 光标移动
            if(col == COLS-1)
                col <= 3'd0;   // 回卷
            else
                col <= col + 1;
        end

        //------------------------------------------------------
        // 底层写时序
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
