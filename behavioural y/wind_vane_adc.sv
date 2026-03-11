///////////////////////////////////////////////////////////////////////
//
// Wind Vane ADC module (system2 stimulus version)
//
//    Returns 12-bit ADC value based on WindDirection (3.3V, 10k).
//    Same interface as system/wind_vane_adc.sv for drop-in use with
//    +define+stimulus=system2/storm1.sv (compile with -y system2 -y system).
//
///////////////////////////////////////////////////////////////////////

module wind_vane_adc (
  output SDATA,
  input SCLK,
  input nCS
  );

  timeunit 1ns;
  timeprecision 100ps;

  // WindDirection set by testbench (e.g. VANE.WindDirection=S)
  // Use 4-bit index: 0=N, 1=NNE, ..., 15=NNW (matches compass_t in system.sv)
  logic [3:0] WindDirection;

  // Nominal 12-bit ADC values per direction (3.3V, 10k). V=3.3*R/(10k+R), ADC=round(V/3.3*4096)
  function automatic logic [11:0] adc_for_dir(input logic [3:0] d);
    case (d)
      4'd0:  adc_for_dir = 12'd3143;  // N
      4'd1:  adc_for_dir = 12'd2458;  // NNE
      4'd2:  adc_for_dir = 12'd2570;  // NE
      4'd3:  adc_for_dir = 12'd335;   // ENE
      4'd4:  adc_for_dir = 12'd372;   // E
      4'd5:  adc_for_dir = 12'd264;   // ESE
      4'd6:  adc_for_dir = 12'd744;   // SE
      4'd7:  adc_for_dir = 12'd893;   // SSE
      4'd8:  adc_for_dir = 12'd1154;  // S
      4'd9:  adc_for_dir = 12'd1067;  // SSW
      4'd10: adc_for_dir = 12'd1476;  // SW
      4'd11: adc_for_dir = 12'd2556;  // WSW
      4'd12: adc_for_dir = 12'd3782;  // W
      4'd13: adc_for_dir = 12'd3425;  // WNW
      4'd14: adc_for_dir = 12'd2842;  // NW
      4'd15: adc_for_dir = 12'd2655;  // NNW
      default: adc_for_dir = 12'd3143;
    endcase
  endfunction

  logic data_out = 1;
  assign SDATA = (!nCS) ? data_out : 'z;

  // AD7466: 4 leading zeros then 12 bits MSB first; data valid on SCLK falling edge
  always @(negedge nCS) begin
    data_out = 0;
    repeat (3) @(negedge SCLK) data_out = 0;  // 1 zero before SCLK + 3 on first 3 negedges = 4 leading zeros
    // Shift out 12 bits MSB first (value for current WindDirection)
    begin
      logic [11:0] val;
      int b;
      val = adc_for_dir(WindDirection);
      for (b = 11; b >= 0; b = b - 1) begin
        @(negedge SCLK) data_out = val[b];
      end
    end
    @(negedge SCLK);
    data_out = 'z;
  end

endmodule
