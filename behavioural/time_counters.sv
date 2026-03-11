`timescale 1ns / 1ps

// Time of Day counter (HH:MM:SS, 24h). Supports normal run and "Setting the Time".

module time_counters (
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1Hz,
    input  logic nClear_time,

    input  logic [1:0] time_set_field,
    input  logic       time_increment_pulse,
    input  logic       time_zero_seconds_pulse,

    output logic [3:0] hour_tens, hour_units,
    output logic [3:0] min_tens,  min_units,
    output logic [3:0] sec_tens,  sec_units
);

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (!nClear_time) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (time_increment_pulse) begin
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
        end else if (tick_1Hz) begin
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

