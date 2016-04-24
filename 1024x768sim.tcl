#!/usr/bin/tclsh
# This generates a single frame's worth of output describing control signals
# in 1024x768 video output.  It's meant for comparison against the output
# of the ANALYZE_VIDEO_TIMINGS code in fpga_robots_game_video.v.

# Timings for this mode:
# see http://tinyvga.com/vga-timing/1024x768@60Hz

# Output format: see the Verilog code

proc gen_frame {} {
    # 768 lines visible
    gen_line 1 1 0
    for {set i 0} {$i < 767} {incr i} {
        gen_line 0 1 0
    }
    # 3 lines front porch
    foreach _ {_ _ _} {
        gen_line 0 0 0
    }
    # 6 lines sync pulse
    foreach _ {_ _ _ _ _ _} {
        gen_line 0 0 1
    }
    # 29 lines back porch
    foreach _ {_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _} {
        gen_line 0 0 0
    }
}

proc gen_line {first visible vsync} {
    # 1024 clocks visible
    gen_pixel $first $visible $vsync 0
    for {set i 0} {$i < 1023} {incr i} {
        gen_pixel 0 $visible $vsync 0
    }
    # 24 clocks front porch
    for {set i 0} {$i < 24} {incr i} {
        gen_pixel 0 0 $vsync 0
    }
    # 136 clocks sync pulse
    for {set i 0} {$i < 136} {incr i} {
        gen_pixel 0 0 $vsync 1
    }
    # 160 clocks back porch
    for {set i 0} {$i < 160} {incr i} {
        gen_pixel 0 0 $vsync 0
    }
}

proc gen_pixel {first visible vsync hsync} {
    set byte [expr {
        ($visible ? 0x3f : 0x00) |
        ($hsync ? 0x00 : 0x40) |
        ($vsync ? 0x00 : 0x80)}]
    puts [format {[%02x]%s} \
        $byte [expr {$first ? "*" : " "}]]
}

gen_frame

