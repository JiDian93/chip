module weather (
  output SDO,
  output RnW,
  input nReset,
  input [7:0] DB_In,
  output MOSI,
  input nWind,
  input nMode,
  output nVaneCS,
  output RS,
  input MISO,
  input Test,
  input nStart,
  input SDI,
  output EN,
  output SPICLK,
  input Demo,
  input ScanEnable,
  input nRain,
  output nBaroCS,
  input Clock
);

  wire CORE_SDO;
  wire CORE_RnW;
  wire CORE_nVaneCS;
  wire CORE_RS;
  wire CORE_MISO;
  wire CORE_nReset;
  wire [7:0] CORE_DB_In;
  wire CORE_MOSI;
  wire CORE_nWind;
  wire CORE_nMode;
  wire CORE_EN;
  wire CORE_SPICLK;
  wire CORE_Demo;
  wire CORE_ScanEnable;
  wire CORE_Test;
  wire CORE_SDI;
  wire CORE_nStart;
  wire CORE_nBaroCS;
  wire CORE_nRain;
  wire CORE_Clock;

  BU8P PAD_MOSI ( .PAD(MOSI), .A(CORE_MOSI) );
  BU8P PAD_nVaneCS ( .PAD(nVaneCS), .A(CORE_nVaneCS) );
  ICP PAD_MISO ( .PAD(MISO), .Y(CORE_MISO) );
  BU8P PAD_SPICLK ( .PAD(SPICLK), .A(CORE_SPICLK) );
  ICP PAD_nMode ( .PAD(nMode), .Y(CORE_nMode) );
  ICP PAD_nStart ( .PAD(nStart), .Y(CORE_nStart) );
  ICP PAD_nRain ( .PAD(nRain), .Y(CORE_nRain) );
  BU8P PAD_nBaroCS ( .PAD(nBaroCS), .A(CORE_nBaroCS) );
  ICP PAD_Demo ( .PAD(Demo), .Y(CORE_Demo) );
  BU8P PAD_SDO ( .PAD(SDO), .A(CORE_SDO) );
  ICP PAD_SDI ( .PAD(SDI), .Y(CORE_SDI) );
  ICCK2P PAD_Clock ( .PAD(Clock), .Y(CORE_Clock) );
  ICP PAD_nReset ( .PAD(nReset), .Y(CORE_nReset) );
  ICP PAD_Test ( .PAD(Test), .Y(CORE_Test) );
  ICP PAD_ScanEnable ( .PAD(ScanEnable), .Y(CORE_ScanEnable) );
  ICP PAD_DB_In_7 ( .PAD(DB_In[7]), .Y(CORE_DB_In[7]) );
  ICP PAD_DB_In_6 ( .PAD(DB_In[6]), .Y(CORE_DB_In[6]) );
  ICP PAD_DB_In_5 ( .PAD(DB_In[5]), .Y(CORE_DB_In[5]) );
  ICP PAD_DB_In_4 ( .PAD(DB_In[4]), .Y(CORE_DB_In[4]) );
  ICP PAD_DB_In_3 ( .PAD(DB_In[3]), .Y(CORE_DB_In[3]) );
  ICP PAD_DB_In_2 ( .PAD(DB_In[2]), .Y(CORE_DB_In[2]) );
  ICP PAD_nWind ( .PAD(nWind), .Y(CORE_nWind) );
  BU8P PAD_RS ( .PAD(RS), .A(CORE_RS) );
  BU8P PAD_RnW ( .PAD(RnW), .A(CORE_RnW) );
  BU8P PAD_EN ( .PAD(EN), .A(CORE_EN) );
  BU8P PAD_DB_In_0 ( .PAD(DB_In[0]), .A(CORE_DB_In[0]) );
  BU8P PAD_DB_In_1 ( .PAD(DB_In[1]), .A(CORE_DB_In[1]) );

  weather_core core_inst (
    .SDO(CORE_SDO),
    .RnW(CORE_RnW),
    .nVaneCS(CORE_nVaneCS),
    .RS(CORE_RS),
    .MISO(CORE_MISO),
    .nReset(CORE_nReset),
    .DB_In(CORE_DB_In),
    .MOSI(CORE_MOSI),
    .nWind(CORE_nWind),
    .nMode(CORE_nMode),
    .EN(CORE_EN),
    .SPICLK(CORE_SPICLK),
    .Demo(CORE_Demo),
    .ScanEnable(CORE_ScanEnable),
    .Test(CORE_Test),
    .SDI(CORE_SDI),
    .nStart(CORE_nStart),
    .nBaroCS(CORE_nBaroCS),
    .nRain(CORE_nRain),
    .Clock(CORE_Clock)
  );

endmodule
