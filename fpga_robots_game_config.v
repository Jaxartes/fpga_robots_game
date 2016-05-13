// fpga_robots_game_config.v
// Jeremy Dilatush - started May 2016

// Various "defines" which control the Verilog code

// FPGA_ROBOTS_ANIMATE - `define this in order to enable animated graphics
// in the play area.  Without it, the game might be more boring, but it'll
// take up less logic space on the FPGA.
`define FPGA_ROBOTS_ANIMATE 1

// FPGA_ROBOTS_SQUARE - `define this if the "beep" sound is too mellow,
// or if it takes too much logic space on the FPGA.  Then a harsher but
// simpler square wave will be used
// `define FPGA_ROBOTS_SQUARE 1
