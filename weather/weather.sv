module weather (
  input Clock,
  input nRain,
  input Demo,
  input nWind,
  output nVaneCS,
  output SPICLK,
  input [7:0] DB,
  input nReset,
  output RnW,
  output nBaroCS,
  input nStart,
  output En,
  output RS,
  input MISO,
  output MOSI,
  input nMode
);

wire [7:0] DB_In, DB_Out;
wire DB_nEnable;
assign DB = ( ! DB_nEnable ) ? DB_Out : 'z;
assign DB_In = DB;

  wire CORE_nRain;
  wire CORE_Clock;
  wire CORE_nWind;
  wire CORE_Demo;
  wire [7:0] CORE_DB;
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

  BU8P PAD_MOSI ( .PAD(MOSI), .A(CORE_MOSI) );
  BU8P PAD_nVaneCS ( .PAD(nVaneCS), .A(CORE_nVaneCS) );
  ICP PAD_MISO ( .PAD(MISO), .Y(CORE_MISO) );
  BU8P PAD_SPICLK ( .PAD(SPICLK), .A(CORE_SPICLK) );
  ICP PAD_nMode ( .PAD(nMode), .Y(CORE_nMode) );
  ICP PAD_nStart ( .PAD(nStart), .Y(CORE_nStart) );
  ICP PAD_nRain ( .PAD(nRain), .Y(CORE_nRain) );
  BU8P PAD_nBaroCS ( .PAD(nBaroCS), .A(CORE_nBaroCS) );
  ICP PAD_Demo ( .PAD(Demo), .Y(CORE_Demo) );
  ICCK2P PAD_Clock ( .PAD(Clock), .Y(CORE_Clock) );
  ICP PAD_nReset ( .PAD(nReset), .Y(CORE_nReset) );
  ICP PAD_DB_7 ( .PAD(DB[7]), .Y(CORE_DB[7]) );
  ICP PAD_DB_6 ( .PAD(DB[6]), .Y(CORE_DB[6]) );
  ICP PAD_DB_5 ( .PAD(DB[5]), .Y(CORE_DB[5]) );
  ICP PAD_DB_4 ( .PAD(DB[4]), .Y(CORE_DB[4]) );
  ICP PAD_DB_3 ( .PAD(DB[3]), .Y(CORE_DB[3]) );
  ICP PAD_DB_2 ( .PAD(DB[2]), .Y(CORE_DB[2]) );
  ICP PAD_nWind ( .PAD(nWind), .Y(CORE_nWind) );
  BU8P PAD_RS ( .PAD(RS), .A(CORE_RS) );
  BU8P PAD_RnW ( .PAD(RnW), .A(CORE_RnW) );
  BU8P PAD_EN ( .PAD(En), .A(CORE_EN) );
  BU8P PAD_DB_0 ( .PAD(DB[0]), .A(CORE_DB[0]) );
  BU8P PAD_DB_1 ( .PAD(DB[1]), .A(CORE_DB[1]) );

  weather_core core_inst (
    .nRain(CORE_nRain),
    .Clock(CORE_Clock),
    .nWind(CORE_nWind),
    .Demo(CORE_Demo),
    .DB_In(CORE_DB),
    // DB_Out/DB_nEnable are not connected in this simple wrapper
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
