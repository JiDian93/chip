module pressure_temperature_core(
  input  logic Clock,
  input  logic nReset,
  input  logic baro_pause,
  input  logic MISO,
  output logic MOSI,
  output logic SPICLK_out,
  output logic nBaroCS,
  output logic baro_quiet,
  output logic [1:0] pressure_slot_type [8],
  output logic [7:0] pressure_slot_data [8],
  output logic [1:0] temp_slot_type    [8],
  output logic [7:0] temp_slot_data    [8]
);
  timeunit 1ns;
  timeprecision 100ps;

  localparam logic [7:0] CMD_RESET    = 8'h1E;
  localparam logic [7:0] CMD_D1_256   = 8'h40;
  localparam logic [7:0] CMD_D2_256   = 8'h50;
  localparam logic [7:0] CMD_ADC_READ = 8'h00;
  localparam logic [7:0] CMD_PROM0    = 8'hA0;

  localparam int SPI_TICK_DIV      = 5;
  // Clock is ~32.768kHz (30.5176us period). Use cycle counts that satisfy
  // MS5803 timing with margin while keeping the update rate responsive.
  localparam int WAIT_RESET_CYCLES = 120;   // ~3.66ms, spec reset reload is 2.8ms
  localparam int WAIT_CONV_CYCLES  = 25;    // ~0.76ms, OSR=256 max conversion is 0.60ms
  localparam int WAIT_NEXT_CYCLES  = 200;

  typedef enum logic [5:0] {
    ST_IDLE,
    ST_SEND_RESET, ST_WAIT_RESET,
    ST_SEND_PROM, ST_WAIT_PROM, ST_STORE_PROM,
    ST_SEND_D1, ST_WAIT_D1_CONV,
    ST_READ_D1, ST_WAIT_D1_READ,
    ST_SEND_D2, ST_WAIT_D2_CONV,
    ST_READ_D2, ST_WAIT_D2_READ,
    ST_DECODE, ST_CYCLE_WAIT
  } state_t;

  state_t state;

  logic [16:0] wait_cnt;
  logic [2:0]  prom_idx;
  logic [15:0] c1, c2, c3, c4, c5, c6;
  logic [15:0] prom_word;
  logic [23:0] d1_raw, d2_raw;
  logic [15:0] pressure_mbar;
  logic signed [15:0] temp_c_x10;

  // ------------------------------------------------------------------
  // SPI transfer engine (CPOL=1, sample on rising edge)
  // ------------------------------------------------------------------
  logic [7:0]  tick_cnt;
  logic        spi_tick;
  logic        xfer_active, xfer_done;
  logic [5:0]  xfer_idx, xfer_total_bits;
  logic [7:0]  xfer_cmd;
  logic [23:0] xfer_rx_shift;
  logic [23:0] xfer_rx_data;
  logic [15:0] xfer_rx_data16;
  logic        xfer_phase_low;
  logic        cs_release_pending;
  logic        nBaroCS_drv;
  logic        MOSI_drv;

  logic        start_xfer;
  logic        clear_xfer_done;
  logic [7:0]  start_cmd;
  logic [5:0]  start_total_bits;

  logic [15:0] p_live;
  logic signed [15:0] t_live;

  logic        prom_done;
  logic        conv_guard;
  logic [16:0] conv_guard_cnt;
  logic        in_conv_zone;

  function automatic void ms5803_decode(
    input  logic [23:0] d1_in,
    input  logic [23:0] d2_in,
    input  logic [15:0] c1_i, c2_i, c3_i, c4_i, c5_i, c6_i,
    output logic [15:0] p_mbar_out,
    output logic signed [15:0] t_c_x10_out
  );
    logic signed [25:0] dT;
    logic signed [42:0] prod;
    logic signed [19:0] TEMP;
    logic signed [41:0] OFF, SENS;
    logic signed [51:0] dT_sq;
    logic signed [19:0] T2, tmp;
    logic signed [39:0] tmp_sq;
    logic signed [41:0] OFF2, SENS2;
    logic signed [60:0] d1s;
    logic signed [41:0] p_sub;
    logic signed [24:0] P;
    logic signed [17:0] t_rnd;
    begin
      dT = $signed({2'b00, d2_in}) - $signed({2'b00, c5_i, 8'b0});

      prod = dT * $signed({1'b0, c6_i});
      TEMP = 20'sd2000 + 20'(prod >>> 23);

      prod = $signed({1'b0, c4_i}) * dT;
      OFF  = $signed({9'b0, c2_i, 17'b0}) + 42'(prod >>> 6);

      prod = $signed({1'b0, c3_i}) * dT;
      SENS = $signed({10'b0, c1_i, 16'b0}) + 42'(prod >>> 7);

      T2 = 0; OFF2 = 0; SENS2 = 0;
      if (TEMP < 20'sd2000) begin
        dT_sq = dT * dT;
        T2    = 20'(dT_sq >>> 31);
        tmp   = TEMP - 20'sd2000;
        tmp_sq = tmp * tmp;
        OFF2  = ($signed({2'b00, tmp_sq}) * 42'sd61) >>> 4;
        SENS2 = $signed({2'b00, tmp_sq}) <<< 1;
        if (TEMP < -20'sd1500) begin
          tmp   = TEMP + 20'sd1500;
          tmp_sq = tmp * tmp;
          OFF2  = OFF2  + $signed({2'b00, tmp_sq}) * 42'sd20;
          SENS2 = SENS2 + $signed({2'b00, tmp_sq}) * 42'sd12;
        end
      end

      TEMP = TEMP - 20'(T2);
      OFF  = OFF  - OFF2;
      SENS = SENS - SENS2;

      d1s   = $signed({1'b0, d1_in}) * SENS;
      p_sub = 42'(d1s >>> 21) - OFF;
      P     = 25'(p_sub >>> 15);

      if (P < 25'sd30000)  P = 25'sd30000;
      if (P > 25'sd110000) P = 25'sd110000;
      if (TEMP < -20'sd4000) TEMP = -20'sd4000;
      if (TEMP >  20'sd8500) TEMP =  20'sd8500;

      p_mbar_out  = ($unsigned(P) + 50) / 100;
      t_rnd = (TEMP >= 0) ? 18'(TEMP + 20'sd5) : 18'(TEMP - 20'sd5);
      t_c_x10_out = t_rnd / 10;
    end
  endfunction

  always_ff @( posedge Clock, negedge nReset)
    if (!nReset) begin
      tick_cnt <= '0;
      spi_tick <= 1'b0;
    end else begin
      if (tick_cnt >= SPI_TICK_DIV - 1) begin
        tick_cnt <= '0;
        spi_tick <= 1'b1;
      end else begin
        tick_cnt <= tick_cnt + 1'b1;
        spi_tick <= 1'b0;
      end
    end


  always_ff @( posedge Clock, negedge nReset)
    if (!nReset) begin
      MOSI_drv       <= 1'b0;
      SPICLK_out     <= 1'b1;
      nBaroCS_drv    <= 1'b1;
      xfer_active    <= 1'b0;
      xfer_done      <= 1'b0;
      xfer_idx       <= '0;
      xfer_total_bits<= '0;
      xfer_cmd       <= '0;
      xfer_rx_shift  <= '0;
      xfer_rx_data   <= '0;
      xfer_rx_data16 <= '0;
      xfer_phase_low <= 1'b0;
      cs_release_pending <= 1'b0;
    end else begin
      if (baro_pause) begin
        // Release the shared bus immediately while wind-direction mode owns SPI.
        MOSI_drv           <= 1'b0;
        SPICLK_out         <= 1'b1;
        nBaroCS_drv        <= 1'b1;
        xfer_active        <= 1'b0;
        xfer_done          <= 1'b0;
        xfer_idx           <= '0;
        xfer_phase_low     <= 1'b0;
        cs_release_pending <= 1'b0;
      end else begin
        if (clear_xfer_done) xfer_done <= 1'b0;

        if (cs_release_pending) begin
          cs_release_pending <= 1'b0;
          nBaroCS_drv <= 1'b1;
          MOSI_drv <= 1'b0;
        end else if (start_xfer && !xfer_active) begin
          xfer_active     <= 1'b1;
          xfer_idx        <= '0;
          xfer_total_bits <= start_total_bits;
          xfer_cmd        <= start_cmd;
          xfer_rx_shift   <= '0;
          SPICLK_out      <= 1'b1;
          xfer_phase_low  <= 1'b0;
          nBaroCS_drv     <= 1'b0;
          MOSI_drv        <= start_cmd[7];
        end else if (xfer_active && spi_tick) begin
          if (!xfer_phase_low) begin
            // Falling edge: prepare next SDI bit, which is sampled on next rising edge.
            SPICLK_out <= 1'b0;
            xfer_phase_low <= 1'b1;
            if (xfer_idx < 6'd8) MOSI_drv <= xfer_cmd[7 - xfer_idx];
            else                 MOSI_drv <= 1'b0;
          end else begin
            // Rising edge: sample MISO.
            SPICLK_out <= 1'b1;
            xfer_phase_low <= 1'b0;

            if (xfer_idx >= 6'd8) begin
              xfer_rx_shift <= {xfer_rx_shift[22:0], MISO};
            end

            if (xfer_idx + 1 >= xfer_total_bits) begin
              xfer_active <= 1'b0;
              xfer_done   <= 1'b1;
              cs_release_pending <= 1'b1;
              xfer_rx_data   <= {xfer_rx_shift[22:0], MISO};
              xfer_rx_data16 <= {xfer_rx_shift[14:0], MISO};
            end else begin
              xfer_idx <= xfer_idx + 1'b1;
            end
          end
        end
      end
    end


  always_ff @( posedge Clock, negedge nReset)
    if (!nReset) begin
      state        <= ST_IDLE;
      wait_cnt     <= '0;
      prom_idx     <= 3'd1;
      c1 <= 16'd46372; c2 <= 16'd43981; c3 <= 16'd29059;
      c4 <= 16'd27842; c5 <= 16'd31553; c6 <= 16'd28165;
      prom_done    <= 1'b0;
      prom_word    <= '0;
      d1_raw       <= '0;
      d2_raw       <= '0;
      pressure_mbar<= 16'd1013;
      temp_c_x10   <= 16'sd250;
      start_xfer   <= 1'b0;
      clear_xfer_done <= 1'b0;
      start_cmd    <= 8'h00;
      start_total_bits <= 6'd0;
    end else begin
      start_xfer <= 1'b0;
      clear_xfer_done <= 1'b0;
      // Keep one common datapath for RTL and gate-level behavior consistency.
      ms5803_decode(d1_raw, d2_raw, c1, c2, c3, c4, c5, c6, p_live, t_live);

      if (baro_pause) begin
        state <= ST_IDLE;
        wait_cnt <= '0;
        prom_idx <= 3'd1;
      end else begin

      pressure_mbar <= p_live;
      temp_c_x10    <= t_live;

      case (state)
        ST_IDLE: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= 17'd4000) begin
            wait_cnt <= '0;
            clear_xfer_done <= 1'b1;
            if (prom_done) begin
              start_cmd <= CMD_D1_256;
              start_total_bits <= 6'd8;
              start_xfer <= 1'b1;
              state <= ST_SEND_D1;
            end else begin
              start_cmd <= CMD_RESET;
              start_total_bits <= 6'd8;
              start_xfer <= 1'b1;
              state <= ST_SEND_RESET;
            end
          end
        end

        ST_SEND_RESET: if (xfer_done && !start_xfer) begin
          wait_cnt <= '0;
          state <= ST_WAIT_RESET;
        end

        ST_WAIT_RESET: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= WAIT_RESET_CYCLES) begin
            wait_cnt <= '0;
            prom_idx <= 3'd1;
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_PROM0 + 8'd2;
            start_total_bits <= 6'd24; // 8 cmd + 16 data
            start_xfer <= 1'b1;
            state <= ST_SEND_PROM;
          end
        end

        ST_SEND_PROM: if (xfer_done && !start_xfer) begin
          prom_word <= xfer_rx_data16;
          state <= ST_STORE_PROM;
        end

        ST_STORE_PROM: begin
          // synthesis translate_off
          // $display("[BARO DBG] PROM[%0d] = 0x%04h (%0d) at %0t", prom_idx, prom_word, prom_word, $time);
          // synthesis translate_on
          unique case (prom_idx)
            3'd1: if (prom_word != 16'd0) c1 <= prom_word;
            3'd2: if (prom_word != 16'd0) c2 <= prom_word;
            3'd3: if (prom_word != 16'd0) c3 <= prom_word;
            3'd4: if (prom_word != 16'd0) c4 <= prom_word;
            3'd5: if (prom_word != 16'd0) c5 <= prom_word;
            3'd6: if (prom_word != 16'd0) c6 <= prom_word;
            default: ;
          endcase

          if (prom_idx >= 3'd6) begin
            prom_done <= 1'b1;
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_D1_256;
            start_total_bits <= 6'd8;
            start_xfer <= 1'b1;
            state <= ST_SEND_D1;
          end else begin
            prom_idx <= prom_idx + 1'b1;
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_PROM0 + {prom_idx + 1'b1, 1'b0};
            start_total_bits <= 6'd24;
            start_xfer <= 1'b1;
            state <= ST_SEND_PROM;
          end
        end

        ST_SEND_D1: if (xfer_done && !start_xfer) begin
          wait_cnt <= '0;
          state <= ST_WAIT_D1_CONV;
        end

        ST_WAIT_D1_CONV: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= WAIT_CONV_CYCLES) begin
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_ADC_READ;
            start_total_bits <= 6'd32;
            start_xfer <= 1'b1;
            state <= ST_READ_D1;
          end
        end

        ST_READ_D1: if (xfer_done && !start_xfer) begin
          // synthesis translate_off
          // $display("[BARO DBG] D1 raw = 0x%06h (%0d) at %0t", xfer_rx_data, xfer_rx_data, $time);
          // synthesis translate_on
          if (xfer_rx_data != 24'd0) d1_raw <= xfer_rx_data;
          clear_xfer_done <= 1'b1;
          start_cmd <= CMD_D2_256;
          start_total_bits <= 6'd8;
          start_xfer <= 1'b1;
          state <= ST_SEND_D2;
        end

        ST_SEND_D2: if (xfer_done && !start_xfer) begin
          wait_cnt <= '0;
          state <= ST_WAIT_D2_CONV;
        end

        ST_WAIT_D2_CONV: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= WAIT_CONV_CYCLES) begin
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_ADC_READ;
            start_total_bits <= 6'd32;
            start_xfer <= 1'b1;
            state <= ST_READ_D2;
          end
        end

        ST_READ_D2: if (xfer_done && !start_xfer) begin
          // synthesis translate_off
          // $display("[BARO DBG] D2 raw = 0x%06h (%0d) at %0t", xfer_rx_data, xfer_rx_data, $time);
          // synthesis translate_on
          if (xfer_rx_data != 24'd0) d2_raw <= xfer_rx_data;
          state <= ST_DECODE;
        end

        ST_DECODE: begin
          wait_cnt <= '0;
          state <= ST_CYCLE_WAIT;
        end

        ST_CYCLE_WAIT: begin
          wait_cnt <= wait_cnt + 1'b1;
          if (wait_cnt >= WAIT_NEXT_CYCLES) begin
            clear_xfer_done <= 1'b1;
            start_cmd <= CMD_D1_256;
            start_total_bits <= 6'd8;
            start_xfer <= 1'b1;
            state <= ST_SEND_D1;
          end
        end

        default: state <= ST_IDLE;
      endcase
      end
    end


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
    pressure_slot_type[7] = 2'b01; pressure_slot_data[7] = "b";
    pressure_slot_type[6] = 2'b01; pressure_slot_data[6] = "m";
    pressure_slot_type[5] = 2'b01; pressure_slot_data[5] = 8'h20;
    pressure_slot_type[4] = 2'b00; pressure_slot_data[4] = {4'b0000, p_ones};
    pressure_slot_type[3] = 2'b00; pressure_slot_data[3] = {4'b0000, p_tens};
    if (p_thou != 0 || p_hund != 0) begin
      pressure_slot_type[2] = 2'b00; pressure_slot_data[2] = {4'b0000, p_hund};
    end
    if (p_thou != 0) begin
      pressure_slot_type[1] = 2'b00; pressure_slot_data[1] = {4'b0000, p_thou};
    end
  end

  logic signed [15:0] t_abs;
  logic [3:0] t_tens, t_ones, t_tenths;
  assign t_abs = (temp_c_x10 < 0) ? -temp_c_x10 : temp_c_x10;
  assign t_tens = (t_abs / 100) % 10;
  assign t_ones = (t_abs / 10) % 10;
  assign t_tenths = t_abs % 10;

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      temp_slot_type[i] = 2'b01;
      temp_slot_data[i] = 8'h20;
    end
    temp_slot_type[7] = 2'b01; temp_slot_data[7] = "C";
    temp_slot_type[6] = 2'b01; temp_slot_data[6] = 8'h20;
    temp_slot_type[5] = 2'b00; temp_slot_data[5] = {4'b0000, t_tenths};
    temp_slot_type[4] = 2'b01; temp_slot_data[4] = ".";
    temp_slot_type[3] = 2'b00; temp_slot_data[3] = {4'b0000, t_ones};
    if (t_tens != 0) begin
      temp_slot_type[2] = 2'b00; temp_slot_data[2] = {4'b0000, t_tens};
    end
    temp_slot_type[1] = 2'b01; temp_slot_data[1] = (temp_c_x10 < 0) ? "-" : 8'h20;
  end

  // Detect states where a sensor ADC conversion may be in progress.
  assign in_conv_zone = (state == ST_SEND_D1) || (state == ST_WAIT_D1_CONV) ||
                        (state == ST_SEND_D2) || (state == ST_WAIT_D2_CONV);

  // Conversion guard: keeps SCLK quiet even after baro_pause forces the state
  // machine to IDLE, covering the remainder of any in-flight sensor conversion.
  always_ff @( posedge Clock, negedge nReset)
    if (!nReset) begin
      conv_guard     <= 1'b0;
      conv_guard_cnt <= '0;
    end else begin
      if (baro_pause && in_conv_zone) begin
        conv_guard     <= 1'b1;
        conv_guard_cnt <= '0;
      end else if (conv_guard) begin
        if (conv_guard_cnt >= WAIT_CONV_CYCLES) begin
          conv_guard <= 1'b0;
        end else begin
          conv_guard_cnt <= conv_guard_cnt + 1'b1;
        end
      end
    end


  always_ff @( posedge Clock, negedge nReset)
    if (!nReset) begin
      MOSI    <= 1'b0;
      nBaroCS <= 1'b1;
    end else begin
      MOSI    <= MOSI_drv;
      nBaroCS <= nBaroCS_drv;
    end

  // During reset/convert phases the MS5803 model requires a quiet SPI clock line.
  assign baro_quiet = conv_guard ||
                      (state != ST_IDLE && state != ST_DECODE && state != ST_CYCLE_WAIT);

endmodule