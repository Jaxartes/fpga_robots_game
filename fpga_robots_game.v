// fpga_robots_game.v
// Jeremy Dilatush - started April 2016
//
// "Top level" module for the FPGA based "robots" game.  This brings together
// the other components, as well as providing as much as possible of the
// platform specific detail.

// XXX work in progress

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
    fpga_robots_game_clock clock(
        .iclk(board_clk), .oclk(clk), .locked(clklck),
        // XXX hook up baud1, baud8, sixus
        .anitog(anitog)
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

`ifdef NOT_DEFINED  // XXX debugging stuff, put back one day
    always @(posedge clk) board_led <= rst ? 1'd0 : blink_state[0];
`else
    always @* board_led = anitog;
`endif

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
        .tm_wen(1'd0),

        // control animation
        .anitog(anitog)
    );

    // convert 6 bit to 12 bit color
    assign o_video_r[1:0] = o_video_r[3:2];
    assign o_video_g[1:0] = o_video_g[3:2];
    assign o_video_b[1:0] = o_video_b[3:2];

    // Dummy signals: eventually hook these up or something XXX
    assign serial_tx = 1'd1;
    assign o_audio_l = 1'd0;
    assign o_audio_r = 1'd0;
endmodule
