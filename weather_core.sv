///////////////////////////////////////////////////////////////////////
//
// weather_core module
//
//    this is the behavioural model of the weather station without pads
//
///////////////////////////////////////////////////////////////////////

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

// Total rainfall (count of nRain pulses) – internal to core
logic [15:0] total_rain_pulses;

// 4 BCD digits in ddd.d mm format: 3 integer + 1 fractional – internal to core
logic [3:0] rain_hundreds_bcd;
logic [3:0] rain_tens_bcd;
logic [3:0] rain_units_bcd;
logic [3:0] rain_tenths_bcd;

// Rain submodule: total rainfall and ddd.d mm BCD digits
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

//==========================================================
// LCD display: 8x1 character LCD, format ddd.d mm
//==========================================================

localparam int LCD_COLS = 8;

// Slot type and data
//  slot_type: 00 = BCD digit, 01 = ASCII
logic [1:0] lcd_slot_type [LCD_COLS];
logic [7:0] lcd_slot_data [LCD_COLS];

// Formatter -> HD44780 LCD ASCII stream
logic [7:0] lcd_ascii;
logic       lcd_ascii_valid;

// LCD internal signals
logic [7:0] lcd_data;
logic       lcd_rs;
logic       lcd_rw;
logic       lcd_en;
logic       lcd_init_done;

// Combinational: map rain BCD digits to 8 slots
// Format: ddd.d mm (as shown in spec figure for 17.2mm)
// Slot 0: rain_hundreds_bcd
// Slot 1: rain_tens_bcd
// Slot 2: rain_units_bcd
// Slot 3: decimal point '.'
// Slot 4: rain_tenths_bcd
// Slot 5: space ' '
// Slot 6: 'm'
// Slot 7: 'm'
integer i;

always_comb begin
  // Default: space ASCII
  for(i = 0; i < LCD_COLS; i++) begin
    lcd_slot_type[i] = 2'b01;
    lcd_slot_data[i] = 8'h20;
  end

  // Slot 0: Hundreds digit - suppress leading zero
  if(rain_hundreds_bcd == 4'd0) begin
    lcd_slot_type[0] = 2'b01;       // ASCII space
    lcd_slot_data[0] = 8'h20;
  end else begin
    lcd_slot_type[0] = 2'b00;       // BCD digit
    lcd_slot_data[0] = {4'b0000, rain_hundreds_bcd};
  end

  // Slot 1: Tens digit - suppress if hundreds is also zero
  if(rain_hundreds_bcd == 4'd0 && rain_tens_bcd == 4'd0) begin
    lcd_slot_type[1] = 2'b01;       // ASCII space
    lcd_slot_data[1] = 8'h20;
  end else begin
    lcd_slot_type[1] = 2'b00;       // BCD digit
    lcd_slot_data[1] = {4'b0000, rain_tens_bcd};
  end

  // Slot 2: Units digit - always display (at least one digit before decimal)
  lcd_slot_type[2] = 2'b00;
  lcd_slot_data[2] = {4'b0000, rain_units_bcd};

  // Slot 3: Decimal point '.'
  lcd_slot_type[3] = 2'b01;
  lcd_slot_data[3] = 8'h2E;

  // Slot 4: Tenths digit - always display
  lcd_slot_type[4] = 2'b00;
  lcd_slot_data[4] = {4'b0000, rain_tenths_bcd};

  // Slot 5: Space separator
  lcd_slot_type[5] = 2'b01;
  lcd_slot_data[5] = 8'h20;

  // Slot 6-7: Unit "mm"
  lcd_slot_type[6] = 2'b01;
  lcd_slot_data[6] = "m";

  lcd_slot_type[7] = 2'b01;
  lcd_slot_data[7] = "m";
end

// Slots -> ASCII stream
lcd_formatter_8x1 #(
  .CLK_HZ(32768),
  .COLS(LCD_COLS),
  .CHAR_PERIOD_MS(2)
) u_lcd_formatter_8x1 (
  .clk        (Clock),
  .rst_n      (nReset),
  .lcd_ready  (lcd_init_done),
  .slot_type  (lcd_slot_type),
  .slot_data  (lcd_slot_data),
  .ascii_out  (lcd_ascii),
  .ascii_valid(lcd_ascii_valid)
);

// ASCII stream -> HD44780 LCD timing
lcd #(
  .CLK_HZ(32768),
  .COLS  (LCD_COLS)
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

// SPI controller for wind vane ADC
// Generates 16 clock pulses with ~9ms periods, CS low during transfer
// Repeats every ~2 seconds

localparam int SPI_WAIT_CYCLES = 65536;   // ~2s at 32768 Hz
localparam int SPI_HALF_PERIOD = 148;     // ~4.5ms half period (9ms full period)

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
    spi_state      <= SPI_IDLE;
    spi_wait_cnt   <= '0;
    spi_period_cnt <= '0;
    spi_bit_cnt    <= '0;
    SPICLK         <= 1'b1;
    nVaneCS        <= 1'b1;
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
        end else begin
          spi_wait_cnt <= spi_wait_cnt + 1;
        end
      end

      SPI_CLK_HIGH: begin
        SPICLK <= 1'b1;
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

// this module makes no attempt to communicate with the LCD

assign RS  = lcd_rs;
assign RnW = lcd_rw;      // This design is write-only (lcd_rw is always 0)
assign En  = lcd_en;

assign DB_Out     = lcd_data;
assign DB_nEnable = 1'b0; // Always drive data bus

anemometer u_ane(
  .clk(Clock),
  .rst_n(nReset),
  .anemo_sw(nWind),
  .slot_type(),
  .slot_data(),
  .wind_tenths()
);


endmodule
