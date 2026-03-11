`timescale 1ns / 1ps

module clock_divider (
    input  logic Clock,     // 32.768 kHz system clock
    input  logic nReset,    // Active-low asynchronous reset
    input  logic Demo,      // Simulation speedup

    output logic tick_1kHz, // ~1kHz (1024Hz)
    output logic tick_1Hz   // 1Hz (64Hz in Demo mode)
);

    logic [14:0] counter;

    always_ff @(posedge Clock or negedge nReset) begin
        if (!nReset) begin
            counter   <= 15'd0;
            tick_1kHz <= 1'b0;
            tick_1Hz  <= 1'b0;
        end else begin
            counter <= counter + 1'b1;

            // Generate ~1kHz tick
            tick_1kHz <= (counter[4:0] == 5'd31);

            // Generate 1Hz tick with Demo acceleration
            if (Demo) begin
                tick_1Hz <= (counter[8:0] == 9'd511);
            end else begin
                tick_1Hz <= (counter == 15'd32767);
            end
        end
    end

endmodule
