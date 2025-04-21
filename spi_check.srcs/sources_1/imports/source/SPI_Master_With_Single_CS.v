///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              With single chip-select (AKA Slave Select) capability
//
//              Supports arbitrary length byte transfers.
// 
//              Instantiates a SPI Master and adds single CS.
//              If multiple CS signals are needed, will need to use different
//              module, OR multiplex the CS from this at a higher level.
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
//
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
//              MAX_BYTES_PER_CS - Set to the maximum number of bytes that
//              will be sent during a single CS-low pulse.
// 
//              CS_INACTIVE_CLKS - Sets the amount of time in clock cycles to
//              hold the state of Chip-Selct high (inactive) before next 
//              command is allowed on the line.  Useful if chip requires some
//              time when CS is high between trasnfers.
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// Description: SPI Master With Single CS
//  - Wraps the SPI_Master module to automatically drive the chip-select (CS)
//    signal for multi-word transfers. Each word is DATA_WIDTH bits.
//  - The state machine controls CS so that a transaction spans multiple words.
// Parameters:
//   SPI_MODE, CLKS_PER_HALF_BIT: as before
//   MAX_BYTES_PER_CS: maximum words per CS low period.
//   CS_INACTIVE_CLKS: idle time (in clock cycles) after transaction.
//   DATA_WIDTH: bit width of each word.
// In our project, we will set DATA_WIDTH = 15.
///////////////////////////////////////////////////////////////////////////////
module SPI_Master_With_Single_CS
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 2,
    parameter MAX_BYTES_PER_CS = 2,
    parameter CS_INACTIVE_CLKS = 1,
    parameter DATA_WIDTH = 8)
  (
   // Control/Data Signals
   input         i_Rst_L,
   input         i_Clk,
   // TX (MOSI) Signals
   input  [$clog2(MAX_BYTES_PER_CS+1)-1:0] i_TX_Count,  // Number of words to transfer
   input  [DATA_WIDTH-1:0]  i_TX_Byte,  // Word to transmit
   input         i_TX_DV,     // Data valid pulse for word
   output        o_TX_Ready,  // Ready for next word
   // RX (MISO) Signals
   output reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] o_RX_Count, // Count of words received
   output        o_RX_DV,     // Data valid pulse (1 clock)
   output [DATA_WIDTH-1:0] o_RX_Byte, // Word received
   // SPI Interface
   output        o_SPI_Clk,
   input         i_SPI_MISO,
   output        o_SPI_MOSI,
   output        o_SPI_CS_n  // Generated chip-select (active low)
   );

  localparam IDLE        = 2'b00;
  localparam TRANSFER    = 2'b01;
  localparam CS_INACTIVE = 2'b10;

  reg [1:0] r_SM_CS;
  reg       r_CS_n;
  reg [$clog2(CS_INACTIVE_CLKS)-1:0] r_CS_Inactive_Count;
  reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_TX_Count;
  wire w_Master_Ready;

  // Instantiate the SPI_Master module with parameterized DATA_WIDTH
  SPI_Master
    #(.SPI_MODE(SPI_MODE),
      .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
      .DATA_WIDTH(DATA_WIDTH)
     ) SPI_Master_Inst (
       .i_Rst_L(i_Rst_L),
       .i_Clk(i_Clk),
       .i_TX_Byte(i_TX_Byte),
       .i_TX_DV(i_TX_DV),
       .o_TX_Ready(w_Master_Ready),
       .o_RX_DV(o_RX_DV),
       .o_RX_Byte(o_RX_Byte),
       .o_SPI_Clk(o_SPI_Clk),
       .i_SPI_MISO(i_SPI_MISO),
       .o_SPI_MOSI(o_SPI_MOSI)
     );

  // State machine to control chip-select (CS)
  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      r_SM_CS <= IDLE;
      r_CS_n  <= 1'b1;   // Default CS high (inactive)
      r_TX_Count <= 0;
      r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
    end else begin
      case (r_SM_CS)
        IDLE: begin
          if (r_CS_n & i_TX_DV) begin
            r_TX_Count <= i_TX_Count - 1;
            r_CS_n     <= 1'b0;  // Drive CS low to start transaction
            r_SM_CS    <= TRANSFER;
          end
        end
        TRANSFER: begin
          if (w_Master_Ready) begin
            if (r_TX_Count > 0) begin
              if (i_TX_DV)
                r_TX_Count <= r_TX_Count - 1;
            end else begin
              r_CS_n  <= 1'b1;  // Transaction complete: drive CS high
              r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
              r_SM_CS <= CS_INACTIVE;
            end
          end
        end
        CS_INACTIVE: begin
          if (r_CS_Inactive_Count > 0)
            r_CS_Inactive_Count <= r_CS_Inactive_Count - 1;
          else
            r_SM_CS <= IDLE;
        end
        default: begin
          r_CS_n  <= 1'b1;
          r_SM_CS <= IDLE;
        end
      endcase
    end
  end

  // Track the count of received words
  always @(posedge i_Clk) begin
    if (r_CS_n)
      o_RX_Count <= 0;
    else if (o_RX_DV)
      o_RX_Count <= o_RX_Count + 1;
  end

  assign o_SPI_CS_n = r_CS_n;
  assign o_TX_Ready  = ((r_SM_CS == IDLE) || (r_SM_CS == TRANSFER && w_Master_Ready && (r_TX_Count > 0))) & ~i_TX_DV;

endmodule