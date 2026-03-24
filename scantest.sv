// Scan-chain focused stimulus for gate-level simulation.
// Included into system/system.sv via +define++stimulus=system2/scantest.sv

localparam integer SCAN_PATTERN_LEN = 8;
localparam integer MAX_SCAN_DELAY   = 16384;
localparam integer POST_PASS_CYCLES = 3000;
localparam integer RESET_HOLD_CYCLES = 32;
localparam integer FLUSH_CYCLES     = 1024;
localparam [SCAN_PATTERN_LEN-1:0] SCAN_PATTERN = 8'b1011_0010;

reg tx_bits [0:SCAN_PATTERN_LEN-1];
reg rx_bits [0:SCAN_PATTERN_LEN+MAX_SCAN_DELAY-1];
integer i, d;
integer found_delay;
integer found_inv;
integer is_match;
integer scan_cycle_count;
integer cycle_after_reset;
integer first_sdo_rise_after_reset;
integer first_sdo_edge_after_reset;
reg observed_bit;
reg sdo_monitor_enable;
reg sdo_prev_sampled;

task automatic scan_shift_sample(
  input  reg sdi_bit,
  output reg sdo_bit
);
  begin
    // Drive SDI away from active edge, then sample SDO at active edge.
    @(negedge Clock);
    SDI = sdi_bit;
    @(posedge Clock);
    sdo_bit = SDO;
  end
endtask

initial begin
  // Keep non-scan asynchronous inputs quiet.
  Mode    = 0;
  Start   = 0;
  Rain    = 0;
  Wind    = 0;
  Button3 = 0;
  mode_index = 0;

  // Requirement: enable scan mode first.
  Test       = 1'b1;
  ScanEnable = 1'b1;
  SDI        = 1'b0;
  nReset     = 1'b0;
  sdo_monitor_enable = 1'b0;
  scan_cycle_count   = 0;
  cycle_after_reset  = 0;
  first_sdo_rise_after_reset = -1;
  first_sdo_edge_after_reset = -1;
  sdo_prev_sampled   = 1'b0;

  // Keep reset low for one clock cycle, then release.
  repeat (1) @(posedge Clock);
  nReset = 1'b1;
  sdo_monitor_enable = 1'b1;
  sdo_prev_sampled = SDO;
  $display("[SCAN][RESET_RELEASE] time=%0t", $realtime);

  // Flush the scan chain: shift enough zeros to push initial state
  // through all FFs, eliminating the QN-connection transient.
  for (i = 0; i < FLUSH_CYCLES; i = i + 1) begin
    scan_shift_sample(1'b0, observed_bit);
  end
  sdo_prev_sampled = SDO;
  $display("[SCAN][FLUSH_DONE] time=%0t flushed=%0d cycles", $realtime, FLUSH_CYCLES);

  // Build a short deterministic scan pattern.
  for (i = 0; i < SCAN_PATTERN_LEN; i = i + 1) begin
    tx_bits[i] = SCAN_PATTERN[i];
  end

  // Shift pattern in and capture output stream.
  for (i = 0; i < SCAN_PATTERN_LEN; i = i + 1) begin
    scan_shift_sample(tx_bits[i], observed_bit);
    rx_bits[i] = observed_bit;
  end

  // Keep shifting zeros to observe delayed scan-out.
  for (i = SCAN_PATTERN_LEN; i < SCAN_PATTERN_LEN + MAX_SCAN_DELAY; i = i + 1) begin
    scan_shift_sample(1'b0, observed_bit);
    rx_bits[i] = observed_bit;
  end

  found_delay = -1;
  found_inv   = 0;

  // Search for delay n where SDO equals SDI (or inverse).
  for (d = 1; d <= MAX_SCAN_DELAY; d = d + 1) begin
    // Same-polarity match
    is_match = 1;
    for (i = 0; i < SCAN_PATTERN_LEN; i = i + 1) begin
      if (rx_bits[i + d] !== tx_bits[i]) begin
        is_match = 0;
        i = SCAN_PATTERN_LEN;
      end
    end
    if (is_match && (found_delay < 0)) begin
      found_delay = d;
      found_inv   = 0;
    end

    // Inverted-polarity match
    is_match = 1;
    for (i = 0; i < SCAN_PATTERN_LEN; i = i + 1) begin
      if (rx_bits[i + d] !== ~tx_bits[i]) begin
        is_match = 0;
        i = SCAN_PATTERN_LEN;
      end
    end
    if (is_match && (found_delay < 0)) begin
      found_delay = d;
      found_inv   = 1;
    end
  end

  if (found_delay < 0) begin
    $error("[SCAN][FAIL] No valid delay <= %0d found for same/inverse relation.", MAX_SCAN_DELAY);
  end else begin
    $display("[SCAN][PASS] Found delay n=%0d cycles, relation=%0s",
             found_delay, (found_inv ? "INVERSE" : "SAME"));
  end

  // Keep simulation running so gate-level waveform can clearly show
  // SDI/SDO relationship after long chain delay (e.g. n > 800).
  repeat (POST_PASS_CYCLES) @(posedge Clock);
  $stop;
  $finish;
end

always @(posedge Clock) begin
  if (sdo_monitor_enable) begin
    scan_cycle_count = scan_cycle_count + 1;
    if (nReset === 1'b1)
      cycle_after_reset = cycle_after_reset + 1;

    if (cycle_after_reset == 1) begin
      $display("[SCAN][FIRST_SAMPLE_AFTER_RESET] time=%0t cycle_after_reset=1 SDI=%0b SDO=%0b",
               $realtime, SDI, SDO);
    end

    // Only report the first clocked SDO edge after reset release.
    if ((first_sdo_edge_after_reset < 0) && (SDO !== sdo_prev_sampled)) begin
      first_sdo_edge_after_reset = cycle_after_reset;
      $display("[SCAN][FIRST_SDO_EDGE_AFTER_RESET] time=%0t cycle_after_reset=%0d SDO:%0b->%0b",
               $realtime, cycle_after_reset, sdo_prev_sampled, SDO);
    end

    // Keep this if you want the first 0->1 cycle specifically.
    if ((first_sdo_rise_after_reset < 0) &&
        (sdo_prev_sampled === 1'b0) &&
        (SDO === 1'b1)) begin
      first_sdo_rise_after_reset = cycle_after_reset;
      $display("[SCAN][FIRST_SDO_RISE_AFTER_RESET] time=%0t cycle_after_reset=%0d",
               $realtime, cycle_after_reset);
    end
  end
  sdo_prev_sampled = SDO;
end

initial begin
  Clock = 1'b0;
  #`clock_period;
  forever begin
    Clock = 1'b1;
    #(`clock_period / 2) Clock = 1'b0;
    #(`clock_period / 2) Clock = 1'b0;
  end
end
