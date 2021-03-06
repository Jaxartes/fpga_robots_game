// Copyright (c) 2016 Jeremy Dilatush
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY JEREMY DILATUSH AND CONTRIBUTORS
// ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL JEREMY DILATUSH OR CONTRIBUTORS
// BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

// fpga_robots_game_clock.v
// started April 2016

// This module converts the on-board clock signal at whatever speed it is
// (the Papilio Pro board's is 32MHz) into about 65MHz, which is the
// target speed for this game's logic.  It uses modules which are probably
// different for every FPGA vendor and product type (the Papilio Pro uses
// a Xilinx Spartan-6).

// It also generates a few synchronous pulse trains to time other things
// that happen in the system, like the serial port.

`include "fpga_robots_game_config.v"

module fpga_robots_game_clock(
    // main clock
    input iclk, // input clock, probably coming from an oscillator somewhere
    output oclk, // output clock, to be used by the game's logic
    output locked, // indicate if it's "locked" thus ready to run

    // serial port timing: for 115,200 baud
    output baud1, // single clock cycle pulse 115,200 times a second
    output baud8, // single clock cycle pulse 921,600 times a second

    // PS/2 port timing
    output sixus // single clock cycle pulse every ~6 microseconds

`ifdef FPGA_ROBOTS_ANIMATE
    // frame by frame animated video
    , output anitog // will flip flop every so often
`endif
);

`ifdef __ICARUS__
    // Dummy clock for Icarus Verilog
    assign oclk = iclk;
    assign locked = 1'd1;
`else
`ifdef FPGA_ROBOTS_CLK_XS6_32
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
        .CLKOUT0_DIVIDE(8)    // and give output 0, 416MHz / 8 = 52MHz
    ) pll1 (
        .CLKIN(iclk),         // input clock
        .CLKOUT0(ocub1),      // output clock
        .CLKFBIN(fb1),        // feedback to keep the PLL running
        .CLKFBOUT(fb1),
        .RST(1'd0)            // I guess you need to keep it from
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
        .RST(1'd0)            // I guess you need to keep it from
                              // resetting itself...
    );

    // fake "locked" signal, we could use the two "LOCKED" outputs but they're
    // asynchonous, and it's hard to synchronize them if we might not be
    // able to rely on our clock...
    assign locked = 1'd1;
`endif // FPGA_ROBOTS_CLK_XS6_32
`ifdef FPGA_ROBOTS_CLK_XS6_50
    // For Pepino, and other boards with a Xilinx Spartan-6, one
    // or more PLLs available, and a 50MHz clock input:
    // Generate a 65MHz clock using one PLL.
    //      pll1: 50MHz -> 65MHz; oscillator 650MHz; ratio 13/10

    wire fb1; // feedback within PLL
    wire ocub1; // unbuffered output clock from PLL

    BUFG outbuf1(.I(ocub1), .O(oclk));

    PLL_BASE #(
        //  pll1: 50MHz -> 65MHz; oscillator 650Hz; ratio 13/10
        .CLKIN_PERIOD(20.00), // 20.000 ns means 50MHz, input clock frequency
        .DIVCLK_DIVIDE(1),    // feed 50MHz to the PLL input
        .CLKFBOUT_MULT(13),   // run the VCO at 50*13=650Hz (ideal seems to be
                              // a little over 400MHz)
        .CLKOUT0_DIVIDE(10)   // and give output 0, 650MHz / 10 = 65MHz
    ) pll1 (
        .CLKIN(iclk),         // input clock
        .CLKOUT0(ocub1),      // output clock
        .CLKFBIN(fb1),        // feedback to keep the PLL running
        .CLKFBOUT(fb1),
        .RST(1'd0)            // I guess you need to keep it from
                              // resetting itself...
    );

    // fake "locked" signal, we could use the two "LOCKED" outputs but they're
    // asynchonous, and it's hard to synchronize them if we might not be
    // able to rely on our clock...
    assign locked = 1'd1;
`endif // FPGA_ROBOTS_CLK_XS6_50
`endif // !__ICARUS__

    parameter BAUDCTR_STEP = 19'd929; // appropriate for 65MHz

    // Serial port timing, for 115,200 baud.
    reg [18:0] baudctr = 19'd0;
    wire [19:0] baudctr_nxt = baudctr + BAUDCTR_STEP;
    always @(posedge oclk) baudctr <= baudctr_nxt[18:0];
    assign baud1 = baudctr_nxt[19];
    assign baud8 = baudctr_nxt[16] ^ baudctr[16];

    // PS/2 port timing, for a pulse every ~6us.  This assumes 65MHz system
    // clock.  Uses the fact that baud8 pulses about every microsecond.
    reg [2:0]sixctr = 3'd0;
    always @(posedge oclk) if (baud8) sixctr <= { sixctr[1:0], ~sixctr[2] };
    assign sixus = (sixctr == 3'd7);

`ifdef FPGA_ROBOTS_ANIMATE
    // Animated video; the clock for it is run off the 115,200 baud serial  
    // clock.
    parameter ANIMATION_RATE = 20'd18; // 5 here means 1.1Hz
    reg [19:0] anictr = 20'd0;
    always @(posedge oclk)
        if (baud1)
            anictr <= anictr + ANIMATION_RATE;
    assign anitog = anictr[19];
`endif // FPGA_ROBOTS_ANIMATE

endmodule
