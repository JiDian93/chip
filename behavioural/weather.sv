module weather (
  input Clock,
  input nRain,
  input Demo,
  input nWind,
  output nVaneCS,
  output SPICLK,
  inout [7:0] DB,
  input nReset,
  output RnW,
  output nBaroCS,
  input nStart,
  output En,
  output RS,
  input MISO,
  output MOSI,
  input nMode,

  output SDO,
  input Test,
  input SDI,
  input ScanEnable

);



  wire CORE_nRain;
  wire CORE_Clock;
  wire CORE_nWind;
  wire CORE_Demo;
  wire [7:0] CORE_DB_In;
  wire [7:0] CORE_DB_Out;
  wire [7:0] CORE_DB_PadOut;
  wire CORE_DB_nEnable;
  wire CORE_SPICLK;
  wire CORE_nVaneCS;
  wire CORE_nReset;
  wire CORE_nStart;
  wire CORE_nBaroCS;
  wire CORE_RnW;
  wire CORE_MISO;
  wire CORE_EN;
  wire CORE_RS;
  wire CORE_nMode;
  wire CORE_MOSI;
  wire SYNC_MID_nReset;
  wire SYNC_IN_nReset;
  wire SYNC_IN_nMode;
  wire SYNC_MID_nMode;
  wire SYNC_IN_nStart;
  wire SYNC_MID_nStart;
  wire SYNC_IN_nRain;
  wire SYNC_MID_nRain;
  wire SYNC_IN_nWind;
  wire SYNC_MID_nWind;
  // This design only writes the character LCD bus, so always drive DB.
  // Avoiding tri-state selection here prevents gate-level X propagation.
  assign CORE_DB_PadOut = CORE_DB_Out;
  assign CORE_DB_In = DB;
  wire CORE_SDO;
  wire CORE_Test;
  wire CORE_SDI;
  wire CORE_ScanEnable;


  BU8P PAD_MOSI ( .PAD(MOSI), .A(CORE_MOSI) );
  BU8P PAD_nVaneCS ( .PAD(nVaneCS), .A(CORE_nVaneCS) );
  ICP PAD_MISO ( .PAD(MISO), .Y(CORE_MISO) );
  BU8P PAD_SPICLK ( .PAD(SPICLK), .A(CORE_SPICLK) );
  ICUP PAD_nMode ( .PAD(nMode), .Y(SYNC_IN_nMode) );
  ICUP PAD_nStart ( .PAD(nStart), .Y(SYNC_IN_nStart) );
  ICUP PAD_nRain ( .PAD(nRain), .Y(SYNC_IN_nRain) );
  BU8P PAD_nBaroCS ( .PAD(nBaroCS), .A(CORE_nBaroCS) );
  ICP PAD_Demo ( .PAD(Demo), .Y(CORE_Demo) );
  ICCK2P PAD_Clock ( .PAD(Clock), .Y(CORE_Clock) );
  ICP PAD_nReset ( .PAD(nReset), .Y(SYNC_IN_nReset) );
  BU8P PAD_DB_7 ( .PAD(DB[7]), .A(CORE_DB_PadOut[7]) );
  BU8P PAD_DB_6 ( .PAD(DB[6]), .A(CORE_DB_PadOut[6]) );
  BU8P PAD_DB_5 ( .PAD(DB[5]), .A(CORE_DB_PadOut[5]) );
  BU8P PAD_DB_4 ( .PAD(DB[4]), .A(CORE_DB_PadOut[4]) );
  BU8P PAD_DB_3 ( .PAD(DB[3]), .A(CORE_DB_PadOut[3]) );
  BU8P PAD_DB_2 ( .PAD(DB[2]), .A(CORE_DB_PadOut[2]) );
  ICUP PAD_nWind ( .PAD(nWind), .Y(SYNC_IN_nWind) );
  BU8P PAD_RS ( .PAD(RS), .A(CORE_RS) );
  BU8P PAD_RnW ( .PAD(RnW), .A(CORE_RnW) );
  BU8P PAD_EN ( .PAD(En), .A(CORE_EN) );
  BU8P PAD_DB_0 ( .PAD(DB[0]), .A(CORE_DB_PadOut[0]) );
  BU8P PAD_DB_1 ( .PAD(DB[1]), .A(CORE_DB_PadOut[1]) );

  ICP PAD_ScanEnable ( .PAD(ScanEnable), .Y(CORE_ScanEnable) );
  ICP PAD_Test ( .PAD(Test), .Y(CORE_Test) );
  ICP PAD_SDI ( .PAD(SDI), .Y(CORE_SDI) );
  BU8P PAD_SDO ( .PAD(SDO), .A(CORE_SDO) );

  // Reset synchronization: two-stage DFF syncs async reset to CORE_Cslock domain
  // synopsys dc_tcl_script_begin
  // set_dont_touch [get_cells RESET_SYNC_FF*]
  // synopsys dc_tcl_script_end

  DFC1 RESET_SYNC_FF1 (
  .D('1),              .Q(SYNC_MID_nReset), .C(CORE_Clock), .RN(SYNC_IN_nReset)
);

DFC1 RESET_SYNC_FF2 (
   .D(SYNC_MID_nReset), .Q(CORE_nReset),    .C(CORE_Clock), .RN(SYNC_IN_nReset)
);

  // Input synchronization: two-stage DFF syncs async inputs to CORE_Clock domain
  DFC1 NMODE_SYNC_FF1 (
    .D(SYNC_IN_nMode), .Q(SYNC_MID_nMode), .C(CORE_Clock), .RN(CORE_nReset)
  );
  DFC1 NMODE_SYNC_FF2 (
    .D(SYNC_MID_nMode), .Q(CORE_nMode), .C(CORE_Clock), .RN(CORE_nReset)
  );

  DFC1 NSTART_SYNC_FF1 (
    .D(SYNC_IN_nStart), .Q(SYNC_MID_nStart), .C(CORE_Clock), .RN(CORE_nReset)
  );
  DFC1 NSTART_SYNC_FF2 (
    .D(SYNC_MID_nStart), .Q(CORE_nStart), .C(CORE_Clock), .RN(CORE_nReset)
  );

  DFC1 NRAIN_SYNC_FF1 (
    .D(SYNC_IN_nRain), .Q(SYNC_MID_nRain), .C(CORE_Clock), .RN(CORE_nReset)
  );
  DFC1 NRAIN_SYNC_FF2 (
    .D(SYNC_MID_nRain), .Q(CORE_nRain), .C(CORE_Clock), .RN(CORE_nReset)
  );

  DFC1 NWIND_SYNC_FF1 (
    .D(SYNC_IN_nWind), .Q(SYNC_MID_nWind), .C(CORE_Clock), .RN(CORE_nReset)
  );
  DFC1 NWIND_SYNC_FF2 (
    .D(SYNC_MID_nWind), .Q(CORE_nWind), .C(CORE_Clock), .RN(CORE_nReset)
  );

  weather_core core_inst (
    .nRain(CORE_nRain),
    .Clock(CORE_Clock),
    .nWind(CORE_nWind),
    .Demo(CORE_Demo),
    .DB_In(CORE_DB_In),
    .DB_Out(CORE_DB_Out),
    .DB_nEnable(CORE_DB_nEnable),
    .SPICLK(CORE_SPICLK),
    .nVaneCS(CORE_nVaneCS),
    .nReset(CORE_nReset),
    .nStart(CORE_nStart),
    .nBaroCS(CORE_nBaroCS),
    .RnW(CORE_RnW),
    .MISO(CORE_MISO),
    .En(CORE_EN),
    .RS(CORE_RS),
    .nMode(CORE_nMode),
    .MOSI(CORE_MOSI)
  );

endmodule