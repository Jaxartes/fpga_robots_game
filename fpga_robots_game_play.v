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
    input dumpcmd_start, // pulses to trigger a dump
    input dumpcmd_pause, // high to indicate dump output is paused

    // Signal to get the user's attention, like with a beep
    output want_attention,

    // When is video in vertical blanking interval?
    input vbi,

    // Access to the tile map memory
    output reg [12:0]tm_adr, // address: location we want to access
    output reg [7:0]tm_wrt, // data to write to it
    output reg tm_wen, // enable writing
    input [7:0]tm_red, // data read from last clock cycle's address

    // Transmit data on the serial port, for a debugging dump
    output [7:0]ser_tx_dat, // the data
    output      ser_tx_stb, // pulse when ser_tx_dat is valid & new
    input       ser_tx_rdy, // high when all data has been transmitted

    // debugging, just in case we want it
    output dbg
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
    // And the "OPC_DUMP" opcode requires a wait between bytes of output
    // so that the serial port can keep up.

    parameter WAIT_FOR_VBI = 1'd1; // prettier but slow

    // The "opcodes" form a state machine; here they are:
    parameter OPC_IDLE         = 4'd0; // wait for a command & perform it
    parameter OPC_DUMP         = 4'd1; // dump game state to serial port
    parameter OPC_NEWGAME      = 4'd2; // start a new game
    parameter OPC_NEWLEVEL     = 4'd3; // start a level of the game
    parameter OPC_ENDLEVEL     = 4'd4; // end a level of the game
    parameter OPC_BOOT         = 4'd7; // start-up time
    parameter OPC_MV_ZEROTOP   = 4'd8; // zero the upper half bytes
    parameter OPC_MV_DOMOVE    = 4'd9; // do a single move, into upper halves
    parameter OPC_MV_COPYDOWN  = 4'd10; // copy move results from upper halves

    // things that go in the play area
    parameter PAC_EMPTY  = 2'd0;
    parameter PAC_ROBOT  = 2'd1;
    parameter PAC_TRASH  = 2'd2;
    parameter PAC_PLAYER = 2'd3;

    // Handling commands which come in through 'cmd', which are one bit
    // each, except some of the moves which are kept separately.
    reg cmd_quit = 1'd0; // quit command
    reg cmd_quit_clr;
    reg [2:0]cmd_fns = 3'd0; // F1, F2, F3 keys do "special" things
    reg [2:0]cmd_fns_clr;
    reg cmd_dump_pending = 1'd0; // a 'dump' has been requested
    reg cmd_dump_clr;

    always @(posedge clk)
        if (rst) begin
            cmd_quit <= 4'd0;
            cmd_fns <= 3'd0;
            cmd_dump_pending <= 1'd0;
        end else begin
            cmd_quit <= (cmd_quit & ~cmd_quit_clr) | cmd[11];
            cmd_fns <= (cmd_fns & ~cmd_fns_clr) | cmd[10:8];
            cmd_dump_pending <= (cmd_dump_pending & ~cmd_dump_clr) |
                dumpcmd_start;
        end

    // Pseudorandom number generation.  This is used for filling in the
    // playing field at the start of each level.  It's run continuously,
    // generating eight bits per clock.  We may want more bits than
    // that, but we can wait several clocks for them.
    reg [28:0]prng_st = 29'd1;
    wire [28:0]prng_st_nxt;
    lfsr_29_8 prng_lfsr(.in(prng_st), .out(prng_st_nxt));
    always @(posedge clk) prng_st <= rst ? 29'd1 : prng_st_nxt;

    // Extract the most recent 16 bits (two clock cycles' worth)
    wire [15:0]prng = prng_st[15:0];

    // Core state machine "loop"
    reg [3:0]sml_opcode = OPC_BOOT; // "opcode" running now
    reg [6:0]sml_x = 7'd127; // X coordinate in cells, 0-127
    reg [5:0]sml_y = 6'd47; // Y coordinate in pairs of cells, 0-47
        // note: sml_x, sml_y are the current place in the scan,
        // which doesn't necessarily correspond to the memory being accessed
        // every time.
    reg sml_x_max = 1'd1; // sml_x == 127
    reg sml_y_max = 1'd1; // sml_y == 47
    reg [2:0]sml_ph = 3'd0; // memory access phases at each position
    reg [3:0]sml_opcode_next; // next command to perform
    reg sml_suspend; // halt the loop waiting for something
    always @(posedge clk)
        if (rst) begin
            sml_opcode <= OPC_BOOT;
            sml_x <= 7'd127;
            sml_x_max <= 1'd1;
            sml_y <= 6'd47;
            sml_y_max <= 1'd1;
            sml_ph <= 3'd0;
        end else if (sml_suspend) begin
            // nothing happening, we're just waiting
        end else if (sml_opcode == OPC_IDLE) begin
            // idle, so can switch states any time
            sml_opcode <= sml_opcode_next;
        end else if (sml_ph != 3'd4) begin
            // continue through this cell pair's actions
            sml_ph <= sml_ph + 3'd1;
        end else if (sml_x != 7'd0) begin
            // next cell pair horizontally
            sml_x <= sml_x - 7'd1;
            sml_x_max <= 1'd0;
            sml_ph <= 3'd0;
        end else if (sml_y != 6'd0) begin
            // next row of cell pairs
            sml_x <= 7'd127;
            sml_x_max <= 1'd1;
            sml_y <= sml_y - 6'd1;
            sml_y_max <= 1'd0;
            sml_ph <= 3'd0;
        end else begin
            // completed this opcode
            sml_x <= 7'd127;
            sml_x_max <= 1'd1;
            sml_y <= 6'd47;
            sml_y_max <= 1'd1;
            sml_opcode <= sml_opcode_next;
            sml_ph <= 3'd0;
        end

    // Derived from state machine loop state
    wire [12:0]sml_adr = { sml_y, sml_x }; // memory address, if that's the
                                           // one we're addressing
    wire sml_rgt = (sml_x[6:3] == 4'd15); // is in right side (1) where scores
                                          // are, or left side (0) game play
                                          // area?
    wire sml_ph0 = (sml_ph == 3'd0); // five clock cycles per address
    wire sml_ph1 = (sml_ph == 3'd1);
    wire sml_ph2 = (sml_ph == 3'd2);
    wire sml_ph3 = (sml_ph == 3'd3);
    wire sml_ph4 = (sml_ph == 3'd4);
    wire sml_x_min = !(|sml_x); // sml_x == 0
    wire sml_y_min = !(|sml_y); // sml_y == 0
    wire sml_single = // pulses once per opcode, for things that only
                      // need to be done that one time
        sml_ph0 && sml_x_min && sml_y_min;

    // Score keeping
    reg score_reset; // pulse to reset the store
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
    wire sk_score_inc; // pulse to increment
    digit6 sk_score_digit6(
        .clk(clk), .rst(rst || score_reset),
        .data(sk_score), .mask(sk_score_mask), .inc(sk_score_inc)
    );
    digit6 sk_high_digit6(
        .clk(clk), .rst(1'd0),
        .data(sk_high), .mask(sk_high_mask),
        // If the score increases, and it was equal to the high score,
        // the high score increases.  That's any easier way to keep the
        // high score up to date, than comparing the two scores and
        // copying one.
        .inc(sk_score_inc && (sk_score == sk_high))
    );

    // Allow several to be added, one per clock cycle.
    // Assumes either sk_score_add or sk_score_acc is always zero, and
    // that no backlog accumulates.  These assumptions are borne up by
    // the way it's used here:  Up to four points (two robots times two
    // points each) in a five clock period.
    //      Input: sk_score_add, points to add
    //      Output: sk_score_inc, add a point a clock cycle or not
    reg [2:0]sk_score_acc = 3'd0;
    wire [2:0]sk_score_add; // XXX generate this signal somewhere
    always @(posedge clk)
        if (rst || score_reset)
            sk_score_acc <= 3'd0;
        else if (sk_score_acc)
            sk_score_acc <= sk_score_acc - 3'd1;
        else if (sk_score_add)
            sk_score_acc <= sk_score_add;
    assign sk_score_inc = |sk_score_acc;

    // And the logic for writing those scores into memory.  Which happens
    // in many (not all) of the opcodes in the state machine.
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

    // Logic for determining the number of robots that go on a new level.
    // In the original robots game, there were 10 robots per level on a
    // 60x22 field.  Our field is 128x96: 9.3x the area.  We'd have 93 robots
    // per level to achieve the same density.  Split the difference and
    // 32 robots per level seems about right.  In terms of probability
    // that's 1/384 per level.  Put the probability in units of 1/2^16
    // and it's about 171.  We won't bother trying to get an exact number
    // of robots, just count on the probability to make it mostly right.
    parameter ROBOT_PROB_CONST = 12'd171; // robots per 2^16 cells
    reg [11:0]robot_prob = 12'd0;
    always @(posedge clk)
        if (rst || score_reset)
            // the nonexistent level zero has no robots
            robot_prob <= 12'd0;
        else if (sk_level_inc)
            // each level has more robots than the last, until we wrap
            // around; but we want to avoid completely wrapping around,
            // since having a level without robots is inconvenient
            robot_prob <= { 1'd0, robot_prob[10:0] } + ROBOT_PROB_CONST;
    wire place_robot = (prng[15:0] < { 4'd0, robot_prob });

    // and in each pair of cells, save the top value (computed in ph0)
    // until we get the bottom value (computed in ph3)
    reg place_robot_old = 1'd0;
    always @(posedge clk)
        if (rst)
            place_robot_old <= 1'd0;
        else if (sml_ph0)
            place_robot_old <= place_robot;

    // Logic for determining a player position, pseudorandomly, when starting
    // a new level.
    reg [6:0]player_x = 7'd0;
    reg [6:0]player_y = 7'd0;
    wire [6:0]simple_new_player_x = prng[6:0]; // 0-127, but 120-127 not good
    wire [6:0]new_player_x = (prng[12:6] < 7'd120) ?
                             prng[12:6] : // 0-119
                             7'd60; // 60
    wire [6:0]new_player_y = { 1'd0, prng[5:0] } + 6'd16; // 16-79
    always @(posedge clk)
        if (rst || score_reset) begin
            player_x <= 7'd0;
            player_y <= 7'd0;
        end else if (sk_level_inc) begin
            player_x <= new_player_x;
            player_y <= new_player_y;
        end
    wire place_player_pair =
        (sml_x == player_x) && // right cell horizontally
        (sml_y == player_y[6:1]); // right *pair* of cells vertically

    // Logic for data dump over the serial port
    reg dump_going;
    wire dump_suspend = !ser_tx_rdy;
    reg [7:0]dump_tx_dat;
    reg dump_tx_stb;
    assign ser_tx_dat = dump_tx_dat;
    assign ser_tx_stb =
        dump_tx_stb && ser_tx_rdy && dump_going && !dumpcmd_pause;

    always @* begin
        dump_tx_dat = 8'd0;
        dump_tx_stb = 1'd0;

        if (sml_ph0 && sml_x_max && sml_y_max) begin
            // start the dump
            dump_tx_dat = 8'd35;
            dump_tx_stb = 1'd1;
        end else if (sml_ph1 && sml_x_max) begin
            // start a row of the dump
            dump_tx_dat = 8'd36;
            dump_tx_stb = 1'd1;
        end else if (sml_ph2) begin
            // single byte's worth of data
            if (sml_rgt && tm_red[7])
                // 64-127: 6 bits data, tagged scoreboard information
                dump_tx_dat = { 2'd1, tm_red[6:5], tm_red[3:0] };
            else
                // 48-63: 4 bits data, either untagged scoreboard information
                // or normal visible play area information
                dump_tx_dat = { 4'd3, tm_red[3:0] };
            dump_tx_stb = 1'd1;
        end else if (sml_ph3 && sml_x_min) begin
            // end a row of the dump
            dump_tx_dat = 8'd37;
            dump_tx_stb = 1'd1;
        end else if (sml_ph4 && sml_x_min && sml_y_min) begin
            // end the dump
            dump_tx_dat = 8'd38;
            dump_tx_stb = 1'd1;
        end
    end

    // In-progress and in-future move commands.
    // Main state variables:
    //      mcmd_pending - indicates what command is pending if any
    //      mcmd_modified - indicates command has modifier set, which
    //          when applied to the directional and "stay" commands,
    //          results in them continuing as long as they safely can
    // Input & control signals:
    //      mcmd_clear_pending - clear the pending command
    // Output signals:
    //      mcmd_pending_any - any command is pending
    //      move_player_{x,y} - where the player is moving to during a move
    // Constants:
    //      MCMD_* - codes defining the particular commands; see also
    //          key_table_gen.tcl.  The choice of these values isn't
    //          arbitrary; some patterns:
    //              . all non-MCMD_NONE values have their [4] bit set
    //              . all directional values are in the range 16-23
    parameter MCMD_NONE = 5'd0;
    parameter MCMD_E    = 5'd16;
    parameter MCMD_SE   = 5'd17;
    parameter MCMD_S    = 5'd18;
    parameter MCMD_SW   = 5'd19;
    parameter MCMD_W    = 5'd20;
    parameter MCMD_NW   = 5'd21;
    parameter MCMD_N    = 5'd22;
    parameter MCMD_NE   = 5'd23;
    parameter MCMD_STAY = 5'd24;
    parameter MCMD_WAIT = 5'd25;
    parameter MCMD_TELE = 5'd26;
    reg [4:0]mcmd_pending = MCMD_NONE;
    reg mcmd_modified = 1'd0;
    reg mcmd_clear_pending;

    wire mcmd_pending_any = mcmd_pending[4];
    wire cmd_any = cmd[4];
    wire cmd_modified = cmd[15];

    always @(posedge clk)
        if (rst) begin
            // reset: don't have any commands pending
            mcmd_pending <= MCMD_NONE;
            mcmd_modified <= 1'd0;
        end else if (cmd_any && !mcmd_pending_any) begin
            // If no command was pending and a new command comes in, record
            // it.  (If a command comes in while another was pending, ignore
            // it.)
            mcmd_pending <= cmd[4:0];
            mcmd_modified <= cmd_modified;
        end else if (mcmd_clear_pending) begin
            // we've been signalled to clear the pending command, it's done
            mcmd_pending <= MCMD_NONE;
            mcmd_modified <= 1'd0;
        end

    // Figure out some things about the move command mcmd_pending
    //      move_player_{x,y} - where the player is moving to
    //      mcmd_{n,s,e,w}ward - movement in a general direction
    //      mcmd_dec_{stay,wait,tele} - indicates these three commands
    //      move_oobounds - indicates move is out of bounds
    //      mcmd_nonlethal - if this move would result in player death, does
    //          that prevent it from happening?
    //      mcmd_continuous - does this move continue happening as long as
    //          it can?
    reg [6:0]move_player_x;
    reg [6:0]move_player_y;
    reg move_oobounds;
    reg mcmd_nward, mcmd_sward, mcmd_eward, mcmd_wward;
    always @* begin
        mcmd_nward = 1'd0;
        mcmd_sward = 1'd0;
        mcmd_eward = 1'd0;
        mcmd_wward = 1'd0;
        case (mcmd_pending)
        MCMD_E: mcmd_eward = 1'd1;
        MCMD_W: mcmd_wward = 1'd1;
        MCMD_N: mcmd_nward = 1'd1;
        MCMD_S: mcmd_sward = 1'd1;
        MCMD_NE: { mcmd_nward, mcmd_eward } = 2'd3;
        MCMD_NW: { mcmd_nward, mcmd_wward } = 2'd3;
        MCMD_SE: { mcmd_sward, mcmd_eward } = 2'd3;
        MCMD_SW: { mcmd_sward, mcmd_wward } = 2'd3;
        endcase
    end
    wire mcmd_dec_stay = (mcmd_pending == MCMD_STAY);
    wire mcmd_dec_wait = (mcmd_pending == MCMD_WAIT);
    wire mcmd_dec_tele = (mcmd_pending == MCMD_TELE);

    always @* begin
        move_player_x = player_x;
        move_player_y = player_y;
        move_oobounds = 1'd0;
        if (mcmd_wward) begin
            move_player_x = player_x - 7'd1;
            move_oobounds = (move_player_x == 7'd0);
        end else if (mcmd_eward) begin
            move_player_x = player_x + 7'd1;
            move_oobounds = (move_player_x == 7'd127);
        end else if (mcmd_dec_tele)
            move_player_x = new_player_x;

        if (mcmd_nward) begin
            move_player_y = player_y - 7'd1;
            move_oobounds = (move_player_y == 7'd0);
        end else if (mcmd_sward) begin
            move_player_y = player_y + 7'd1;
            move_oobounds = (move_player_y == 7'd95);
        end else if (mcmd_dec_tele)
            move_player_y = new_player_y;
    end

    reg mcmd_nonlethal, mcmd_continuous;
    always @* begin
        mcmd_nonlethal = 1'd1;
        mcmd_continuous = 1'd0;
        case (mcmd_pending)
        MCMD_WAIT: begin
            // 'w' command: wait for the robots to catch you
            mcmd_nonlethal = 1'd0;
            mcmd_continuous = 1'd1;
        end
        MCMD_TELE: begin
            // 't' command: teleport and hope you don't land on a robot
            // or trash
            mcmd_nonlethal = 1'd0;
        end
        default: begin
            // directional move commands and MCMD_STAY: These move
            // one step, or continuously if the modifier key is pressed.
            // They don't move at all if it's not safe.
            mcmd_continuous = mcmd_modified;
        end
        endcase
    end

    // Logic for moving the playing field elements (esp robots) when the
    // player moves; see OPC_MV_DOMOVE below.
    // Major signals:
    //      move_red - low (visible) half of byte that was read in ph0 that
    //          contains the elements being moved
    //      move_from_where_{x,y} - coordinates element is being moved from
    //      move_what - current cell's two-bit extract from that byte (PAC_*)
    //      move_to_adr - address of the cell it'd move *to*
    //      move_to_half - cell in upper (0) or lower (1) half of the byte?
    //      move_result - byte to write to that address
    //      move_kill_robots - 0-2 points, to add to score in this move
    //      move_kill_player - whether this move kills the player
    wire [3:0]move_red = sml_ph1 ? tm_red : move_red_save;
    reg [3:0]move_red_save = 4'd0;
    always @(posedge clk) move_red_save <= rst ? 4'd0 : move_red;

    wire [6:0]move_from_where_x = sml_x;
    wire [6:0]move_from_where_y = { sml_y, (sml_ph3 || sml_ph4) };

    wire [1:0]move_what = move_from_where_y[0] ? move_red[3:2] : move_red[1:0];

    reg [6:0]move_to_x_delta;
    reg [6:0]move_to_y_delta;
    always @* begin
        move_to_x_delta = 7'd0;
        move_to_y_delta = 7'd0;
        if (move_what == PAC_ROBOT || move_what == PAC_PLAYER) begin
            // robot can move; figure out direction in X & Y dimensions
            // player can move too
            if (move_player_x < move_from_where_x) begin
                // leftward
                move_to_x_delta = 7'd127;
            end else if (move_player_x > move_from_where_x) begin
                // rightward
                move_to_x_delta = 7'd1;
            end
            if (move_player_y < move_from_where_y) begin
                // upward
                move_to_y_delta = 7'd127;
            end else if (move_player_y > move_from_where_y) begin
                // downward
                move_to_y_delta = 7'd1;
            end
        end
    end
    wire [6:0]move_to_x = move_from_where_x + move_to_x_delta;
    wire [6:0]move_to_y = move_from_where_y + move_to_y_delta;
    wire [12:0]move_to_adr = { move_to_y[6:1], move_to_x[6:0] };
    wire move_to_half = move_to_y[0];

    // generate move_result, which is the byte which will be written back.
    // This depends on what's moving, where it's moving to, and what's
    // already moved there.  Even things that don't move - trash - are
    // still "moved" in the sense that they're put somewhere by the
    // computation.  It just always happends to be, where they already were.
    reg [7:0]move_result;
    wire [1:0]move_obstruction; // what was already there
    reg [1:0]move_kill_robots;
    reg move_kill_player;
    reg [1:0]move_combined; // combination of move_what & move_obstruction

    assign move_obstruction = move_to_half ? tm_red[7:6] : tm_red[5:4];

    always @* begin
        move_kill_robots = 2'd0; // no points unless determined otherwise
        move_kill_player = 1'd0; // survive unless determined otherwise

        case (move_what)
        PAC_EMPTY:
            // Nothing is being moved.
            move_combined = move_obstruction;
        PAC_ROBOT:
            // Robot is being moved.
            case (move_obstruction)
            PAC_EMPTY:
                // Robot safely moves.
                move_combined = PAC_ROBOT;
            PAC_ROBOT: begin
                // Two robots collide
                move_combined = PAC_TRASH;
                move_kill_robots = 2'd2;
            end
            PAC_TRASH: begin
                // One robot collides with trash
                move_combined = PAC_TRASH;
                move_kill_robots = 2'd1;
            end
            PAC_PLAYER: begin
                // Robot kills the player
                move_combined = PAC_ROBOT;
                move_kill_player = 1'd1;
            end
            endcase
        PAC_TRASH:
            // Trash is being "moved".  Since it never goes anywhere,
            // move_obstruction == PAC_TRASH too.
            move_combined = PAC_TRASH;
        PAC_PLAYER:
            // Player is being moved.
            case (move_obstruction)
            PAC_EMPTY:
                // Player safely moves.
                move_combined = PAC_PLAYER;
            PAC_ROBOT: begin
                // Player hits robot
                move_combined = PAC_ROBOT;
                move_kill_player = 1'd1;
            end
            PAC_TRASH: begin
                // Player hits trash.  Really this never happens, but
                // if it does, player dies; which is used to prevent
                // it from happening.
                move_combined = PAC_TRASH;
                move_kill_player = 1'd1;
            end
            PAC_PLAYER:
                // Shouldn't happen (shouldn't have two players to move)
                // but it's harmless if it does.
                move_combined = PAC_PLAYER;
            endcase
        endcase
    end

    always @* begin
        move_result = tm_red;
        if (move_to_half)
            move_result[7:6] = move_combined;
        else
            move_result[5:4] = move_combined;
    end

    // A player move command is handled in a sequence of OPC_MV_* states:
    //      OPC_MV_ZEROTOP - preparation
    //      OPC_MV_DOMOVE - perform the move; this is a "dry run" that
    //          isn't permanently stored & doesn't increase the score,
    //          it's just for figuring out if the move can complete.
    //      If move doesn't complete: it ends here; otherwise:
    //      OPC_MV_ZEROTOP - preparation for the real thing
    //      OPC_MV_DOMOVE - do the real thing including scoring
    //      OPC_MV_COPYDOWN - make the result visible
    //      If move continues: repeat from top
    // This is the logic to sequence those.
    // Major inputs:
    //      mcmd_pending_any - a command is pending
    // XXX

    // Handle the "opcodes" of the state machine loop, especially
    // memory access.
    reg want_attention_f2;
    always @* begin
        tm_adr = 13'd0;
        tm_wrt = 8'd0;
        tm_wen = 1'd0;
        sml_opcode_next = OPC_IDLE;
        sml_suspend = 1'd0;
        cmd_fns_clr = 3'd0;
        cmd_quit_clr = 1'd0;
        cmd_dump_clr = 1'd0;
        skw_didread = 1'd0;
        sk_level_inc = 1'd0;
        score_reset = 1'd0;
        want_attention_f2 = 1'd0;
        dump_going = 1'd0;
        mcmd_clear_pending = 1'd0;

        case(sml_opcode)
        OPC_IDLE: begin
            // This is where we handle commands received from 'cmd' and
            // processed through 'cmd_*'.  Move commands are processed
            // through an intermediate layer before coming here, see 'mcmd'.

            if (cmd_fns[2]) begin // F3: starts some parts of a "move"
                cmd_fns_clr[2] = 1'd1; // clear the command pending indicator
                sml_opcode_next = OPC_MV_ZEROTOP;
            end else if (cmd_fns[0]) begin // F1: new level
                cmd_fns_clr[0] = 1'd1; // clear the command pending indicator
                sk_level_inc = 1'd1;
                sml_opcode_next = OPC_NEWLEVEL;
            end else if (cmd_fns[1]) begin // F2: beep
                cmd_fns_clr[1] = 1'd1; // clear the command pending indicator
                want_attention_f2 = 1'd1; // signal for a beep
            end else if (cmd_quit) begin // q/esc/bs: new game
                cmd_quit_clr = 1'd1;
                score_reset = 1'd1; // reset score & level (but not high)
                sml_opcode_next = OPC_NEWGAME; // and fill in the level
            end else if (cmd_dump_pending) begin // data dump over serial port
                cmd_dump_clr = 1'd1;
                sml_opcode_next = OPC_DUMP;
            end else if (mcmd_pending_any) begin // command to move player
                // XXX this is just dummy code and doesn't do the whole thing,
                // for now it just does a dummy move like F3
                sml_opcode_next = OPC_MV_ZEROTOP;
            end
            // XXX handle all the commands here
        end
        OPC_NEWGAME : begin
            // Begin a new game.  This begins the first level of the game.
            // Hardly anything is done in this opcode, even though we give
            // it plenty of time.  Much is done in OPC_IDLE (before
            // OPC_NEWGAME) and the rest in OPC_NEWLEVEL (after OPC_NEWGAME).
            // The one thing that doesn't fit between is pulsing sk_level_inc,
            // because it can't happen at the same time as score_reset.

            // pulse sk_level_inc once, during the entire time this opcode runs.
            sk_level_inc = sml_single;
            sml_opcode_next = OPC_NEWLEVEL;
        end
        OPC_NEWLEVEL: begin
            // Begin a new level (possibly a new game).  Does the following:
            //      + clears existing play field
            //      + fills in new robots
            //      + fills in player
            // When entering this opcode do the following:
            //      + pulse sk_level_inc; that will increment the next level and
            //      increase the number of robots accordingly, and come up
            //      with a pseudorandom player position
            // At each address (five clocks, two playing area cells)
            // it does the following:
            //      1st clock: collects the decision of whether the top cell of
            //          the pair should have a robot
            //      5th clock: decides whether the bottom cell of the pair
            //          should have a robot; and stores the resulting byte
            //          of play area memory.
            // the 1st clock stuff is done elsewhere, see place_robot and
            // place_robot_old.
            // The reason for doing nothing for three cycles in between,
            // is just so that the pseudo random number generator can refresh.

            tm_adr = sml_adr;
            if (sml_rgt) begin
                // score update
                skw_didread = sml_ph1;
                tm_adr = sml_adr;
                tm_wen = skw_wen;
                tm_wrt = skw_wrt;
            end else begin
                // playing area update
                tm_wen = sml_ph3 && (!sml_rgt);
                tm_wrt[7:4] = 4'd0; // invisible temp storage, not used here
                if (place_player_pair && player_y[0])
                    tm_wrt[3:2] = PAC_PLAYER; // lower cell
                else if (place_robot)
                    tm_wrt[3:2] = PAC_ROBOT;
                else
                    tm_wrt[3:2] = PAC_EMPTY;
                if (place_player_pair && !player_y[0])
                    tm_wrt[1:0] = PAC_PLAYER; // upper cell
                else if (place_robot_old)
                    tm_wrt[1:0] = PAC_ROBOT;
                else
                    tm_wrt[1:0] = PAC_EMPTY;
                end
        end
        OPC_DUMP: begin
            // Dump: Dump the data in the tile map memory over the serial
            // port.
            dump_going = 1'd1;
            tm_adr = sml_adr;
            sml_suspend = dump_suspend;
        end
        OPC_ENDLEVEL: begin
            // XXX
        end
        OPC_BOOT: begin
            // At reset or startup: start a new game
            score_reset = 1'd1; // reset score & level (but not high)
            sml_opcode_next = OPC_NEWGAME; // and fill in the level
        end
        OPC_MV_ZEROTOP: begin
            // As part of a move, zero the upper 4 bits of each byte in
            // the play area.

            // Those will later be used for storing the results of the
            // move, provisionally, before they're copied down to the lower
            // 4 bits where they actually display.

            // Uses sml_ph0 to read the byte and sml_ph1 to write back
            // the modified value.

            tm_adr = sml_adr;
            tm_wen = sml_ph1 && !sml_rgt;
            tm_wrt = { 4'd0, tm_red[3:0] };

            // And the opcode OPC_MV_DOMOVE always follows it.
            sml_opcode_next = OPC_MV_DOMOVE;
        end
        OPC_MV_DOMOVE: begin
            // Do a move: Transferring playing field elements to their
            // new positions, in the upper (invisible) half of each byte
            // of the playing area.  Later (in OPC_MV_COPYDOWN) this will
            // be copied into the lower (visible) halves of the bytes.

            // This opcode uses all five phases:
            //      ph0 - reads the byte to move from
            //      ph1 - reads the byte to move the upper part to
            //      ph2 - writes back that byte, modified
            //      ph3 - reads the byte to move the lower part to
            //      ph4 - writes back that byte, modified

            if (sml_ph0) begin
                // ph0 - reads the byte to move from
                tm_adr = sml_adr;
            end else begin
                // ph1-ph4 - operations on the "move to" address
                tm_adr = move_to_adr;
            end
            tm_wen = (sml_ph2 || sml_ph4) && !sml_rgt;
            tm_wrt = move_result; // only matters in ph2 & ph4
            sml_opcode_next = OPC_MV_COPYDOWN; // XXX do for real
            // XXX handle score keeping
            // XXX handle failure
        end
        OPC_MV_COPYDOWN: begin
            // At the end of a successful move, copy from the upper half
            // bytes (which hold temporary results) to the lower half
            // (which hold displayed results).

            // Halt operation until we're in the vertical blanking interval,
            // for the best looking results
            sml_suspend = WAIT_FOR_VBI && !vbi;

            // Do the copy, by reading at ph0 & writing back at ph1.
            tm_adr = sml_adr;
            tm_wen = sml_ph1 && !sml_rgt && (vbi || !WAIT_FOR_VBI);
            tm_wrt = { 4'd0, tm_red[7:4] };

            // When this is done, go back to OPC_IDLE which gets to decide
            // what we'll be doing.
            sml_opcode_next = OPC_IDLE;
            mcmd_clear_pending = 1'd1; // clear the command, it's served
        end
        endcase
    end

    // Logic for getting the player's attention
    assign want_attention = want_attention_f2; // XXX add more

endmodule
