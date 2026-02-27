`timescale 1ns / 1ps

module main_fsm (
    input  logic Clock,       // 32.768 kHz
    input  logic nReset,      // Asynchronous Reset
    input  logic tick_1kHz,   // 1ms tick
    
    input  logic nMode,       
    input  logic nStart,      

    output logic [2:0] display_mode, 
    output logic nClear_rain, 
    output logic nClear_time  
);

    logic mode_stable, start_stable;
    logic [4:0] mode_cnt, start_cnt;

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            mode_cnt     <= '0;
            start_cnt    <= '0;
            mode_stable  <= 1'b1; 
            start_stable <= 1'b1;
        end else if (tick_1kHz) begin
            if (nMode == mode_stable) mode_cnt <= '0;
            else if (mode_cnt == 5'd24) begin mode_stable <= nMode; mode_cnt <= '0; end
            else mode_cnt <= mode_cnt + 1'b1;
            
            if (nStart == start_stable) start_cnt <= '0;
            else if (start_cnt == 5'd24) begin start_stable <= nStart; start_cnt <= '0; end
            else start_cnt <= start_cnt + 1'b1;
        end
    end

    logic prev_mode;
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) prev_mode <= 1'b1;
        else prev_mode <= mode_stable;
    end

    logic mode_pressed;
    assign mode_pressed  = (prev_mode == 1'b1) && (mode_stable == 1'b0);
    assign both_held     = (mode_stable == 1'b0) && (start_stable == 1'b0);

    typedef enum logic [2:0] {
        MODE_RAIN      = 3'd0,
        MODE_WIND_SPD  = 3'd1,
        MODE_WIND_DIR  = 3'd2,
        MODE_ELAPSED   = 3'd3,
        MODE_CALIB     = 3'd4  
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) current_state <= MODE_RAIN;
        else current_state <= next_state;
    end

    always_comb begin
        next_state   = current_state;
        display_mode = current_state; 
        nClear_rain  = 1'b1;  
        nClear_time  = 1'b1;

        case (current_state)
            MODE_RAIN: begin
                if (mode_pressed && !both_held) next_state = MODE_WIND_SPD;
                else if (both_held) next_state = MODE_CALIB;
                if (!start_stable && !both_held) nClear_rain = 1'b0;
            end
            MODE_WIND_SPD: begin
                if (mode_pressed && !both_held) next_state = MODE_WIND_DIR;
                else if (both_held) next_state = MODE_CALIB;
            end
            MODE_WIND_DIR: begin
                if (mode_pressed && !both_held) next_state = MODE_ELAPSED;
                else if (both_held) next_state = MODE_CALIB;
            end
            MODE_ELAPSED: begin
                if (mode_pressed && !both_held) next_state = MODE_RAIN;
                else if (both_held) next_state = MODE_CALIB;
                if (!start_stable && !both_held) nClear_time = 1'b0;
            end
            MODE_CALIB: begin
                if (mode_pressed) next_state = MODE_RAIN;
            end
            default: next_state = MODE_RAIN;
        endcase
    end

endmodule
