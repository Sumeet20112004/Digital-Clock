`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name   : clock_divider
// Description   : Divides the 100 MHz Basys3 system clock down to a 1 Hz output
//                 clock. This 1 Hz signal is used as the heartbeat for all
//                 time-keeping logic in the digital clock (clock, stopwatch,
//                 alarm, and timer modes).
//
// How it works  : A 32-bit counter increments on every rising edge of clk_in.
//                 When the counter reaches half the desired period, the output
//                 is toggled and the counter resets. This produces a symmetric
//                 square wave at the target frequency.
//
// Input Clock   : 100 MHz (Basys3 onboard oscillator, XDC pin W5)
// Output Clock  : 1 Hz
//
// Parameters
//   DIVISOR     : Total number of input clock cycles per one output clock cycle.
//                 Default = 100,000,000 → 100 MHz input produces 1 Hz output.
//                 Change this value to target a different output frequency.
//
// Timing example (default):
//   count increments each tick (10 ns at 100 MHz)
//   count reaches (100,000,000 / 2) - 1 = 49,999,999 → output toggles
//   50,000,000 ticks HIGH + 50,000,000 ticks LOW = 100,000,000 ticks = 1 second
//////////////////////////////////////////////////////////////////////////////////

module clock_divider #(
    parameter DIVISOR = 100_000_000    // input clock cycles per output clock cycle
)(
    input  wire clk_in,                // 100 MHz system clock input
    output reg  clk_out                // divided clock output (1 Hz by default)
);

    // Counter width: must hold up to (DIVISOR/2 - 1).
    // At default DIVISOR, max count = 49,999,999 which needs 26 bits.
    // 32 bits is used for safety margin and to support lower target frequencies.
    reg [31:0] count;

    initial begin
        clk_out = 1'b0;
        count   = 32'd0;
    end

    always @(posedge clk_in) begin
        if (count == (DIVISOR / 2) - 1) begin
            clk_out <= ~clk_out;    // toggle output at each half-period boundary
            count   <= 32'd0;       // reset counter for the next half period
        end else begin
            count <= count + 1'b1;
        end
    end

endmodule
