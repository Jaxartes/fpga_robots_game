#!/usr/bin/wish
# fpga_robots_gfxer.tcl
# Jeremy Dilatush - started April 2016
# This utility is to help prepare the following inputs to the FPGA robots
# game:
#   tile_map_init.mem
#       This fills in the "tile map" memory, which says what tile is drawn
#       where.
#   tile_images.mem
#       This fills in the tile image memory, with 128 8x8 pixel 4bpp tiles.
# It generates the latter.  It doesn't generate the former, instead you edit
# it manually and this helps you preview it.

# The input file is a PNG image which should be 160x80 pixels, in which each
# 10x10 pixel area contains an 8x8 tile image at its center.

# Colors won't be reproduced exactly, far from it.

# XXX

# check the command line
if {[llength $argv] != 3} {
    puts stderr "ARGS: tile-map-filename input-filename output-filename"
    exit 1
}
set tile_map_filename [lindex $argv 0]
set input_filename [lindex $argv 1]
set output_filename [lindex $argv 2]
if {[file exists $output_filename]} {
    puts stderr "'$output_filename' already exists, sorry"
    exit 1
}

# read the tile map: at least 6k bytes in hex, one per line, nothing else
set tilemap() 0
set fp [open $tile_map_filename r]
while {![eof $fp]} {
    set line [string trim [gets $fp]]
    if {$line eq ""} continue
    if {[string length $line] ne 2 || ![string is xdigit -strict $line]} {
        error "Bad tile map line '$line'"
    }
    set tilemap($tilemap()) [scan $line %x]
    incr tilemap()
}
close $fp
puts stderr "Read $tilemap() bytes of tile map from $tile_map_filename"
if {$tilemap() < 6144} {
    puts stderr "Tile map too short!  Need 6144 bytes."
    exit 1
}

# read the tile images
image create photo tile_images -file $input_filename -format png
set tixdim [image width tile_images]
set tiydim [image height tile_images]
puts stderr "Read $tixdim x $tiydim pixel tile images from $input_filename"
if {$tixdim != 160 || $tiydim != 80} {
    puts stderr "Tile image input must be exactly 160x80 pixels"
    exit 1
}

# insert some dummy score data
foreach {svalue scode stype} {
    5678 224 "high score"
    1234 192 "current score"
    9    160 "current level"
} {
    for {set y 0} {$y < 48} {incr y} {
        for {set x 120} {$x < 128} {incr x} {
            if {($tilemap([expr {$x + $y * 128}]) & 0xe0) == $scode} {
                set digits [string length $svalue]
                for {set i 0} {$i < $digits} {incr i} {
                    set digit [string index $svalue $i]
                    set tilemap([expr {$x + $y * 128 - $digits + 1 + $i}]) \
                        [expr {$digit * 1}]
                }
            }
        }
    }
}

# choose actual tiles in each position
for {set y 0} {$y < 96} {incr y} {
    # play area: see s2_pa_tile in fpga_robots_game_video.v
    for {set x 0} {$x < 120} {incr x} {
        set byte $tilemap([expr {$x + ($y >> 1) * 128}])
        set unit [expr {(($y & 1) ? ($byte >> 2) : $byte) & 3}]
        set grid(${x},$y) [expr {96 + 8 * $unit + int(rand()*8)}]
        # puts -nonewline stderr " $grid(${x},$y)"
    }
    # status area: see s2_sa_tile in fpga_robots_game_video.v
    for {set x 120} {$x < 128} {incr x} {
        set byte $tilemap([expr {$x + ($y >> 1) * 128}])
        # puts -nonewline stderr " $byte"
        if {$byte & 0xc0} {
            set byte [expr {$byte & 0x1f}]
        }
        set grid(${x},$y) [expr {($byte << 1) ^ ($y & 1)}]
        # puts -nonewline stderr " $grid(${x},$y)"
    }
}
puts stderr "Chose tiles in 6144 positions"

# colors we have available to use: RGBI
set palette {
    0   0 0 0
    1   170 0 0
    2   0 170 0
    3   170 170 0
    4   0 0 170
    5   170 0 170
    6   0 170 170
    7   170 170 170
    8   85 85 85
    9   255 85 85
    10  85 255 85
    11  255 255 85
    12  85 85 255
    13  255 85 255
    14  85 255 255
    15  255 255 255
}

# examine the pixels of the input file, choosing colors to go in the 4kB
# tile image db.  At 4bpp they're only a very rough approximation.
set tile_pix() 0
for {set tile 0} {$tile < 128} {incr tile} {
    for {set y 0} {$y < 8} {incr y} {
        for {set x 0} {$x < 8} {incr x} {
            # get this pixel's actual color
            lassign [tile_images get \
                    [expr {$x + ($tile & 15) * 10 + 1}] \
                    [expr {$y + (($tile >> 4) & 7) * 10 + 1}]] \
                red grn blu
            # compare it to the sixteen possible colors
            set mndev ""
            foreach {pcn pcr pcg pcb} $palette {
                set dev [expr {sqrt(pow($pcr - $red, 2) + \
                                    pow($pcg - $grn, 2) + \
                                    pow($pcb - $blu, 2))}]
                if {$mndev eq "" || $mndev > $dev} {
                    set mndev $dev
                    set tile_pix($tile_pix()) \
                        [list $pcn $pcr $pcg $pcb]
                }
            }
            # puts -nonewline stderr " [lindex $tile_pix($tile_pix()) 0]"
            incr tile_pix()
        }
    }
}
puts stderr "Chose pixel colors for tile images"

# generate a preview display
puts stderr "Generating preview bitmap"
image create photo preview -width 1024 -height 768
for {set y 0} {$y < 768} {incr y} {
    for {set x 0} {$x < 1024} {incr x} {
        set tile $grid([expr {$x >> 3}],[expr {$y >> 3}])
        set pix $tile_pix([expr {($tile << 6) + ($x & 7) + (($y & 7) << 3)}])
        lassign $pix pcn pcr pcg pcb
        preview put \
            [format "\#%02x%02x%02x" $pcr $pcg $pcb] \
            -to $x $y
    }
}
canvas .preview -width 1034 -height 778 -background black
.preview create image 5 5 -image preview -anchor nw
pack .preview

button .btn -text "Write '$output_filename'" -command do_write
pack .btn

proc do_write {} {
    # Write the tile image file: 4,096 hex bytes, one per line, each
    # containing two pixels from tile_pix()
    global tile_pix output_filename

    set fp [open $output_filename {WRONLY CREAT EXCL}]
    for {set i 0} {$i < 4096} {incr i} {
        set pix1 $tile_pix([expr {$i << 1}])
        set pix2 $tile_pix([expr {($i << 1) | 1}])
        puts $fp [format %02x \
            [expr {([lindex $pix1 0] << 4) | [lindex $pix2 0]}]]
    }
    close $fp
    .btn configure -text "Exit" -command exit
}


