// fpga_robots_game_config.v
// Jeremy Dilatush - started May 2016

// Various "defines" which control the Verilog code

// XXX go through and adjust these for real use, when done testing & debugging

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
`define FPGA_ROBOTS_CORNER_DEBUG 1

// FPGA_ROBOTS_F1_LEVEL - Enable a debug/cheat feature: The F1 key will
// result in going to a new level.
`define FPGA_ROBOTS_F1_LEVEL 1

// FPGA_ROBOTS_UPPERLEFT - Enable a debug feature: About 1/4 of the time,
// when coming up with a random player position, instead of being spread
// out over most of the screen, it'll be in the upper left hand corner
// or the cell right below it.
// `define FPGA_ROBOTS_UPPERLEFT 1

