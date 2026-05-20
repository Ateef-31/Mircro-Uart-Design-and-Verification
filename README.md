
# UART Transceiver Design and Verification

##  Project Overview

This project implements a **parameterized UART (Universal Asynchronous Receiver Transmitter) transceiver** in Verilog HDL. The design supports full-duplex serial communication with 16x oversampling for reliable data recovery. A comprehensive self-checking testbench with reference model achieves **99.58% code coverage**.

---

##  Key Features

### Design Features
- **Parameterized Architecture** – Configurable word length (default: 8-bit), baud rate (default: 2400), and system clock (default: 100 MHz)
- **16x Oversampling** – Provides robust start bit detection and data recovery
- **2-FF Synchronizers** – Metastability removal for asynchronous inputs
- **Robust Receiver** – False start rejection, framing error detection, line initialization (32 consecutive HIGHs)
- **Full Transmitter** – Start/Stop bit generation, LSB-first data transmission
- **Asynchronous Reset** – Active-low reset for reliable initialization

### Verification Features
- **Self-Checking Testbench** – Automatic comparison with reference model
- **Reference Model** – Golden model for expected output generation
- **20 Directed Test Cases** – Covering all functional scenarios
- **Corner Case Coverage** – Glitch rejection, false start, framing error, back-to-back transmission
- **Timeout Protection** – Prevents simulation from hanging

---

##  Simulation Results

| Metric | Result |
|--------|--------|
| Total Test Cases | 20 |
| Tests Passed | 20 |
| Tests Failed | 0 |
| Pass Rate | **100%** |

### Code Coverage Metrics

| Coverage Type | Coverage % |
|---------------|------------|
| Statement Coverage | 100.00% |
| Branch Coverage | 97.50% |
| FEC Expression | 100.00% |
| FEC Condition | 100.00% | 
| Toggle Coverage | 100.00% |
| FSM State Coverage | 100.00% |
| FSM Transition Coverage | 100.00% |
| **Total Coverage** | **99.58%** | 


**Tools Used**
Simulation and Design code Development IDE : Vivado 2025  \
Code Coverage and Waveform generation : Questa csh 

**Author** \
Name: M ATEEF BAIG \
Role: Design and Verification Engineer
