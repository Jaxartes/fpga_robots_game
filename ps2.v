// Copyright (c) 2015-2016 Jeremy Dilatush
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

// ps2.v
// PS/2 keyboard/mouse port interface.  Adapted from the one in VTJ-1.

// ps2() - main module including external interface
module ps2(
    // general system stuff
    input clk, // system clock: rising edge active
    input rst, // system reset: active-high synchronous

    // system interface
    input sixus, // a single cycle clock pulse every six microseconds
    output reg [7:0]ps2_rx_dat = 8'd0, // data RX'ed
    output reg      ps2_rx_stb = 1'd0, // strobe: will pulse when new & valid
    input ps2_tx_reset, // pulse this to transmit a reset (8'hff) byte

    // external interface
    inout ps2clk, // PS/2 port's "clock" line
    inout ps2dat // PS/2 port's "data" line
);
    // tx_reset_sema - keep track of whether a reset has been requested.
    // The two bits will be unequal if so.
    reg [1:0]tx_reset_sema = 2'd0;

    always @(posedge clk)
        if (rst)
            tx_reset_sema[0] <= 1'd0;
        else if (ps2_tx_reset)
            tx_reset_sema[0] <= ~tx_reset_sema[1];

    // Now oversample the data & clock lines & take the average of 5 samples.
    // And take 3 more samples for synchronization.
    reg [2:0] datsyn = 3'd0, clksyn = 3'd0;
    reg [6:2] datosa = 5'd0, clkosa = 5'd0;
    always @(posedge clk)
        if (rst) begin
            datsyn <= 3'd7;
            clksyn <= 3'd7;
        end else begin
            datsyn <= { datsyn[1:0], ps2dat };
            clksyn <= { clksyn[1:0], ps2clk };
        end
    always @(posedge clk)
        if (rst) begin
            datosa <= 5'd31;
            clkosa <= 5'd31;
        end else if (sixus) begin
            datosa <= { datosa[5:2], datsyn[2] };
            clkosa <= { clkosa[5:2], clksyn[2] };
        end
    wire datin, clkin;
    avg5 datavg(datin, datosa[6:2]);
    avg5 clkavg(clkin, clkosa[6:2]);

    // detect rising edge of clkin
    reg clkold = 1'b0;
    always @(posedge clk)
        if (rst)
            clkold <= 1'b0;
        else if (sixus)
            clkold <= clkin;
    wire clkfall = clkold && !clkin;

    // RX: sample the data line ~18us after the clock goes
    // low.  This code shifts it into an 11-bit shift register.  This
    // also takes an input signal, suppress_rx, so that we don't
    // "receive" the signals we send.
    // When the "start bit" makes its way through 'rxsr' we know that the
    // byte is in there and we let the downstream code know we got something.
    // The byte is accepted whether or not its parity is valid.
    reg [9:0] rxsr = 10'd1023;
    reg [2:0] xtrig = 3'd0; // timing after the clock goes low
    wire suppress_rx;
    always @(posedge clk)
        if (rst) begin
            xtrig <= 3'd0;
            rxsr <= 10'd1023;
            ps2_rx_dat <= 8'd0;
            ps2_rx_stb <= 1'd0;
        end else if (sixus) begin
            ps2_rx_stb <= 1'd0;
            if (xtrig[2] && !suppress_rx) begin
                if (rxsr[0])
                    // not a byte yet; just shift the bit into the register
                    rxsr <= { datin, rxsr[9:1] };
                else begin
                    // received a byte:
                    //      rxsr[0] holds the start bit (0)
                    //      rxsr[1-8] hold the data byte, LSbit first
                    //      rxsr[9] holds the parity bit (odd parity)
                    //      datin holds the stop bit (1)
                    // clear the shift register
                    rxsr <= 10'd1023;

                    // let the downstream code know that we've RX'ed a byte
                    ps2_rx_dat <= rxsr[8:1];
                    ps2_rx_stb <= 1'd1;
                end
            end
            xtrig <= clkfall ? 3'd1 : { xtrig[1:0], 1'b0 };
        end else
            ps2_rx_stb <= 1'd0;

    // TX: Transmission of bytes from the host to the peripheral.  The only
    // byte we transmit is a reset (0xff).

    // txsr is a shift register with what we're transmitting incl parity
    //      and a '1' start bit
    // txctr is a state variable:
    //      0 - not transmitting
    //      1 - finishing transmission (acknowledgement bit from device)
    //      2-11 - 1 plus number of bits not yet transmitted
    //      12-31 - counts 6us periods for starting communication
    reg [9:0] txsr = 10'd1023;
    reg [4:0] txctr = 5'd0;
    wire tx_going = |txctr; // indicates a TX operation is happening
    assign suppress_rx = tx_going; // no RX while any TX is happening
    wire tx_initiate = txctr >= 12; // pull ps2clk down to initiate
    wire tx_transmit = txctr >= 2 && txctr <= 11; // operate ps2dat
    wire tx_transmit_ex = tx_transmit || txctr == 12; // pull ps2dat down
    wire tx_waitack = txctr == 1; // expecting acknowledgement
    wire [4:0] txctr_minus_1 = txctr - 1;
    always @(posedge clk)
        if (rst) begin
            txsr <= 10'd1023; // start with nothing to transmit
            txctr <= 5'd0; // start with not transmitting
            tx_reset_sema[1] <= 1'd0; // start with nothing in transmit FIFO
        end else if (tx_initiate && sixus)
            txctr <= txctr_minus_1; // countdown to start
        else if (tx_transmit && sixus && clkfall) begin
            // transmitting a bit
            txctr <= txctr_minus_1; // countdown to next bit
            txsr <= { 1'b1, txsr[9:1] }; // shift out a bit
        end else if (tx_waitack && sixus && clkfall) begin
            // acknowledgement bit
            txctr <= txctr_minus_1;
        end else if ((tx_reset_sema[0] != tx_reset_sema[1]) && !tx_going) begin
            // we have a byte to transmit: start transmitting
            txctr <= 5'd31; // start the countdown
            txsr <= { 1'd1, // parity bit
                      8'hff, // reset code for PS/2 keyboard
                      1'b0 }; // start bit
            tx_reset_sema[1] <= tx_reset_sema[0]; // no longer waiting
        end
    assign ps2clk = tx_initiate ? 1'b0 : 1'bz;
    assign ps2dat = (tx_transmit_ex && !txsr[0]) ? 1'b0 : 1'bz;
endmodule

// avg5() -- average of 5 input bits.  Should compact into a LUT5 (half
// a LUT) on Spartan6.  I'm not sure it does, but it seems ok to me.
module avg5(output o, input [4:0] i);
    assign o = ((i[0] ? 1 : 0) +
                (i[1] ? 1 : 0) +
                (i[2] ? 1 : 0) +
                (i[3] ? 1 : 0) +
                (i[4] ? 1 : 0)) > 2;
endmodule
