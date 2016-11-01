#!/usr/bin/tclsh
# fpga_robots_test.tcl
# started September 2016
# Test program for the FPGA robots game.  The way this tester works is it
# transmits keycode commands to the FPGA and requests dumps of its state.
# It compares the results it gets to the expected results.

# This program is far from the only testing I've done, but it allows for
# testing game logic in detail and in quantity.

# A game state is represented in this program as a list of the following:
#       + boolean: player is alive?
#       + current score
#       + current level
#       + player position
#       + list of robot positions
#       + list of trash positions
# Positions in turn are each represented as a list with two elements,
# 0-based X & Y coordinates.  Position lists are sorted.

# Parameters:
#   strategy $num - Probability $num (in range 0-1) that it chooses
#       a "strategic" move instead of a "random" one, each time.  Default 0.5.
#   butfast $num - Probability $num (in range 0-1) that, when doing a
#       "strategic" move, it just continues it as long as it can.  Default 0.1.
#   teles $num - Probability $num (in range 0-1) that, when doing a
#       "random" move, it teleports.  Default 0.01.
#   newgame $num - Probability $num (in range 0-1) of starting a new game
#       even when you don't need one.  Default 0.0.
#   newgamelevel $num - When doing a new game (see newgame), probability
#       (repeated, in range 0-1) of going to a new level using F1.
#       To work this requires FPGA_ROBOTS_F1_LEVEL be defined in
#       fpga_robots_game_config.v.  Default 0.0.
#   dumps $num - Probability $num (in range 0-1) that it requests a dump
#       after each move.  The probability doesn't matter after certain moves,
#       ones which leave the state uncertain ("t", "q", "w").  Default 0.5.
#   eom - End the test on the first mismatch, instead of the default, which
#       is to continue indefinitely, counting the mismatches.
#   nocont - don't do any continuous moves
#   3to1 - when coming up with "strategic" moves, prefer ones that cause
#       three robots to collide into one place
#   shiftdot $num - probability $num (in range 0-1) of doing "shift dot"
#       in place of other random moves, when doing a random move, excluding
#       the ones produced by the 'teles' option.  Even
#       if this is zero, the "shift dot" move will occur sometimes anyway.
#       default 0.0.
#   keydelay $ms - Delay in milliseconds after each keycode sent.
#       Default 200.
#   movedelay $ms - Delay in milliseconds after moving, per move performed.
#       Default 200.
#   commdelay $ms - Time in milliseconds to wait for things to happen
#       in communication with the FPGA.  Default 200.
#   device $dev - Device to contact.  Default /dev/ttyUSB1.
#   verbose - increase verbosity of output
#   lrcd - every time a dump happens, collect & print the 4 bits of debug
#       data from the lower right corner; see also FPGA_ROBOTS_CORNER_DEBUG
#       in the Verilog code.
#   baud $baud - set baud rate of serial communication.  Default 115200.

### Read parameters from command line

array set cfg {
    ,strategy p strategy 0.5
    ,butfast p butfast 0.1
    ,teles p teles 0.01
    ,newgame p newgame 0.0
    ,newgamelevel p newgamelevel 0.0
    ,dumps p dumps 0.5
    ,nocont + nocont 0
    ,3to1 + 3to1 0
    ,shiftdot p shiftdot 0.0
    ,eom + eom 0
    ,keydelay ms keydelay 200
    ,movedelay ms movedelay 200
    ,commdelay ms commdelay 200
    ,device - device /dev/ttyUSB1
    ,verbose + verbose 0
    ,lrcd + lrcd 0
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
        p {
            # probability
            set badarg "must be real number in range 0.0-1.0"
            if {[string is double -strict $arg]} {
                set arg [expr {double($arg)}]
                if {$arg >= 0.0 && $arg <= 1.0} {
                    set badarg ""
                    set cfg($opt) $arg
                    incr p 2
                }
            }
        }
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

set xdim 120 ; # horizontal size of playing area
set ydim 96 ; # vertical size of playing area
set sdim 8 ; # horizontal size of score keeping area
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

# fpgatalk_keymit - Send bytes to the FPGA to act like a given key, or
# combination of keys, was pressed.
#   $keys - a list with two elements per key, containing:
#       boolean - whether the keycode contains $E0
#       byte - final byte of keycode
# If the list contains a modifier key it should come before the key it
# modifies.  This acts as though all the keys were pressed at once.
# If you want to press one key after another, make multiple calls to it.
proc fpgatalk_keymit {keys} {
    global fpgafp cfg

    set bytes [list]
    # build a list of bytes to send (and delays)
    foreach break {0 1} {
        # $break is 0 for make codes, 1 for break codes
        foreach {kcext kcbyt} $keys {
            if {$kcext} { lappend bytes 0xe0 }
            if {$break} { lappend bytes 0xf0 }
            lappend bytes $kcbyt
            lappend bytes -1 ; # delay
        }
    }
    # send them
    foreach byte $bytes {
        if {$byte < 0} {
            # not a byte, a delay
            after $cfg(keydelay)
        } else {
            # send a key code byte, as two serial bytes
            puts -nonewline $fpgafp [format %c%c \
                [expr {0x40 + (($byte >> 4) & 0x0f)}] \
                [expr {0x50 + (($byte     ) & 0x0f)}]]
            flush $fpgafp
        }
    }
}

# fpgatalk_move - tell the FPGA to perform a normal move
#       $dx - -1, 0, or 1 giving horizontal part of direction
#       $dy - -1, 0, or 1 giving vertical part of direction
#       $cont - whether it's a continuous move
# should be followed by a delay of $cfg(movedelay) times either 1
# (if $cont is zero) or the number of move steps that would be tried, plus 1.
proc fpgatalk_move {dx dy cont} {
    set keys [list]
    if {$cont} {
        lappend keys 0 0x12 ; # Shift_L
    }
    if {$dx < 0} {
        if {$dy < 0} { lappend keys 0 0x35 ; # y
        } elseif {$dy > 0} { lappend keys 0 0x32 ; # b
        } else { lappend keys 0 0x33 ; # h
        }
    } elseif {$dx > 0} {
        if {$dy < 0} { lappend keys 0 0x3c ; # u
        } elseif {$dy > 0} { lappend keys 0 0x31 ; # n
        } else { lappend keys 0 0x4b ; # l
        }
    } else {
        if {$dy < 0} { lappend keys 0 0x42 ; # k
        } elseif {$dy > 0} { lappend keys 0 0x3b ; # j
        } else { lappend keys 0 0x49 ; # period
        }
    }
    fpgatalk_keymit $keys
}

# fpgatalk_command - give a command to the FPGA, other than move
# should be followed by a delay of $cfg(movedelay)
proc fpgatalk_command {cmd} {
    switch -- $cmd {
        "tele" { fpgatalk_keymit [list 0 0x2c] }
        "quit" { fpgatalk_keymit [list 0 0x15] }
        "wait" { fpgatalk_keymit [list 0 0x1d] }
        "f1"   { fpgatalk_keymit [list 0 0x05] }
        "f2"   { fpgatalk_keymit [list 0 0x06] }
        "f3"   { fpgatalk_keymit [list 0 0x04] }
        default { error "*** bug in tester: unknown command $cmd" }
    }
}

# fpgatalk_get_dump - retrieve a dump of the game state & return a game
# state structure.  This may throw an error, in case of communications
# problem, or return empty string, in case of bogus data.
proc fpgatalk_get_dump {} {
    global fpgafp cfg xdim ydim sdim

    # consume any input that isn't the dump
    fpgatalk_eat

    # trigger the dump
    puts -nonewline $fpgafp [format %c 96]
    flush $fpgafp
    after $cfg(commdelay)

    # now collect the dump output as long as we have any
    set raw [fpgatalk_eat]
    if {$cfg(verbose)} {
        puts stderr "Dump received [string length $raw] bytes"
    }

    # now try to parse it
    set len [string length $raw]
    set pos 0
    set score ""
    set level ""
    set robots [list]
    set trashes [list]
    set player ""
    # dump starts with char 35, "#"
    if {$pos >= $len} {
        error "Bad dump: empty"
    }
    if {[string index $raw $pos] ne "\#"} {
        error [format "Bad dump: start char %d expect 35" \
            [scan [string index $raw $pos] %c]]
    }
    incr pos
    for {set y 0} {$y < $ydim} {incr y 2} {
        # row starts with char 36, "$"
        if {$pos >= $len} {
            error "Bad dump: cut short (i)"
        }
        if {[string index $raw $pos] ne "\$"} {
            error [format "Bad dump: row start char %d expect 36" \
                [scan [string index $raw $pos] %c]]
        }
        incr pos
        # followed by score keeping info
        set taggedfield "" ; # indicates what field if any is seen
        set taggedvalue "" ; # indicates what value it has
        set taggedcont 0 ; # indicates that the value continues
        for {set x 0} {$x < $sdim} {incr x} {
            if {$pos >= $len} {
                error "Bad dump: cut short (ii)"
            }
            set code [scan [string index $raw $pos] %c]
            incr pos
            if {$code & 64} {
                # { 2'd1, byte[6:5], byte[3:0] } for byte >= 128
                # a "tag" marking a score keeping field's rightmost digit
                if {($code & 15) >= 10} {
                    # but it's blank
                    set taggedfield ""
                    set taggedvalue ""
                    set taggedcont 0
                } else {
                    set taggedfield [expr {($code >> 4) & 3}]
                    set taggedvalue [expr {$code & 15}]
                    set taggedcont 1
                }
            } else {
                # { 4'd3, byte[3:0] } for byte < 128
                # giving a digit value (or garbage)
                if {($code & 15) >= 10} {
                    # blank ends it
                    set taggedcont 0
                } elseif {$taggedcont} {
                    # another digit on the left
                    set taggedvalue [expr {$code & 15}]$taggedvalue
                }
            }
            if {$cfg(lrcd) && !$y && !$x} {
                puts stderr \
                    [format "Lower right corner debug byte: 0x%x" \
                        [expr {$code & 15}]]
            }
        }
        if {$taggedfield ne ""} {
            # got a score keeping field!
            switch -- $taggedfield {
                1 { set level $taggedvalue }
                2 { set score $taggedvalue }
            }
        }
        # followed by playing area info
        for {set x 0} {$x < $xdim} {incr x} {
            # one byte, for two cells
            if {$pos >= $len} {
                error "Bad dump: cut short (iii)"
            }
            set code [scan [string index $raw $pos] %c]
            incr pos
            if {$code < 48 || $code >= 64} {
                error [format "Bad dump: playing area byte %d exp 48-63" $code]
            }

            # the two cells and their coordinates, unreversed
            set cells [list]
            lappend cells [expr {$xdim - 1 - $x}]
            lappend cells [expr {$ydim - 2 - $y}]
            lappend cells [expr {$code & 3}]
            lappend cells [expr {$xdim - 1 - $x}]
            lappend cells [expr {$ydim - 1 - $y}]
            lappend cells [expr {($code >> 2) & 3}]
            foreach {xx yy cv} $cells {
                switch -- $cv {
                    0 { # empty
                    }
                    1 { # robot
                        lappend robots [list $xx $yy]
                    }
                    2 { # trash
                        lappend trashes [list $xx $yy] 
                    }
                    3 { # player
                        if {$player eq ""} {
                            set player [list $xx $yy]
                        } else {
                            puts stderr "*** received dump with multiple players including two at $player and [list $xx $yy]"
                            return ""
                        }
                    }
                }
            }
        }

        # row ends with char 37, "%"
        if {$pos >= $len} {
            error "Bad dump: cut short (iv)"
        }
        if {[string index $raw $pos] ne "%"} {
            error [format "Bad dump: row end char %d expect 37" \
                [scan [string index $raw $pos] %c]]
        }
        incr pos
    }

    # dump ends with char 38, "&"
    if {$pos >= $len} {
        error "Bad dump: cut short (v)"
    }
    if {[string index $raw $pos] ne "&"} {
        error [format "Bad dump: row end char %d expect 38" \
            [scan [string index $raw $pos] %c]]
    }
    incr pos

    # dump should be done, but ignore any remaining characters we got

    # put the results together
    if {$score eq ""} {
        error "Bad dump: missing score"
    }
    if {$level eq ""} {
        error "Bad dump: missing level"
    }
    set state [list]
    lappend state [expr {$player ne ""}] ; # player alive?
    lappend state $score
    lappend state $level
    if {$player ne ""} {
        lappend state $player
    } else {
        lappend state [list 0 0] ; # just a fake player position
    }
    lappend state [lsort $robots]
    lappend state [lsort $trashes]

    return $state
}

### Misc utility functions

# equal_state: Compare two states; are they equivalent?
proc equal_state {s1 s2} {
    # Nearly trivial because of how they're stored
    return [expr {$s1 eq $s2}]
}

# represent_state: Create a string which represents the given game state.
proc represent_state {state {indent ""}} {
    global xdim ydim

    lassign $state alive score level player robots trashes

    foreach robot $robots {
        set roba($robot) 1
    }
    foreach trash $trashes {
        set traa($trash) 1
    }

    set s ""
    append s "${indent}Player "
    append s [expr {$alive ? "alive @ $player" : "dead"}]
    append s ", score ${score}, level ${level}"
    append s "\n${indent}[llength $robots] robots;"
    append s " [llength $trashes] trashes.\n"

    for {set y -1} {$y <= $ydim} {incr y} {
        append s $indent
        for {set x -1} {$x <= $xdim} {incr x} {
            # deal with boundary
            set xbdy [expr {$x < 0 || $x == $xdim}]
            set ybdy [expr {$y < 0 || $y == $ydim}]
            if {$xbdy && $ybdy} { append s "+" ; continue }
            if {$xbdy} { append s "|" ; continue }
            if {$ybdy} { append s "-" ; continue }

            # deal with what's sitting here
            set pos [list $x $y]
            if {$alive && $pos eq $player} { append s "@" ; continue }
            if {[info exists traa($pos)]} { append s "*" ; continue }
            if {[info exists roba($pos)]} { append s "+" ; continue }
            if {($x % 5) || ($y % 5)} { append s "." ; continue }
            append s ","
        }
        append s "\n"
    }

    return $s
}

# Tcl 8.5 doesn't have "signum" (does any version?)
proc ::tcl::mathfunc::signum {x} {
    if {$x < 0} {
        return -1
    } elseif {$x > 0} {
        return 1
    } else {
        return 0
    }
}

### For determining what effect a move would have 

# robot_move: Figure out where a robot would move, toward the player
proc robot_move {from player} {
    lassign $from rx ry
    lassign $player px py

    set rx2 $rx
    set ry2 $ry
    if {$px < $rx} {
        incr rx2 -1
    } elseif {$px > $rx} {
        incr rx2 1
    }
    if {$py < $ry} {
        incr ry2 -1
    } elseif {$py > $ry} {
        incr ry2 1
    }
    return [list $rx2 $ry2]
}

# apply_move: Apply a single move to a game state, returning a new game state.
# This doesn't handle random moves or moves that go to a new level, etc.
# Those require special handling.
#   $state - incoming state
#   $dx - X change in the move (-1, 0, 1)
#   $dy - Y change in the move (-1, 0, 1)
#   $mul - score multiplier (1, 2)
# Returns a list of:
#   + whether the move could actually be performed
#   + the new state
proc apply_move {state dx dy mul} {
    global xdim ydim

    # extract move info
    lassign $state alive score level pos robots trashes
    lassign $pos px py
    set px2 [expr {$px + $dx}]
    set py2 [expr {$py + $dy}]

    # basic checks
    if {!$alive} {
        # a dead player cannot move
        return [list 0 $state]
    }
    if {$px2 < 0 || $py2 < 0 || $px2 >= $xdim || $py2 >= $ydim} {
        # can't move out of bounds
        return [list 0 $state]
    }

    # perform the move
    set score2 $score
    set pos2 [list $px2 $py2]
    # arrays robots2a & trashes2a will hold new robot & trash positions
    foreach trash $trashes {
        set trashes2a($trash) 1 ; # there's trash in this space
    }
    foreach robot $robots {
        # from robot's old position, figure out new position
        lassign $robot rx ry
        set robot2 [robot_move $robot $pos2]
        if {![info exists robots2a($robot2)]} {
            set robots2a($robot2) 0
        }
        incr robots2a($robot2) 1
    }
    foreach robot [array names robots2a] {
        if {$robots2a($robot) > 1 || [info exists trashes2a($robot)]} {
            # one or more robots destroyed by collision
            set trashes2a($robot) 1
            incr score2 [expr {$robots2a($robot) * $mul}]
            unset robots2a($robot)
        }
    }
    set trashes2 [lsort [array names trashes2a]]
    set robots2 [lsort [array names robots2a]]
    if {[info exists trashes2a($pos2)] ||
        [info exists robots2a($pos2)]} {
        # a robot got to the player (or player got into trash): player dead
        return [list 1 [list 0 $score $level [list 0 0] $robots2 $trashes2]]
    }
    return [list 1 [list 1 $score2 $level $pos2 $robots2 $trashes2]]
}

### For determining a strategic move

# good_move - Given a state of the game, figure out a good next move.
# Returns the move as one of the following:
#   tele - recommend teleport
#   wait - recommend wait
#   $dx $dy - move by relative x & y coordinates
# This logic is not very efficient, but that's ok.  Running on a gigahertz
# range CPU, to test a low-cost FPGA implementation of a minicomputer game
# from the 1980s, not much is needed.
#
# Also, this strategy isn't very good.  Not sure I care, this script is
# just for testing after all.
proc good_move {state} {
    global cfg

    lassign $state alive score level player robots trashes

    if {!$alive} {
        error "Internal error: good_move called when player not alive"
    }

    # Consider what "wait" would do.  If we survive it, it's the best option.
    set state2 $state
    while {1} {
        if {![lindex $state2 0]} {
            # player didn't survive: don't use "wait"
            break
        }
        if {[llength [lindex $state2 4]] == 0} {
            # robots didn't survive: that's good
            return "wait"
        }
        lassign [apply_move $state2 0 0 2] possible state2
        if {!$possible} {
            # can't
            break
        }
    }
    
    # Consider the possible eight directions of move and what happens from
    # each.
    foreach dx {-1 0 1} {
        foreach dy {-1 0 1} {
            lassign [apply_move $state $dx $dy 1] possible state2
            if {$possible && [lindex $state2 0]} {
                # we only care about moves that are possible and survivable
                set dirs([list $dx $dy]) $state2
            }
        }
    }
    if {[array size dirs] == 0} {
        # no acceptable moves, there's only one thing left to do
        return "tele"
    }
    if {[array size dirs] == 1} {
        # only one move is acceptable, best to do it then
        return [lindex [array names dirs] 0]
    }

    # Two or more moves are possible: Try to pick a good one.
    # If we can complete the level in one move, that's best.  If not,
    # there's a tradeoff of three things:
    #       + destroying robots (that is the end goal)
    #       + creating trashes (to destroy more robots in the future)
    #       + getting robots into a narrow space (easier to destroy)
    #       + being away from robots
    set bestdir ""
    set bestdirgoodness 0
    foreach {dir state2} [array get dirs] {
        lassign $state2 alive2 score2 level2 player2 robots2 trashes2
        lassign $player2 px2 py2

        # look for an immediate win
        if {[llength $robots2] == 0} {
            # yay!  no more robots!
            return $dir
        }

        # score the "goodness" of the move
        #       -3 points per robot
        #       +2 points per trash
        #       -1 point per unit of smallest dimension robots occupy
        #       +1 point per unit of distance from nearest robot
        # The "3to1" option changes this with
        #       +5 points per new trash formed by three robots together
        set goodness 0
        incr goodness [expr {-3 * [llength $robots2]}]
        incr goodness [expr {2 * [llength $trashes2]}]
        if {$cfg(3to1)} {
            foreach trash $trashes {
                set otra($trash) 1
            }
            foreach robot $robots {
                set robot2 [robot_move $robot $player2]
                if {![info exists robto($robot2)]} {
                    set robto($robot2) 0
                }
                incr robto($robot2)
            }
            foreach p [array names robto] {
                if {[info exists otra($p)]} continue ; # old trash, new robots
                if {$robto($p) == 3} { incr goodness 5 }
            }
        }
        set minx 999 ; set miny 999 ; set maxx -999 ; set maxy -999
        set mind 999
        foreach robot $robots2 {
            lassign $robot x y
            set minx [expr {min($x,$minx)}]
            set maxx [expr {max($x,$maxx)}]
            set miny [expr {min($y,$miny)}]
            set maxy [expr {max($y,$maxy)}]
            set dx [expr {abs($x - $px2)}]
            set dy [expr {abs($y - $py2)}]
            set mind [expr {min(max($dx,$dy),$mind)}]
        }
        incr goodness [expr {-1 * min($maxx-$minx,$maxy-$miny)}]
        incr goodness $mind

        # is it the best so far?
        if {$bestdir eq "" || $goodness > $bestdirgoodness} {
            set bestdirgoodness $goodness
            set bestdir $dir
        }
    }

    return $bestdir
}

### Main program skeleton

# initialization
set state "" ; # dummy state to force a new game
set ctr(move) 0 ; # number of moves performed so far
set ctr(dump) 0 ; # number of dumps performed so far
set ctr(err) 0 ; # number of errors detected so far (game bugs only)
set infosec 0 ; # time in seconds we last showed info
fpgatalk_init ; # connect to the FPGA
set firstsec [clock seconds] ; # time we started

# repeated operation
while {1} {
    if {[info exists _do_not_run_]} break
    # Give a status report, some times.
    if {!($ctr(move) & ($ctr(move) - 1)) ||
        [clock seconds] > $infosec + 60 ||
        $cfg(verbose)} {
        set infosec [clock seconds]
        set sofar \
            [format {%s moves, %s dumps, %s mismatches, in %s seconds} \
                $ctr(move) $ctr(dump) $ctr(err) \
                [expr {$infosec - $firstsec}]]
        puts "So far: $sofar"
    }
    if {$cfg(eom) && $ctr(err) > 0} {
        puts stderr "Exit due to combination of mismatch & 'eom' option."
        exit 0
    }

    # Do we need to start a new game?
    if {$state eq "" || (rand() < 0.6 && ![lindex $state 0]) ||
        (rand() < $cfg(newgame))} {
        puts stderr "Starting a new game"
        fpgatalk_command quit
	incr ctr(move)
        after $cfg(movedelay)
        set expectlevel 1

        while {rand() < $cfg(newgamelevel)} {
            puts stderr "Advancing level using F1"
            fpgatalk_command f1
            incr ctr(move)
            after $cfg(movedelay)
            incr expectlevel
        }

        while {1} {
            if {[catch {fpgatalk_get_dump} state]} {
                puts stderr $state
                continue
            } else {
		incr ctr(dump)
                break
            }
        }
        if {$state eq ""} {
            puts stderr "*** Bogus data in dump (i)"
            incr ctr(err)
            continue
        }

        # check it
        lassign $state alive score level player robots trashes
        if {!$alive} {
            puts stderr "*** bad result: on new game, player is dead"
            incr ctr(err)
            continue
        } elseif {$expectlevel != $level} {
            puts stderr "*** bad result: on new game, level is $level, expected $expectlevel"
            incr ctr(err)
            continue
        } elseif {[llength $trashes] > 0} {
            puts stderr "*** bad result: on new game, there is trash"
            incr ctr(err)
            continue
        } elseif {[llength $robots] == 0} {
            puts stderr "*** bad result: on new game, there are no robots"
            incr ctr(err)
            continue
        } elseif {$score} {
            puts stderr "*** bad result: on new game, nonzero score"
            incr ctr(err)
            continue
        } else {
            # looks good
            puts stderr "Level $level robots count: [llength $robots]"
            continue
        }
    }

    # Pick a move to try next.
    if {rand() < $cfg(strategy) && [lindex $state 0]} {
        # try a good move
        set move [good_move $state]
        set cont [expr {[llength $move] > 0 && rand() < $cfg(butfast) && \
                        !$cfg(nocont)}]
        puts stderr "Next move '$move' (strategic) (cont=$cont)"
    } else {
        # try a random move
        if {rand() < $cfg(teles)} {
            set move "tele"
            set cont 0
        } elseif {rand() < $cfg(shiftdot)} {
            set move [list 0 0]
            set cont 1
        } elseif {rand() < 0.001} {
            set move "wait"
            set cont 0
        } else {
            set move [list [expr {int(rand()*3)-1}] [expr {int(rand()*3)-1}]]
            set cont [expr {rand() < 0.2 && !$cfg(nocont)}]
        }
        puts stderr "Next move '$move' (random) (cont=$cont)"
    }

    # Perform the move on the FPGA.
    if {[llength $move] > 1} {
        # a move
        fpgatalk_move [lindex $move 0] [lindex $move 1] $cont
    } else {
        # another command
        fpgatalk_command $move
    }
    incr ctr(move)

    # Perform the move on our internal state.  This is also where we figure
    # out how long to delay after the move.
    set ostate $state
    set delays 1
    set force_dump "" ; # if a dump is forced, this contains the reason
    if {$move eq "tele"} {
        # A teleport, there's no way to predict where it will go.
        # Below, we'll do a dump and check that it was reasonable.
        set force_dump tele
    } elseif {$move eq "wait"} {
        # A wait.  The player stands still until they're dead or all
        # the robots are.
        while {1} {
            if {![lindex $state 0]} break ; # player dead
            if {![llength [lindex $state 4]]} break ; # level cleared
            lassign [apply_move $state 0 0 2] _ state
            incr delays
        }
    } elseif {[llength $move] < 2} {
        # Should never happen.
        error "Internal error, questionable move '$move'"
    } elseif {$cont} {
        # A continuous move.  It happens until it doesn't happen.
        while {1} {
            if {![llength [lindex $state2 3]]} break ; # no move: level ended
            lassign [apply_move $state [lindex $move 0] [lindex $move 1] 1] \
                possible state2
            if {!$possible} break ; # doesn't happen: can't
            if {![lindex $state2 0]} break ; # doesn't happen: unsafe
            # happens, and maybe another happens
            incr delays
            set state $state2
        }
    } else {
        # Single move.  It happens or doesn't happen.
        lassign [apply_move $state [lindex $move 0] [lindex $move 1] 1] \
            possible state2
        if {$possible && [lindex $state2 0]} {
            set state $state2
        }
    }

    # Delay, so there's time for the move to complete on the FPGA.
    after [expr {$cfg(movedelay) * $delays}]

    # Maybe perform a dump to check the result of the move
    if {[lindex $state 0] && ![llength [lindex $state 4]]} {
        # Player has cleared the level; we can't predict how the new
        # level will be laid out so we need to dump.
        set force_dump level
    }
    if {$force_dump eq "" && rand() < $cfg(dumps)} {
        # Dump every now and then even if we don't strictly need to, so
        # we can check the state against what we expect.
        set force_dump random
    }
    if {$force_dump ne ""} {
        puts stderr "Getting dump; reason: $force_dump"
        while {1} {
            if {[catch {fpgatalk_get_dump} dstate]} {
                puts stderr $dstate
                continue
            } else {
                incr ctr(dump)
                break
            }
        }
        if {$dstate eq ""} {
            puts stderr "*** Bogus data in dump (ii)"
            incr ctr(err)
            continue
        }

        # Now that we have a dump, examine it

        lassign $state alive score level player robots trashes
        lassign $dstate dalive dscore dlevel dplayer drobots dtrashes
        lassign $ostate oalive oscore olevel oplayer orobots otrashes

        if {$force_dump eq "tele"} {
            # A teleport happened.  The new player position is
            # unpredictable, the rest of the state isn't.
            # Build a substitute $state with the unpredictable parts
            # derived from $dstate.

            if {$dalive} {
                # player survived, so we know where they jumped, from the dump
                set tplayer $dplayer
                set state \
                    [list $oalive $oscore $olevel $tplayer $orobots $otrashes]
                lassign [apply_move $state 0 0 1] _ state
            } elseif {!$oalive} {
                # Dead players can't teleport.
                set state $ostate
                lassign $state alive score level player robots trashes
            } else {
                # Player died in the teleport.  So the dump includes no player
                # position, which in turn makes it hard to figure out where
                # the robots were supposed to go.  Solve this by the brute
                # force method: try all possible places the player could
                # have jumped to, and see if any of them produce
                # matching results.
                set foundone 0
                set telescan_start [clock microseconds]
                for {set x 0} {$x < $xdim && !$foundone} {incr x} {
                    for {set y 0} {$y < $ydim && !$foundone} {incr y} {
                        set tplayer [list $x $y]
                        set tstate \
                            [list $oalive $oscore $olevel $tplayer \
                                $orobots $otrashes]
                        lassign [apply_move $tstate 0 0 1] moved tstate
                        if {$moved && [equal_state $dstate $tstate]} {
                            set foundone 1
                            set state $tstate
                            lassign $state \
                                alive score level player robots trashes
                        }
                    }
                }
                if {$cfg(verbose) > 0} {
                    puts stderr "Tried all possible teleport destinations in [expr {[clock microseconds] - $telescan_start}] microseconds."
                }
                if {$foundone} {
                    if {$cfg(verbose) > 0} {
                        puts stderr "Found successfully."
                    }
                } else {
                    puts stderr "Fatal teleport result not consistent with any possible destination."
                    if {$cfg($verbose) > 0} {
                        puts stderr "    ostate= $ostate"
                        puts stderr "     state= $state"
                        puts stderr "    dstate= $dstate"
                    }
                }
            }
        }
        if {[lindex $state 0] && ![llength [lindex $state 4]]} {
            # By whatever means, the player has cleared the level and
            # goes on to another one!  The layout of the new level
            # is unpredictable, but not its score or level number.
            # The number of robots is interesting; display it.
            # And build a substitute $state with the unpredictable parts
            # derived from $dstate.

            puts stderr "New level player position: [lindex $dstate 3]"

            set state [list $alive $score [expr {$level + 1}] \
                $dplayer $drobots $dtrashes]
        }
        if {$force_dump ne "random" && $alive} {
            # New random player position (not a random dump, therefore
            # a random position - yeah, it confused me too); report it.

            puts stderr "Random player position: [lindex $dstate 3]"
        }
        if {![equal_state $state $dstate]} {
            puts stderr "*** bad result: state mismatch"
            incr ctr(err)
            puts stderr "  move was $move (cont=$cont)"
            puts stderr "  dump reason was $force_dump"
            if {$cfg(verbose)} {
                puts stderr "  Previous state was:"
                if {$cfg(verbose) > 1} {
                    puts stderr [represent_state $ostate "    "]
                } else {
                    puts stderr "    $ostate"
                }
                puts stderr "  Predicted state was:"
                if {$cfg(verbose) > 1} {
                    puts stderr [represent_state $state "    "]
                } else {
                    puts stderr "    $state"
                }
                puts stderr "  Dumped state was:"
                if {$cfg(verbose) > 1} {
                    puts stderr [represent_state $dstate "    "]
                } else {
                    puts stderr "    $dstate"
                }
            }
        }

        # Since we did a dump we know what the state is.
        set state $dstate
    }
}
