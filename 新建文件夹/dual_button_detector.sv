`timescale 1ns / 1ps

//==============================================================================
// Dual Button Time Window Detector
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

    // Edge Detection
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
    
    // Time Window State Machine
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
    
    // State Register and Window Counter
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            current_state  <= IDLE;
            window_counter <= 8'd0;
        end else begin
            current_state <= next_state;
            
            if (current_state == WAIT_BUTTON1 || current_state == WAIT_BUTTON2) begin
                if (tick_1kHz && !window_timeout)
                    window_counter <= window_counter + 1'b1;
            end else begin
                window_counter <= 8'd0;
            end
        end
    end
    
    // State Transition Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (button1_falling && button2_stable == 1'b0)
                    next_state = BOTH_DETECTED;
                else if (button2_falling && button1_stable == 1'b0)
                    next_state = BOTH_DETECTED;
                else if (button1_falling)
                    next_state = WAIT_BUTTON2;
                else if (button2_falling)
                    next_state = WAIT_BUTTON1;
            end
            
            WAIT_BUTTON2: begin
                if (button2_falling)
                    next_state = BOTH_DETECTED;
                else if (window_timeout)
                    next_state = BUTTON1_SINGLE;
                else if (button1_stable == 1'b1)
                    next_state = BUTTON1_SINGLE;
            end
            
            WAIT_BUTTON1: begin
                if (button1_falling)
                    next_state = BOTH_DETECTED;
                else if (window_timeout)
                    next_state = BUTTON2_SINGLE;
                else if (button2_stable == 1'b1)
                    next_state = BUTTON2_SINGLE;
            end
            
            BOTH_DETECTED: begin
                if (button1_stable == 1'b1 || button2_stable == 1'b1)
                    next_state = IDLE;
            end
            
            BUTTON1_SINGLE: begin
                next_state = IDLE;
            end
            
            BUTTON2_SINGLE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Output Logic (Pulse Generation)
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
                    BOTH_DETECTED:    both_pressed    <= 1'b1;
                    BUTTON1_SINGLE:   button1_pressed <= 1'b1;
                    BUTTON2_SINGLE:   button2_pressed <= 1'b1;
                endcase
            end
        end
    end

endmodule

