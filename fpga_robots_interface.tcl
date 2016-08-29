#!/usr/bin/wish
# fpga_robots_interface.tcl
# Jeremy Dilatush - started May 2016
#
# This provides an interface to the FPGA robots game.  It communicates with
# the FPGA over a serial port, and can send key codes, instead of
# using a PS/2 keyboard connected to the FPGA.

# It needs to be run in a graphical environment, not just on a TTY.
# (SSH's "port forwarding" is a dear friend.)  I tried writing one that
# would work on a TTY, but it required messing with TTY state more than
# I feel like.

# The GUI window accepts keystrokes, and also has a picture of a keyboard
# (with just the relevant keys) where you can perform commands using
# mouse-clicks.

# To run:  wish fpga_robots_interface.tcl
# optionally followed by additional words:
#       /dev/tty... - name of TTY device to use

# basic configuration settings

set dev /dev/ttyUSB1
set baud 115200
set handshake xonxoff
set delay 100 ; # milliseconds between key movements

foreach arg $argv {
    if {[string index $arg 0] eq "/"} {
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
    -buffering none -encoding binary -translation binary -blocking 1 \
    -handshake $handshake

# database of the keys we're interested in
foreach {keysym sticky kcext kcbyte altkeysym} {
    Shift_L    1 0 0x12 ""
    Control_L  1 0 0x14 ""
    Alt_L      1 0 0x11 ""
    Meta_L     1 1 0x1f ""
    Super_L    1 1 0x1f ""
    Shift_R    1 0 0x59 ""
    Control_R  1 1 0x14 ""
    Alt_R      1 1 0x11 ""
    Meta_R     1 1 0x27 ""
    Super_R    1 1 0x27 ""
    t          0 0 0x2c ""
    q          0 0 0x15 ""
    w          0 0 0x1d ""
    F1         0 0 0x05 ""
    F2         0 0 0x06 ""
    F3         0 0 0x04 ""
    y          0 0 0x35 ""
    k          0 0 0x42 ""
    u          0 0 0x3c ""
    h          0 0 0x33 ""
    period     0 0 0x49 greater
    l          0 0 0x4b ""
    b          0 0 0x32 ""
    j          0 0 0x3b ""
    n          0 0 0x31 ""
    Scroll     0 0 0x7e ""
    Up         0 1 0x75 ""
    Down       0 1 0x72 ""
    Left       0 1 0x6B ""
    Right      0 1 0x74 ""
} {
    set kslist [list]
    lappend kslist $keysym
    lappend kslist [string toupper $keysym]
    lappend kslist [string tolower $keysym]
    if {$altkeysym ne ""} {
        lappend kslist $altkeysym
    }
    foreach ks $kslist {
        set bykeysym($ks) [list $sticky $kcext $kcbyte]
    }
}

# and corresponding characters
foreach letter {t q w y k u h l b j n} {
    set bychar($letter) [list 0 $letter]
    set bychar([string toupper $letter]) [list 1 $letter]
}
foreach {char shifted keysym} {
    "." 0 "period"
    ">" 1 "greater"
} {
    set bychar($char) [list $shifted $keysym]
}

# core logic

# keymit: A key press (or release) occurs
proc keymit {down keysym} {
    global bykeysym fp

    # up or down
    set duc [expr {$down ? "+" : "-"}]

    # do we know about this key?
    if {[info exists bykeysym($keysym)]} {
        # yes; extract information & show the user
        lassign $bykeysym($keysym) sticky kcext kcbyte
        puts stderr [format {%s %10s -- 0x%02x%s%s} \
            $duc $keysym $kcbyte \
            [expr {$kcext ? " extended" : ""}] \
            [expr {$sticky ? " sticky" : ""}]]
    } else {
        # no; show the user & just ignore it
        puts stderr [format {%s %10s -- ?} $duc $keysym]
        return
    }

    # send the key to the device, through the serial port
    set s ""
    if {$kcext} {
        # modifier byte 0xe0: extends the keycode
        # represent it as 0x4e 0x50
        append s NP
    }
    if {!$down} {
        # modifier byte 0xf0: makes it a break code
        # represent it as 0x4f 0x50
        append s OP
    }
    if {1} {
        # the given key code $kcbyte
        # represent 0xuv as 0x4u 0x5v
        append s [format %c%c \
            [expr {0x40 + (($kcbyte >> 4) & 0x0f)}] \
            [expr {0x50 + (($kcbyte     ) & 0x0f)}]]
    }
    puts -nonewline $fp $s
    flush $fp
}

# gui_button: handle a GUI button which corresponds to key symbol $sym.
proc gui_button {sym} {
    global stuck bykeysym delay
    lassign $bykeysym($sym) sty ext byt
    if {$sty} {
        # sticky: down or up, alternating each time
        set stuck($sym) [expr {!$stuck($sym)}]
        keymit $stuck($sym) $sym
        gui_button_flash $sym
    } else {
        # not sticky: press it down for 1/10 second
        keymit 1 $sym
        gui_button_flash $sym
        after $delay keymit 0 $sym
        after $delay gui_button_flash $sym
    }
}

# gui_reset_button: handle the "RST" GUI button to reset the game logic
# by simulating SHIFT-SCROLL-SCROLL
proc gui_reset_button {sym} {
    global delay
    set keymits [list]
    lappend keymits 1 Shift_L
    lappend keymits 1 Scroll
    lappend keymits 0 Scroll
    lappend keymits 1 Scroll
    lappend keymits 0 Scroll
    lappend keymits 0 Shift_L
    set accdelay $delay
    foreach {kmd kmk} $keymits {
        after $accdelay keymit $kmd $kmk
        set accdelay [expr {$accdelay + $delay}]
    }
    gui_button_flash $sym
    after $accdelay gui_button_flash $sym
}

# gui_button_flash: put the gui button in/out of inverse video to indicate
# it's active
proc gui_button_flash {sym} {
    set c1 [.c itemcget bdy$sym -fill]
    set c2 [.c itemcget bdy$sym -outline]
    .c itemconfigure bdy$sym -fill $c2
    .c itemconfigure bdy$sym -outline $c1
    .c itemconfigure cap$sym -fill $c1
}

# handle_stdin: a character might be readable on standard input
# YYY: This code cannoy handle multi-character keys such as you get with,
# say, arrow keys.  But that's okay.
proc handle_stdin {} {
    global bychar delay

    if {[eof stdin]} {
        # no more input recognized, we got EOF
        chan event readable ""
        return
    }
    set ch [read stdin 1]
    if {[info exists bychar($ch)]} {
        lassign $bychar($ch) shifted keysym
        if {$shifted} {
            # emit: shift; key down; key up; unshift
            keymit 1 Shift_L
            after $delay keymit 1 $keysym
            after [expr {$delay * 2}] keymit 0 $keysym
            after [expr {$delay * 3}] keymit 0 Shift_L
        } else {
            # emit: key down; key up
            keymit 1 $keysym
            after $delay keymit 0 $keysym
        }
    }
}

# start up graphical interface if desired
if {1} {
    package require Tk
    canvas .c -width 320 -height 240 -background "\#000"
    foreach {culx culy clrx clry txt sym} {
        0 0 0 0 "shft" "Shift_L"
        2 0 2 0 "tele" "t"
        3 0 3 0 "quit" "q"
        0 1 0 1 y y
        1 1 1 1 k k
        2 1 2 1 u u
        0 2 0 2 h h
        1 2 1 2 . period
        2 2 2 2 l l
        0 3 0 3 b b
        1 3 1 3 j j
        2 3 2 3 n n
        0 4 1 4 "wait" "w"
        4 5 4 5 "F1" "F1"
        5 5 5 5 "F2" "F2"
        6 5 6 5 "F3" "F3"
        6 1 6 1 "RST" "RST"
    } {
        # draw the "key"
        .c create rectangle \
            [expr {$culx * 40 + 2}]  [expr {$culy * 40 + 2}] \
            [expr {$clrx * 40 + 38}] [expr {$clry * 40 + 38}] \
            -outline "\#0cc" -fill "\#333" \
            -tags [list key$sym bdy$sym]
        .c create text \
            [expr {$culx * 20 + $clrx * 20 + 20}] \
            [expr {$culy * 20 + $clry * 20 + 20}] \
            -fill "\#0cc" -font "Serif 9" \
            -anchor center -text $txt \
            -tags [list key$sym cap$sym]
        # initialize its state 
        set stuck($sym) 0
        .c bind key$sym <Button-1> [list gui_button $sym]
    }

    # bind what happens to actual keystrokes
    bind . <KeyPress> "keymit 1 %K"
    bind . <KeyRelease> "keymit 0 %K"

    # the "RST" button is special
    .c itemconfigure bdyRST -fill "\#c00" -outline "\#ccc"
    .c itemconfigure capRST -fill "\#ccc"
    .c bind keyRST <Button-1> [list gui_reset_button RST]

    pack .c
}

# accept characters from the terminal and treat them as keys too
fconfigure stdin \
    -buffering none -blocking 0 -encoding binary -translation platform
chan event stdin readable handle_stdin
puts stderr \
    "Start typing - characters received will be passed on if recognized."

# now that everything is set up, go into the event loop where we wait for
# things to happen (keys and buttons moving).

# Tk will go into an event loop on its own when it gets to the end
# of code
