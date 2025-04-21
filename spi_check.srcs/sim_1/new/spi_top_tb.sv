`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/07/2025 02:45:46 PM
// Design Name: 
// Module Name: spi_top_tb
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

module spi_top_tb;

    // Clock and reset signals
    logic i_Rst_L;
    logic i_Clk;

    // Master interface signals (15-bit transfers)
    logic [1:0] master_TX_Count;  // For one-word transfers, set to 1.
    logic [14:0] master_TX_Byte;   // 15-bit word to send.
    logic        master_TX_DV;
    logic        master_TX_Ready;
    logic        master_RX_DV;
    logic [14:0] master_RX_Byte;
    logic [1:0] master_RX_Count;

    // Slave interface signals
    logic        slave_TX_DV;
    logic [1:0]  slave_TX_Byte;    // 2-bit data for slave to send (will be padded)
    logic        slave_RX_DV;
    logic [14:0] slave_RX_Byte;

    // Instantiate the top module
    spi_top dut (
        .i_Rst_L(i_Rst_L),
        .i_Clk(i_Clk),
        .master_TX_Count(master_TX_Count),
        .master_TX_Byte(master_TX_Byte),
        .master_TX_DV(master_TX_DV),
        .master_TX_Ready(master_TX_Ready),
        .master_RX_DV(master_RX_DV),
        .master_RX_Byte(master_RX_Byte),
        .master_RX_Count(master_RX_Count),
        .slave_TX_DV(slave_TX_DV),
        .slave_TX_Byte(slave_TX_Byte),
        .slave_RX_DV(slave_RX_DV),
        .slave_RX_Byte(slave_RX_Byte)
    );

    // Clock Generation: 100 MHz, period = 10 ns.
    initial begin
      i_Clk = 0;
      forever #5 i_Clk = ~i_Clk;
    end

    // Reset Generation: Assert reset low for 20 ns.
    initial begin
      i_Rst_L = 0;
      #20;
      i_Rst_L = 1;
    end

    // Stimulus Process
    initial begin
      // Initialize master signals
      master_TX_Count = 1;           // One 15-bit word per transaction.
      master_TX_Byte  = 15'h1ABC;     // Example 15-bit value to send.
      master_TX_DV    = 0;
      // Initialize slave signals:
      // We will preload the slave with its 2-bit data.
      slave_TX_Byte   = 2'b11;        // The 2-bit data to be sent on MISO.
      slave_TX_DV     = 0;

      // Wait for reset deassertion and stabilization.
      @(posedge i_Rst_L);
      #50;

      // --- Step 1: Preload Slave's TX Data ---
      $display("Preloading slave TX data (2-bit value)...");
      slave_TX_DV = 1;
      #10;
      slave_TX_DV = 0;

      // Allow some extra time.
      #100;

      // --- Step 2: Start SPI Transaction ---
      $display("Starting SPI Transaction:");
      $display("  Master sends: %h", master_TX_Byte);
      $display("  Expecting slave to send: %b (padded to 15 bits)", slave_TX_Byte);
      master_TX_DV = 1;
      #10;
      master_TX_DV = 0;

      // Wait for master to indicate RX valid.
      wait (master_RX_DV);
      #20;

      $display("SPI Transaction Complete:");
      $display("  Master received: %h (RX Count: %0d)", master_RX_Byte, master_RX_Count);
      $display("  Slave received:  %h", slave_RX_Byte);

      #100;
      $finish;
    end

endmodule
