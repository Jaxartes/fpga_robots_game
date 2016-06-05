// misc.v
// Jeremy Dilatush - started April 2016

`include "fpga_robots_game_config.v"

// pseudorandom_20_3() - Given 20 bits of input, generate 3 bits of output
// pseudorandomly derived from it.  Used to generate some jittery
// animation in this game.  For best results, give it several clock
// cycles (and a consistent number of them) between 'stb' pulses.
module pseudorandom_20_3(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    input [19:0]inp, // input value
    output reg [2:0]out = 3'd0, // output value
    input stb // Strobe: Causes the value of 'inp' to be read this cycle, and
              // 'out' to be changed *next* cycle, based on the *last* input.
);
    // Pair of 16-entry 12-bit "S-box" look up tables, at the heart of this
    // pseudorandom function.  Based on the hexadecimal expansion of 1/e.
    // One out of every four hex digits was omitted due to an error on my
    // part.  Oh well.

    wire [3:0]sb1in;
    reg [11:0]sb1out;
    always @*
        case(sb1in)
            4'b0000: sb1out = 12'hE2D;
            4'b0001: sb1out = 12'h8D8;
            4'b0010: sb1out = 12'h3BC;
            4'b0011: sb1out = 12'hF1A;
            4'b0100: sb1out = 12'hADE;
            4'b0101: sb1out = 12'h782;
            4'b0110: sb1out = 12'h054;
            4'b0111: sb1out = 12'h90D;
            4'b1000: sb1out = 12'hA98;
            4'b1001: sb1out = 12'h5AA;
            4'b1010: sb1out = 12'h56C;
            4'b1011: sb1out = 12'h733;
            4'b1100: sb1out = 12'h024;
            4'b1101: sb1out = 12'h9D0;
            4'b1110: sb1out = 12'h507;
            4'b1111: sb1out = 12'hAED;
        endcase
    wire [3:0]sb2in;
    reg [11:0]sb2out;
    always @*
        case(sb2in)
            4'b0000: sb2out = 12'h164;
            4'b0001: sb2out = 12'h0BF;
            4'b0010: sb2out = 12'h72B;
            4'b0011: sb2out = 12'h215;
            4'b0100: sb2out = 12'h824;
            4'b0101: sb2out = 12'hB66;
            4'b0110: sb2out = 12'hD90;
            4'b0111: sb2out = 12'h27A;
            4'b1000: sb2out = 12'hAEA;
            4'b1001: sb2out = 12'h550;
            4'b1010: sb2out = 12'h68D;
            4'b1011: sb2out = 12'h392;
            4'b1100: sb2out = 12'h9F0;
            4'b1101: sb2out = 12'hC62;
            4'b1110: sb2out = 12'h6DC;
            4'b1111: sb2out = 12'hA58;
        endcase

    // Turn those into a single clock cycle 20-to-20 bit function.
    wire [19:0]rfin;
    assign sb1in = rfin[19:16];
    assign sb2in = rfin[15:12];
    wire [19:0]rfout = { rfin[11:0] ^ sb1out ^ sb2out, rfin[19:12] };

    // And run that 20-to-20 bit function repeatedly to produce
    // the result.
    reg [19:0] state = 20'd0;
    assign rfin = stb ? inp : state;
    always @(posedge clk)
        if (rst) begin
            state <= 20'd0;
            out <= 3'd0;
        end else begin
            state <= rfout;
            if (stb) out <= state[19:17];
        end
endmodule

`ifdef ANALYZE_PRNG_1
// This code is to be run in Icarus Verilog to analyze the output of
// pseudorandom_20_3().
module top( );
    // Simulated clock.
    reg clk = 1'd0;
    initial forever begin #10; clk = ~clk; end
    reg rst = 1'd1;
    initial begin
        #100;
        @(posedge clk);
        rst <= 1'd0;
    end

    // Run four times with each of a million inputs, in four different orders
    reg prstb = 1'd0;
    reg [24:0]cycle = 25'd0;
    reg [19:0]prin = 20'd0;
    reg [19:0]prin_old = 20'dx;
    reg [19:0]prin_older = 20'dx;
    wire [2:0] prout;
    always @(posedge clk)
        if (rst) begin
            prstb <= 1'd0;
            cycle <= 25'd0;
            prin <= 1'd0;
            prin_old <= 20'dx;
            prin_older <= 20'dx;
        end else begin
            prstb <= 1'd0;
            case (cycle[2:0])
                3'd0: begin
                    prstb <= 1'd1;
                end
                3'd1: begin
                    prin_older <= prin_old;
                    prin_old <= prin;
                    // $display("in 0x%05x", prin);
                end
                3'd2: $display("0x%05x => %d", prin_older, prout);
            endcase
            case (cycle[24:23])
                2'd0: prin <= cycle[22:3] ^ // operating cycle
                              { 6 { cycle[2:0] } }; // mess with input when
                                                    // it should be ignored
                2'd1: prin <= (20'd1048575 - cycle[22:3]) ^
                              { 6 { cycle[2:0] } };
                2'd2: prin <= (cycle[22:3] + 20'd123456) ^
                              { 6 { cycle[2:0] } };
                2'd3: prin <= { cycle[12:3] + 10'd123,
                                10'd456 - cycle[22:13] } ^
                              { 6 { cycle[2:0] } };
            endcase
            cycle <= cycle + 25'd1;
        end

    pseudorandom_20_3 prng(
        .clk(clk), .rst(rst), .inp(prin), .out(prout), .stb(prstb)
    );
endmodule
`endif // ANALYZE_PRNG_1

// lfsr_20_3 -- LFSR delivering three bits at once.  This module doesn't
// contain any of the state, it just contains the transfer function.
// Take the result off out[2:0]
module lfsr_20_3(
    input [19:0]in,
    output [19:0]out
);
    // if 1 bit:
    // out = (in << 1) | ((in >> 16) ^ (in >> 19) & 1)

    // if 3 bit:
    // snd = (in << 1) | ((in >> 16) ^ (in >> 19) & 1)
    // trd = (snd << 1) | ((snd >> 16) ^ (snd >> 19) & 1)
    // out = (trd << 1) | ((trd >> 16) ^ (trd >> 19) & 1)

    assign out[19:3] = in[16:0];
    assign out[2] = in[16] ^ in[19];
    assign out[1] = in[15] ^ in[18];
    assign out[0] = in[14] ^ in[17];
endmodule

`ifdef ANALYZE_PRNG_2
// This code is to be run in Icarus Verilog to analyze the output of
// lfsr_20_3()
module top( );
    reg [19:0] state;
    reg [20:0] count;
    wire [19:0] successor;
    lfsr_20_3 prng(.in(state), .out(successor));

    initial begin
        state = 1'd1;
        for (count = 0; count < 'h1fffff; count = count + 1) begin
            $display("%05x %03b", state, state[2:0]);
            #1;
            state = successor;
        end
        $finish;
    end

endmodule
`endif

// sinewaver() - Generate a 16 bit sinusoidal wave.  The period is
// 1609 pulses of 'trigger'
module sinewaver(
    input clk, // system clock and reset
    input rst,
    input trigger, // trigger pulses to advance the state
    output [15:0]out, // the wave form value
    output cross // is at reset point; can use 'cross && trigger' to detect
                 // full cycles
);
    parameter INIT_X = 16'h7800; // almost full deflection, just a little
                                 // bit reduced to make room for error
    parameter INIT_Y = 16'h0000;

    // The driving formula of this is:
    //  (x,y) <= (x-y*c,y+x*c)
    // where in this case c is 1/256.
    // Roundoff errors make this not quite a perfect sine curve, but
    // good enough, as long as we reset it every cycle.
    reg [15:0]x = INIT_X;
    reg [15:0]y = INIT_Y;

    // Use 'y' as the output; but bias it to an unsigned value
    assign out = { ~(y[15]), y[14:0] };

    // signed division by 256
    wire [15:0]xc = { { 8 { x[15] } }, x[15:8] };
    wire [15:0]yc = { { 8 { y[15] } }, y[15:8] };

    // successor function
    wire [15:0]x2 = x - yc;
    wire [15:0]y2 = y + xc;

    // detect origin crossing
    assign cross = y[15] && !y2[15];

    // updates
    always @(posedge clk)
        if (rst)
            { x, y } <= { INIT_X, INIT_Y };
        else if (trigger) begin
            if (cross)
                { x, y } <= { INIT_X, INIT_Y };
            else
                { x, y } <= { x2, y2 };
        end
endmodule

`ifdef TEST_SINEWAVER
// This code is to be run in Icarus Verilog to test sinewaver().
module top( );
    reg [15:0] count;
    wire [15:0] out;
    reg clk, rst, trigger;
    sinewaver sw(.clk(clk), .rst(rst), .trigger(trigger), .out(out));

    initial begin
        clk = 1'd0;
        rst = 1'd1;
        trigger = 1'd0;

        #10; clk = 1'd1; #10; clk = 1'd0;
        #10; clk = 1'd1; #10; clk = 1'd0;
        #10; clk = 1'd1; #10; clk = 1'd0;
        #10; rst = 1'd0; clk = 1'd1; #10; clk = 1'd0;

        for (count = 0; count < 16090; count = count + 1) begin
            #10;
            trigger = 1'd1;
            clk = 1'd1;
            #10;
            clk = 1'd0;
            trigger = 1'd0;
            #10;
            if (out[15]) begin
                // mess with time
                clk = 1'd1;
                #10;
                clk = 1'd0;
                #10;
            end
            if (out[14]) begin
                // mess with time
                clk = 1'd1;
                #10;
                clk = 1'd0;
                #10;
            end
            $display("%d", out);
            $display("# x=%d y=%d x2=%d y2=%d cross=%b",
                     sw.x, sw.y, sw.x2, sw.y2,
                     sw.cross);
        end
        $finish;
    end
endmodule
`endif

// digit() - Keep track of numeric values 0-9 and allow them to be incremented
module digit(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output reg [3:0]digit = 4'd0, // the digit value
    input inc, // pulses each time it should increment
    output reg nine // indicates it's at nine, and another 'inc' pulse
                    // will cause it to wrap around
);
    always @(posedge clk)
        if (rst) begin
            digit <= 4'd0;
            nine <= 1'd0;
        end else begin
            if (inc) begin
                nine <= 1'd0;
                case(digit)
                4'd0: digit <= 4'd1;
                4'd1: digit <= 4'd2;
                4'd2: digit <= 4'd3;
                4'd3: digit <= 4'd4;
                4'd4: digit <= 4'd5;
                4'd5: digit <= 4'd6;
                4'd6: digit <= 4'd7;
                4'd7: digit <= 4'd8;
                4'd8: begin digit <= 4'd9; nine <= 1'd1; end
                default: digit <= 4'd0;
                endcase
            end
        end
endmodule

// digit2() - a 1- or 2-digit number
module digit2(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output [7:0]data, // digit values
    output reg [1:0]mask = 2'd2, // which digits aren't even shown
    input inc // trigger adding one to it
);
    wire wouldcarry;
    digit rgt(
        .clk(clk), .rst(rst),
        .digit(data[3:0]), .inc(inc), .nine(wouldcarry)
    );
    digit lft(
        .clk(clk), .rst(rst),
        .digit(data[7:4]), .inc(wouldcarry && inc)
    );
    always @(posedge clk)
        if (rst)
            mask <= 2'd2; // right digit shows, not left
        else if (wouldcarry && inc)
            mask <= 2'd0; // now they both show: we've reached 10
endmodule

// digit6() - an up to 6-digit number
module digit6(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output [23:0]data, // digit values
    output reg [5:0]mask = 6'd62, // which digits aren't even shown
    input inc // trigger adding one to it
);
    wire [4:0]nines;
    wire [5:1]carries;

    // do the digits, in parallel
    digit d1(
        .clk(clk), .rst(rst), .digit(data[3:0]),
        .inc(inc), .nine(nines[0])
    );
    digit d10(
        .clk(clk), .rst(rst), .digit(data[7:4]),
        .inc(carries[1]), .nine(nines[1])
    );
    digit d100(
        .clk(clk), .rst(rst), .digit(data[11:8]),
        .inc(carries[2]), .nine(nines[2])
    );
    digit d1k(
        .clk(clk), .rst(rst), .digit(data[15:12]),
        .inc(carries[3]), .nine(nines[3])
    );
    digit d10k(
        .clk(clk), .rst(rst), .digit(data[19:16]),
        .inc(carries[4]), .nine(nines[4])
    );
    digit d100k(
        .clk(clk), .rst(rst), .digit(data[23:20]),
        .inc(carries[5])
    );

    // compute the carry from one to another
    assign carries[1] = nines[0] && inc;
    assign carries[2] = nines[0] && nines[1] && inc;
    assign carries[3] = nines[0] && nines[1] && nines[2] && inc;
    wire ln = nines[0] && nines[1] && nines[2] && nines[3];
    assign carries[4] = ln && inc;
    assign carries[5] = ln && nines[4] && inc;

    // deal with digits that aren't there, until they are there
    genvar g;
    generate
        for (g = 1; g < 6; g = g + 1) begin : dodigmask
            always @(posedge clk)
                if (rst)
                    mask[g] <= 1'd1; // digit starts out hidden
                else if (carries[g])
                    mask[g] <= 1'd0; // but appears when it's nonzero
        end
    endgenerate
endmodule

`ifdef TEST_DIGITS
// This code is to be run in Icarus Verilog to test digit*()
module top( );
    // clock
    reg clk = 1'd0;
    initial forever begin #10; clk = ~clk; end

    // reset
    reg rst = 1'd1;
    initial begin
        #100;
        rst <= 1'd0;
        #1500;
        rst <= 1'd1;
        #100;
        rst <= 1'd0;
    end

    // the digits
    reg trigger = 1'd0;
    wire [3:0]d1digits;
    wire [1:0]d2mask;
    wire [7:0]d2digits;
    wire [5:0]d6mask;
    wire [23:0]d6digits;
    digit d1(
        .clk(clk), .rst(rst), .digit(d1digits),
        .inc(trigger)
    );
    digit2 d2(
        .clk(clk), .rst(rst), .data(d2digits), .mask(d2mask),
        .inc(trigger)
    );
    digit6 d6(
        .clk(clk), .rst(rst), .data(d6digits), .mask(d6mask),
        .inc(trigger)
    );

    // operation, while showing the results, and triggering at varying
    // intervals
    integer i, j;
    initial forever begin
        for (i = 0; i < 4; i = i + 1) begin
            // increment
            @(posedge clk);
            trigger <= 1'd1;
            @(negedge clk);
            @(posedge clk);
            trigger <= 1'd0;
            @(negedge clk);
            // delay
            for (j = 0; j < i; j = j + 1) begin
                @(posedge clk);
                @(negedge clk);
            end
            // display
            $write("%c ", d1digits + 48);
            for (j = 1; j >= 0; j = j - 1) begin
                if (d2mask[j])
                    $write(" ");
                else
                    $write("%c", 48 + ((d2digits >> (4 * j)) & 15));
            end
            $write(" ");
            for (j = 5; j >= 0; j = j - 1) begin
                if (d6mask[j])
                    $write(" ");
                else
                    $write("%c", 48 + ((d6digits >> (4 * j)) & 15));
            end
            $display("; @%t", $time);
        end
    end

endmodule
`endif // TEST_DIGITS
