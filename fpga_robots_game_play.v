// fpga_robots_game_play.v
// Jeremy Dilatush - started June 2016
//
// The "heart" of the FPGA robots game code:  This is the part which reacts
// to user input and manipulates the contents of the screen as a result.
// Mainly, it repeatedly passes through the tile map memory (see
// fpga_robots_game_video.v) updating it as appropriate.

`include "fpga_robots_game_config.v"

// XXX work in progress, incomplete, and untested

module fpga_robots_game_play(
    // system wide control signals
    input clk, // clock: rising edge active, everything is synched to this
    input rst, // reset: active high, synchronous

    // Command bits, as found in the keyboard lookup table.  They'll
    // be pulsed when the command is issued, it's up to this module
    // to keep track of pending commands.
    input [15:0]cmd,

    // Access to the tile map memory
    output reg [12:0]tm_adr, // address: location we want to access
    output reg [7:0]tm_wrt, // data to write to it
    output reg tm_wen, // enable writing
    input [7:0]tm_red // data read from last clock cycle's address

    // debugging, just in case we want it
    , output dbg
);

    // This mainly works by going through the tile map memory in reverse
    // order, repeatedly.  Each time through it's running some "opcode".
    // It spends five clock cycles on each byte, which is enough to:
    //      + read that byte
    //      + perform four more operations, such as reading and writing
    //      two other bytes
    // For the 6144 bytes, that will take about half a millisecond.

    // The one other thing it can do is wait.  Some opcodes require a wait
    // for the vertical blanking interval before starting their cycle.
    // And the "CMD_DUMP" opcode requires a wait between bytes of output
    // so that the serial port can keep up.

    // The "opcodes" form a state machine; here they are:
    parameter CMD_IDLE         = 4'd0; // wait for a command & perform it
    parameter CMD_DUMP         = 4'd1; // dump game state to serial port
    parameter CMD_NEWGAME      = 4'd2; // start a game
    parameter CMD_NEWLEVEL     = 4'd3; // start a level of the game
    parameter CMD_ENDLEVEL     = 4'd4; // end a level of the game
    parameter CMD_MOVE         = 4'd5; // perform a single move
    parameter CMD_TRASH        = 4'd6; // fill play area with garbage

    // Handling commands which come in through 'cmd'
    reg [7:0]cmd_smove = 8'd0; // single moves pending: E SE S SW W NW N NE
    reg [7:0]cmd_rmove = 8'd0; // repeated moves pending
    wire [7:0]cmd_smove_clr; // will pulse when one of these is done
    wire [7:0]cmd_rmove_clr; // will pulse when one of these is done
    reg cmd_tele = 1'd0; // teleport command
    reg cmd_wait = 1'd0; // wait command
    reg cmd_turn = 1'd0; // waste turn command
    reg cmd_quit = 1'd0; // quit command
    wire cmd_tele_clr, cmd_wait_clr, cmd_turn_clr, cmd_quit_clr;
    reg [2:0]cmd_fns = 3'd0; // F1, F2, F3 keys do "special" things
    reg [2:0]cmd_fns_clr;
        // XXX generate cmd_*_clr somewhere

    always @(posedge clk)
        if (rst) begin
            cmd_smove <= 8'd0;
            cmd_rmove <= 8'd0;
            { cmd_tele, cmd_wait, cmd_turn, cmd_quit } <= 4'd0;
            cmd_fns <= 3'd0;
        end else begin
            cmd_smove <= (cmd_smove & ~cmd_smove_clr) |
                         (cmd[15] ? 8'd0 : cmd[7:0]);
            cmd_rmove <= (cmd_rmove & ~cmd_rmove_clr) |
                         (cmd[15] ? cmd[7:0] : 8'd0);
            cmd_tele <= (cmd_tele & ~cmd_tele_clr) | cmd[14];
            cmd_wait <= (cmd_wait & ~cmd_wait_clr) | cmd[13];
            cmd_turn <= (cmd_turn & ~cmd_turn_clr) | cmd[12];
            cmd_quit <= (cmd_quit & ~cmd_quit_clr) | cmd[11];
            cmd_fns <= (cmd_fns & ~cmd_fns_clr) | cmd[10:8];
        end

    // Pseudorandom number generation.  This is used for filling in the
    // playing field at the start of each level.  It's run continuously,
    // generating three bits per clock.  We usuall want more bits than
    // that, but we can wait several clocks for them.  Take the result
    // of the right side of 'prng'.
    reg [19:0]prng = 20'd1;
    wire [19:0]prng_succ;
    lfsr_20_3 prng_lfsr(.in(prng), .out(prng_succ));
    always @(posedge clk) prng <= rst ? 20'd1 : prng_succ;

    // Core state machine "loop"
    reg [3:0]sml_opcode = CMD_IDLE; // "opcode" running now
    reg [6:0]sml_x = 7'd127; // X coordinate in cells, 0-127
    reg [5:0]sml_y = 6'd47; // Y coordinate in pairs of cells, 0-47
        // note: sml_x, sml_y are the current place in the scan,
        // which doesn't necessarily correspond to the memory being accessed
        // every time.
    reg [2:0]sml_ph = 3'd0; // memory access phases at each position
    reg [3:0]sml_opcode_next; // next command to perform
    reg sml_suspend; // halt the loop waiting for something
    always @(posedge clk)
        if (rst) begin
            sml_opcode <= CMD_IDLE;
            sml_x <= 7'd127;
            sml_y <= 6'd47;
            sml_ph <= 3'd0;
        end else if (sml_suspend) begin
            // nothing happening, we're just waiting
        end else if (sml_opcode == CMD_IDLE) begin
            // idle, so can switch states any time
            sml_opcode <= sml_opcode_next;
        end else if (sml_ph != 3'd4) begin
            // continue through this cell pair's actions
            sml_ph <= sml_ph + 3'd1;
        end else if (sml_x != 7'd0) begin
            // next cell pair horizontally
            sml_x <= sml_x - 7'd1;
            sml_ph <= 3'd0;
        end else if (sml_y != 6'd0) begin
            // next row of cell pairs
            sml_x <= 7'd127;
            sml_y <= sml_y - 6'd1;
            sml_ph <= 3'd0;
        end else begin
            // completed this opcode
            sml_x <= 7'd127;
            sml_y <= 6'd47;
            sml_opcode <= sml_opcode_next;
            sml_ph <= 3'd0;
        end

    // Derived from state machine loop state
    wire [12:0]sml_adr = { sml_y, sml_x }; // memory address, if that's the
                                           // one we're addressing
    wire sml_rgt = (sml_x[6:3] == 4'd15); // is in right side (1) where scores
                                          // are, or left side (0) game play
                                          // area?
    wire sml_ph0 = (sml_ph == 3'd0);
    wire sml_ph1 = (sml_ph == 3'd1);
    wire sml_ph2 = (sml_ph == 3'd2);
    wire sml_ph3 = (sml_ph == 3'd3);
    wire sml_ph4 = (sml_ph == 3'd4);

    // Score keeping
    wire score_reset; // pulse to reset the store
    wire [7:0]sk_level; // 2-digit level number
    wire [1:0]sk_level_mask; // hide digits
    reg sk_level_inc; // pulse to increment it
    digit2 sk_level_digit2(
        .clk(clk), .rst(rst || score_reset),
        .data(sk_level), .mask(sk_level_mask),
        .inc(sk_level_inc)
    );
    wire [23:0]sk_score; // 6-digit current score
    wire [23:0]sk_high; // 6-digit high score
    wire [5:0]sk_score_mask; // hide digits
    wire [5:0]sk_high_mask;
    reg sk_score_inc, sk_high_inc; // pulse to increment
    digit6 sk_score_digit6(
        .clk(clk), .rst(rst || score_reset),
        .data(sk_score), .mask(sk_score_mask), .inc(sk_score_inc)
    );
    digit6 sk_high_digit6(
        .clk(clk), .rst(1'd0),
        .data(sk_high), .mask(sk_high_mask), .inc(sk_high_inc)
    );

    // And the logic for writing those scores into memory.  Which happens
    // in many (not all) of the opcodes in the state machine.
    // XXX do the various parts of this
    reg [23:0]skw_data = 24'd0; // digits to write
    reg [23:0]skw_data_saved = 24'd0; // old value of that
    reg [5:0]skw_mask = 6'd0; // digits to hide
    reg [5:0]skw_mask_saved = 6'd0; // old value of that
    reg [2:0]skw_count = 3'd0; // number of digits remaining to write
    reg [2:0]skw_count_saved = 3'd0; // old value of that
    reg skw_didread; // pulse when the result of a read, done on
                     // behalf of the score writing, is done; in
                     // the same cycle a write may be performed
    wire skw_wen; // write enable
    wire [7:0]skw_wrt; // data to write

    always @(posedge clk)
        if (rst) begin
            skw_data_saved <= 24'd0;
            skw_mask_saved <= 6'd0;
            skw_count_saved <= 3'd0;
        end else begin
            skw_data_saved <= skw_data;
            skw_mask_saved <= skw_mask;
            skw_count_saved <= skw_count;
        end

    always @* begin
        skw_data = skw_data_saved;
        skw_mask = skw_mask_saved;
        skw_count = skw_count_saved;

        if (sml_rgt && skw_didread) begin
            // Recognize a 'tag' in the memory we just read
            case (tm_red[7:5])
            3'd5: begin // 160 - tag to start level number
                skw_data = { 16'd0, sk_level };
                skw_mask = { 4'd15, sk_level_mask };
                skw_count = 3'd2;
            end
            3'd6: begin // 192 - tag to start score
                skw_data = sk_score;
                skw_mask = sk_score_mask;
                skw_count = 3'd6;
            end
            3'd7: begin // 224 - tag to start high score
                skw_data = sk_high;
                skw_mask = sk_high_mask;
                skw_count = 3'd6;
            end
            default: // no recognized tag - one more digit
                if (skw_count_saved) begin
                    skw_data = { 4'd0, skw_data_saved[23:4] };
                    skw_mask = { 1'd1, skw_mask_saved[5:1] };
                    skw_count = skw_count_saved - 3'd1;
                end
            endcase
        end
    end

    assign skw_wen = skw_count && skw_didread;
    assign skw_wrt = { tm_red[7:4], skw_mask[0] ? 4'd10 : skw_data[3:0] };
    
    // Handle the "opcodes" of the state machine loop, especially
    // memory access.
    always @* begin
        tm_adr = 13'd0;
        tm_wrt = 8'd0;
        tm_wen = 1'd0;
        sml_opcode_next = CMD_IDLE;
        sml_suspend = 1'd0;
        cmd_fns_clr = 3'd0;
        skw_didread = 1'd0;
        sk_level_inc = 1'd0;
        sk_score_inc = 1'd0;
        sk_high_inc = 1'd0;

        case(sml_opcode)
        CMD_IDLE: begin
            // This is where we handle commands received from 'cmd' and
            // processed through 'cmd_*'
            if (cmd_fns[2]) begin // F3: trash; increment score
                cmd_fns_clr[2] = 1'd1;
                sml_opcode_next = CMD_TRASH;
                sk_score_inc = 1'd1;
            end else if (cmd_fns[0]) begin // F1: increment level
                cmd_fns_clr[0] = 1'd1;
                sk_level_inc = 1'd1;
            end else if (cmd_fns[1]) begin // F2: increment high score
                cmd_fns_clr[1] = 1'd1;
                sk_high_inc = 1'd1;
            end
            // XXX handle all the commands here
        end
        CMD_DUMP: begin
            // XXX
        end
        CMD_NEWGAME: begin
            // XXX
        end
        CMD_NEWLEVEL: begin
            // XXX
        end
        CMD_ENDLEVEL: begin
            // XXX
        end
        CMD_MOVE: begin
            // XXX
        end
        CMD_TRASH: begin
            // "Trash" command: fill play area with garbage, for testing
            // and debugging.
            if (sml_rgt) begin
                // score update
                skw_didread = sml_ph1;
                tm_adr = sml_adr;
                tm_wen = skw_wen;
                tm_wrt = skw_wrt;
            end else begin
                if (sml_ph0) begin
                    // garbage from the PRNG
                    tm_wen = 1'd1;
                    tm_adr = sml_adr;
                    tm_wrt = prng[7:0];
                end
            end
        end
        endcase
        // XXX
    end

    // XXX
endmodule
