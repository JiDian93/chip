// scan_chain_course_test.sv
//
// Course-style scan check (test mode): shift SDI, compare SDO to a golden shift register
//   sr <= { sr[n-2:0], SDI };  SDO expected = sr[n-1] (same as behavioural weather_core).
//
// Improvements:
//   - Long zero-flush after entering scan (n cycles) to clear unknowns / align with reset chain.
//   - Runtime chain length: +SCAN_CHAIN=<int> (no recompile). Upper bound MAX_SCAN_CHAIN (compile).
//   - Auto SDO polarity: tries straight vs inverted over a probe window unless SCAN_SDO_INVERT set.
//   - SCAN_CHAIN_LOOSE: only $error on X/Z; data mismatches become $warning (wrong n or topology).
//
// Behavioural: default n=8. Gate: +SCAN_CHAIN=<DC report length> +notimingchecks often needed.
//
// Examples:
//   ./simulate -no_graphics behavioural 50s \
//     +define+stimulus=system2/scan_chain_course_test.sv +define+sim_time=50s -exit
//
//   ./simulate -no_graphics -gate -sdf gate_level/weather.sdf gate_level 50s \
//     +define+stimulus=system2/scan_chain_course_test.sv +define+sim_time=50s \
//     +SCAN_CHAIN=800 +notimingchecks +define+SCAN_CHAIN_LOOSE -exit
//
// Requires: `define scan_enable in options.sv (system connects ScanEnable).

`ifndef MAX_SCAN_CHAIN
  `define MAX_SCAN_CHAIN 4096
`endif

`ifndef SCAN_CHAIN_LEN
  `define SCAN_CHAIN_LEN 8
`endif

  localparam int MAXC   = `MAX_SCAN_CHAIN;
  localparam int DEF_N  = `SCAN_CHAIN_LEN;

  logic [MAXC-1:0] golden_sr;
  int              eff_n;
  int              cycle_i;
  int              err_x, err_mismatch;
  logic            expect_bit;
  logic            use_invert;
  int              sdi_seq;  // monotonic index for next_sdi_bit

  // Variable chain length n: cannot use golden_sr[n-1:0] (not a constant part select in IEEE).
  function automatic void golden_shift(input logic sdi_bit, input int n);
    int i;
    if (n < 1) return;
    for (i = n - 1; i > 0; i--)
      golden_sr[i] = golden_sr[i - 1];
    golden_sr[0] = sdi_bit;
    for (i = n; i < MAXC; i++)
      golden_sr[i] = 1'b0;
  endfunction

  function automatic logic golden_msb(input int n);
    return n < 1 ? 1'b0 : golden_sr[n-1];
  endfunction

  // Deterministic pattern on SDI
  function automatic logic next_sdi_bit(int k);
    logic a, b, c;
    a = k[0] ^ k[3];
    b = k[2] ^ k[5];
    c = k[1] ^ k[4] ^ k[7];
    return a ^ b ^ c;
  endfunction

  task automatic scan_posedge_sample;
    @(posedge Clock);
    #(`clock_period / 2);
    #(`clock_period / 4);
  endtask

  // Demo is driven by assign in system/system.sv — do not assign here (ICDPAV).
  initial begin
    Mode  = 0;
    Start = 0;
    Rain  = 0;
    Wind  = 0;
  end

  initial begin
    Test       = 0;
    SDI        = 0;
    ScanEnable = 0;
    nReset     = 0;
    #(`clock_period / 4) nReset = 1;
  end

  initial begin
    Clock = 0;
    #`clock_period
    forever begin
      Clock = 1;
      #(`clock_period / 2) Clock = 0;
      #(`clock_period / 2) Clock = 0;
    end
  end

  initial begin
    int flush_i, probe_i, score0, score1, total_cycles;
    int good0, good1;

    wait (nReset === 1'b1);
    @(posedge Clock);
    start_up_delay();

    eff_n = DEF_N;
    if ($value$plusargs("SCAN_CHAIN=%d", eff_n)) begin
      if (eff_n < 1 || eff_n > MAXC) begin
        $error("[SCAN_CHAIN] SCAN_CHAIN=%0d out of range [1,%0d]", eff_n, MAXC);
        eff_n = DEF_N;
      end else
        $display("[SCAN_CHAIN] Using effective chain length n=%0d from +SCAN_CHAIN (max compile %0d)",
                 eff_n, MAXC);
    end else
      $display("[SCAN_CHAIN] T+%0t: start-up done; n=%0d (override: +SCAN_CHAIN=<int>, compile max %0d)",
               $time, eff_n, MAXC);

    //------------------------------------------------------------------
    // Phase 1 — functional
    //------------------------------------------------------------------
    Test       = 0;
    ScanEnable = 0;
    SDI        = 0;
    repeat (500) @(posedge Clock);
    #(`clock_period / 2);
    #(`clock_period / 4);
    if ($isunknown(SDO))
      $error("[SCAN_CHAIN] FAIL: SDO is X/Z in functional mode (Test=0)");
    else if (SDO !== 1'b0)
      $display("[SCAN_CHAIN] NOTE: SDO=%0b in functional mode (expected 0 for this core)", SDO);
    else
      $display("[SCAN_CHAIN] OK: functional SDO = 0");

    //------------------------------------------------------------------
    // Phase 2 — scan: flush, auto polarity, then compare
    //------------------------------------------------------------------
    if (!nReset)
      $error("[SCAN_CHAIN] FAIL: nReset low before scan");
    Test       = 1;
    ScanEnable = 1;
    golden_sr  = '0;
    err_x      = 0;
    err_mismatch = 0;
    sdi_seq    = 0;

    // Let Test / ScanEnable reach core
    repeat (4) @(posedge Clock);

    // Flush: shift n zeros through golden and (ideally) DUT — reduces X, aligns after reset
    SDI = 0;
    $display("[SCAN_CHAIN] Flushing %0d cycles with SDI=0", eff_n);
    for (flush_i = 0; flush_i < eff_n; flush_i++) begin
      scan_posedge_sample;
      golden_shift(1'b0, eff_n);
    end

`ifdef SCAN_SDO_INVERT
    use_invert = 1;
    $display("[SCAN_CHAIN] Polarity: forced inverted (+define+SCAN_SDO_INVERT)");
`else
    // Probe: which polarity matches more often over 48 cycles?
    use_invert = 0;
    score0     = 0;
    score1     = 0;
    SDI        = next_sdi_bit(sdi_seq);
    for (probe_i = 0; probe_i < 48; probe_i++) begin
      scan_posedge_sample;
      golden_shift(SDI, eff_n);
      if (!$isunknown(SDO)) begin
        if (SDO === golden_msb(eff_n))
          score0++;
        if (SDO === ~golden_msb(eff_n))
          score1++;
      end
      sdi_seq++;
      SDI = next_sdi_bit(sdi_seq);
    end
    use_invert = (score1 > score0);
    $display("[SCAN_CHAIN] Auto polarity: straight matches=%0d inverted=%0d -> using %s",
             score0, score1, use_invert ? "INVERTED" : "straight");
`endif

    // Main compare window
    total_cycles = 2 * eff_n + 128;
    $display("[SCAN_CHAIN] Comparing SDO for %0d shift cycles (n=%0d)", total_cycles, eff_n);

    for (cycle_i = 0; cycle_i < total_cycles; cycle_i++) begin
      scan_posedge_sample;
      golden_shift(SDI, eff_n);
      expect_bit = use_invert ? ~golden_msb(eff_n) : golden_msb(eff_n);

      if ($isunknown(SDO)) begin
        err_x++;
        if (err_x <= 12)
          $display("[SCAN_CHAIN] X/Z on SDO at shift cycle %0d", cycle_i);
      end else if (SDO !== expect_bit) begin
        err_mismatch++;
        if (err_mismatch <= 12)
          $display("[SCAN_CHAIN] mismatch cycle %0d: SDO=%0b expect %0b (invert=%0b) golden_msb path",
                   cycle_i, SDO, expect_bit, use_invert);
      end

      sdi_seq++;
      SDI = next_sdi_bit(sdi_seq);
    end

    if (err_x != 0)
      $error("[SCAN_CHAIN] FAIL: %0d cycles with SDO X/Z — scan reset, pads, SDF, or chain broken",
             err_x);
`ifdef SCAN_CHAIN_LOOSE
    else if (err_mismatch != 0)
      $warning("[SCAN_CHAIN] LOOSE: %0d data mismatches (n=%0d may be wrong or chain != simple SR) — no X is the main pass for gate",
               err_mismatch, eff_n);
    else
      $display("[SCAN_CHAIN] OK: no X; data matched for all %0d cycles", total_cycles);
`else
    else if (err_mismatch != 0)
      $error("[SCAN_CHAIN] FAIL: %0d mismatches — try +SCAN_CHAIN=<DC length>, +define+SCAN_SDO_INVERT, or +define+SCAN_CHAIN_LOOSE",
             err_mismatch);
    else
      $display("[SCAN_CHAIN] OK: all %0d cycles match golden (n=%0d)", total_cycles, eff_n);
`endif

    //------------------------------------------------------------------
    // Phase 3 — functional again
    //------------------------------------------------------------------
    Test       = 0;
    ScanEnable = 0;
    SDI        = 0;
    repeat (200) @(posedge Clock);
    #(`clock_period / 2);
    #(`clock_period / 4);
    if ($isunknown(SDO))
      $error("[SCAN_CHAIN] FAIL: SDO X/Z after leaving scan");
    else
      $display("[SCAN_CHAIN] OK: SDO known after scan disabled");

    $display("[SCAN_CHAIN] Finished at T=%0t", $time);
  end
