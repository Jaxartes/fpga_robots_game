#!/usr/bin/tclsh
# Copyright (c) 2016 Jeremy Dilatush
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY JEREMY DILATUSH AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL JEREMY DILATUSH OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# 1024x768sim.tcl:
# This generates a single frame's worth of output describing control signals
# in 1024x768 video output.  It's meant for comparison against the output
# of the ANALYZE_VIDEO_TIMINGS code in fpga_robots_game_video.v.

# Timings for this mode:
# see http://tinyvga.com/vga-timing/1024x768@60Hz

# Output format: a sequence of bytes, in hexadecimal, one per line,
# with various bit fields reflecting the various output signals.  Each
# byte corresponds to a single pixel's worth of time.  The fields are:
#       &0x80 - vsync
#       &0x40 - hsync
#       &0x30 - blue
#       &0x0c - green
#       &0x03 - red
# That color information won't be very interesting since in test mode the
# screen is all white.

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

