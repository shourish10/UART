
// Module  : uart_rx
// Purpose : UART receiver (no FIFO).
//           Detects start bit, samples each bit at mid-point,
//           optionally checks parity, detects framing errors.
//
// Key design decisions:
//   1. 2-FF synchroniser on rx input (metastability protection).
//   2. Start bit confirmed at tick 7 (mid-point of START period).
//      If rx_s = 1 at tick 7 → false start, return to IDLE.
//   3. Data bits sampled at tick 15 (mid-point of each bit period).
//   4. LSB arrives first from the transmitter → shift right.
//
// Parameters
//   DATA_BITS  : 5–8 (default 8)
//   STOP_TICKS : 16 = 1 stop bit | 32 = 2 stop bits
//
// Outputs
//   dout        : received parallel byte (valid when rx_done = 1)
//   rx_done     : 1-cycle pulse indicating a new valid byte in dout
//   parity_err  : 1-cycle pulse — parity mismatch detected
//   frame_err   : 1-cycle pulse — stop bit was 0 (framing error)


module uart_rx #(
    parameter integer DATA_BITS  = 8,
    parameter integer STOP_TICKS = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  s_tick,       // 16× baud tick
    input  wire                  rx,           // async serial input
    input  wire                  parity_en,    // 1 = expect parity bit
    input  wire                  parity_type,  // 0 = even, 1 = odd
    output reg  [DATA_BITS-1:0] dout,         // received byte
    output reg                  rx_done,      // byte ready (valid for 1 clk)
    output reg                  parity_err,   // parity error flag
    output reg                  frame_err     // framing error flag
);
 
    // State encoding
  
    localparam [2:0]
        ST_IDLE  = 3'd0,
        ST_START = 3'd1,
        ST_DATA  = 3'd2,
        ST_PAR   = 3'd3,
        ST_STOP  = 3'd4;
    
    // 2-FF synchroniser (prevents metastability on async RX input)
   
    reg rx_ff1, rx_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ff1 <= 1'b1; // line idles high
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= rx;
            rx_ff2 <= rx_ff1;
        end
    end
    wire rx_s = rx_ff2; // synchronised, metastability-safe RX signal

   
    // Internal registers
   
    reg [2:0]           state;
    reg [3:0]           tick_cnt; // 0..15 within each bit period
    reg [3:0]           bit_cnt;  // 0..DATA_BITS-1
    reg [DATA_BITS-1:0] shift_reg;   // assembled data word
    reg                 rx_par_rcv; // parity bit captured from line

    
    // Sequential FSM
  
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            tick_cnt   <= 4'd0;
            bit_cnt    <= 4'd0;
            shift_reg  <= {DATA_BITS{1'b0}};
            dout       <= {DATA_BITS{1'b0}};
            rx_done    <= 1'b0;
            parity_err <= 1'b0;
            frame_err  <= 1'b0;
            rx_par_rcv <= 1'b0;
        end else begin

            // Default: clear single-cycle status pulses
            rx_done    <= 1'b0;
            parity_err <= 1'b0;
            frame_err  <= 1'b0;

            case (state)

         
            // IDLE — wait for falling edge on RX (start-bit detection)
          
            ST_IDLE: begin
                if (!rx_s) begin           // falling edge detected
                    state    <= ST_START;
                    tick_cnt <= 4'd0;
                end
            end

           
            // START — wait to tick 7 (mid-point) then confirm start bit
         
            ST_START: begin
                if (s_tick) begin
                    if (tick_cnt == 4'd7) begin
                        if (!rx_s) begin
                            // Valid start bit confirmed
                            tick_cnt <= 4'd0;
                            bit_cnt  <= 4'd0;
                            state    <= ST_DATA;
                        end else begin
                            // False start (noise) — back to idle
                            state <= ST_IDLE;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

          
            // DATA — sample each bit at mid-point (tick 15)
            //        Shift right because LSB arrives first
       
            ST_DATA: begin
                if (s_tick) begin
                    if (tick_cnt == 4'd15) begin
                        tick_cnt  <= 4'd0;
                        // Insert received bit at MSB position then shift right.
                        // After DATA_BITS shifts, shift_reg holds the byte
                        // correctly assembled (LSB in bit 0).
                        shift_reg <= {rx_s, shift_reg[DATA_BITS-1:1]};
                        if (bit_cnt == DATA_BITS - 1) begin
                            state <= parity_en ? ST_PAR : ST_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

         
            // PAR — sample the parity bit at mid-point
          
            ST_PAR: begin
                if (s_tick) begin
                    if (tick_cnt == 4'd15) begin
                        tick_cnt   <= 4'd0;
                        rx_par_rcv <= rx_s;   // store received parity
                        state      <= ST_STOP;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // STOP — sample stop bit, check errors, output data
       
            ST_STOP: begin
                if (s_tick) begin
                    if (tick_cnt == STOP_TICKS - 1) begin
                        state <= ST_IDLE;
                        if (!rx_s) begin
                            // Stop bit must be '1'; if '0' → framing error
                            frame_err <= 1'b1;
                        end else begin
                            // Framing OK — check parity if enabled
                            if (parity_en) begin
                                if (parity_type == 1'b0)
                                    // Even: XOR of data bits XOR received parity = 0
                                    parity_err <= (^shift_reg) ^ rx_par_rcv;
                                else
                                    // Odd: XOR of data bits XOR received parity = 1
                                    parity_err <= ~((^shift_reg) ^ rx_par_rcv);
                            end
                            // Latch data and signal done
                            dout    <= shift_reg;
                            rx_done <= 1'b1;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // Safety net
            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
