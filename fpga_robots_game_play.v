// fpga_robots_game_play.v
// Jeremy Dilatush - started June 2016
//
// The "heart" of the FPGA robots game code:  This is the part which reacts
// to user input and manipulates the contents of the screen as a result.
// Mainly, it repeatedly passes through the tile map memory (see
// fpga_robots_game_video.v) updating it as appropriate.

`include "fpga_robots_game_config.v"

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

    // Memory access logic driven by the state machine "loop"
    always @* begin
        tm_adr = 13'd0;
        tm_wrt = 8'd0;
        tm_wen = 1'd0;
        sml_opcode_next = CMD_IDLE;
        sml_suspend = 1'd0;

        case(sml_opcode)
        CMD_IDLE: begin
            // XXX
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
        endcase
        // XXX
    end
endmodule
