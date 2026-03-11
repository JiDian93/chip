///////////////////////////////////////////////////////////////////////
//
// pressure_temperature module
//
//  MS5803-02BA SPI pressure/temperature sensor driver.
//  Shares SPICLK and MISO with wind vane ADC; adds MOSI and nBaroCS.
//  Two display modes: pressure (e.g. "1013 mb"), temperature (e.g. " 25.3 C").
//  Protocol: Reset 0x1E, Convert D1 0x40, Convert D2 0x50, Read ADC 0x00 + 24 bits.
//
///////////////////////////////////////////////////////////////////////

module pressure_temperature(

  input  logic Clock,
  input  logic nReset,

  input  logic MISO,
  output logic MOSI,
  output logic SPICLK_out,
  output logic nBaroCS,

  output logic [1:0] pressure_slot_type [8],
  output logic [7:0] pressure_slot_data [8],
  output logic [1:0] temp_slot_type    [8],
  output logic [7:0] temp_slot_data    [8]

  );

  timeunit 1ns;
  timeprecision 100ps;

  //----------------------------------------------------------------------
  // MS5803 commands (8-bit)
  //----------------------------------------------------------------------
  localparam logic [7:0] CMD_RESET    = 8'h1E;
  localparam logic [7:0] CMD_D1_256   = 8'h40;  // pressure conversion OSR 256
  localparam logic [7:0] CMD_D2_256   = 8'h50;  // temperature conversion OSR 256
  localparam logic [7:0] CMD_ADC_READ = 8'h00;

  //----------------------------------------------------------------------
  // SPI timing: same style as wind_direction (~9 ms period for 32 kHz)
  //----------------------------------------------------------------------
  localparam int SPI_HALF_PERIOD = 148;
  localparam int CONV_WAIT_CYCLES = 40000;  // ~1.22 ms wait after conversion start

  typedef enum logic [3:0] {
    S_IDLE,
    S_RESET_CMD,
    S_RESET_WAIT,
    S_D1_CMD,
    S_D1_CONV_WAIT,
    S_D1_READ_CMD,
    S_D1_READ_24,
    S_D2_CMD,
    S_D2_CONV_WAIT,
    S_D2_READ_CMD,
    S_D2_READ_24,
    S_UPDATE,
    S_CYCLE_WAIT
  } state_t;

  state_t state;
  logic [16:0] wait_cnt;
  logic [7:0]  period_cnt;
  logic [4:0]  bit_cnt;   // 0..7 for 8-bit, 0..23 for 24-bit
  logic [7:0]  cmd_byte;
  logic [23:0] adc_shift;
  logic [23:0] D1_raw, D2_raw;

  // SPI clock: when we are in a transfer we toggle; otherwise hold high (idle)
  logic spi_clk_en;
  logic spi_clk_phase;
  // Meet sensor setup/hold: CS and SDI stable 25ns before/after posedge SCLK
  logic spi_cs_setup;   // one cycle delay before first SCLK edge after CS assert
  logic spi_cs_release;  // one cycle delay before CS deassert after last SCLK edge
  logic nBaroCS_int;     // internal CS; output is one cycle delayed to avoid hold violation

  always_ff @(posedge Clock or negedge nReset) begin
    if (!nReset) begin
      state      <= S_IDLE;
      wait_cnt   <= '0;
      period_cnt <= '0;
      bit_cnt    <= '0;
      nBaroCS_int<= 1'b1;
      MOSI       <= 1'b0;
      SPICLK_out <= 1'b1;
      spi_clk_en <= 1'b0;
      spi_clk_phase <= 1'b0;
      spi_cs_setup  <= 1'b0;
      spi_cs_release<= 1'b0;
      cmd_byte   <= '0;
      adc_shift  <= '0;
      D1_raw     <= 24'd0;
      D2_raw     <= 24'd0;
    end else begin
      case (state)
        S_IDLE: begin
          nBaroCS_int<= 1'b1;
          SPICLK_out <= 1'b1;
          MOSI       <= 1'b0;
          spi_clk_en <= 1'b0;
          wait_cnt   <= wait_cnt + 1'b1;
          if (wait_cnt >= 17'd65535) begin  // ~2 s between full reads
            wait_cnt <= '0;
            cmd_byte <= CMD_RESET;
            bit_cnt  <= '0;
            period_cnt <= '0;
            nBaroCS_int<= 1'b0;
            spi_cs_setup <= 1'b1;
            SPICLK_out <= 1'b0;  // no SCLK edge when asserting CS
            state    <= S_RESET_CMD;
          end
        end

        S_RESET_CMD: begin
          if (spi_cs_setup) begin
            spi_cs_setup <= 1'b0;
            MOSI <= cmd_byte[7];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (!spi_clk_en) begin
            MOSI <= cmd_byte[7 - bit_cnt];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
              if (bit_cnt < 5'd7) MOSI <= cmd_byte[7 - (bit_cnt + 1)];
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              if (bit_cnt >= 5'd7) begin
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                spi_cs_release <= 1'b1;
                state <= S_RESET_WAIT;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_RESET_WAIT: begin
          if (spi_cs_release) begin
            nBaroCS_int <= 1'b1;
            spi_cs_release <= 1'b0;
          end else if (wait_cnt >= 17'd1000) begin
            wait_cnt <= '0;
            cmd_byte <= CMD_D1_256;
            bit_cnt  <= '0;
            period_cnt <= '0;
            nBaroCS_int<= 1'b0;
            spi_cs_setup <= 1'b1;
            state    <= S_D1_CMD;
            SPICLK_out <= 1'b0;  // no SCLK edge when asserting CS
          end else
            SPICLK_out <= 1'b1;
          wait_cnt <= wait_cnt + 1'b1;
        end

        S_D1_CMD: begin
          if (spi_cs_setup) begin
            spi_cs_setup <= 1'b0;
            MOSI <= cmd_byte[7];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (!spi_clk_en) begin
            MOSI <= cmd_byte[7 - bit_cnt];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
              if (bit_cnt < 5'd7) MOSI <= cmd_byte[7 - (bit_cnt + 1)];
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              if (bit_cnt >= 5'd7) begin
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                spi_cs_release <= 1'b1;
                state <= S_D1_CONV_WAIT;
                wait_cnt <= '0;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_D1_CONV_WAIT: begin
          if (spi_cs_release) begin
            nBaroCS_int <= 1'b1;
            spi_cs_release <= 1'b0;
          end else if (wait_cnt >= CONV_WAIT_CYCLES) begin
            wait_cnt <= '0;
            cmd_byte <= CMD_ADC_READ;
            bit_cnt  <= '0;
            period_cnt <= '0;
            adc_shift <= '0;
            nBaroCS_int<= 1'b0;
            spi_cs_setup <= 1'b1;
            state    <= S_D1_READ_CMD;
            SPICLK_out <= 1'b0;
          end else
            SPICLK_out <= 1'b1;
          wait_cnt <= wait_cnt + 1'b1;
        end

        S_D1_READ_CMD: begin
          if (spi_cs_setup) begin
            spi_cs_setup <= 1'b0;
            MOSI <= cmd_byte[7];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (!spi_clk_en) begin
            MOSI <= cmd_byte[7 - bit_cnt];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
              if (bit_cnt < 5'd7) MOSI <= cmd_byte[7 - (bit_cnt + 1)];
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              adc_shift <= {adc_shift[22:0], MISO};
              if (bit_cnt >= 5'd7) begin
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                state <= S_D1_READ_24;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_D1_READ_24: begin
          if (!spi_clk_en) begin
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              adc_shift <= {adc_shift[22:0], MISO};
              if (bit_cnt >= 5'd23) begin
                D1_raw <= {adc_shift[22:0], MISO};
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                SPICLK_out <= 1'b1;
                cmd_byte <= CMD_D2_256;
                spi_cs_setup <= 1'b1;
                state <= S_D2_CMD;
                period_cnt <= '0;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_D2_CMD: begin
          if (spi_cs_setup) begin
            spi_cs_setup <= 1'b0;
            MOSI <= cmd_byte[7];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (!spi_clk_en) begin
            MOSI <= cmd_byte[7 - bit_cnt];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
              if (bit_cnt < 5'd7) MOSI <= cmd_byte[7 - (bit_cnt + 1)];
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              if (bit_cnt >= 5'd7) begin
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                spi_cs_release <= 1'b1;
                state <= S_D2_CONV_WAIT;
                wait_cnt <= '0;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_D2_CONV_WAIT: begin
          if (spi_cs_release) begin
            nBaroCS_int <= 1'b1;
            spi_cs_release <= 1'b0;
          end else if (wait_cnt >= CONV_WAIT_CYCLES) begin
            wait_cnt <= '0;
            cmd_byte <= CMD_ADC_READ;
            bit_cnt  <= '0;
            period_cnt <= '0;
            adc_shift <= '0;
            nBaroCS_int<= 1'b0;
            spi_cs_setup <= 1'b1;
            state    <= S_D2_READ_CMD;
            SPICLK_out <= 1'b0;
          end else
            SPICLK_out <= 1'b1;
          wait_cnt <= wait_cnt + 1'b1;
        end

        S_D2_READ_CMD: begin
          if (spi_cs_setup) begin
            spi_cs_setup <= 1'b0;
            MOSI <= cmd_byte[7];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (!spi_clk_en) begin
            MOSI <= cmd_byte[7 - bit_cnt];
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
              if (bit_cnt < 5'd7) MOSI <= cmd_byte[7 - (bit_cnt + 1)];
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              adc_shift <= {adc_shift[22:0], MISO};
              if (bit_cnt >= 5'd7) begin
                bit_cnt <= '0;
                spi_clk_en <= 1'b0;
                state <= S_D2_READ_24;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_D2_READ_24: begin
          if (!spi_clk_en) begin
            spi_clk_en <= 1'b1;
            spi_clk_phase <= 1'b1;
            period_cnt <= '0;
          end else if (spi_clk_phase) begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              SPICLK_out <= 1'b0;
              spi_clk_phase <= 1'b0;
            end else period_cnt <= period_cnt + 1'b1;
          end else begin
            if (period_cnt >= SPI_HALF_PERIOD - 1) begin
              period_cnt <= '0;
              adc_shift <= {adc_shift[22:0], MISO};
              if (bit_cnt >= 5'd23) begin
                D2_raw <= {adc_shift[22:0], MISO};
                spi_clk_en <= 1'b0;
                SPICLK_out <= 1'b1;
                spi_cs_release <= 1'b1;
                state <= S_UPDATE;
              end else begin
                bit_cnt <= bit_cnt + 1'b1;
                SPICLK_out <= 1'b1;
                spi_clk_phase <= 1'b1;
              end
            end else period_cnt <= period_cnt + 1'b1;
          end
        end

        S_UPDATE: begin
          if (spi_cs_release) begin
            nBaroCS_int<= 1'b1;
            spi_cs_release <= 1'b0;
          end
          state <= S_CYCLE_WAIT;
          wait_cnt <= '0;
        end

        S_CYCLE_WAIT: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= 17'd100) state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // Output register: nBaroCS one cycle behind internal to satisfy sensor hold time
  always_ff @(posedge Clock or negedge nReset) begin
    if (!nReset)
      nBaroCS <= 1'b1;
    else
      nBaroCS <= nBaroCS_int;
  end

  //----------------------------------------------------------------------
  // Simplified conversion: D1/D2 -> pressure (mbar) and temperature (0.1°C)
  // MS5803-02BA: P = f(D1, D2, C1..C6). Here we use a linear scaling for display.
  // Typical: D1 ~ 0x5F2E00, D2 ~ 0x6E6A00 for 1013 mbar, 25°C.
  // pressure_mbar = 300 + (D1>>12)*scale; temp_c_x10 = (D2 - 0x400000)*k
  //----------------------------------------------------------------------
  logic [15:0] pressure_mbar;   // 300..1100
  logic signed [15:0] temp_c_x10;  // -400 to +850 (i.e. -40.0°C to 85.0°C)

  logic [15:0] p_next;
  logic signed [15:0] t_next;

  always_ff @(posedge Clock or negedge nReset) begin
    if (!nReset) begin
      pressure_mbar <= 16'd1013;
      temp_c_x10    <= 16'sd250;  // 25.0°C
    end else if (state == S_UPDATE) begin
      p_next = 16'd300 + (D1_raw[23:12] * 16'd800 / 16'd4096);
      if (p_next > 16'd1100) p_next = 16'd1100;
      if (p_next < 16'd300)  p_next = 16'd300;
      pressure_mbar <= p_next;
      t_next = (($signed(D2_raw) - 24'sh400000) * 85 / 24'sh400000) + 16'sd250;
      if (t_next > 16'sd850) t_next = 16'sd850;
      if (t_next < -16'sd400) t_next = -16'sd400;
      temp_c_x10 <= t_next;
    end
  end

  //----------------------------------------------------------------------
  // Pressure LCD slots: "XXXX mb" (4 digits, space, m, b)
  //----------------------------------------------------------------------
  logic [3:0] p_thou, p_hund, p_tens, p_ones;
  assign p_thou = (pressure_mbar / 1000) % 10;
  assign p_hund = (pressure_mbar / 100) % 10;
  assign p_tens = (pressure_mbar / 10) % 10;
  assign p_ones = pressure_mbar % 10;

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      pressure_slot_type[i] = 2'b01;
      pressure_slot_data[i] = 8'h20;
    end
    if (p_thou == 4'd0) begin
      pressure_slot_type[0] = 2'b01;
      pressure_slot_data[0] = 8'h20;
    end else begin
      pressure_slot_type[0] = 2'b00;
      pressure_slot_data[0] = {4'b0000, p_thou};
    end
    if (p_thou == 4'd0 && p_hund == 4'd0) begin
      pressure_slot_type[1] = 2'b01;
      pressure_slot_data[1] = 8'h20;
    end else begin
      pressure_slot_type[1] = 2'b00;
      pressure_slot_data[1] = {4'b0000, p_hund};
    end
    pressure_slot_type[2] = 2'b00;
    pressure_slot_data[2] = {4'b0000, p_tens};
    pressure_slot_type[3] = 2'b00;
    pressure_slot_data[3] = {4'b0000, p_ones};
    pressure_slot_type[4] = 2'b01;
    pressure_slot_data[4] = 8'h20;
    pressure_slot_type[5] = 2'b01;
    pressure_slot_data[5] = "m";
    pressure_slot_type[6] = 2'b01;
    pressure_slot_data[6] = "b";
    pressure_slot_type[7] = 2'b01;
    pressure_slot_data[7] = 8'h20;
  end

  //----------------------------------------------------------------------
  // Temperature LCD slots: " XX.X C" or "-XX.X C" (sign, 2-3 digits, dot, 1 digit, space, C)
  //----------------------------------------------------------------------
  logic signed [15:0] t_abs;
  logic [3:0] t_tens, t_ones, t_tenths;
  assign t_abs = (temp_c_x10 < 0) ? -temp_c_x10 : temp_c_x10;
  assign t_tens   = (t_abs / 100) % 10;
  assign t_ones   = (t_abs / 10) % 10;
  assign t_tenths = t_abs % 10;

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      temp_slot_type[i] = 2'b01;
      temp_slot_data[i] = 8'h20;
    end
    if (temp_c_x10 < 0) begin
      temp_slot_type[0] = 2'b01;
      temp_slot_data[0] = "-";
    end else begin
      temp_slot_type[0] = 2'b01;
      temp_slot_data[0] = 8'h20;
    end
    if (t_tens == 4'd0) begin
      temp_slot_type[1] = 2'b01;
      temp_slot_data[1] = 8'h20;
    end else begin
      temp_slot_type[1] = 2'b00;
      temp_slot_data[1] = {4'b0000, t_tens};
    end
    temp_slot_type[2] = 2'b00;
    temp_slot_data[2] = {4'b0000, t_ones};
    temp_slot_type[3] = 2'b01;
    temp_slot_data[3] = ".";
    temp_slot_type[4] = 2'b00;
    temp_slot_data[4] = {4'b0000, t_tenths};
    temp_slot_type[5] = 2'b01;
    temp_slot_data[5] = 8'h20;
    temp_slot_type[6] = 2'b01;
    temp_slot_data[6] = "C";
    temp_slot_type[7] = 2'b01;
    temp_slot_data[7] = 8'h20;
  end

endmodule
