# Prevent interactive paging ("--More--") in batch runs.
catch {set_app_var sh_enable_page_mode false}

proc run_step {name cmd} {
  echo "==> $name"
  if {[catch {uplevel #0 $cmd} err]} {
    echo "$name FAILED"
    echo "ERROR: $err"
    exit 1
  }
}

run_step "analyze" {
  analyze -format sv "../behavioural/anemometer.sv \
../behavioural/clock_divider.sv \
../behavioural/dual_button_detector.sv \
../behavioural/elapsed_time_counter.sv \
../behavioural/lcd.sv \
../behavioural/lcd_formatter_8x1.sv \
../behavioural/main_fsm.sv \
../behavioural/options.sv \
../behavioural/rain_gauge.sv \
../behavioural/time_counters.sv \
../behavioural/weather_core.sv \
../behavioural/wind_direction.sv \
../behavioural/pressure_temperature_core.sv \
../behavioural/weather.sv"
}

run_step "elaborate" {elaborate weather}

run_step "constraints" {
  create_clock -name master_clock  -period 30517.6 [get_ports Clock]
  set_clock_latency     2.5 [get_clocks master_clock]
  set_clock_transition  0.5 [get_clocks master_clock]
  set_clock_uncertainty 1.0 [get_clocks master_clock]
  set_input_delay  12.0 -max -network_latency_included -clock master_clock [remove_from_collection [all_inputs] [get_ports Clock]]
  set_input_delay  0.5 -min -network_latency_included -clock master_clock [remove_from_collection [all_inputs] [get_ports Clock]]
  set_output_delay 8.0 -max -network_latency_included -clock master_clock [all_outputs]
  set_output_delay 0.5 -min -network_latency_included -clock master_clock [all_outputs]

  set_load 1.0  -max [all_outputs]
  set_load 0.01 -min [all_outputs]
  # AREA: BU24P (24x strength) is overkill at 32.768 kHz and forces DC to
  # build long inverter chains downstream to taper the strong drive into the
  # core's small loads.  BU8P gives plenty of drive while letting DC use
  # smaller buffers internally - measurably reduces the inverter count.
  set_driving_cell -max -library c35_IOLIB_WC -lib_cell BU8P -pin PAD [all_inputs]
  set_driving_cell -min -library c35_IOLIB_WC -lib_cell BU1P -pin PAD [all_inputs]
  set_false_path -from [get_ports nReset]
}

run_step "remove_attribute" {remove_attribute [get_cells RESET_SYNC_FF*] dont_touch}

set compile_seqmap_no_scan_cell_inversion true

# ---------------------------------------------------------------------------
# AREA OPTIMIZATION SETUP
# Clock is 32.768 kHz (period = 30.5 us) so every path has enormous timing
# slack.  Tell DC to spend that slack on area instead.
# ---------------------------------------------------------------------------
run_step "area_setup" {
  # Hard target: drive the optimizer toward zero area.
  set_max_area 0

  # Bias resource sharing / arithmetic implementation toward smallest gates.
  if {[catch {set_resource_allocation area_only}     _]} {echo "  (set_resource_allocation not supported; skipping)"}
  if {[catch {set_resource_implementation area_only} _]} {echo "  (set_resource_implementation not supported; skipping)"}
  if {[catch {set_app_var hlo_resource_allocation area_only} _]} {}

  # Boolean structuring on, timing-driven structuring off -> smaller AOI/OAI maps.
  if {[catch {set_structure -boolean true -timing false} _]} {echo "  (set_structure flag not supported; skipping)"}

  # Allow DC to ungroup small DesignWare blocks so adders/comparators in
  # different modules can share logic.
  set_app_var compile_ultra_ungroup_dw true

  # Constant propagation through sequential elements (eliminates flops driven
  # by tied 0/1 - e.g. SDO, DB_nEnable in this design).
  set_app_var compile_seqmap_propagate_constants true

  # Cross-module resource sharing.
  if {[catch {set_app_var hdlin_enable_hier_synthesis_resource_sharing true} _]} {}

  # Slightly more aggressive register inference / flop-merging.
  if {[catch {set_app_var compile_register_replication false} _]} {}

  # Allow output-pin inversions in scan flops -> fewer inverters around scan path.
  if {[catch {set_app_var compile_seqmap_enable_output_inversion true} _]} {}
}

# Area-effort and map-effort cranked up; -boundary_optimization lets the tool
# erase logic that becomes constant once it sees through hierarchy.
run_step "compile_scan" {compile -scan -map_effort high -area_effort high -boundary_optimization}

# AREA: After the first compile, the DesignWare arithmetic blocks (dividers,
# multipliers, modulo, adders) still appear as black-box hierarchical
# instances.  Your QoR report showed Macro/Black Box Area = 919k, which is
# 24% of total cell area.  Flatten those (and all small leaf hierarchies)
# so the second compile pass can map them directly into standard cells and
# share gates across former module boundaries.
run_step "ungroup_for_area" {
  # Flatten leaf-level DesignWare components (DW_*) and any small blocks.
  if {[catch {ungroup -all -flatten -small -simple_names} err]} {
    # Older DC versions don't accept -small / -simple_names.  Fall back.
    echo "  (ungroup with full flags failed: $err - retrying simpler form)"
    ungroup -all -flatten
  }
}

# AREA: ungroup -all -flatten flattens USER hierarchy but DC tags DesignWare
# IP cells (DW_div_uns, DW_mod_uns, DW_mult_uns, ...) as protected and
# leaves them grouped, which is why the previous run still showed 919k of
# Macro/Black Box Area despite Hierarchical Cell Count dropping to 0.
# Find every DW_* reference cell and force it to be flattened so the next
# compile pass can map its internals directly into standard cells.
run_step "force_ungroup_dw" {
  # Match anything whose ref_name begins with DW (covers DW_*, DW01_*, DW02_*).
  set dw_cells [get_cells -hier -filter "ref_name =~ DW*"]
  set n [sizeof_collection $dw_cells]
  if {$n > 0} {
    echo "  found $n DesignWare cells - flattening"
    if {[catch {ungroup -flatten $dw_cells} err]} {
      echo "  ungroup of DW cells failed: $err"
    }
  } else {
    echo "  (no DW_* cells found - the 919k may come from a different source;"
    echo "   inspect ../gate_level/synth_reference.rpt after the run)"
  }
}

# Second incremental pass cleans up cells the first pass left over and
# re-maps the now-flat DW components.  Done BEFORE DFT insertion so we
# don't disturb the scan chain stitching later.
run_step "incremental_area_compile" {compile -incremental_mapping -area_effort high -map_effort high}

run_step "set_dft_signal_existing" {
  set_dft_signal -view existing_dft -type ScanClock   -port Clock  -timing {45 60}
  set_dft_signal -view existing_dft -type Reset       -port nReset -active_state 0
}

run_step "set_dft_signal_spec" {
  set_dft_signal -view spec -type TestMode    -port Test       -active_state 1
  set_dft_signal -view spec -type ScanEnable  -port ScanEnable -active_state 1
  set_dft_signal -view spec -type ScanDataIn  -port SDI
  set_dft_signal -view spec -type ScanDataOut -port SDO
}

run_step "set_dft_configuration_reset" {
  set_dft_configuration -fix_reset enable
  set_autofix_configuration -type reset -method mux -control Test -test_data nReset
}

run_step "set_dft_configuration_set" {
  set_dft_configuration -fix_set enable
  set_autofix_configuration -type set -method mux -control Test -test_data nReset
}

run_step "set_scan_configuration" {set_scan_configuration -chain_count 1 -add_lockup true}

run_step "create_test_protocol" {create_test_protocol}

run_step "preview_dft" {preview_dft}

set test_disable_find_best_scan_out true

run_step "insert_dft" {insert_dft}

# AREA: post-DFT netlist cleanup.  optimize_netlist works on the final mapped
# netlist (scan chain already in place) and rips out residual logic the
# compile passes left behind: dead cells, redundant inverter pairs,
# unconnected drivers, and so on.  Safe to run after insert_dft because it
# preserves scan connectivity by default.
run_step "optimize_netlist_area" {
  if {[catch {optimize_netlist -area} err]} {
    echo "  (optimize_netlist -area not supported in this DC version: $err)"
  }
}

run_step "dft_drc" {dft_drc > ../gate_level/dft_drc.rpt}

run_step "report_scan_path" {report_scan_path > ../gate_level/scan_chain.rpt}

run_step "report_qor" {report_qor > ../gate_level/report_qor.rpt}

run_step "report_area" {report_area > ../gate_level/synth_area.rpt}

# Hierarchical area breakdown - useful for spotting if any submodule is
# disproportionately large.
run_step "report_area_hier" {
  if {[catch {report_area -hierarchy > ../gate_level/synth_area_hier.rpt} err]} {
    echo "  (report_area -hierarchy not supported: $err)"
  }
}

# Reference report: should show 0 Macros / 0 Black Box Area after ungroup
# + incremental compile.  If you still see large Macro/Black Box numbers,
# the ungroup step didn't take and you'll want to investigate.
run_step "report_reference" {
  if {[catch {report_reference > ../gate_level/synth_reference.rpt} err]} {
    echo "  (report_reference not supported: $err)"
  }
}

run_step "report_names" {report_names -rules verilog}

run_step "change_names" {change_names -rules verilog -hierarchy}

run_step "write_verilog" {write -f verilog -hierarchy -output "../gate_level/weather.v"}

run_step "write_sdc" {write_sdc ../constraints/weather.sdc}

run_step "write_sdf" {write_sdf ../gate_level/weather.sdf}

exit
