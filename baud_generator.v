
// Module  : baud_gen
// Purpose : Parameterised baud-rate generator.
//           Produces a single-cycle pulse (tick16x) at 16× the
//           baud rate, used for oversampled TX and RX operation.
//
// Formula : DIVISOR = CLK_HZ / (BAUD × 16) − 1
//
// Examples
//   50 MHz → 115200 baud : DIVISOR = 26  (error +0.47%)
//   50 MHz →   9600 baud : DIVISOR = 324 (error +0.15%)
//   100 MHz→ 115200 baud : DIVISOR = 53  (error +0.24%)
//
// Ports
//   clk     - system clock (any frequency)
//   rst_n   - active-low synchronous reset
//   tick16x - one-cycle pulse every 1/(BAUD×16) seconds


module baud_gen #(
    parameter integer CLK_HZ = 50_000_000,  // system clock in Hz
    parameter integer BAUD   = 115_200       // target baud rate
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick16x
);
    // Compute the reload value at elaboration time
    localparam integer DIVISOR = (CLK_HZ / (BAUD * 16)) - 1;
    // Counter register — wide enough to hold DIVISOR
    integer cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 0;
            tick16x <= 1'b0;
        end else if (cnt == DIVISOR) begin
            cnt     <= 0;
            tick16x <= 1'b1;   // single-cycle pulse
        end else begin
            cnt     <= cnt + 1;
            tick16x <= 1'b0;
        end
    end

    
    // Simulation-only: print the computed divisor and actual baud rate
    
`ifdef SIM
    initial begin
        $display("[baud_gen] CLK_HZ=%0d  BAUD=%0d  DIVISOR=%0d  Actual=%0d baud  Error=%0.2f%%",
                  CLK_HZ, BAUD, DIVISOR,
                  CLK_HZ / ((DIVISOR + 1) * 16),
                  100.0 * ($itor(CLK_HZ / ((DIVISOR+1)*16)) - BAUD) / BAUD);
    end
`endif

endmodule
