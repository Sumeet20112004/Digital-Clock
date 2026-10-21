`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name   : button_synchronizer
// Description   : Three-stage flip-flop synchronizer chain for asynchronous
//                 button inputs on the Basys3 board. Prevents metastable
//                 voltage levels from propagating into the synchronous clock
//                 domain of the FPGA design.
//
// Problem solved: A button press occurs at a random moment in time, with no
//                 relationship to the FPGA clock. If the raw button signal is
//                 sampled directly by a flip-flop, it may arrive within the
//                 setup/hold time window around the clock edge, placing the
//                 flip-flop into a metastable state. A metastable output is
//                 neither a valid logic 0 nor a valid logic 1, and can cause
//                 different gates downstream to interpret the signal differently,
//                 corrupting the system state.
//
// Solution      : Each synchronizer stage is a D flip-flop clocked by the
//                 system clock. Metastability resolves exponentially with time:
//                   P(still metastable after T) ≈ C × e^(-T/τ)
//                 At 100 MHz (T = 10 ns per stage, τ ≈ 0.05 ns):
//                   After 1 stage: P ≈ 10^(-87)  — effectively zero
//                   After 2 stages: P ≈ 10^(-174) — used as minimum standard
//                 Three stages are used here for additional safety margin.
//
// Important     : This module solves the ELECTRONICS problem (metastability).
//                 It does NOT solve the MECHANICAL problem (contact bounce).
//                 Rapid bounce events (~5–20 ms after a press) may still
//                 register as multiple triggers. A separate debounce counter
//                 would be needed to address that.
//
// Latency       : btn_out is the btn_in signal delayed by exactly 3 clock cycles.
//////////////////////////////////////////////////////////////////////////////////

module button_synchronizer (
    input  wire clk,       // system clock (100 MHz)
    input  wire btn_in,    // raw asynchronous button input from board pin
    output wire btn_out    // synchronized, clock-aligned button output
);

    // Three flip-flop synchronizer chain.
    // Stage 1 samples the raw input and may be metastable.
    // Stage 2 gives stage 1 one full clock period to resolve.
    // Stage 3 provides the final clean output exposed to the rest of the design.
    reg sync_stage_1;
    reg sync_stage_2;
    reg sync_stage_3;

    always @(posedge clk) begin
        sync_stage_1 <= btn_in;        // sample raw asynchronous input
        sync_stage_2 <= sync_stage_1;  // allow one clock period for resolution
        sync_stage_3 <= sync_stage_2;  // final stable output stage
    end

    // Expose the fully synchronized signal to the rest of the design
    assign btn_out = sync_stage_3;

endmodule
