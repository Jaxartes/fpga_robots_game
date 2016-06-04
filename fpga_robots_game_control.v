// fpga_robots_game_control.v
// Jeremy Dilatush - started May 2016
//
// Control the FPGA robots game.  Handles key codes received from the
// keyboard (over the PS/2 interface) or from the host (over the serial
// port) and generates command bits for the game

// XXX this may be tricky enough to need a test in the simulator

`include "fpga_robots_game_config.v"

module fpga_robots_game_control(
    // system wide control signals
    input clk, // clock: rising edge active, everything is synched to this
    input rst, // reset: active high, synchronous

    // received data from PS/2 port
    // XXX hook this up
    input [7:0]ps2_rx_dat, // data
    input      ps2_rx_stb, // strobe: will pulse when data is new & valid

    // received data from serial port
    input [7:0]ser_rx_dat, // data
    input      ser_rx_stb, // strobe: will pulse when data is new & valid

    // transmit data to serial port
    output reg [7:0]ser_tx_dat, // data
    output reg      ser_tx_stb, // strobe: will pulse when data is new & valid
    input           ser_tx_rdy, // ready: will be high when ready to transmit

    // Output command bits, as found in the keyboard lookup table.  They'll
    // be pulsed when the command is issued, it's up to the rest of the
    // game logic to keep track of pending commands.
    output reg [15:0]cmd = 16'd0

    // debugging, just in case we want it
    , output dbg
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
        end else begin
            ser_kc_stb <= 1'd0;
            if (ser_rx_stb) begin
                case (ser_rx_dat[7:4])
                4'h4: fourbuf <= ser_rx_dat[3:0];
                4'h5: begin
                    ser_kc_dat <= { fourbuf, ser_rx_dat[3:0] };
                    ser_kc_stb <= 1'd1;
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
    wire ps2_kc_dat = 1'd0; // XXX temporary dummy
    wire [7:0]kdec_in = ser_kc_stb ? ser_kc_dat : ps2_kc_dat;
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

    wire kdec_modmask = 16'd8000; // which command bits are modifier keys?
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
