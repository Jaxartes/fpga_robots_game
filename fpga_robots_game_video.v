// fpga_robots_game_video.v
// Jeremy Dilatush - started April 2016
//
// Video generator for the FPGA based "robots" game.  This generates a
// 1024x768 pixel video out, generated from a 128x96 grid of tiles.
// It maintains two memories:
//      A 6kB "tile map" indicating what's in position.
//      A 4kB "tile image memory" giving the different tile contents.
// The tile image memory is read-only and private to this module.
// The tile map memory is accessible outside this module.
// 
// Contents of the tile map:
//      Each byte corresponds to a pair of 8x8 pixel cells, one above the
//      other.  Bytes are arranged left to right, then top to bottom.
//      The contents of a byte depend on the position:
//      In the leftmost 120 columns:
//          2 bits - a cell's current contents: black, robot, trash, player
//          2 bits - the other cell below it
//          4 bits - extra work area for use by outside accessor, not used
//              by video
//      In the rightmost 8 columns:
//          0-63 - pair of tiles to display
//          64-255 - pair of tiles to display from lower half (0-31) plus
//              a "tag" 2-7 which is not used by this video generator but
//              is available for the outside accessor to use for its own
//              purposes.

// The tile image memory contains 128 tiles, each 8x8 pixels, each pixel
// 4 bits (RGBI encoding, R is the low bit, I the high bit).

// XXX this has been coded, but not tested; only the timings have
// been tested in simulation

module fpga_robots_game_video(
    // system interface
    input clk, // clock signal: about 65MHz; everything happens on rising edge
    input rst, // reset signal: synchronous, active-high
    // video output
    output reg [1:0] v_red = 2'd0, // "red" color signal
    output reg [1:0] v_grn = 2'd0, // "green" color signal
    output reg [1:0] v_blu = 2'd0, // "blue" color signal
    output reg       v_hsy = 1'd0, // horizontal sync signal
    output reg       v_vsy = 1'd0, // vertical sync signal
    // outside access to tile map memory
    //      all outputs delayed by one clock from their corresponding inputs
    input     [12:0] tm_adr,        // address
    output reg [7:0] tm_red = 8'd0, // data read from last address
    input            tm_wrt,        // data to be written
    input            tm_wen,        // enable write
    // animation control
    input [2:0] animode // select tile from sets of eight for animated robots
);
    // This code is pipeline oriented.  Each internal signal is marked
    // with its pipeline stage as prefix like "s1_".  Some signals are
    // carried from one pipeline stage to another, without any change,
    // just a delay and a change to the prefix.

    // // // //
    // Stage 1: Position counter.  This generates X and Y coordinates
    // including not only the visible part of the screen (X = 0 - 1023,
    // Y = 0 - 767) but also the blanking intervals (X = 0 - 1343,
    // Y = 0 - 805).

    // X position: increment every clock cycle, 0-1343.
    reg [10:0] s1_x = 11'd0;
    wire [10:0] s1_x_plus_1 = s1_x + 11'd1;
    wire s1_x_wrap = (s1_x_plus_1[10:6] == 5'd21);
    always @(posedge clk)
        s1_x <= rst ? 11'd0 : (s1_x_wrap ? 11'd0 : s1_x_plus_1);

    // Y position: increment whenever X wraps around, 0-805.
    reg [9:0] s1_y = 10'd0;
    wire [9:0] s1_y_plus_1 = s1_y + 10'd1;
    wire s1_y_wrap = (s1_y_plus_1 == 10'd806);
    always @(posedge clk)
        if (rst)
            s1_y <= 10'd0;
        else if (s1_x_wrap)
            s1_y <= s1_y_wrap ? 10'd0 : s1_y_plus_1;

    // Address for own internal accesses to tile map memory.
    //      s1_x - each 8 pixels make a 1 byte step
    //      s1_y - each 16 pixels make a 128 byte step
    wire [12:0] s1_tm_adr_v = {
        s1_y[9:4], // each 16 vert pixels make a 128 byte step, 0-47
        s1_x[9:3]  // each 8 horiz pixels make a 1 byte step, 0-127
    };

    // // // //
    // Stages 1-2: Tile map memory.  Inputs to it are stage 1, outputs
    // come a cycle later, so stage 2.  The memory is dual-ported, so I
    // hope your FPGA has double ported RAM.

    // the memory
    // YYY I only need 6kB, but this is 8kB for now
    reg [7:0] tile_map[0:8191];

    // initialize the memory contents
`ifndef ANALYZE_VIDEO_TIMINGS
    initial $readmemh("tile_map_init.mem", tile_map, 0, 8191);
`else
    // dummy values
    reg [13:0] tmi;
    initial begin
        for (tmi = 0; tmi < 8192; tmi = tmi + 1)
            tile_map[tmi] = 8'd255;
    end
`endif // ANALYZE_VIDEO_TIMINGS

    // read/write the memory, two ports
    reg [7:0] s2_tm_red_v = 8'd0; // result of video reads
    always @(posedge clk)
        if (rst) begin
            tm_red <= 8'd0;
            s2_tm_red_v <= 8'd0;
        end else begin
            // read-write external port
            tm_red <= tile_map[tm_adr];
            if (tm_wen) begin
                tile_map[tm_adr] <= tm_wrt;
                tm_red <= tm_wrt;
            end
            // read-only internal ("_v") port
            s2_tm_red_v <= tile_map[s1_tm_adr_v];
        end

    // // // //
    // Stage 2: Decode what we got from the tile map, to decide what tile
    // should appear in this 8x8 cell.

    // bringing signals forward from stage 1
    reg [10:0]s2_x = 11'd0;
    reg [9:0]s2_y = 10'd0;
    always @(posedge clk) s2_x <= rst ? 11'd0 : s1_x;
    always @(posedge clk) s2_y <= rst ? 10'd0 : s1_y;

    // if this is in the leftmost 120 grid columns (960 pixels): play area
    wire [1:0]s2_pa_what = s2_y[3] ? s2_tm_red_v[3:2] : s2_tm_red_v[1:0];
    wire [6:0]s2_pa_tile =
        { 2'd3, // tiles 96-127 hold the play area graphics
          s2_pa_what, // blank, robot, trash, player
          animode }; // eight animation frames of each

    // if this is in the rightmost 120 grid columns (64 pixels): status area
    // pairs of tiles, 0-63, or 0-31 plus invisible "tag" 2-7
    wire [6:0]s2_sa_tile = {
        (s2_tm_red_v[7:6] == 2'd3) ? 1'd0 : s2_tm_red_v[5],
        s2_tm_red_v[4:0],
        s2_y[3]
    };

    // so, which is it?
    wire [6:0]s2_tile = (s2_x[9:6] == 4'd15) ? s2_sa_tile : s2_pa_tile;

    // and from that we can address a particular byte of tile
    // image memory
    wire [11:0]s2_tile_img_adr = {
        s2_tile,   // 7 bit tile number
        s2_y[2:0], // 3 bit row number within tile
        s2_x[2:1]  // upper 2 bits of 2 bit column number within tile
    };

    // // // //
    // Stages 2-3: Tile image memory.  Inputs to this are in stage 2; outputs,
    // on stage 3.  It's 4kB storing 128 tile images, 8x8 pixels, 4 bits per
    // pixel.

    // The access bus to this is 8 bits (2 pixels) wide.  Why?  Because
    // it's a common memory width so seems a little more likely to be
    // portable.

    reg [7:0] tile_images [0:4095];
    reg [7:0] s3_tile_images_red = 8'd0;

`ifndef ANALYZE_VIDEO_TIMINGS
    initial $readmemh("tile_images.mem", tile_images, 0, 4095);
`else
    // dummy values to make a blank white screen, for simulation
    // of video timings
    reg [12:0] tii;
    initial begin
        for (tii = 0; tii < 4096; tii = tii + 1)
            tile_images[tii] = 8'd255;
    end
`endif // ANALYZE_VIDEO_TIMINGS

    always @(posedge clk)
        s3_tile_images_red <= rst ? 8'd0 : tile_images[s2_tile_img_adr];

    // // // //
    // Stage 3: Generate the video output

    // bringing signals forward from stage 2
    reg [10:0]s3_x = 11'd0;
    reg [9:0]s3_y = 10'd0;
    always @(posedge clk) s3_x <= rst ? 11'd0 : s2_x;
    always @(posedge clk) s3_y <= rst ? 10'd0 : s2_y;

    // Determine whether this is in horizontal sync, vertical sync, etc
    wire s3_in_hblank = s3_x[10]; // X >= 1024
    wire s3_in_vblank = (s3_y[9:8] == 2'd3); // Y >= 768
    wire s3_visible = !(s3_in_hblank || s3_in_vblank);
    wire s3_in_hsync = // 1048-1183
        (s3_x[10:8] == 3'd4) && (s3_x[7:3] >= 5'd3) && (s3_x[7:5] < 3'd5);
    wire s3_in_vsync = // 771-776
        s3_in_vblank && (s3_y[5:0] >= 6'd3) && (s3_y[5:0] <= 6'd8);

    // select one of the two pixels from the tile image we got
    wire [3:0] s3_rgbi = s3_x[0] ? s3_tile_images_red[3:0] :
                                   s3_tile_images_red[7:4];

    // convert that to real color outputs, 2 bits per component
    wire [1:0] s3_v_red = s3_visible ? { s3_rgbi[0], s3_rgbi[3] } : 2'd0;
    wire [1:0] s3_v_grn = s3_visible ? { s3_rgbi[1], s3_rgbi[3] } : 2'd0;
    wire [1:0] s3_v_blu = s3_visible ? { s3_rgbi[2], s3_rgbi[3] } : 2'd0;

    // // // //
    // After all the pipeline stages: register the outputs

    always @(posedge clk)
        if (rst) begin
            { v_red, v_grn, v_blu } <= 6'd0;
            v_hsy <= 1'd1;
            v_vsy <= 1'd1;
        end else begin
            v_red <= s3_v_red;
            v_grn <= s3_v_grn;
            v_blu <= s3_v_blu;
            v_hsy <= !s3_in_hsync;
            v_vsy <= !s3_in_vsync;
        end
endmodule

`ifdef ANALYZE_VIDEO_TIMINGS
    // ANALYZE_VIDEO_TIMINGS is meant for running this code standalone
    // in Icarus Verilog just to see what the timings of sync pulses, etc,
    // are, before hooking up to a real video screen.  It generates an
    // output of one line per clock, of two hex digits:
    //      &0x80 - vsync
    //      &0x40 - hsync
    //      &0x30 - blue
    //      &0x0c - green
    //      &0x03 - blue
    // with square brackets around it

module top();
    reg clk = 1'd0;
    initial forever begin #10; clk <= ~clk; end
    reg rst = 1'd1;
    initial begin
        #100;
        @(posedge clk);
        rst <= 1'd0;
    end

    wire [7:0]video;
    reg [2:0] animode = 3'd0;
    always @(posedge clk) animode <= animode + 1;

    fpga_robots_game_video it(
        .clk(clk), .rst(rst),
        .v_vsy(video[7]),
        .v_hsy(video[6]),
        .v_blu(video[5:4]),
        .v_grn(video[3:2]),
        .v_red(video[1:0]),
        .tm_adr(13'd0), .tm_wrt(8'd0), .tm_wen(1'd0),
        .animode(animode)
    );

    wire s3_framestart = (it.s3_x == 0) && (it.s3_y == 0);
    reg framestart = 1'd0;
    always @(posedge clk) framestart <= s3_framestart;

    always @(negedge clk)
        $display("[%02x]%s", video, framestart ? "*" : "");
endmodule
`endif // ANALYZE_VIDEO_TIMINGS
