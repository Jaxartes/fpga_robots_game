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

// fpga_robots_game_control.v
// started May 2016

// Keyboard control of the FPGA robots game.  Handles key codes received
// from the keyboard (over the PS/2 interface) or from the host (over the
// serial port) and generates command bits for the game

`include "fpga_robots_game_config.v"

module fpga_robots_game_control(
    // system wide control signals
    input clk, // clock: rising edge active, everything is synched to this
    input rst, // reset: active high, synchronous

    // received data from PS/2 port
    input [7:0]ps2_rx_dat, // data
    input      ps2_rx_stb, // strobe: will pulse when data is new & valid

    // received data from serial port
    input [7:0]ser_rx_dat, // data
    input      ser_rx_stb, // strobe: will pulse when data is new & valid

    // Output command bits, as found in the keyboard lookup table.  They'll
    // be pulsed when the command is issued, it's up to the rest of the
    // game logic to keep track of pending commands.
    output reg [15:0]cmd = 16'd0,

    // Commands to perform and control data dump
    output reg dumpcmd_start = 1'd0, // pulsed to start a dump
    output reg dumpcmd_pause = 1'd0, // high as long as dump should be paused

    // debugging, just in case we want it
    output dbg
);
`ifdef FPGA_ROBOTS_BIG_KEY_TABLE
    // Lookup table for controlling the keyboard: 512 x 16 bits; expanded
    // to 1024 x 16 bits to work around a supposed bug.
    reg [15:0]key_table[0:1023];
    reg [15:0]key_table_dat = 16'd0;
    wire [8:0]key_table_adr;
    initial begin
        $readmemh("key_table.mem", key_table, 0, 511);
        $readmemh("key_table.mem", key_table, 512, 1023);
    end
    reg garbage_bit = 1'd0;
    always @(posedge clk)
        if (rst)
            key_table_dat <= 16'd0;
        else
            key_table_dat <= key_table[{ garbage_bit, key_table_adr }];
    always @(posedge clk) garbage_bit <= !garbage_bit;
`else // !FPGA_ROBOTS_BIG_KEY_TABLE
    // Lookup table for controlling the keyboard: 512 x 16 bits
    reg [15:0]key_table[0:511];
    reg [15:0]key_table_dat = 16'd0;
    wire [8:0]key_table_adr;
    initial $readmemh("key_table.mem", key_table, 0, 511);
    always @(posedge clk)
        if (rst)
            key_table_dat <= 16'd0;
        else
            key_table_dat <= key_table[key_table_adr];
`endif // !FPGA_ROBOTS_BIG_KEY_TABLE

    // State machine for converting serial port RX bytes into key code
    // equivalents:
    //      64-79 - copy 4 bits into buffer
    //      80-95 - take buffer contents & 4 more bits as an 8 bit key code
    reg [3:0]fourbuf = 4'd0;
    reg ser_kc_stb = 1'd0;
    reg [7:0]ser_kc_dat = 8'd0;
    always @(posedge clk)
        if (rst) begin
            fourbuf <= 4'd0;
            ser_kc_stb <= 1'd0;
            ser_kc_dat <= 8'd0;
            dumpcmd_start <= 1'd0;
            dumpcmd_pause <= 1'd0;
        end else begin
            ser_kc_stb <= 1'd0;
            dumpcmd_start <= 1'd0;
            if (ser_rx_stb) begin
                case (ser_rx_dat[7:4])
                4'h1: begin
                    if (ser_rx_dat[3:0] == 4'd1) 
                        // 17: XON, resume transmission
                        dumpcmd_pause <= 1'd0;
                    else if (ser_rx_dat[3:0] == 4'd3)
                        // 19: XOFF, pause transmission
                        dumpcmd_pause <= 1'd1;
                end
                // 64-79 - buffer a half byte
                4'h4: fourbuf <= ser_rx_dat[3:0];
                // 80-95 - fake a byte received from keyboard
                4'h5: begin
                    ser_kc_dat <= { fourbuf, ser_rx_dat[3:0] };
                    ser_kc_stb <= 1'd1;
                end
                4'h6: begin
                    if (ser_rx_dat[3:0] == 4'd0) begin
                        // 96: dump game state
                        dumpcmd_start <= 1'd1;
                        dumpcmd_pause <= 1'd0;
                    end
                end
                endcase
            end
        end

    // State machine for converting keycodes into commands, using the
    // lookup table 'key_table'.  By the way, it's unlikely for the PS/2
    // keyboard and the serial port to be used at the same time, and on
    // the off chance they provide a keycode at the same time, one will
    // be lost.
    reg kdec_ext = 1'd0; // extended keycode with 0xe0
    reg kdec_brk = 1'd0; // "break" keycode with 0xf0
    reg kdec_stb = 1'd0; // indicates key_table_dat is "interesting"
    wire [7:0]kdec_in = ser_kc_stb ? ser_kc_dat : ps2_rx_dat;
    assign key_table_adr = { kdec_ext, kdec_in };

    always @(posedge clk)
        if (rst) begin
            kdec_stb <= 1'd0; // whatever lookup was in progress, forget it
            kdec_ext <= 1'd0;
            kdec_brk <= 1'd0;
        end else begin
            kdec_stb <= 1'd0; // normally the lookup is uninteresting
            if (ser_kc_stb || ps2_rx_stb) begin
                // there's a key code, but is it a key or a modifier?
                if (kdec_in == 8'he0) begin
                    // 0xe0 modifies the next keycode
                    kdec_ext <= 1'd1;
                end else if (kdec_in == 8'hf0) begin
                    // 0xf0 means the key is released; a "break" code
                    kdec_brk <= 1'd1;
                end else begin
                    // yes, it's interesting
                    kdec_stb <= 1'd1;
                    kdec_ext <= 1'd0;
                    kdec_brk <= 1'd0;
                end
            end
        end

    wire [15:0]kdec_modmask = 16'h8000; // which command bits are modifier keys?
    reg kdec_brk_d1 = 1'd0;
    always @(posedge clk) kdec_brk_d1 <= rst ? 1'd0 : kdec_brk;
    always @(posedge clk)
        if (rst) begin
            cmd <= 16'd0;
        end else begin
            cmd <= (cmd & // old command bits
                    kdec_modmask & // but only the "modifier key" ones persist
                    ((kdec_stb && kdec_brk_d1) ?
                     (~key_table_dat) : 16'hffff)) | // until released
                   ((kdec_stb && (!kdec_brk_d1)) ? // when new ones are pressed
                    key_table_dat : 16'h0000); // they assert the command bits
        end

    // 'dbg' unconnected for now
    assign dbg = 1'd0;
endmodule
