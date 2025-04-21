`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Slave
//              Creates slave based on input configuration.
//              Receives a byte one bit at a time on MOSI
//              Will also push out byte data one bit at a time on MISO.  
//              Any data on input byte will be shipped out on MISO.
//              Supports multiple bytes per transaction when CS_n is kept 
//              low during the transaction.
//
// Note:        i_Clk must be at least 4x faster than i_SPI_Clk
//              MISO is tri-stated when not communicating.  Allows for multiple
//              SPI Slaves on the same interface.
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//              More info: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// Description: Parameterized SPI Slave
//  - Receives DATA_WIDTH bits from MOSI (stored in o_RX_Byte).
//  - Transmits a word on MISO with a significant portion SLAVE_TX_WIDTH;
//    the remaining (DATA_WIDTH - SLAVE_TX_WIDTH) bits are padded with zeros.
//  - Uses a chip-select (active low) to frame the transaction.
// Parameters:
//   SPI_MODE: as before,
//   DATA_WIDTH: overall word length (must match master; e.g., 15)
//   SLAVE_TX_WIDTH: number of significant bits to transmit (e.g., 2)
// In our design, the slave receives 15 bits and sends only 2 meaningful bits.
///////////////////////////////////////////////////////////////////////////////
module SPI_Slave
  #(parameter SPI_MODE = 0,
    parameter DATA_WIDTH = 15,
    parameter SLAVE_TX_WIDTH = 2)
  (
   // Control/Data Signals
   input              i_Rst_L,   // Active low reset
   input              i_Clk,     // System clock
   output reg         o_RX_DV,   // Data valid pulse (1 clock)
   output reg [DATA_WIDTH-1:0] o_RX_Byte, // Received word from MOSI
   input              i_TX_DV,   // Pulse to load transmit data
   input  [SLAVE_TX_WIDTH-1:0] i_TX_Byte, // Significant bits to send on MISO
   // SPI Interface
   input      i_SPI_Clk,
   output     o_SPI_MISO, // Tri-stated when CS is high
   input      i_SPI_MOSI,
   input      i_SPI_CS_n  // Active low chip-select
   );

  // Derived constant for full transfer bit count:
  localparam BIT_COUNT_WIDTH = $clog2(DATA_WIDTH);

  // SPI mode settings:
  wire w_CPOL = (SPI_MODE == 2) || (SPI_MODE == 3);
  wire w_CPHA = (SPI_MODE == 1) || (SPI_MODE == 3);
  // For the slave, choose a clock for data shifting. Use w_SPI_Clk =
  // (w_CPHA ? ~i_SPI_Clk : i_SPI_Clk).
  wire w_SPI_Clk = w_CPHA ? ~i_SPI_Clk : i_SPI_Clk;

  // Reception registers:
  reg [DATA_WIDTH-1:0] r_Temp_RX_Byte;
  reg [BIT_COUNT_WIDTH-1:0] r_RX_Bit_Count;
  reg r_RX_Done;
  // Cross-domain synchronizers for RX_DV:
  reg r2_RX_Done, r3_RX_Done;

  // Transmission registers:
  // r_TX_Byte holds the SLAVE_TX_WIDTH-bit data. It will be padded with zeros.
  reg [SLAVE_TX_WIDTH-1:0] r_TX_Byte;
  reg [BIT_COUNT_WIDTH-1:0] r_TX_Bit_Count; // Count from DATA_WIDTH-1 down to 0
  reg r_SPI_MISO_Bit;
  reg r_Preload_MISO;

  // ---------------------
  // RECEIVE LOGIC (from MOSI)
  // ---------------------
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n) begin
    if (i_SPI_CS_n) begin
      r_RX_Bit_Count <= DATA_WIDTH - 1;
      r_RX_Done <= 1'b0;
    end else begin
      r_Temp_RX_Byte <= {r_Temp_RX_Byte[DATA_WIDTH-2:0], i_SPI_MOSI};
      if (r_RX_Bit_Count == 0) begin
        r_RX_Done <= 1'b1;
        o_RX_Byte <= {r_Temp_RX_Byte[DATA_WIDTH-2:0], i_SPI_MOSI};
      end else begin
        r_RX_Bit_Count <= r_RX_Bit_Count - 1;
      end
    end
  end

  // Cross from SPI clock domain to i_Clk domain for o_RX_DV:
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      r2_RX_Done <= 1'b0;
      r3_RX_Done <= 1'b0;
      o_RX_DV <= 1'b0;
    end else begin
      r2_RX_Done <= r_RX_Done;
      r3_RX_Done <= r2_RX_Done;
      if (!r3_RX_Done && r2_RX_Done)
        o_RX_DV <= 1'b1;
      else
        o_RX_DV <= 1'b0;
    end
  end

  // ---------------------
  // TRANSMIT LOGIC (to MISO)
  // ---------------------
  // Latch TX data (only SLAVE_TX_WIDTH bits) on i_TX_DV.
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L)
      r_TX_Byte <= {SLAVE_TX_WIDTH{1'b0}};
    else if (i_TX_DV)
      r_TX_Byte <= i_TX_Byte;
  end

  // Control preload signal for MISO (CS high resets preload)
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n) begin
    if (i_SPI_CS_n)
      r_Preload_MISO <= 1'b1;
    else
      r_Preload_MISO <= 1'b0;
  end

  // Transmit shifting: count from DATA_WIDTH-1 downto 0.
  // For bits where the count is >= SLAVE_TX_WIDTH, drive 0;
  // else drive the corresponding bit from r_TX_Byte.
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n) begin
    if (i_SPI_CS_n) begin
      r_TX_Bit_Count <= DATA_WIDTH - 1;
      // On reset, preload: if DATA_WIDTH-1 < SLAVE_TX_WIDTH, output that bit;
      // otherwise, drive 0.
      if ((DATA_WIDTH - 1) < SLAVE_TX_WIDTH)
         r_SPI_MISO_Bit <= r_TX_Byte[DATA_WIDTH-1];
      else
         r_SPI_MISO_Bit <= 1'b0;
    end else begin
      r_TX_Bit_Count <= r_TX_Bit_Count - 1;
      if (r_TX_Bit_Count < SLAVE_TX_WIDTH)
         r_SPI_MISO_Bit <= r_TX_Byte[r_TX_Bit_Count];
      else
         r_SPI_MISO_Bit <= 1'b0;
    end
  end

  // Tri-state the MISO line when CS is high.
  assign o_SPI_MISO = i_SPI_CS_n ? 1'bZ : r_SPI_MISO_Bit;

endmodule

