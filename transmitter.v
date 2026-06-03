
// Module  : uart_tx
// Purpose : UART transmitter (no FIFO).
//           The CPU presents din and asserts tx_start for exactly
//           ONE clock cycle. The FSM serialises the byte and
//           pulses tx_done when the stop bit is complete.
//
// Frame layout (8N1 example, LSB first):
//   IDLE(1) | START(0) | D0 D1 D2 D3 D4 D5 D6 D7 | [PAR] | STOP(1)
//
// Parameters
//   DATA_BITS  : word length, 5–8 (default 8)
//   STOP_TICKS : 16 = 1 stop bit | 24 = 1.5 | 32 = 2 stop bits
//
// Usage
//   1. Ensure tx_busy = 0.
//   2. Place data on din. Assert tx_start for one clk cycle.
//   3. Wait for tx_done pulse before sending the next byte.

module uart_tx #(
    parameter integer DATA_BITS  = 8,   // word length
    parameter integer STOP_TICKS = 16   // 16×baud ticks per stop bit(s)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 s_tick,       // 16× baud tick from baud_gen
    input  wire                 tx_start,     // 1-cycle pulse: begin frame
    input  wire [DATA_BITS-1:0] din,          // parallel data to transmit
    input  wire                 parity_en,    // 1 = include parity bit
    input  wire                 parity_type,  // 0 = even parity, 1 = odd
    output reg                  tx,           // serial output (idle = 1)
    output reg                  tx_busy,      // high during entire frame
    output reg                  tx_done       // 1-cycle pulse when frame done
);
    
    // State encoding
  
    localparam [2:0]
        ST_IDLE  = 3'd0,
        ST_START = 3'd1,
        ST_DATA  = 3'd2,
        ST_PAR   = 3'd3,
        ST_STOP  = 3'd4;
    reg [2:0]           state;
    reg [3:0]           tick_cnt; // counts 16× ticks within one bit period (0..15)
    reg [3:0]           bit_cnt;  // counts transmitted data bits (0..DATA_BITS-1)
    reg [DATA_BITS-1:0] shift_reg; // holds data while shifting

    
    // Parity bit generation
    //   Even: XOR of all data bits = 0  ⟹ par_bit = ^shift_reg
    //   Odd : XOR of all data bits = 1  ⟹ par_bit = ~^shift_reg
   
    wire par_bit = parity_type ? ~(^shift_reg) : (^shift_reg);

   
    // Sequential FSM
  
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            tx       <= 1'b1;    // idle mark (line high)
            tx_busy  <= 1'b0;
            tx_done  <= 1'b0;
            tick_cnt <= 4'd0;
            bit_cnt  <= 4'd0;
            shift_reg<= {DATA_BITS{1'b0}};
        end else begin

            // Default: clear single-cycle outputs each clock
            tx_done <= 1'b0;
            case (state)

            // IDLE — line is high, wait for tx_start
          
            ST_IDLE: begin
                tx      <= 1'b1;
                tx_busy <= 1'b0;
                if (tx_start) begin
                    shift_reg <= din; // latch data
                    tx_busy   <= 1'b1;
                    tick_cnt  <= 4'd0;
                    state     <= ST_START;
                end
            end


            // START — drive TX low for exactly one bit period (16 ticks)
          
            ST_START: begin
                tx <= 1'b0;
                if (s_tick) begin
                    if (tick_cnt == 4'd15) begin
                        tick_cnt <= 4'd0;
                        bit_cnt  <= 4'd0;
                        state    <= ST_DATA;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // DATA — shift out DATA_BITS bits, LSB first
        
            ST_DATA: begin
                tx <= shift_reg[0];   // LSB first
                if (s_tick) begin
                    if (tick_cnt == 4'd15) begin
                        tick_cnt  <= 4'd0;
                        // Right-shift: next LSB moves into position 0
                        shift_reg <= {{1{1'b0}}, shift_reg[DATA_BITS-1:1]};
                        if (bit_cnt == DATA_BITS - 1) begin
                            // All data bits sent — go to parity or stop
                            state <= parity_en ? ST_PAR : ST_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // PAR — transmit one parity bit
           
            ST_PAR: begin
                tx <= par_bit;
                if (s_tick) begin
                    if (tick_cnt == 4'd15) begin
                        tick_cnt <= 4'd0;
                        state    <= ST_STOP;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

            // STOP — drive TX high for STOP_TICKS ticks, then done
      
            ST_STOP: begin
                tx <= 1'b1;
                if (s_tick) begin
                    if (tick_cnt == STOP_TICKS - 1) begin
                        tx_done <= 1'b1; // frame complete
                        state   <= ST_IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
            end

       
            // Safety net — should never reach here
       
            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
