`timescale 1ns / 1ps

module elapsed_time_counter (
    input  logic Clock,
    input  logic nReset,
    input  logic tick_1Hz,
    input  logic start_adjust_hit,

    output logic [3:0] hour_tens, hour_units,
    output logic [3:0] min_tens,  min_units
);

    logic [3:0] sec_tens, sec_units;

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (start_adjust_hit) begin
            {hour_tens, hour_units, min_tens, min_units, sec_tens, sec_units} <= '0;
        end else if (tick_1Hz) begin
            if (sec_units == 4'd9) begin
                sec_units <= 4'd0;
                if (sec_tens == 4'd5) begin
                    sec_tens <= 4'd0;
                    if (min_units == 4'd9) begin
                        min_units <= 4'd0;
                        if (min_tens == 4'd5) begin
                            min_tens <= 4'd0;
                            if (hour_units == 4'd9) begin
                                hour_units <= 4'd0;
                                if (hour_tens == 4'd9)
                                    hour_tens <= 4'd9;
                                else
                                    hour_tens <= hour_tens + 1'b1;
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

