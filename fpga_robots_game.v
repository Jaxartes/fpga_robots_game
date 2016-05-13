// fpga_robots_game.v
// Jeremy Dilatush - started April 2016
//
// "Top level" module for the FPGA based "robots" game.  This brings together
// the other components, as well as providing as much as possible of the
// platform specific detail.

// XXX work in progress

`include "fpga_robots_game_config.v"

module fpga_robots_game(
    // all these are signals going out of the FPGA chip itself
    input board_clk, // original clock signal
    output reg board_led, // light emitting diode used for signalling
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
`ifdef FPGA_ROBOTS_ANIMATE
    wire anitog;
`endif
    fpga_robots_game_clock clock(
        .iclk(board_clk), .oclk(clk), .locked(clklck)
        // XXX hook up baud1, baud8, sixus
`ifdef FPGA_ROBOTS_ANIMATE
        ,.anitog(anitog)
`endif
    );

    // Reset.  Driven by the reset button and the clock's "LOCKED" signal.
    reg rst2 = 1'd1, rst3 = 1'd1, rst4 = 1'd1;
    reg [3:0] rstctr = 4'd0;
    always @(posedge clk) begin
        // synchronize the incoming reset button signal
        { rst3, rst4 } <= { rst4, i_reset };
        // count how long it's been sinvce the button went up
        if (rst3 || ~clklck) begin
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

    always @(posedge clk) board_led <= rst ? 1'd0 : blink_state[0];

    // Video output generator.  It owns the "tile map" memory which is also
    // used by the game play logic.
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
            // XXX this is dummy & not really filled in
        .tm_adr(13'd0),
        // .tm_red(XXX),
        .tm_wrt(8'd0),
        .tm_wen(1'd0)

`ifdef FPGA_ROBOTS_ANIMATE
        // control animation
        , .anitog(anitog)
`endif
        , .attention(attention)
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

    // Dummy signals: eventually hook these up or something XXX
    assign serial_tx = 1'd1;
    assign attention = board_led;
endmodule
