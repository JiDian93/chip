`timescale 1ns / 1ps

//==============================================================================
// Weather Station Main FSM - With Time Window Detection
// File: main_fsm.sv
// Module: main_fsm
// Contains: 5 display modes + calibration modes + time setting mode
//==============================================================================

module main_fsm (
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1kHz,
    
    input  logic nMode,
    input  logic nStart,

    output logic [2:0] display_mode,
    
    output logic clear_rain_pulse,
    output logic clear_time_pulse,
    
    output logic in_calibration,
    output logic is_rain_calib,
    output logic [1:0] calib_digit_index,
    output logic calib_increment_pulse,
    
    output logic in_time_setting,
    output logic [1:0] time_set_field,
    output logic time_increment_pulse,
    output logic time_zero_seconds_pulse
);

    //==========================================================================
    // State Definitions
    //   - 0..5 : main display modes
    //   - 6    : temperature display mode
    //   - 7..9 : calibration / time setting modes
    //==========================================================================
    typedef enum logic [3:0] {
        MODE_RAIN           = 4'd0,
        MODE_WIND_SPD       = 4'd1,
        MODE_WIND_DIR       = 4'd2,
        MODE_ELAPSED        = 4'd3,
        MODE_TIME           = 4'd4,
        MODE_PRESSURE       = 4'd5,
        MODE_TEMPERATURE    = 4'd6,
        MODE_RAIN_CALIB     = 4'd7,
        MODE_WIND_CALIB     = 4'd8,
        MODE_TIME_SETTING   = 4'd9
    } state_t;

    state_t current_state, next_state;

    //==========================================================================
    // Button Debounce: 25ms
    //==========================================================================
    logic mode_stable, start_stable;
    logic [4:0] mode_cnt, start_cnt;

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            mode_cnt     <= '0;
            start_cnt    <= '0;
            mode_stable  <= 1'b1;
            start_stable <= 1'b1;
        end else if (tick_1kHz) begin
            if (nMode == mode_stable)
                mode_cnt <= '0;
            else if (mode_cnt == 5'd24)
                begin
                    mode_stable <= nMode;
                    mode_cnt <= '0;
                end
            else
                mode_cnt <= mode_cnt + 1'b1;
            
            if (nStart == start_stable)
                start_cnt <= '0;
            else if (start_cnt == 5'd24)
                begin
                    start_stable <= nStart;
                    start_cnt <= '0;
                end
            else
                start_cnt <= start_cnt + 1'b1;
        end
    end

    //==========================================================================
    // Dual Button Time Window Detector (100ms window)
    //==========================================================================
    logic mode_pressed_single;
    logic start_pressed_single;
    logic both_pressed;
    
    dual_button_detector #(
        .WINDOW_TIME_MS(100)
    ) btn_detector (
        .Clock(Clock),
        .nReset(nReset),
        .tick_1kHz(tick_1kHz),
        .button1_stable(mode_stable),
        .button2_stable(start_stable),
        .button1_pressed(mode_pressed_single),
        .button2_pressed(start_pressed_single),
        .both_pressed(both_pressed)
    );

    //==========================================================================
    // State Register
    //==========================================================================
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset)
            current_state <= MODE_RAIN;
        else
            current_state <= next_state;
    end

    //==========================================================================
    // Sub-state Counter for Calibration and Time Setting
    //==========================================================================
    logic [1:0] sub_state_counter;
    
    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            sub_state_counter <= 2'd0;
        end else begin
            if (next_state == MODE_RAIN_CALIB ||
                next_state == MODE_WIND_CALIB ||
                next_state == MODE_TIME_SETTING) begin
                if (current_state != next_state) begin
                    sub_state_counter <= 2'd0;
                end else if (mode_pressed_single) begin
                    if (current_state == MODE_TIME_SETTING) begin
                        if (sub_state_counter < 2'd2)
                            sub_state_counter <= sub_state_counter + 1'b1;
                        else
                            sub_state_counter <= 2'd0;
                    end else begin
                        sub_state_counter <= sub_state_counter + 1'b1;
                    end
                end
            end else begin
                sub_state_counter <= 2'd0;
            end
        end
    end

    //==========================================================================
    // State Transition Logic & Output Logic
    //==========================================================================
    always_comb begin
        next_state              = current_state;
        display_mode            = current_state[2:0];
        
        clear_rain_pulse        = 1'b0;
        clear_time_pulse        = 1'b0;
        
        in_calibration          = 1'b0;
        is_rain_calib           = 1'b0;
        calib_digit_index       = 2'd0;
        calib_increment_pulse   = 1'b0;
        
        in_time_setting         = 1'b0;
        time_set_field          = 2'd0;
        time_increment_pulse    = 1'b0;
        time_zero_seconds_pulse = 1'b0;

        case (current_state)
            //==================================================================
            // Main Display Modes
            //==================================================================
            
            MODE_RAIN: begin
                display_mode = 3'd0;
                
                if (mode_pressed_single)
                    next_state = MODE_WIND_SPD;
                
                if (start_pressed_single && !both_pressed)
                    clear_rain_pulse = 1'b1;
                
                if (both_pressed)
                    next_state = MODE_RAIN_CALIB;
            end

            MODE_WIND_SPD: begin
                display_mode = 3'd1;
                
                if (mode_pressed_single)
                    next_state = MODE_WIND_DIR;
                
                if (both_pressed)
                    next_state = MODE_WIND_CALIB;
            end

            MODE_WIND_DIR: begin
                display_mode = 3'd2;
                
                if (mode_pressed_single)
                    next_state = MODE_ELAPSED;
            end

            MODE_ELAPSED: begin
                display_mode = 3'd3;
                
                if (mode_pressed_single)
                    next_state = MODE_TIME;
                
                if (start_pressed_single && !both_pressed)
                    clear_time_pulse = 1'b1;
            end

            MODE_TIME: begin
                display_mode = 3'd4;
                
                if (mode_pressed_single)
                    next_state = MODE_PRESSURE;
                
                if (both_pressed)
                    next_state = MODE_TIME_SETTING;
            end

            MODE_PRESSURE: begin
                display_mode = 3'd5;

                if (mode_pressed_single)
                    next_state = MODE_TEMPERATURE;
            end

            MODE_TEMPERATURE: begin
                display_mode = 3'd6;

                if (mode_pressed_single)
                    next_state = MODE_RAIN;
            end

            //==================================================================
            // Calibration Mode: Rainfall
            //==================================================================
            MODE_RAIN_CALIB: begin
                in_calibration    = 1'b1;
                is_rain_calib     = 1'b1;
                display_mode      = 3'd0;
                calib_digit_index = sub_state_counter;
                
                if (start_pressed_single)
                    calib_increment_pulse = 1'b1;
                
                if (mode_pressed_single && sub_state_counter == 2'd3)
                    next_state = MODE_RAIN;
            end

            //==================================================================
            // Calibration Mode: Wind Speed
            //==================================================================
            MODE_WIND_CALIB: begin
                in_calibration    = 1'b1;
                is_rain_calib     = 1'b0;
                display_mode      = 3'd1;
                calib_digit_index = sub_state_counter;
                
                if (start_pressed_single)
                    calib_increment_pulse = 1'b1;
                
                if (mode_pressed_single && sub_state_counter == 2'd3)
                    next_state = MODE_WIND_SPD;
            end

            //==================================================================
            // Time Setting Mode
            //==================================================================
            MODE_TIME_SETTING: begin
                in_time_setting = 1'b1;
                display_mode    = 3'd4;
                time_set_field  = sub_state_counter;
                
                case (sub_state_counter)
                    2'd0: begin
                        if (start_pressed_single)
                            time_increment_pulse = 1'b1;
                    end
                    
                    2'd1: begin
                        if (start_pressed_single)
                            time_increment_pulse = 1'b1;
                    end
                    
                    2'd2: begin
                        if (start_pressed_single)
                            time_zero_seconds_pulse = 1'b1;
                    end
                endcase
                
                if (mode_pressed_single && sub_state_counter == 2'd2)
                    next_state = MODE_TIME;
            end

            default:
                next_state = MODE_RAIN;
        endcase
    end

endmodule
