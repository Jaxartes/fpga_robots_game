// fpga_robots_game.v
// Jeremy Dilatush - started April 2016
//
// "Top level" module for the FPGA based "robots" game.  This brings together
// the other components, as well as providing as much as possible of the
// platform specific detail.

`include "fpga_robots_game_config.v"

module fpga_robots_game(
    // all these are signals going out of the FPGA chip itself
    input board_clk, // original clock signal
    output board_led, // light emitting diode used for signalling
    input i_reset, // reset pushbutton switch
    output [3:0]o_video_r, // video output
    output [3:0]o_video_g,
    output [3:0]o_video_b,
    output o_vsync,
    output o_hsync,
    input serial_rx, // serial port with host (perhaps over USB)
    output serial_tx,
    inout ps2a_clk, // PS/2 port A
    inout ps2a_dat,
    output o_audio_l, // audio output
    output o_audio_r
);

    // Clock.  The logic all runs from a ~65MHz That's
    // determined by the XGA video output timings, with a 65MHz pixel clock.

    wire clk, clklck;
    wire baud1, baud8, sixus;
`ifdef FPGA_ROBOTS_ANIMATE
    wire anitog;
`endif
    fpga_robots_game_clock clock(
        .iclk(board_clk), .oclk(clk), .locked(clklck),
        .baud1(baud1), .baud8(baud8), .sixus(sixus)
`ifdef FPGA_ROBOTS_ANIMATE
        ,.anitog(anitog)
`endif
    );

    // Reset.  Driven by the reset button and the clock's "LOCKED" signal.
    // Or by the shift-scroll key combination (twice).  Also it resets itself
    // at startup time.
    reg rst2 = 1'd1, rst3 = 1'd1, rst4 = 1'd1;
    reg [3:0] rstctr = 4'd0;
    wire ctl_driven_reset;
    always @(posedge clk) begin
        // synchronize the incoming reset button signal
        { rst3, rst4 } <= { rst4, i_reset };
        // count how long it's been since the button went up
        if (rst3 || ~clklck || ctl_driven_reset) begin
            rstctr <= 4'd0;
            rst2 <= 1'd1;
        end else if (rstctr != 4'd15) begin
            rstctr <= rstctr + 4'd1;
            rst2 <= 1'd1;
        end else
            rst2 <= 1'd0;
    end
    wire rst = rst2 || ~clklck;

    // A signal to get the user's attention
    wire attention;

    // Blink the board_led twice, for 1/16 second, every second, 3/16
    // second apart.  This allows us to determine that it's up and running
    // and clocking properly.
    reg [21:0] blink_ctr = 22'd0;
    wire [22:0] blink_inc = blink_ctr + 22'd1;
    always @(posedge clk) blink_ctr <= rst ? 22'd0 : blink_inc[21:0];
    reg [15:0] blink_state = 16'd17;
    always @(posedge clk)
        if (rst)
            blink_state <= 16'd17;
        else if (blink_inc[22])
            blink_state <= { blink_state[14:0], blink_state[15] };

    reg blink_out = 1'd0;
    always @(posedge clk) blink_out <= rst ? 1'd0 : blink_state[0];

    assign board_led = blink_out;

    // Video output generator.  It owns the "tile map" memory which is also
    // used by the game play logic.
    wire [12:0]tm_adr; // access to tile map memory: address
    wire [7:0] tm_wrt; // access to tile map memory: write data
    wire [7:0] tm_red; // access to tile map memory: read data
    wire       tm_wen; // access to tile map memory: write enable
    wire framepulse;   // there's a pulse 60 times a second
    wire vbi;          // it's in the vertical blanking interval
    fpga_robots_game_video video(
        // system interface
        .clk(clk), .rst(rst),

        // video output
        .v_red(o_video_r[3:2]),
        .v_grn(o_video_g[3:2]),
        .v_blu(o_video_b[3:2]),
        .v_hsy(o_hsync),
        .v_vsy(o_vsync),

        // tile map memory access
        .tm_adr(tm_adr),
        .tm_red(tm_red),
        .tm_wrt(tm_wrt),
        .tm_wen(tm_wen)

`ifdef FPGA_ROBOTS_ANIMATE
        // control animation
        , .anitog(anitog)
`endif
        , .attention(attention)
        , .frame(framepulse)
        , .vbi(vbi)
    );

    // convert 6 bit to 12 bit color
    assign o_video_r[1:0] = o_video_r[3:2];
    assign o_video_g[1:0] = o_video_g[3:2];
    assign o_video_b[1:0] = o_video_b[3:2];

    // Audio output.  We can do a nice sine wave or an ugly but simple
    // (and familiar) square wave.
`ifdef FPGA_ROBOTS_SQUARE
    // Square wave at about 450Hz, by dividing baud1 down by 256
    wire audio;
    reg [7:0]audiv = 8'd0;
    always @(posedge clk)
        if (rst)
            audiv <= 8'd0;
        else if (baud1 && attention)
            audiv <= audiv + 8'd1;
    assign audio = audiv[7];
`else // !FPGA_ROBOTS_SQUARE
    // Sine wave at about 573Hz, by triggering sinewaver() from baud8.
    // baud8's 921,600 pulses per second divided by sinewaver()'s
    // 1609 pulses per cycle makes about 573Hz.
    // The output is fed into a simple sigma-delta converter.
    wire [15:0]audwave;
    reg audio = 1'd0;
    reg [15:0]audacc = 16'd0;
    sinewaver audsine(.clk(clk), .rst(rst),
                      .trigger(attention && baud8), .out(audwave));
    always @(posedge clk)
        { audio, audacc } <= audacc + audwave;
`endif // !FPGA_ROBOTS_SQUARE

    // Either way, this game doesn't do stereo.
    assign o_audio_l = audio;
    assign o_audio_r = audio;

    // Decide when to reset the keyboard.  I'm tempted to do that every
    // time the player executes a 'quit' command but for now I won't.
    // Just reset the keyboard shortly after the system comes out of
    // reset.  How long is "shortly"?  Let's say ~1/5 second, counted
    // by video frames.
    reg [3:0]kbdrstctr = 4'd0;
    reg ps2_tx_reset = 1'd0;
    always @(posedge clk)
        if (rst) begin
            kbdrstctr <= 4'd12; // 12 frames at 60 frames per second
            ps2_tx_reset <= 1'd0;
        end else begin
            ps2_tx_reset <= 1'd0;
            if ((|kbdrstctr) && framepulse) begin
                if (kbdrstctr == 4'd1) ps2_tx_reset <= 1'd1;
                kbdrstctr <= kbdrstctr - 4'd1;
            end
        end

    // Serial port
    wire [7:0]ser_rx_dat;
    wire [7:0]ser_tx_dat;
    wire ser_rx_stb;
    wire ser_tx_stb;
    wire ser_tx_rdy;
    serial_port ser(
        // general system stuff
        .clk(clk), .rst(rst),
        // the external serial port
        .rx_raw(serial_rx), .tx(serial_tx),
        // timing control signal, determines the baud rate
        .baud1(baud1), .baud8(baud8),
        // serial port RX and TX bytes
        .rx_dat(ser_rx_dat), .rx_stb(ser_rx_stb),
        .tx_dat(ser_tx_dat), .tx_stb(ser_tx_stb), .tx_rdy(ser_tx_rdy)
    );

    // PS/2 port
    wire [7:0]ps2_rx_dat;
    wire ps2_rx_stb;
    ps2 ps2(
        // general system stuff
        .clk(clk), .rst(rst),
        // the external PS/2 port
        .ps2clk(ps2a_clk), .ps2dat(ps2a_dat),
        // system interface
        .sixus(sixus),
        .ps2_rx_dat(ps2_rx_dat), .ps2_rx_stb(ps2_rx_stb),
        .ps2_tx_reset(ps2_tx_reset)
    );

    // Control interface: Receives signals from serial port & from PS/2
    // keyboard.
    wire [15:0]ctl_cmd;
    wire ctl_dumpcmd, ctl_dumppause;
    wire ctl_dbg;
    fpga_robots_game_control ctl(
        // general system stuff
        .clk(clk), .rst(rst),
        // PS/2 port: get commands from keyboard
        .ps2_rx_dat(ps2_rx_dat), .ps2_rx_stb(ps2_rx_stb),
        // Serial port: another way to get commands
        .ser_rx_dat(ser_rx_dat),
        .ser_rx_stb(ser_rx_stb),
        // Command bits output
        .cmd(ctl_cmd),
        .dumpcmd_start(ctl_dumpcmd),
        .dumpcmd_pause(ctl_dumppause),

        // debugging
        .dbg(ctl_dbg)
    );

    // And the keyboard, in turn, can produce a reset.
    wire ctl_driven_reset_key = ctl_cmd[14]; // scroll lock
    wire ctl_driven_reset_mod = ctl_cmd[15]; // shift or other modifier
    reg ctl_driven_reset_seen = 1'd0; // have we gotten it once already?
    reg ctl_driven_reset_r = 1'd0;
    assign ctl_driven_reset = ctl_driven_reset_r;
    always @(posedge clk)
        if (rst) begin
            ctl_driven_reset_seen <= 1'd0;
            ctl_driven_reset_r <= 1'd0;
        end else if (ctl_driven_reset_key && ctl_driven_reset_mod) begin
            if (ctl_driven_reset_seen) // shift-scroll twice
                ctl_driven_reset_r <= 1'd1;
            ctl_driven_reset_seen <= 1'd1;
        end

    // Game play logic.
    wire play_dbg;
    wire want_attention_short;
    wire want_attention_long;
    fpga_robots_game_play play(
        // general system stuff
        .clk(clk), .rst(rst),
        // Command bits input, from keyboard or whatever
        .cmd(ctl_cmd),
        .dumpcmd_start(ctl_dumpcmd),
        .dumpcmd_pause(ctl_dumppause),
        // output: start a beep
        .want_attention_short(want_attention_short),
        .want_attention_long(want_attention_long),
        // access to the tile map memory
        .tm_adr(tm_adr), .tm_wrt(tm_wrt), .tm_red(tm_red), .tm_wen(tm_wen),
        // serial port access for data dump
        .ser_tx_dat(ser_tx_dat),
        .ser_tx_stb(ser_tx_stb),
        .ser_tx_rdy(ser_tx_rdy),
        // sometimes we want to sychronize with the screen
        .vbi(vbi),

        // debugging
        .dbg(play_dbg)
    );

    // Attention signal: visual and audible for short period counted by
    // video frames
    reg [5:0]atnctr = 6'd0;
    assign attention = |atnctr;
    always @(posedge clk)
        if (rst)
            atnctr <= 6'd0;
        else if (want_attention_short)
            atnctr <= 6'd15; // 15 frames = ~1/4 second
        else if (want_attention_long)
            atnctr <= 6'd45; // 45 frames = ~3/4 second
        else if (framepulse && attention)
            atnctr <= atnctr - 6'd1;

endmodule

