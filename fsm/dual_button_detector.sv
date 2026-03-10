`timescale 1ns / 1ps

//==============================================================================
// Dual Button Time Window Detector
// File: dual_button_detector.sv
// Module: dual_button_detector
// 
// Detects if two buttons are pressed within a time window
//
// Operation:
//   1. When first button pressed, open time window (default 100ms)
//   2. If second button pressed within window -> "both pressed"
//   3. If window timeout -> "first button only"
//   4. If first button released early -> "first button only"
//
// Parameter:
//   WINDOW_TIME_MS: Time window size in milliseconds (recommended: 50-150ms)
//==============================================================================

module dual_button_detector #(
    parameter WINDOW_TIME_MS = 100
)(
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1kHz,
    
    input  logic button1_stable,
    input  logic button2_stable,
    
    output logic button1_pressed,
    output logic button2_pressed,
    output logic both_pressed
);

    //==========================================================================
    // Edge Detection
    //==========================================================================
    logic prev_button1, prev_button2;
    
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            prev_button1 <= 1'b1;
            prev_button2 <= 1'b1;
        end else begin
            prev_button1 <= button1_stable;
            prev_button2 <= button2_stable;
        end
    end
    
    logic button1_falling, button2_falling;
    assign button1_falling = (prev_button1 == 1'b1) && (button1_stable == 1'b0);
    assign button2_falling = (prev_button2 == 1'b1) && (button2_stable == 1'b0);
    
    //==========================================================================
    // Time Window State Machine
    //==========================================================================
    typedef enum logic [2:0] {
        IDLE,
        WAIT_BUTTON2,
        WAIT_BUTTON1,
        BOTH_DETECTED,
        BUTTON1_SINGLE,
        BUTTON2_SINGLE
    } state_t;
    
    state_t current_state, next_state;
    
    logic [7:0] window_counter;
    logic window_timeout;
    
    assign window_timeout = (window_counter >= WINDOW_TIME_MS[7:0]);
    
    //==========================================================================
    // State Register and Window Counter
    //==========================================================================
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            current_state <= IDLE;
            window_counter <= 8'd0;
        end else begin
            current_state <= next_state;
            
            if (current_state == WAIT_BUTTON1 || current_state == WAIT_BUTTON2) begin
                if (tick_1kHz && !window_timeout) begin
                    window_counter <= window_counter + 1'b1;
                end
            end else begin
                window_counter <= 8'd0;
            end
        end
    end
    
    //==========================================================================
    // State Transition Logic
    //==========================================================================
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (button1_falling && button2_stable == 1'b0) begin
                    next_state = BOTH_DETECTED;
                end else if (button2_falling && button1_stable == 1'b0) begin
                    next_state = BOTH_DETECTED;
                end else if (button1_falling) begin
                    next_state = WAIT_BUTTON2;
                end else if (button2_falling) begin
                    next_state = WAIT_BUTTON1;
                end
            end
            
            WAIT_BUTTON2: begin
                if (button2_falling) begin
                    next_state = BOTH_DETECTED;
                end else if (window_timeout) begin
                    next_state = BUTTON1_SINGLE;
                end else if (button1_stable == 1'b1) begin
                    next_state = BUTTON1_SINGLE;
                end
            end
            
            WAIT_BUTTON1: begin
                if (button1_falling) begin
                    next_state = BOTH_DETECTED;
                end else if (window_timeout) begin
                    next_state = BUTTON2_SINGLE;
                end else if (button2_stable == 1'b1) begin
                    next_state = BUTTON2_SINGLE;
                end
            end
            
            BOTH_DETECTED: begin
                if (button1_stable == 1'b1 || button2_stable == 1'b1) begin
                    next_state = IDLE;
                end
            end
            
            BUTTON1_SINGLE: begin
                next_state = IDLE;
            end
            
            BUTTON2_SINGLE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    //==========================================================================
    // Output Logic (Pulse Generation)
    //==========================================================================
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            button1_pressed <= 1'b0;
            button2_pressed <= 1'b0;
            both_pressed    <= 1'b0;
        end else begin
            button1_pressed <= 1'b0;
            button2_pressed <= 1'b0;
            both_pressed    <= 1'b0;
            
            if (current_state != next_state) begin
                case (next_state)
                    BOTH_DETECTED: begin
                        both_pressed <= 1'b1;
                    end
                    
                    BUTTON1_SINGLE: begin
                        button1_pressed <= 1'b1;
                    end
                    
                    BUTTON2_SINGLE: begin
                        button2_pressed <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
