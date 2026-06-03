# UART Transceiver in Verilog

## Overview

This project implements a configurable UART (Universal Asynchronous Receiver Transmitter) in Verilog HDL for asynchronous serial communication. The design includes UART Transmitter (TX), UART Receiver (RX), and a baud rate generator. Additional features such as parity generation/checking, framing error detection, and 16× oversampling have been implemented to improve communication reliability.

## Features

- 8-bit data transmission and reception
- Programmable baud rate generation
- Even/Odd parity generation and checking
- Start and stop bit handling
- 16× oversampling receiver
- Framing error detection
- Metastability protection using a 2-FF synchronizer
- Modular TX, RX, and baud generator design
- RTL and testbench verification

## Architecture

The UART subsystem consists of:
- Baud Rate Generator
- UART Transmitter (TX)
- UART Receiver (RX)
- Parity Generator/Checker
- Start Bit Detection Logic
- Framing Error Detection Logic
- Synchronization Circuitry

## Verification

The design was verified using a Verilog testbench in QuestaSim. Various test cases were simulated, including:
- Normal data transmission and reception
- Multiple consecutive transfers
- Parity error detection
- Framing error detection
- Different baud rate configurations

## Tools Used

- Verilog HDL
- QuestaSim

## Applications

- Embedded Systems
- FPGA-Based Communication Interfaces
- Microcontroller Serial Communication
- Debug and Monitoring Interfaces

## Author

Shourish
