
// Module  : uart_top
// Purpose : Top-level integration of baud_gen, uart_tx, uart_rx.
//           No FIFO — CPU must read rx_data within one frame period.
//
// Hierarchy:
//   uart_top
//   ├── baud_gen  (shared 16× tick for TX and RX)
//   ├── uart_tx   (serialises a byte on tx pin)
//   └── uart_rx   (deserialises a byte from rx pin)
//
// Usage (transmit):
//   1. Poll or wait for tx_busy == 0.
//   2. Drive tx_data with the byte to send.
//   3. Pulse tx_start high for exactly ONE clk cycle.
//   4. Wait until tx_done pulses high (frame complete).
//
// Usage (receive):
//   1. Poll for rx_done == 1.
//   2. Read rx_data on the same or next clock cycle.
//   3. Check parity_err and frame_err; discard byte if either is set.
//
// Notes:
//   - parity_en and parity_type must match the remote sender/receiver.
//   - At 115200 baud (8N1) you have ~87 µs per byte to read rx_data
//     before the next frame arrives (overrun risk without a FIFO).

`include "transmitter.v"
`include "receiver.v"
`include "baud_generator.v"
module uart_top #(
    parameter integer CLK_HZ = 50_000_000,  // system clock frequency (Hz)
    parameter integer BAUD   = 115_200       // baud rate
)(
    input  wire       clk,
    input  wire       rst_n,

    // Transmit interface 
    input  wire       tx_start,     // 1-cycle pulse to begin TX
    input  wire [7:0] tx_data,      // byte to transmit
    input  wire       parity_en,    // 1 = include parity bit
    input  wire       parity_type,  // 0 = even, 1 = odd
    output wire       tx,           // serial TX output pin
    output wire       tx_busy,      // high while frame in progress
    output wire       tx_done,      // 1-cycle pulse when frame done

    // Receive interface
    input  wire       rx,           // serial RX input pin (async)
    output wire [7:0] rx_data,      // received byte
    output wire       rx_done,      // 1-cycle pulse: rx_data valid
    output wire       parity_err,   // 1-cycle pulse: parity mismatch
    output wire       frame_err     // 1-cycle pulse: framing error
);
    //Shared 16× baud tick 
    wire s_tick;
    baud_gen #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) u_baud_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .tick16x(s_tick)
    );
    //Transmitter
    uart_tx #(
        .DATA_BITS  (8),
        .STOP_TICKS (16)    // 1 stop bit
    ) u_uart_tx (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_tick      (s_tick),
        .tx_start    (tx_start),
        .din         (tx_data),
        .parity_en   (parity_en),
        .parity_type (parity_type),
        .tx          (tx),
        .tx_busy     (tx_busy),
        .tx_done     (tx_done)
    );
    //  Receiver 
    uart_rx #(
        .DATA_BITS  (8),
        .STOP_TICKS (16)
    ) u_uart_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_tick      (s_tick),
        .rx          (rx),
        .parity_en   (parity_en),
        .parity_type (parity_type),
        .dout        (rx_data),
        .rx_done     (rx_done),
        .parity_err  (parity_err),
        .frame_err   (frame_err)
    );
endmodule
