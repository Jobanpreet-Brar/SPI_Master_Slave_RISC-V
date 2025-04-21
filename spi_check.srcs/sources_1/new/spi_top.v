`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/07/2025 02:45:19 PM
// Design Name: 
// Module Name: spi_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module spi_top (
    input         i_Rst_L,       // Active low reset
    input         i_Clk,         // System clock
    // Master side configuration and data
    input  [$clog2(2+1)-1:0] master_TX_Count,  // Number of words to transfer per CS; set to 1 for one word.
    input  [14:0] master_TX_Byte,  // 15-bit word to send from master
    input         master_TX_DV,    // Data valid pulse for master
    output        master_TX_Ready, // Indicates master ready for next word
    output        master_RX_DV,    // RX valid pulse (after full transfer)
    output [14:0] master_RX_Byte,  // 15-bit received word from slave
    output [($clog2(2+1))-1:0] master_RX_Count, // Count of received words
    // Slave side data
    input         slave_TX_DV,     // Data valid pulse for slave TX data load
    input  [1:0]  slave_TX_Byte,   // 2-bit data to send from slave (will be padded with zeros)
    output        slave_RX_DV,     // Slave receive valid pulse (after full transfer)
    output [14:0] slave_RX_Byte    // 15-bit word received from master
);

  // Internal SPI interconnect signals.
  wire spi_clk;
  wire spi_mosi;
  wire spi_miso;
  wire spi_cs_n;

  // Instantiate the SPI master with integrated CS.
  SPI_Master_With_Single_CS #(
      .SPI_MODE(0),
      .CLKS_PER_HALF_BIT(2),
      .MAX_BYTES_PER_CS(2),   // maximum number of words per transaction
      .CS_INACTIVE_CLKS(1),
      .DATA_WIDTH(15)         // 15-bit transfer
  ) u_spi_master (
      .i_Rst_L(i_Rst_L),
      .i_Clk(i_Clk),
      .i_TX_Count(master_TX_Count),
      .i_TX_Byte(master_TX_Byte),
      .i_TX_DV(master_TX_DV),
      .o_TX_Ready(master_TX_Ready),
      .o_RX_Count(master_RX_Count),
      .o_RX_DV(master_RX_DV),
      .o_RX_Byte(master_RX_Byte),
      .o_SPI_Clk(spi_clk),
      .i_SPI_MISO(spi_miso),
      .o_SPI_MOSI(spi_mosi),
      .o_SPI_CS_n(spi_cs_n)
  );

  // Instantiate the SPI slave.
  SPI_Slave #(
      .SPI_MODE(0),
      .DATA_WIDTH(15),    // Must match master's DATA_WIDTH
      .SLAVE_TX_WIDTH(2)  // Only 2 bits are significant for slave TX
  ) u_spi_slave (
      .i_Rst_L(i_Rst_L),
      .i_Clk(i_Clk),
      .o_RX_DV(slave_RX_DV),
      .o_RX_Byte(slave_RX_Byte),
      .i_TX_DV(slave_TX_DV),
      .i_TX_Byte(slave_TX_Byte),
      .i_SPI_Clk(spi_clk),
      .o_SPI_MISO(spi_miso),
      .i_SPI_MOSI(spi_mosi),
      .i_SPI_CS_n(spi_cs_n)
  );

endmodule
