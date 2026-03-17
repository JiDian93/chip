`timescale 1ns / 1ps

// Time of Day: normal HH:MM:SS 24h; Demo mode MM:SS:xx (sixtieths), roll over after 24 minutes.

module time_counters (
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1Hz,
    input  logic nClear_time,
    input  logic Demo,

    input  logic [1:0] time_set_field,
    input  logic       time_increment_pulse,
    input  logic       time_zero_seconds_pulse,

    output logic [3:0] hour_tens, hour_units,
    output logic [3:0] min_tens,  min_units,
    output logic [3:0] sec_tens,  sec_units,
    output logic [3:0] sixtieths_tens, sixtieths_units
);

    // Demo mode: count sixtieths (0-59), sec (0-59), min (0-23), roll at 24 min. tick_1Hz = 60 Hz.
    logic [5:0] demo_sixtieths;  // 0..59
    logic [5:0] demo_sec;
    logic [4:0] demo_min;        // 0..23

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
            {sixtieths_tens, sixtieths_units} <= '0;
            demo_sixtieths <= 6'd0;
            demo_sec       <= 6'd0;
            demo_min       <= 5'd0;
        end else if (Demo) begin
            // Demo: each tick_1Hz = 1/60 sec; display MM:SS:xx, roll at 24 min
            if (tick_1Hz) begin
                if (demo_sixtieths >= 6'd59) begin
                    demo_sixtieths <= 6'd0;
                    if (demo_sec >= 6'd59) begin
                        demo_sec <= 6'd0;
                        if (demo_min >= 5'd23)
                            demo_min <= 5'd0;
                        else
                            demo_min <= demo_min + 1'b1;
                    end else begin
                        demo_sec <= demo_sec + 1'b1;
                    end
                end else begin
                    demo_sixtieths <= demo_sixtieths + 1'b1;
                end
            end
            sixtieths_tens  <= demo_sixtieths / 6'd10;
            sixtieths_units <= demo_sixtieths % 6'd10;
            sec_tens        <= demo_sec[5:4];  // 0-5
            sec_units       <= demo_sec[3:0];  // 0-9
            min_tens        <= (demo_min >= 5'd20) ? 4'd2 : (demo_min >= 5'd10) ? 4'd1 : 4'd0;
            min_units       <= (demo_min >= 5'd20) ? 4'(demo_min - 5'd20) : (demo_min >= 5'd10) ? 4'(demo_min - 5'd10) : 4'(demo_min);
            hour_tens       <= 4'd0;
            hour_units      <= 4'd0;
        end else if (!nClear_time) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
            {sixtieths_tens, sixtieths_units} <= '0;
        end else if (time_increment_pulse) begin
            sixtieths_tens  <= 4'd0;
            sixtieths_units <= 4'd0;
            if (time_set_field == 2'd0) begin
                if (hour_tens == 4'd2 && hour_units == 4'd3) begin
                    hour_tens  <= 4'd0;
                    hour_units <= 4'd0;
                end else if (hour_units == 4'd9) begin
                    hour_units <= 4'd0;
                    hour_tens  <= hour_tens + 1'b1;
                end else begin
                    hour_units <= hour_units + 1'b1;
                end
            end else if (time_set_field == 2'd1) begin
                if (min_tens == 4'd5 && min_units == 4'd9) begin
                    min_tens  <= 4'd0;
                    min_units <= 4'd0;
                end else if (min_units == 4'd9) begin
                    min_units <= 4'd0;
                    min_tens  <= min_tens + 1'b1;
                end else begin
                    min_units <= min_units + 1'b1;
                end
            end
        end else if (time_zero_seconds_pulse) begin
            sec_tens  <= 4'd0;
            sec_units <= 4'd0;
            sixtieths_tens  <= 4'd0;
            sixtieths_units <= 4'd0;
        end else if (tick_1Hz) begin
            sixtieths_tens  <= 4'd0;
            sixtieths_units <= 4'd0;
            if (sec_units == 4'd9) begin
                sec_units <= 4'd0;
                if (sec_tens == 4'd5) begin
                    sec_tens <= 4'd0;
                    if (min_units == 4'd9) begin
                        min_units <= 4'd0;
                        if (min_tens == 4'd5) begin
                            min_tens <= 4'd0;
                            if (hour_tens == 4'd2 && hour_units == 4'd3) begin
                                hour_tens  <= 4'd0;
                                hour_units <= 4'd0;
                            end else if (hour_units == 4'd9) begin
                                hour_units <= 4'd0;
                                hour_tens  <= hour_tens + 1'b1;
                            end else begin
                                hour_units <= hour_units + 1'b1;
                            end
                        end else begin
                            min_tens <= min_tens + 1'b1;
                        end
                    end else begin
                        min_units <= min_units + 1'b1;
                    end
                end else begin
                    sec_tens <= sec_tens + 1'b1;
                end
            end else begin
                sec_units <= sec_units + 1'b1;
            end
        end
    end

endmodule
