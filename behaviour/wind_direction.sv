///////////////////////////////////////////////////////////////////////
//
// wind_direction module
//
//  Drives wind vane ADC via SPI (AD7466: 4 leading zeros, 12-bit MSB first),
//  converts ADC value to direction by nearest-neighbour, outputs 3 ASCII
//  chars for LCD (N, NNE, NE, ...).
//
///////////////////////////////////////////////////////////////////////

module wind_direction(

  input  logic Clock,
  input  logic nReset,

  input  logic MISO,

  output logic       SPICLK,
  output logic       nVaneCS,

  output logic [7:0] char0,
  output logic [7:0] char1,
  output logic [7:0] char2

  );

timeunit 1ns;
timeprecision 100ps;

//----------------------------------------------------------------------
// SPI controller: 16 SCLK pulses ~9ms period, CS low during transfer, repeat ~2s
//----------------------------------------------------------------------
localparam int SPI_WAIT_CYCLES = 65536;   // ~2s at 32768 Hz
localparam int SPI_HALF_PERIOD = 148;      // ~4.5ms half period (9ms full period)

typedef enum logic [1:0] {
  SPI_IDLE,
  SPI_CLK_LOW,
  SPI_CLK_HIGH,
  SPI_DONE
} spi_state_t;

spi_state_t spi_state;
logic [16:0] spi_wait_cnt;
logic [7:0]  spi_period_cnt;
logic [4:0]  spi_bit_cnt;

logic [11:0] vane_adc_shift;
logic [11:0] vane_adc_value;

always_ff @(posedge Clock or negedge nReset) begin
  if (!nReset) begin
    spi_state      <= SPI_IDLE;
    spi_wait_cnt   <= '0;
    spi_period_cnt <= '0;
    spi_bit_cnt    <= '0;
    SPICLK         <= 1'b1;
    nVaneCS        <= 1'b1;
    vane_adc_shift <= 12'b0;
    vane_adc_value <= 12'd3143;  // N (0°) until first SPI read
  end else begin
    case (spi_state)
      SPI_IDLE: begin
        SPICLK  <= 1'b1;
        nVaneCS <= 1'b1;
        if (spi_wait_cnt >= SPI_WAIT_CYCLES - 1) begin
          spi_wait_cnt   <= '0;
          spi_period_cnt <= '0;
          spi_bit_cnt    <= '0;
          nVaneCS        <= 1'b0;
          spi_state      <= SPI_CLK_HIGH;
          vane_adc_shift <= 12'b0;
        end else begin
          spi_wait_cnt <= spi_wait_cnt + 1;
        end
      end

      SPI_CLK_HIGH: begin
        SPICLK <= 1'b1;
        if (spi_period_cnt == 0 && spi_bit_cnt >= 4 && spi_bit_cnt < 16)
          vane_adc_shift <= {vane_adc_shift[10:0], MISO};
        if (spi_period_cnt >= SPI_HALF_PERIOD - 1) begin
          spi_period_cnt <= '0;
          SPICLK         <= 1'b0;
          spi_state      <= SPI_CLK_LOW;
        end else begin
          spi_period_cnt <= spi_period_cnt + 1;
        end
      end

      SPI_CLK_LOW: begin
        SPICLK <= 1'b0;
        if (spi_period_cnt >= SPI_HALF_PERIOD - 1) begin
          spi_period_cnt <= '0;
          if (spi_bit_cnt >= 15) begin
            spi_state <= SPI_DONE;
          end else begin
            spi_bit_cnt <= spi_bit_cnt + 1;
            SPICLK      <= 1'b1;
            spi_state   <= SPI_CLK_HIGH;
          end
        end else begin
          spi_period_cnt <= spi_period_cnt + 1;
        end
      end

      SPI_DONE: begin
        if (spi_period_cnt == 0)
          vane_adc_value <= vane_adc_shift;
        if (spi_period_cnt >= SPI_HALF_PERIOD - 1) begin
          nVaneCS        <= 1'b1;
          spi_period_cnt <= '0;
          spi_state      <= SPI_IDLE;
        end else begin
          spi_period_cnt <= spi_period_cnt + 1;
        end
      end
    endcase
  end
end

//----------------------------------------------------------------------
// ADC value -> direction index: nearest-neighbour (3.3V, 10k nominal)
//----------------------------------------------------------------------
localparam logic [11:0] NOMINAL_ADC [0:15] = '{
  12'd3143, 12'd2458, 12'd2570, 12'd335,  12'd372,  12'd264,   // N, NNE, NE, ENE, E, ESE
  12'd744,  12'd893,  12'd1154, 12'd1067, 12'd1476, 12'd2556,  // SE, SSE, S, SSW, SW, WSW
  12'd3782, 12'd3425, 12'd2842, 12'd2655                        // W, WNW, NW, NNW
};

logic [3:0] dir_index;
logic [11:0] vane_dist [0:15];
logic [11:0] min_dist;
int d;

always_comb begin
  for (d = 0; d < 16; d++)
    vane_dist[d] = (vane_adc_value >= NOMINAL_ADC[d]) ? (vane_adc_value - NOMINAL_ADC[d]) : (NOMINAL_ADC[d] - vane_adc_value);
  min_dist = vane_dist[0];
  dir_index = 4'd0;
  for (d = 1; d < 16; d++)
    if (vane_dist[d] < min_dist) begin
      min_dist = vane_dist[d];
      dir_index = 4'(d);
    end
end

//----------------------------------------------------------------------
// Direction index -> 3 ASCII chars for LCD
//----------------------------------------------------------------------
always_comb begin
  case (dir_index)
    4'd0:  begin char0 = "N"; char1 = " "; char2 = " "; end
    4'd1:  begin char0 = "N"; char1 = "N"; char2 = "E"; end
    4'd2:  begin char0 = "N"; char1 = "E"; char2 = " "; end
    4'd3:  begin char0 = "E"; char1 = "N"; char2 = "E"; end
    4'd4:  begin char0 = "E"; char1 = " "; char2 = " "; end
    4'd5:  begin char0 = "E"; char1 = "S"; char2 = "E"; end
    4'd6:  begin char0 = "S"; char1 = "E"; char2 = " "; end
    4'd7:  begin char0 = "S"; char1 = "S"; char2 = "E"; end
    4'd8:  begin char0 = "S"; char1 = " "; char2 = " "; end
    4'd9:  begin char0 = "S"; char1 = "S"; char2 = "W"; end
    4'd10: begin char0 = "S"; char1 = "W"; char2 = " "; end
    4'd11: begin char0 = "W"; char1 = "S"; char2 = "W"; end
    4'd12: begin char0 = "W"; char1 = " "; char2 = " "; end
    4'd13: begin char0 = "W"; char1 = "N"; char2 = "W"; end
    4'd14: begin char0 = "N"; char1 = "W"; char2 = " "; end
    4'd15: begin char0 = "N"; char1 = "N"; char2 = "W"; end
    default: begin char0 = "?"; char1 = " "; char2 = " "; end
  endcase
end

endmodule
