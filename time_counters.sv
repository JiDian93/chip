`timescale 1ns / 1ps

module time_counters (
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1Hz,
    input  logic nClear_time,

    output logic [3:0] min_tens, min_units,
    output logic [3:0] sec_tens, sec_units
);

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            {min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (!nClear_time) begin
            {min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (tick_1Hz) begin
            if (sec_units == 4'd9) begin
                sec_units <= 4'd0;
                if (sec_tens == 4'd5) begin
                    sec_tens <= 4'd0;
                    if (min_units == 4'd9) begin
                        min_units <= 4'd0;
                        if (min_tens == 4'd9) min_tens <= 4'd0;
                        else min_tens <= min_tens + 1'b1;
                    end else min_units <= min_units + 1'b1;
                end else sec_tens <= sec_tens + 1'b1;
            end else sec_units <= sec_units + 1'b1;
        end
    end

endmodule
