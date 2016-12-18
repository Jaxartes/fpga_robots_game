// fpga_robots_game_config.v

// // //
// Various "defines" which control the Verilog code related to game features.
// // //

// FPGA_ROBOTS_ANIMATE - `define this in order to enable animated graphics
// in the play area.  Without it, the game might be more boring, but it'll
// take up less logic space on the FPGA.
`define FPGA_ROBOTS_ANIMATE 1

// FPGA_ROBOTS_SQUARE - `define this if the "beep" sound is too mellow,
// or if it takes too much logic space on the FPGA.  Then a harsher but
// simpler square wave will be used
// `define FPGA_ROBOTS_SQUARE 1

// FPGA_ROBOTS_BIG_KEY_TABLE - make key_table[] larger.  It really only
// needs to be 8k bits, but ISE warns me about a bug with initializing
// 9kbit BRAMs so I'll expand it to 18kbit to work around it.
`define FPGA_ROBOTS_BIG_KEY_TABLE 1

// FPGA_ROBOTS_CORNER_DEBUG - Enable the bottom right corner of screen dumps
// to hold debugging information.  This is likely of interest only at
// development time, and not wanted when *playing* the game.
// `define FPGA_ROBOTS_CORNER_DEBUG 1

// FPGA_ROBOTS_F1_LEVEL - Enable a debug/cheat feature: The F1 key will
// result in going to a new level.
// `define FPGA_ROBOTS_F1_LEVEL 1

// FPGA_ROBOTS_UPPERLEFT - Enable a debug feature: About 1/4 of the time,
// when coming up with a random player position, instead of being spread
// out over most of the screen, it'll be in the upper left hand corner
// or the cell right below it.
// `define FPGA_ROBOTS_UPPERLEFT 1

// FPGA_ROBOTS_POSITION_DUMP - Replaces the full playing area dump
// (6242 bytes) with one of just the player position.  Used for testing
// the random player position.
// `define FPGA_ROBOTS_POSITION_DUMP 1

// // //
// Various "defines" which control the Verilog code related to board
// compatibility.  Choose the ones which are right for your board.
// // //

// FPGA_ROBOTS_VIDEO444 - Select your board's video type.
// FPGA_ROBOTS_VIDEO332
// Enable *exactly one* of these.
// For Papilio Pro + Papilio Arcade: FPGA_ROBOTS_VIDEO444
//      Which could also be used for any other board which has 4 bits
//      for red, 4 bits for green, 4 bits for blue.
// For Pepino board: FPGA_ROBOTS_VIDEO332
//      Which could also be used for any other board which has 3 bits
//      for red, 3 bits for green, 2 bits for blue.
`define FPGA_ROBOTS_VIDEO444 1
// `define FPGA_ROBOTS_VIDEO332 1

// FPGA_ROBOTS_CLK_XS6_32 - Select your board's clock type.
// FPGA_ROBOTS_CLK_XS6_50
// Enable *exactly one* of these.
// For Papilio Pro board: FPGA_ROBOTS_CLK_XS6_32
//      Which could also be used for any other board which has a
//      Xilinx Spartan6, two or more PLL's, and a 32MHz clock input.
// For Pepino board: FPGA_ROBOTS_CLK_XS6_50
//      Which could also be used for any other board which has a
//      Xilinx Spartan6, one or more PLL's, and a 50MHz clock input.
`define FPGA_ROBOTS_CLK_XS6_32 1
// `define FPGA_ROBOTS_CLK_XS6_50 1
