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
  set_driving_cell -max -library c35_IOLIB_WC -lib_cell BU24P -pin PAD [all_inputs]
  set_driving_cell -min -library c35_IOLIB_WC -lib_cell BU1P  -pin PAD [all_inputs]
  set_false_path -from [get_ports nReset]
}

run_step "remove_attribute" {remove_attribute [get_cells RESET_SYNC_FF*] dont_touch}

run_step "compile_scan" {compile -scan}

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

run_step "create_test_protocol" {create_test_protocol}

run_step "set_scan_configuration" {set_scan_configuration -chain_count 1}

run_step "preview_dft" {preview_dft}

run_step "insert_dft" {insert_dft}

run_step "dft_drc" {dft_drc}

run_step "report_names" {report_names -rules verilog}

run_step "change_names" {change_names -rules verilog -hierarchy}

run_step "write_verilog" {write -f verilog -hierarchy -output "../gate_level/weather.v"}

run_step "write_sdc" {write_sdc ../constraints/weather.sdc}

run_step "write_sdf" {write_sdf ../gate_level/weather.sdf}

exit
