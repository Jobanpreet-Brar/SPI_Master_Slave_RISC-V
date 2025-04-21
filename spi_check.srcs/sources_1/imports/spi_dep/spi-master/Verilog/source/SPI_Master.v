`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              Creates master based on input configuration.
//              Sends a byte one bit at a time on MOSI
//              Will also receive byte data one bit at a time on MISO.
//              Any data on input byte will be shipped out on MOSI.
//
//              To kick-off transaction, user must pulse i_TX_DV.
//              This module supports multi-byte transmissions by pulsing
//              i_TX_DV and loading up i_TX_Byte when o_TX_Ready is high.
//
//              This module is only responsible for controlling Clk, MOSI, 
//              and MISO.  If the SPI peripheral requires a chip-select, 
//              this must be done at a higher level.
//
// Note:        i_Clk must be at least 2x faster than i_SPI_Clk
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//              More: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
///////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
// Description: Parameterized SPI Master
//  - Transmits DATA_WIDTH bits (MSB first) on MOSI and simultaneously
//    samples DATA_WIDTH bits from MISO.
//  - To trigger a transfer, pulse i_TX_DV when o_TX_Ready is high.
//  - The number of SPI clock edges is 2*DATA_WIDTH.
// Parameters:
//   SPI_MODE: 0, 1, 2, or 3 (defines CPOL/CPHA)
//   CLKS_PER_HALF_BIT: Number of i_Clk cycles per half SPI bit period.
//   DATA_WIDTH: Number of bits to transfer (default 8)
//     In our project, we will set DATA_WIDTH=15.
///////////////////////////////////////////////////////////////////////////////
module SPI_Master
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 2,
    parameter DATA_WIDTH = 8)
  (
   // Control/Data Signals
   input                 i_Rst_L,     // Active low reset
   input                 i_Clk,       // System clock
   // TX Signals
   input  [DATA_WIDTH-1:0] i_TX_Byte, // Word to transmit on MOSI
   input                 i_TX_DV,     // Data valid pulse to latch word
   output reg            o_TX_Ready,  // Indicates ready for next word
   // RX Signals
   output reg            o_RX_DV,     // Data valid pulse (1 clock)
   output reg [DATA_WIDTH-1:0] o_RX_Byte, // Word received on MISO
   // SPI Interface
   output reg            o_SPI_Clk,
   input                 i_SPI_MISO,
   output reg            o_SPI_MOSI
   );

  // Derived constant for bit-counter width
  localparam BIT_COUNT_WIDTH = $clog2(DATA_WIDTH);
 
  // Determine clock polarity and phase based on SPI_MODE.
  wire w_CPOL = (SPI_MODE == 2) || (SPI_MODE == 3);
  wire w_CPHA = (SPI_MODE == 1) || (SPI_MODE == 3);

  // Internal signals:
  reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count;
  reg [BIT_COUNT_WIDTH-1:0] r_TX_Bit_Count;
  reg [BIT_COUNT_WIDTH-1:0] r_RX_Bit_Count;
  reg [15:0] r_SPI_Clk_Edges; // Will count 2*DATA_WIDTH edges
  reg r_Leading_Edge, r_Trailing_Edge;
  reg r_TX_DV;
  reg [DATA_WIDTH-1:0] r_TX_Byte;

  // SPI clock edge generation:
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      o_TX_Ready      <= 1'b0;
      r_SPI_Clk_Edges <= 0;
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      o_SPI_Clk       <= w_CPOL;
      r_SPI_Clk_Count <= 0;
    end else begin
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      if (i_TX_DV) begin
        o_TX_Ready      <= 1'b0;
        r_SPI_Clk_Edges <= DATA_WIDTH * 2;  // Number of edges for full transfer
      end else if (r_SPI_Clk_Edges > 0) begin
        o_TX_Ready <= 1'b0;
        if (r_SPI_Clk_Count == (CLKS_PER_HALF_BIT*2 - 1)) begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;
          r_Trailing_Edge <= 1'b1;
          r_SPI_Clk_Count <= 0;
          o_SPI_Clk       <= ~o_SPI_Clk;
        end else if (r_SPI_Clk_Count == (CLKS_PER_HALF_BIT - 1)) begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;
          r_Leading_Edge  <= 1'b1;
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;
          o_SPI_Clk       <= ~o_SPI_Clk;
        end else begin
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;
        end
      end else begin
        o_TX_Ready <= 1'b1;
      end
    end
  end

  // Latch TX data when triggered:
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      r_TX_Byte <= {DATA_WIDTH{1'b0}};
      r_TX_DV   <= 1'b0;
    end else begin
      r_TX_DV <= i_TX_DV; // one cycle delay
      if (i_TX_DV)
        r_TX_Byte <= i_TX_Byte;
    end
  end

  // Generate MOSI output (transmit data, MSB first)
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      o_SPI_MOSI   <= 1'b0;
      r_TX_Bit_Count <= DATA_WIDTH - 1;
    end else begin
      if (o_TX_Ready)
        r_TX_Bit_Count <= DATA_WIDTH - 1;
      else if (r_TX_DV && !w_CPHA) begin
        o_SPI_MOSI   <= r_TX_Byte[DATA_WIDTH-1];
        r_TX_Bit_Count <= DATA_WIDTH - 2;
      end else if ((r_Leading_Edge && w_CPHA) || (r_Trailing_Edge && !w_CPHA)) begin
        o_SPI_MOSI <= r_TX_Byte[r_TX_Bit_Count];
        if (r_TX_Bit_Count > 0)
          r_TX_Bit_Count <= r_TX_Bit_Count - 1;
      end
    end
  end

  // Sample incoming MISO and build the RX word
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      o_RX_Byte <= {DATA_WIDTH{1'b0}};
      o_RX_DV   <= 1'b0;
      r_RX_Bit_Count <= DATA_WIDTH - 1;
    end else begin
      o_RX_DV <= 1'b0;
      if (o_TX_Ready)
        r_RX_Bit_Count <= DATA_WIDTH - 1;
      else if ((r_Leading_Edge && !w_CPHA) || (r_Trailing_Edge && w_CPHA)) begin
        o_RX_Byte[r_RX_Bit_Count] <= i_SPI_MISO;
        if (r_RX_Bit_Count > 0)
          r_RX_Bit_Count <= r_RX_Bit_Count - 1;
        else
          o_RX_DV <= 1'b1;  // Entire word received
      end
    end
  end

endmodule

