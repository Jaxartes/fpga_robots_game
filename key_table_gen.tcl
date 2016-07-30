#!/usr/bin/tclsh
# Jeremy Dilatush - May 2016
# key_table_gen.tcl - Generate a table for decoding PS/2 keyboard
# scancodes, for use in the "fpga_robots_game" game.

set verbose 0
if {[lindex $argv 0] eq "verbose"} {
    set argv [lrange $argv 1 end]
    set verbose 1
}

# Table of what keys have what meanings.
# format: label-list flag-list
# flag-list consists of one or more names, defined below in flag_codes().
# The name is because at one time they were all single bits.  Not any more,
# but the name sticks.
set meanings {
    {"Y" "KP 7"}           nw
    {"K" "KP 8" "U ARROW"} n
    {"U" "KP 9"}           ne
    {"H" "KP 4" "L ARROW"} w
    {"." "KP 5" "KP ."}    stay
    {"L" "KP 6" "R ARROW"} e
    {"B" "KP 1"}           sw
    {"J" "KP 2" "D ARROW"} s
    {"N" "KP 3"}           se
    {"W" "KP 0"}           wait
    {"T" "KP *"}           teleport
    {"Q" "ESC" "BKSP"}     quit
    {"L SHFT" "R SHFT"
     "L CTRL" "R CTRL"
     "L ALT" "R ALT"
     "L GUI" "R GUI"
     "NUM"}                modifier
    "F1"                   fn1
    "F2"                   fn2
    "F3"                   fn3
    "SCROLL"               scroll_for_reset
}

# and what the named "flags" above are encoded as numerically
array set flag_codes {
    modifier 0x8000
    scroll_for_reset 0x4000
    quit     0x0800
    fn3      0x0400
    fn2      0x0200
    fn1      0x0100
        e       16
        se      17
        s       18
        sw      19
        w       20
        nw      21
        n       22
        ne      23
        stay    24
        wait    25
        teleport 26
}

# Keyboard scan code data, adapted from
# http://www.computer-engineering.org/ps2keyboard/scancodes2.html
# I left out a few weird ones: PRNT SCRN & PAUSE
# format: label make break
set scancodes2 {
    "A" "1C" "F01C"
    "9" "46" "F046"
    "[" "54" "F054"
    "B" "32" "F032"
    "`" "0E" "F00E"
    "INSERT" "E070" "E0F070"
    "C" "21" "F021"
    "-" "4E" "F04E"
    "HOME" "E06C" "E0F06C"
    "D" "23" "F023"
    "=" "55" "F055"
    "PG UP" "E07D" "E0F07D"
    "E" "24" "F024"
    "\\" "5D" "F05D"
    "DELETE" "E071" "E0F071"
    "F" "2B" "F02B"
    "BKSP" "66" "F066"
    "END" "E069" "E0F069"
    "G" "34" "F034"
    "SPACE" "29" "F029"
    "PG DN" "E07A" "E0F07A"
    "H" "33" "F033"
    "TAB" "0D" "F00D"
    "U ARROW" "E075" "E0F075"
    "I" "43" "F043"
    "CAPS" "58" "F058"
    "L ARROW" "E06B" "E0F06B"
    "J" "3B" "F03B"
    "L SHFT" "12" "F012"
    "D ARROW" "E072" "E0F072"
    "K" "42" "F042"
    "L CTRL" "14" "F014"
    "R ARROW" "E074" "E0F074"
    "L" "4B" "F04B"
    "L GUI" "E01F" "E0F01F"
    "NUM" "77" "F077"
    "M" "3A" "F03A"
    "L ALT" "11" "F011"
    "KP /" "E04A" "E0F04A"
    "N" "31" "F031"
    "R SHFT" "59" "F059"
    "KP *" "7C" "F07C"
    "O" "44" "F044"
    "R CTRL" "E014" "E0F014"
    "KP -" "7B" "F07B"
    "P" "4D" "F04D"
    "R GUI" "E027" "E0F027"
    "KP +" "79" "F079"
    "Q" "15" "F015"
    "R ALT" "E011" "E0F011"
    "KP EN" "E05A" "E0F05A"
    "R" "2D" "F02D"
    "APPS" "E02F" "E0F02F"
    "KP ." "71" "F071"
    "S" "1B" "F01B"
    "ENTER" "5A" "F05A"
    "KP 0" "70" "F070"
    "T" "2C" "F02C"
    "ESC" "76" "F076"
    "KP 1" "69" "F069"
    "U" "3C" "F03C"
    "F1" "05" "F005"
    "KP 2" "72" "F072"
    "V" "2A" "F02A"
    "F2" "06" "F006"
    "KP 3" "7A" "F07A"
    "W" "1D" "F01D"
    "F3" "04" "F004"
    "KP 4" "6B" "F06B"
    "X" "22" "F022"
    "F4" "0C" "F00C"
    "KP 5" "73" "F073"
    "Y" "35" "F035"
    "F5" "03" "F003"
    "KP 6" "74" "F074"
    "Z" "1A" "F01A"
    "F6" "0B" "F00B"
    "KP 7" "6C" "F06C"
    "0" "45" "F045"
    "F7" "83" "F083"
    "KP 8" "75" "F075"
    "1" "16" "F016"
    "F8" "0A" "F00A"
    "KP 9" "7D" "F07D"
    "2" "1E" "F01E"
    "F9" "01" "F001"
    "]" "5B" "F05B"
    "3" "26" "F026"
    "F10" "09" "F009"
    ";" "4C" "F04C"
    "4" "25" "F025"
    "F11" "78" "F078"
    "'" "52" "F052"
    "5" "2E" "F02E"
    "F12" "07" "F007"
    "," "41" "F041"
    "6" "36" "F036"
    "." "49" "F049"
    "7" "3D" "F03D"
    "SCROLL" "7E" "F07E"
    "/" "4A" "F04A"
    "8" "3E" "F03E"
    "Power" "E037" "E0F037"
    "Sleep" "E03F" "E0F03F"
    "Wake" "E05E" "E0F05E"
    "Next Track" "E04D" "E0F04D"
    "Previous Track" "E015" "E0F015"
    "Stop" "E03B" "E0F03B"
    "Play/Pause" "E034" "E0F034"
    "Mute" "E023" "E0F023"
    "Volume Up" "E032" "E0F032"
    "Volume Down" "E021" "E0F021"
    "Media Select" "E050" "E0F050"
    "E-Mail" "E048" "E0F048"
    "Calculator" "E02B" "E0F02B"
    "My Computer" "E040" "E0F040"
    "WWW Search" "E010" "E0F010"
    "WWW Home" "E03A" "E0F03A"
    "WWW Back" "E038" "E0F038"
    "WWW Forward" "E030" "E0F030"
    "WWW Stop" "E028" "E0F028"
    "WWW Refresh" "E020" "E0F020"
    "WWW Favorites" "E018" "E0F018"
}

# put the data from $scancodes2 in a bunch of arrays
foreach {l m b} $scancodes2 {
    set bad 0
    foreach {h bv} [list $m makes $b breaks] {
        if {[string length $h] & 1} {
            puts stderr "Bad data for key '$l': odd length hex '$h'"
            set bad 1
        }
        set $bv [list]
        for {set i 0} {$i < [string length $h]} {incr i 2} {
            lappend $bv [scan [string range [string range $h $i end] 0 1] %x]
        }
    }
    if {$l eq ""} {
        puts stderr "Bad data for key '$l': empty label"
        set bad 1
    }
    if {[info exists scmakes($l)]} {
        puts stderr "Bad data for key '$l': duplicate"
        set bad 1
    }
    if {!$bad} {
        set scmakes($l) $makes
        set scbreaks($l) $breaks
    }
}

# initialize the memory table
for {set i 0} {$i < 512} {incr i} {
    set table($i) 0
}

# go through the "meanings" and place each in the memory table
foreach {labels flags} $meanings {
    # go through the flags to build up a "control word"
    set control_word 0
    foreach flag $flags {
        set control_word [expr {$control_word | $flag_codes($flag)}]
    }
    # now go through all the keys it's supposed to go on
    foreach label $labels {
        # look it up in our table of make & break codes
        set makes $scmakes($label)
        set breaks $scbreaks($label)

        # see if it's a normal or extended code; and validate it
        if {[llength $makes] == 2} {
            set extended 1
            if {[lindex $makes 0] != 224} {
                error "Bad extended make code for '$label'"
            }
            set base [lindex $makes 1]
            if {$breaks ne [list 224 240 $base]} {
                error "Bad extended break code for '$label'"
            }
        } elseif {[llength $makes] == 1} {
            set extended 0
            set base [lindex $makes 0]
            if {$breaks ne [list 240 $base]} {
                error "Bad normal break code for '$label'"
            }
        } else {
            error "Bad key make code for $label: not 1 or 2 bytes"
        }

        # apply it
        set address [expr {$base + ($extended ? 256 : 0)}]
        if {$table($address) != 0} {
            error "Duplicate entries at $address including that for '$label'"
        }
        set table($address) $control_word
        if {$verbose} {
            puts stderr \
                [format "\tkey decoding table \[%03d\] := 0x%04x // %s" \
                    $address $control_word $label]
        }
    }
}

# output the resulting table
for {set i 0} {$i < 512} {incr i} {
    puts [format %04x $table($i)]
}

exit 0
