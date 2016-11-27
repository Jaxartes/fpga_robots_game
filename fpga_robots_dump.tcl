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

# fpga_robots_dump.tcl
# started July 2016
# 
# This program dumps the state of the FPGA robots game.  It communicates
# with the FPGA over a serial port.  It sends a command to do a dump,
# and receives back a 6,242 character burst of text which represents
# the contents of the game's tile map memory.  Then this script translates
# the tile map contents into something that looks like the Unix 'robots'
# game's display, only larger and less refined.
#
# To run:  tclsh fpga_robots_dump.tcl
# optionally followed by additional words:
#       /dev/tty... - name of TTY device to use
#       debug - displays internal logic & partially decoded data

# This has some kind of bug where it times out after receiving 227 bytes.
# I think it's somewhere in this script, or in the interaction of the script
# with the OS, and not on the FPGA.  Running it again once or twice usually
# solves the problem.

# basic configuration settings

set dev /dev/ttyUSB1
set baud 115200
set handshake xonxoff
set shortwait 100 ; # milliseconds to wait before listening
set timeout_tolerate 10 ; # timeouts to tolerate
set debug 0

foreach arg $argv {
    if {$arg eq "debug"} {
        set debug 1
    } elseif {[string index $arg 0] eq "/"} {
        set dev $arg
    } else {
        puts stderr "Unknown command line option '$arg'."
        exit 1
    }
}

# connect
set fp [open $dev r+]
fconfigure $fp \
    -mode ${baud},n,8,1 \
    -buffering none -encoding binary -translation binary -blocking 0 \
    -handshake $handshake

# core logic

# consume any data that just happens to already be coming in, and throw
# it away
set gotcnt 0
while {1} {
    update
    set got [read $fp 512]
    if {$got eq ""} { break }
    incr gotcnt [string length $got]
    after $shortwait
}
puts stderr "Consumed $gotcnt bytes of previously buffered data."

# transmit the dump command
puts -nonewline $fp "`"
flush $fp
puts stderr "Issued the dump command"

# receive data in response
set bytes [list]
while {1} {
    # read data

    after $shortwait
    update
    set got [read $fp 512]
    if {$debug} {
        puts stderr "(Got [string length $got] bytes after short wait)"
    }
    if {$got eq ""} {
        if {$timeout_tolerate <= 0} break
        incr timeout_tolerate -1
    }

    # convert it to bytes

    for {set i 0} {$i < [string length $got]} {incr i} {
        lappend bytes [scan [string index $got $i] %c]
    }

    # see if we have enough to stop

    if {[llength $bytes] >= 6242} break
}
set bytes [lrange $bytes 0 6241]
puts stderr "Received [llength $bytes] bytes data dump"

if {$debug} {
    for {set i 0} {$i < [llength $bytes]} {incr i 16} {
        set s [format {data(% 4d)=} $i]
        for {set j 0} {$j < 16 && ($i + $j) < [llength $bytes]} {incr j} {
            append s [format {% 3d} [lindex $bytes $i+$j]]
        }
        puts stderr $s
    }
}

if {[llength $bytes] < 6242} {
    puts stderr "Timeout after [llength $bytes] bytes received"
    exit 1
}

# now that we have the data, parse it
if {[lindex $bytes 0] != 35} {
    puts stderr "Field starter byte (35) missing or wrong!"
    exit 1
}
if {[lindex $bytes end] != 38} {
    puts stderr "Field ending byte (38) missing or wrong!"
    exit 1
}
for {set y 47} {$y >= 0} {incr y -1} {
    # select one row's worth of data (two rows of the playing field)
    set rowbytes [lrange $bytes \
        [expr {1 + (47 - $y) * 130}] \
        [expr {130 + (47 - $y) * 130}]]
    if {[lindex $rowbytes 0] != 36} {
        puts stderr "Row $y starter byte (36) missing or wrong!"
        exit 1
    }
    if {[lindex $rowbytes end] != 37} {
        puts stderr "Row $y ending byte (37) missing or wrong!"
        exit 1
    }
    # extract the contents of the rightmost (first) eight bytes, which form
    # the scores and status area.
    set ontag ""
    foreach byte [lrange $rowbytes 1 8] {
        # maybe this is a "tag" beginning a displayed number
        set gottag 1
        switch -- [expr {$byte & 240}] {
            48  { set gottag 0 }
            64  { set ontag "unused-number" }
            80  { set ontag "level-number" }
            96  { set ontag "current-score" }
            112 { set ontag "high-score" }
            default {
                puts stderr "Bogus or out of place byte value $byte!"
                exit 1
            }
        }
        if {$gottag} {
            # if so start recording the contents
            set tagged_number($ontag) ""
        }
        # and maybe this continues a displayed number
        if {$ontag ne ""} {
            # we're recording a number, add to it
            if {($byte & 15) < 10} {
                # another digit
                set tagged_number($ontag) \
                    [format %c%s \
                        [expr {48 + ($byte & 15)}] \
                        $tagged_number($ontag)]
            } else {
                # no more digits
                set ontag ""
            }
        }
    }
    # extract the contents of the leftmost (last) 120 bytes, which form
    # the play area; each byte contains two play cells, one above the
    # other.
    for {set x 119} {$x >= 0} {incr x -1} {
        set byte [lindex $rowbytes [expr {128 - $x}]]
        set grid([list $x [expr {$y * 2    }]]) [expr {$byte & 3}]
        set grid([list $x [expr {$y * 2 + 1}]]) [expr {($byte >> 2) & 3}]
        if {$byte < 48 || $byte >= 64} {
            puts stderr "Bogus or output place byte value $byte!"
            exit 1
        }
    }
}

# Now that we have the data, display it!
for {set y -1} {$y <= 96} {incr y} {
    set s ""
    for {set x -1} {$x <= 120} {incr x} {
        if {$y < 0 || $y >= 96} {
            if {$x < 0 || $x >= 120} {
                append s "+" ; # corner
            } else {
                append s "-" ; # wall
            }
        } elseif {$x < 0 || $x >= 120} {
            append s "|" ; # wall
        } else {
            # decode & display the contents: blank, robot, trash, player
            switch -- $grid([list $x $y]) {
                0 { append s " " }
                1 { append s "+" }
                2 { append s "*" }
                3 { append s "@" }
                default { append s "?" }
            }
        }
    }
    puts $s
}
foreach numname [lsort [array name tagged_number]] {
    set number $tagged_number($numname)
    if {$number eq ""} continue ; # empty: don't display it
    set len [string length $numname]
    set plen 15
    set paddedname [string repeat " " [expr {$plen - $len}]]$numname
    puts [format {%-.15s = %s} $paddedname $number]
}
exit 0
