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

// serial_port.v
// May 2016 based on work done in 2015
// Asynchronous serial port.  Meant to do a single baud rate (controlled
// externally) in 8n1 and to provide byte values to external logic.

module serial_port(
    // general system interface shared with everything
    input clk, // system clock: rising edge active
    input rst, // system reset: active-high synchronous

    // device specific interface (to go off chip)
    input rx_raw, // raw RX line within the serial port
    output tx, // raw TX line within the serial port

    // timing controls
    input baud1, // a single clock cycle pulse at the baud rate
    input baud8, // similar but at 8x that rate

    // RX side single-byte FIFO
    output reg [7:0] rx_dat = 8'd0, // the data
    output reg rx_stb = 1'd0, // will pulse when rx_dat is valid & has new data

    // TX side single-byte FIFO
    input [7:0] tx_dat, // the data
    input tx_stb, // pulse when tx_dat is valid & has new data
    output tx_rdy // will be high when all data has been transmitted
);

    // External interface to 1 byte TX FIFO.  (The RX FIFO's interface
    // is simpler and fits into the RX logic below.)
    reg [7:0]txf_data = 8'd0; // the byte data
    reg [1:0]txf_sema = 2'd0; // these bits are != if there's a byte in there
    assign tx_rdy = txf_sema[0] == txf_sema[1];
    always @(posedge clk)
        if (rst) begin
            txf_data <= 8'd0;
            txf_sema[0] <= 1'b0;
        end else begin
            if (tx_stb) begin
                // a new byte to TX
                txf_sema[0] <= ~txf_sema[1];
                txf_data <= tx_dat;
            end
        end

    // Transmit data.
    // Transmitted from a shift register in the following order:
    //      + start bit (0)
    //      + data bits from least-order
    //      + parity bit if any
    //      + stop bit(s) (1, same as idle)
    // Signals:
    //      txsr - shift register for transmit, shifts left to right
    //      txctr - counts bits left to transmit from txsr
    //      txempty - indicates 'txsr' is empty
    reg [8:0] txsr = 9'd511;
    reg [3:0] txctr = 4'd0;
    wire txempty = ~|txctr;
    always @(posedge clk)
        if (rst) begin
            // On reset: txsr will be empty & so will the FIFO.
            txsr <= 9'd511;
            txctr <= 4'd0;
            txf_sema[1] <= 1'b0;
        end else if (baud1) begin
            // Time to transmit another bit.  From txsr if empty, otherwise
            // from the FIFO.  If there aren't other bits we'll just
            // transmit '1' until we get some.
            if (txctr > 4'd1) begin
                // txsr contains more than one bit; shift one out & transmit
                // the next
                txsr <= { 1'b1, txsr[8:1] };
                txctr <= txctr - 4'd1;
            end else if (txf_sema[0] != txf_sema[1]) begin
                // Take a new byte off the FIFO, because txsr has become
                // empty (if it wasn't already).
                txsr <= { 
                    // Stop bit(s) are left out of txsr, since they're
                    // the same as idle.
                    txf_data, // data byte (8 bits)
                    1'd0 // start bit
                };
                txctr <= 4'd10;  // 1 start, 8 data, 1 stop
                txf_sema[1] <= txf_sema[0];
            end else begin
                // the shift register and FIFO are empty
                txsr <= 9'd511;
                txctr <= 4'd0;
            end
        end

    assign tx = txsr[0];

    // RX is more complicated than TX, because of oversampling and detecting
    // the start of a byte.

    // Start out by synchronizing the rx signal to our clock.
    reg rx_sync = 1'b1, rx = 1'b1;
    always @(posedge clk)
        if (rst)
            { rx, rx_sync } <= 2'b1;
        else
            { rx, rx_sync } <= { rx_sync, rx_raw };

    // Follow that by sampling at 8x the baud rate, and taking the
    // average of three adjacent samples.
    reg [2:0]rx_sample = 3'd1;
    always @(posedge clk)
        if (rst)
            rx_sample <= 3'd1;
        else if (baud8)
            rx_sample <= { rx_sample[1:0], rx };
    reg rx_avg;
    always @*
        casex (rx_sample)
        3'b00x: rx_avg <= 1'b0;
        3'b11x: rx_avg <= 1'b1;
        default: rx_avg <= rx_sample[0];
        endcase

    // Now pull that into a shift register that holds all the samples
    // we'll need to receive a byte.  It shifts from left to right (so
    // rxsr[0] is the earliest) and looks as follows when a byte has
    // been received:
    //      rxsr[0] - before the start bit: 1
    //      rxsr[8:1] - start bit: 0; value taken at rxsr[4]
    //      rxsr[16:9] - least-order data bit
    //          ...
    //      rxsr[72:65] - greatest-order data bit
    // If we have parity or 7-bit data that will change of course.
    // We don't check for the stop bits, except for the single sample
    // that comes right before the next start bit.
    reg [72:0]rxsr = { 73{1'b1} };
    always @(posedge clk)
        if (rst) begin
            rxsr <= { 73{1'b1} };
            rx_stb <= 1'd0;
        end else begin
            rx_stb <= 1'd0;
            if (baud8) begin
                if (rxsr[4:0] == 5'd1) begin
                    // a byte has been received
                    rx_dat <= {
                        rxsr[68], rxsr[60], rxsr[52], rxsr[44],
                        rxsr[36], rxsr[28], rxsr[20], rxsr[12]
                    };
                    rx_stb <= 1'd1;
                    rxsr <= { rx_avg, { 72{1'b1} } };
                end else begin
                    // just another sample
                    rxsr <= { rx_avg, rxsr[72:1] };
                end
            end
        end
        
endmodule
