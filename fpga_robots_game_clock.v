// fpga_robots_game_clock.v
// Jeremy Dilatush - started April 2016
//
// This module converts the on-board clock signal at whatever speed it is
// (the Papilio Pro board's is 32MHz) into about 65MHz, which is the
// target speed for this game's logic.  It uses modules which are probably
// different for every FPGA vendor and product type (the Papilio Pro uses
// a Xilinx Spartan-6).

module fpga_robots_game_clock(
    input iclk, // input clock, probably coming from an oscillator somewhere
    output oclk, // output clock, to be used by the game's logic
    output locked // indicate if it's "locked" thus ready to run
);

`ifdef __ICARUS__
    // Dummy clock for Icarus Verilog
    assign oclk = iclk;
    assign locked = 1'd1;
`else
    // For Papilio Pro, and other boards with a Xilinx Spartan-6, two
    // or more PLLs available, and a 32MHz clock input:
    // Generate a 65MHz clock using two PLLs.
    //      pll1: 32MHz -> 52MHz; oscillator 416MHz; ratio 13/8
    //      pll2: 52MHz -> 65MHz; oscillator 520MHz; ratio 10/8
    // Could just use a single PLL, to get 64MHz, that's probably close enough,
    // but 65MHz is even better.

    wire fb1, fb2; // feedback within each PLL
    wire ocub1, ocub2; // unbuffered output clock from each
    wire clk52; // 52MHz intermediate clock

    BUFG outbuf1(.I(ocub1), .O(clk52));
    BUFG outbuf2(.I(ocub2), .O(oclk));

    PLL_BASE #(
        //  pll1: 32MHz -> 52MHz; oscillator 416MHz; ratio 13/8
        .CLKIN_PERIOD(31.25), // 31.250 ns means 32MHz, input clock frequency
        .DIVCLK_DIVIDE(1),    // feed 32MHz to the PLL input
        .CLKFBOUT_MULT(13),   // run the VCO at 32*13=416MHz (ideal seems to be
                              // a little over 400MHz)
        .CLKOUT0_DIVIDE(32)   // and give output 0, 416MHz / 8 = 52MHz
    ) pll1 (
        .CLKIN(iclk),         // input clock
        .CLKOUT0(ocub1),      // output clock
        .CLKFBIN(fb1),        // feedback to keep the PLL running
        .CLKFBOUT(fb1),
        .RST(0)               // I guess you need to keep it from
                              // resetting itself...
    );

    PLL_BASE #(
        //  pll2: 52MHz -> 65MHz; oscillator 520MHz; ratio 10/8
        .CLKIN_PERIOD(19.230769), // 19.230769 ns means 52MHz
        .DIVCLK_DIVIDE(1),    // feed 52MHz to the PLL input
        .CLKFBOUT_MULT(10),   // run the VCO at 52*10=520MHz
        .CLKOUT0_DIVIDE(8)    // and give output 0, 520MHz / 8 = 65MHz
    ) pll2 (
        .CLKIN(clk52),        // input clock
        .CLKOUT0(ocub2),      // output clock
        .CLKFBIN(fb2),        // feedback to keep the PLL running
        .CLKFBOUT(fb2),
        .RST(0)               // I guess you need to keep it from
                              // resetting itself...
    );

    // fake "locked" signal, we could use the two "LOCKED" outputs but they're
    // asynchonous, and it's hard to synchronize them if we might not be
    // able to rely on our clock...
    wire clklck = 1'd1;
`endif
endmodule
