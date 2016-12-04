#!/usr/bin/tclsh
# randomize tile map
# may clobber it, take care

set xdim 128
set ydim 96
set pxmin 0
set pxmax 119
set nbytes [expr {int($xdim * $ydim / 2)}]

set ifp [open tile_map_init.mem r]
for {set i 0} {$i < $nbytes} {incr i} {
    set map($i) [scan [gets $ifp] %02x]
}

proc place {x y v} {
    global map xdim
    set a [expr {$x + int($y / 2) * $xdim}]
    if {$y & 1} {
        set map($a) [expr {($map($a) & 0xf3) | ($v << 2)}]
    } else {
        set map($a) [expr {($map($a) & 0xfc) | $v}]
    }
}

for {set x $pxmin} {$x <= $pxmax} {incr x} {
    for {set y 0} {$y < $ydim} {incr y} {
        if {rand() < 0.95} {
            set v 0 ; # empty
        } elseif {rand() < 0.9} {
            set v 1 ; # robot
        } else {
            set v 2 ; # trash
        }
        place $x $y $v
    }
}

place [expr {$pxmin + int(rand()*($pxmax - $pxmin + 1))}] \
      [expr {int(rand()*$ydim)}] \
      3 ; # player

close $ifp
set ofp [open tile_map_init.mem w]
for {set i 0} {$i < $nbytes} {incr i} {
    puts $ofp [format %02x $map($i)]
}
close $ofp
