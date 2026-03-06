`include "options.sv"

module weather_core(

  output logic RS,
  output logic RnW,
  output logic En,

  input [7:0] DB_In,
  output logic [7:0] DB_Out,
  output logic DB_nEnable,

  input nMode, nStart,
  input nRain, nWind,

  output logic SPICLK, nVaneCS,
  input MISO,

  input Clock, nReset,
  input Demo
);

timeunit 1ns;
timeprecision 100ps;

localparam int LCD_COLS = 8;

///////////////////////////////////////////////////////////////
// Rain gauge signals
///////////////////////////////////////////////////////////////

logic [15:0] total_rain_pulses;

logic [3:0] rain_hundreds_bcd;
logic [3:0] rain_tens_bcd;
logic [3:0] rain_units_bcd;
logic [3:0] rain_tenths_bcd;

rain_gauge RAIN(
  .Clock,
  .nReset,
  .nStart,
  .nRain,
  .total_rain_pulses,
  .rain_hundreds_bcd,
  .rain_tens_bcd,
  .rain_units_bcd,
  .rain_tenths_bcd
);

///////////////////////////////////////////////////////////////
// Rain display slots
///////////////////////////////////////////////////////////////

logic [1:0] rain_slot_type [LCD_COLS];
logic [7:0] rain_slot_data [LCD_COLS];

integer i;

always_comb begin

  for(i=0;i<LCD_COLS;i++) begin
      rain_slot_type[i] = 2'b01;
      rain_slot_data[i] = 8'h20;
  end

  // hundreds
  if(rain_hundreds_bcd == 0) begin
      rain_slot_type[0] = 2'b01;
      rain_slot_data[0] = " ";
  end
  else begin
      rain_slot_type[0] = 2'b00;
      rain_slot_data[0] = {4'b0,rain_hundreds_bcd};
  end

  // tens
  if(rain_hundreds_bcd==0 && rain_tens_bcd==0) begin
      rain_slot_type[1] = 2'b01;
      rain_slot_data[1] = " ";
  end
  else begin
      rain_slot_type[1] = 2'b00;
      rain_slot_data[1] = {4'b0,rain_tens_bcd};
  end

  rain_slot_type[2] = 2'b00;
  rain_slot_data[2] = {4'b0,rain_units_bcd};

  rain_slot_type[3] = 2'b01;
  rain_slot_data[3] = ".";

  rain_slot_type[4] = 2'b00;
  rain_slot_data[4] = {4'b0,rain_tenths_bcd};

  rain_slot_type[5] = 2'b01;
  rain_slot_data[5] = " ";

  rain_slot_type[6] = 2'b01;
  rain_slot_data[6] = "m";

  rain_slot_type[7] = 2'b01;
  rain_slot_data[7] = "m";

end

///////////////////////////////////////////////////////////////
// Anemometer (wind speed)
///////////////////////////////////////////////////////////////

logic [1:0] wind_slot_type [LCD_COLS];
logic [7:0] wind_slot_data [LCD_COLS];
logic [15:0] wind_tenths;

anemometer u_ane(
  .clk(Clock),
  .rst_n(nReset),
  .anemo_sw(nWind),

  .slot_type(wind_slot_type),
  .slot_data(wind_slot_data),

  .wind_tenths(wind_tenths)
);

///////////////////////////////////////////////////////////////
// Display MUX (Rain / Wind)
///////////////////////////////////////////////////////////////

logic [1:0] display_slot_type [LCD_COLS];
logic [7:0] display_slot_data [LCD_COLS];

always_comb begin

  for(int j=0;j<LCD_COLS;j++) begin

      if(nMode==1'b0) begin
          display_slot_type[j] = rain_slot_type[j];
          display_slot_data[j] = rain_slot_data[j];
      end
      else begin
          display_slot_type[j] = wind_slot_type[j];
          display_slot_data[j] = wind_slot_data[j];
      end

  end

end

///////////////////////////////////////////////////////////////
// LCD formatter
///////////////////////////////////////////////////////////////

logic [7:0] lcd_ascii;
logic lcd_ascii_valid;

logic [7:0] lcd_data;
logic lcd_rs;
logic lcd_rw;
logic lcd_en;
logic lcd_init_done;

lcd_formatter_8x1 #(
  .CLK_HZ(32768),
  .COLS(LCD_COLS),
  .CHAR_PERIOD_MS(2)
) u_lcd_formatter_8x1 (

  .clk        (Clock),
  .rst_n      (nReset),
  .lcd_ready  (lcd_init_done),

  .slot_type  (display_slot_type),
  .slot_data  (display_slot_data),

  .ascii_out  (lcd_ascii),
  .ascii_valid(lcd_ascii_valid)
);

///////////////////////////////////////////////////////////////
// LCD driver
///////////////////////////////////////////////////////////////

lcd #(
  .CLK_HZ(32768),
  .COLS(LCD_COLS)
) u_lcd (

  .clk          (Clock),
  .rst_n        (nReset),

  .ascii_in     (lcd_ascii),
  .ascii_valid  (lcd_ascii_valid),

  .lcd_data     (lcd_data),
  .lcd_rs       (lcd_rs),
  .lcd_rw       (lcd_rw),
  .lcd_e        (lcd_en),

  .lcd_init_done(lcd_init_done)
);

///////////////////////////////////////////////////////////////
// LCD output mapping
///////////////////////////////////////////////////////////////

assign RS  = lcd_rs;
assign RnW = lcd_rw;
assign En  = lcd_en;

assign DB_Out     = lcd_data;
assign DB_nEnable = 1'b0;

///////////////////////////////////////////////////////////////
// SPI Wind vane (unchanged)
///////////////////////////////////////////////////////////////

localparam int SPI_WAIT_CYCLES = 65536;
localparam int SPI_HALF_PERIOD = 148;

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

always_ff @(posedge Clock or negedge nReset) begin

  if (!nReset) begin
    spi_state <= SPI_IDLE;
    spi_wait_cnt <= 0;
    spi_period_cnt <= 0;
    spi_bit_cnt <= 0;
    SPICLK <= 1;
    nVaneCS <= 1;
  end
  else begin

    case(spi_state)

    SPI_IDLE: begin
      SPICLK  <= 1;
      nVaneCS <= 1;

      if(spi_wait_cnt >= SPI_WAIT_CYCLES-1) begin
          spi_wait_cnt <= 0;
          spi_bit_cnt <= 0;
          spi_period_cnt <= 0;
          nVaneCS <= 0;
          spi_state <= SPI_CLK_HIGH;
      end
      else
          spi_wait_cnt <= spi_wait_cnt + 1;
    end

    SPI_CLK_HIGH: begin
      SPICLK <= 1;

      if(spi_period_cnt >= SPI_HALF_PERIOD-1) begin
          spi_period_cnt <= 0;
          SPICLK <= 0;
          spi_state <= SPI_CLK_LOW;
      end
      else
          spi_period_cnt <= spi_period_cnt + 1;
    end

    SPI_CLK_LOW: begin
      SPICLK <= 0;

      if(spi_period_cnt >= SPI_HALF_PERIOD-1) begin

          spi_period_cnt <= 0;

          if(spi_bit_cnt >= 15)
              spi_state <= SPI_DONE;
          else begin
              spi_bit_cnt <= spi_bit_cnt + 1;
              spi_state <= SPI_CLK_HIGH;
          end

      end
      else
          spi_period_cnt <= spi_period_cnt + 1;

    end

    SPI_DONE: begin

      if(spi_period_cnt >= SPI_HALF_PERIOD-1) begin
          nVaneCS <= 1;
          spi_state <= SPI_IDLE;
          spi_period_cnt <= 0;
      end
      else
          spi_period_cnt <= spi_period_cnt + 1;

    end

    endcase

  end

end

endmodule
