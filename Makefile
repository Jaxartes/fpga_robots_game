# Makefile: used with 'make' to build stuff
# As yet it does not build the whole thing, just some parts.

VERILOG= \
    fpga_robots_game.v \
    fpga_robots_game_clock.v \
    fpga_robots_game_video.v \
    misc.v \
    fpga_robots_game_config.v \
    serial_port.v \
    ps2.v \
    fpga_robots_game_play.v \
    fpga_robots_game_control.v

build: a.out tile_images.mem key_table.mem

# clean: Remove some generated files.
clean:
	-rm a.out

# a.out: runs Icarus Verilog to check syntax of the Verilog; this doesn't
# build it for the FPGA, which is to be done separately via Xilinx's ISE.
a.out: $(VERILOG)
	iverilog $(VERILOG)

# tile_images.mem: Tile font.
tile_images.mem: tile_images.png
	wish fpga_robots_gfxer.tcl overwrite \
            tile_map_init.mem tile_images.png tile_images.mem

# key_table.mem: Information about keyboard scancodes.
key_table.mem: key_table_gen.tcl
	tclsh key_table_gen.tcl verbose > key_table.mem
