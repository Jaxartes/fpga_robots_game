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

# fpga_robots_position_dumps.tcl
# started November 2016
# For testing one aspect of the FPGA robots game: Random positioning of
# the player.  For this to work, FPGA_ROBOTS_POSITION_DUMP must have
# been `defined when the game was built.  This repeatedly starts a new
# game, does a dump, and prints the X & Y coordinates of the new
# player position.

# Parameters:
#   keydelay $ms - Delay in milliseconds after each keycode ('q') sent.
#       Default 10.  In my testing 3 works.
#   commdelay $ms - Time in milliseconds to wait for things to happen
#       in communication with the FPGA (ie a dump).  Default 5.  In my
#       testing 1 works.
#   device $dev - Device to contact.  Default /dev/ttyUSB1.
#   verbose - increase verbosity of output
#   baud $baud - set baud rate of serial communication.  Default 115200.

### Read parameters from command line

array set cfg {
    ,keydelay ms keydelay 50
    ,commdelay ms commdelay 50
    ,device - device /dev/ttyUSB1
    ,verbose + verbose 0
    ,baud i baud 115200
}
for {set p 0} {$p < [llength $argv]} {} {
    set opt [lindex $argv $p]
    set arg [lindex $argv 1+$p]
    if {![info exists cfg(,$opt)]} {
        error "Unknown option '$opt'"
    }
    set badarg "Bad argument"
    switch -- $cfg(,$opt) {
        ms {
            # time in milliseconds
            set badarg "must be positive integer"
            if {[string is integer -strict $arg]} {
                set arg [expr {int($arg)}]
                if {$arg > 0} {
                    set cfg($opt) $arg
                    set badarg ""
                    incr p 2
                }
            }
        }
        - {
            # no type
            set cfg($opt) $arg
            set badarg ""
            incr p 2
        }
        + {
            # repeated words type
            incr cfg($opt)
            set badarg ""
            incr p 1
        }
        i {
            # integer type
            set badarg "must be integer"
            if {[string is integer -strict $arg]} {
                set arg [expr {int($arg)}]
                set cfg($opt) $arg
                set badarg ""
                incr p 2
            }
        }
        default {
            error "Unknown argument type, bug in argument parsing"
        }
    }
    if {$badarg ne ""} {
        error "Bad argument for option '$opt', '$arg': $badarg"
    }
}

set xbits 7 ; # number of bits in the X coordinate
set ybits 7 ; # number of bits in the Y coordinate
set creps 3 ; # number of repeats of the coordinates, per dump
set fpgafp ""

### For interacting with the FPGA

# fpgatalk_init - connect to the FPGA
proc fpgatalk_init {} {
    global fpgafp cfg

    # has it already been done?
    if {$fpgafp ne ""} continue

    # open the device
    if {[catch {open $cfg(device) r+} fpgafp]} {
        puts stderr "*** error opening $cfg(device): $fpgafp"
        error "fatal error"
    }

    # configure it
    if {[catch {
        fconfigure $fpgafp -blocking 1 -encoding binary -translation binary
        fconfigure $fpgafp -handshake xonxoff
        fconfigure $fpgafp -mode $cfg(baud),n,8,1
    } err]} {
        puts stderr "*** error setting up $cfg(device): $err"
        error "fatal error"
    }

    # get rid of any input that wasn't for us
    fpgatalk_eat
}

# fpgatalk_eat - consume and return any uninteresting input.  Keeps going
# until $cfg(commdelay) milliseconds pass without anything.  If you want
# to collect but ignore output, just ignore the return value of this function.
proc fpgatalk_eat {} {
    global fpgafp cfg

    set all ""
    fconfigure $fpgafp -blocking 0
    while {1} {
        update
        set got [read $fpgafp 512]
        if {$got eq ""} break
        append all $got
        after $cfg(commdelay)
    }
    fconfigure $fpgafp -blocking 1
    return $all
}

# fpgatalk_keymit - Send bytes to the FPGA to start a new game.
proc fpgatalk_newgame {} {
    global fpgafp cfg

    puts -nonewline $fpgafp "AUOPAU" ; # make & break codes for 'q'
    flush $fpgafp
    after $cfg(keydelay)
}

# fpgatalk_get_dump - retrieve a dump of the player position & return a list
# of X & Y coordinates.  This may throw an error, in case of communications
# problem, or return empty string, in case of bogus data.
proc fpgatalk_get_dump {} {
    global fpgafp cfg xbits ybits creps

    # consume any input that isn't the dump
    fpgatalk_eat

    # trigger the dump
    puts -nonewline $fpgafp [format %c 96]
    flush $fpgafp
    after $cfg(commdelay)

    # now collect the dump output as long as we have any
    set data [fpgatalk_eat]
    if {$cfg(verbose)} {
        puts stderr "Dump received [string length $data] bytes"
    }

    # now try to parse it

    # anything before '(' is garbage
    set lft [string first "(" $data]
    if {$lft < 0} {
        error "Bad dump, no open paren"
    } else {
        set data [string range $data 1+$lft end]
        if {$cfg(verbose) && $lft > 0} {
            puts stderr "Dump ignoring $lft bytes before open paren"
        }
    }

    # anything after ')' is garbage
    set rgt [string last ")" $data]
    if {$rgt < 0} {
        error "Bad dump, no close paren after open paren"
    } else {
        set data [string range $data 0 [expr {$rgt - 1}]]
        set glen [expr {[string length $data] - $rgt - 1}]
        if {$cfg(verbose) && $glen > 0} {
            puts stderr "Dump ignoring $glen bytes after close paren"
        }
    }

    # expect a binary string repeated $creps times, ($xbits+$ybits) chars long
    set len [string length $data]
    set elen [expr {($xbits + $ybits) * $creps}]
    if {$len != $elen} {
        error "Bad dump, expected length $elen, actual length $len"
    }
    foreach c [split $data ""] {
        if {$c ne "0" && $c ne "1"} {
            error "Bad dump, contains non binary character"
        }
    }
    for {set i 1} {$i < $creps} {incr i} {
        set dump0 [string range $data 0 [expr {$xbits + $ybits - 1}]]
        set dumpi [string range $data \
            [expr {($xbits + $ybits) * $i}] \
            [expr {($xbits + $ybits) * ($i + 1) - 1}]]
        if {$dump0 ne $dumpi} {
            error "Bad dump, copies 0 and $i don't match"
        }
    }

    # parse it and return it; it's two little endian binary numbers
    set result [list]
    foreach {fs fl} [list 0 $xbits $xbits $ybits] {
        set value 0 ; # accumulated value
        set bvalue 1 ; # value of a bit
        for {set i $fs} {$i < $fs + $fl} {incr i} {
            if {[string index $data $i] eq "1"} {
                incr value $bvalue
            }
            incr bvalue $bvalue
        }
        lappend result $value
    }

    return $result
}

### Main program skeleton

# initialization
fpgatalk_init ; # connect to the FPGA
set tstart [clock milliseconds] ; # time we started

# repeated operation
while {1} {
    if {[info exists _do_not_run_]} break

    # start a new game (to get a new player position)
    fpgatalk_newgame

    # and get a dump
    if {[catch {fpgatalk_get_dump} res]} {
        # an error was thrown
        set dsum "A dump failed ($res)"
    } else {
        # successful dump
        set dsum "Dumped: x= [lindex $res 0] y= [lindex $res 1]"
    }

    # now report it, with time offset from start
    set tnow [clock milliseconds]
    set toff [expr {$tnow - $tstart}]
    puts [format "% 5u.%03u: %s" \
        [expr {int($toff / 1000)}] [expr {$toff % 1000}] $dsum]
    flush stdout
}
