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

// lfsr_29_8 -- LFSR delivering eight bits at once.  This module doesn't
// contain any of the state, it just contains the transfer function.
// Take the result off out[7:0]
module lfsr_29_8(
    input [28:0]in,
    output [28:0]out
);
    assign out[28:8] = in[20:0];
    assign out[7] = in[26] ^ in[28];
    assign out[6] = in[25] ^ in[27];
    assign out[5] = in[24] ^ in[26];
    assign out[4] = in[23] ^ in[25];
    assign out[3] = in[22] ^ in[24];
    assign out[2] = in[21] ^ in[23];
    assign out[1] = in[20] ^ in[22];
    assign out[0] = in[19] ^ in[21];
endmodule

`ifdef ANALYZE_PRNG_3
// This code is to be run in Icarus Verilog to analyze the output of
// lfsr_29_8()
module top( );
    reg [28:0] state;
    wire [28:0] successor;
    lfsr_29_8 prng(.in(state), .out(successor));

    initial begin
        state = 1'd1;
        forever begin
            $display("%08x %02x %08b", state, state[7:0], state[7:0]);
            #1;
            state = successor;
        end
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

// decadd() - Add a value (0-7) to a binary coded decimal digit (0-9) and
// compute a new decimal digit and a carry value.
module decadd(
    input [3:0]idig, // input digit 0-9
    input [2:0]iadd, // value to add, 0-7
    output [3:0]odig, // output digit 0-9
    output ocry // output carry
);
    // binary addition; result bsum, 0-16
    wire [4:0]bsum = { 1'd0, idig } + { 2'd0, iadd };

    // digit value if that would wrap around
    wire [4:0]less10 = bsum - 5'd10;

    // pick one
    assign ocry = !(less10[4]);
    assign odig = less10[4] ? bsum[3:0] : less10[3:0];
endmodule

// digit2() - A 1- or 2-digit number which can be reset to zero or
// incremented by up to 7.
module digit2(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output [7:0]data, // digit values
    output reg [1:0]mask = 2'd2, // which digits aren't even shown
    input [2:0]inc // trigger adding one to it
);
    reg [3:0]dlft = 4'd0; // digit values
    reg [3:0]drgt = 4'd0;
    wire [3:0]dlft2;
    wire [3:0]drgt2;
    wire carry;

    always @(posedge clk) dlft <= rst ? 4'd0 : dlft2;
    always @(posedge clk) drgt <= rst ? 4'd0 : drgt2;
    always @(posedge clk)
        if (rst)
            mask <= 2'd2; // left digit invisible: 0
        else if (carry)
            mask <= 2'd0; // two digits

    decadd argt(.idig(drgt), .iadd(inc),
                .odig(drgt2), .ocry(carry));
    decadd alft(.idig(dlft), .iadd({ 2'd0, carry }),
                .odig(dlft2)); // alft.ocry intentionally ignored

    assign data = { dlft, drgt };
endmodule

// digit6() - an up to 6-digit number which can be reset to zero or
// incremented by up to 7.
module digit6(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output reg [23:0]data = 24'd0, // digit values
    output reg [5:0]mask = 6'd62, // which digits aren't even shown
    input [2:0]inc // add to it
);
    wire [23:0]data2; // digits after addition
    wire [4:0]carry; // carry out of each digit except last

    // this carry chain here is ugly and slow
    decadd a0(.idig(data[3:0]), .iadd(inc),
              .odig(data2[3:0]), .ocry(carry[0]));
    decadd a1(.idig(data[7:4]), .iadd({ 2'd0, carry[0] }),
              .odig(data2[7:4]), .ocry(carry[1]));
    decadd a2(.idig(data[11:8]), .iadd({ 2'd0, carry[1] }),
              .odig(data2[11:8]), .ocry(carry[2]));
    decadd a3(.idig(data[15:12]), .iadd({ 2'd0, carry[2] }),
              .odig(data2[15:12]), .ocry(carry[3]));
    decadd a4(.idig(data[19:16]), .iadd({ 2'd0, carry[3] }),
              .odig(data2[19:16]), .ocry(carry[4]));
    decadd a5(.idig(data[23:20]), .iadd({ 2'd0, carry[4] }),
              .odig(data2[23:20])); // a5.ocry intentionally ignored

    always @(posedge clk) data <= rst ? 24'd0 : data2;
    always @(posedge clk)
        if (rst)
            mask <= 6'd62; // only the rightmost digit is visible at first
        else begin
            if (carry[0]) mask[1] <= 1'd0;
            if (carry[1]) mask[2] <= 1'd0;
            if (carry[2]) mask[3] <= 1'd0;
            if (carry[3]) mask[4] <= 1'd0;
            if (carry[4]) mask[5] <= 1'd0;
        end
endmodule

// digit6max() - for keeping high scores, this keeps six digit values which
// can be reset to zero, or set to the given input if the given input is
// greater than the current value
module digit6max(
    input clk, // system clock (rising edge active)
    input rst, // system reset signal (active high synchronous)
    output reg [23:0]odata = 24'd0, // digit values
    output reg [5:0]omask = 6'd62, // which digits aren't even shown
    input [23:0]idata, // input digits
    input [5:0]imask // input digit mask
);
    always @(posedge clk)
        if (rst) begin
            odata <= 24'd0; // zero
            omask <= 6'd62; // only one digit is visible: zero
        end else if (idata > odata) begin
            // Note, that above comparison is a *binary* comparison even
            // though what we really want to compare are *decimal* values.
            // But the results are the same here.
            odata <= idata;
            omask <= imask;
        end
endmodule

`ifdef TEST_DIGITS
// This code is to be run in Icarus Verilog to test digit*().  It works
// by generating pseudorandom values to add to the counters, and displays
// the addition and the results.  It doesn't test reset, which should
// be simple.
module top( );
    // clock
    reg clk = 1'd0;
    initial forever begin #10; clk = ~clk; end

    // reset
    reg rst = 1'd1;
    initial begin
        #101;
        rst <= 1'd0;
    end

    // what to add
    reg [19:0]addend = 20'd1;
    wire [19:0]addend2;
    lfsr_20_3 prng_addend(.in(addend), .out(addend2));
    always @(posedge clk) addend <= rst ? 20'd1 : addend2;
    wire [2:0]add = addend[2:0];

    // the digits
    wire [1:0]d2mask;
    wire [7:0]d2digits;
    wire [5:0]d6mask;
    wire [23:0]d6digits;
    digit2 d2(
        .clk(clk), .rst(rst), .data(d2digits), .mask(d2mask), .inc(add)
    );
    digit6 d6(
        .clk(clk), .rst(rst), .data(d6digits), .mask(d6mask), .inc(add)
    );

    // a simply binary accumulator
    reg [63:0]accum = 64'd0;
    always @(posedge clk)
        if (rst)
            accum <= 64'd0;
        else
            accum <= accum + add;

    // show results
    always @(negedge clk)
        $display("%c%c / %c%c%c%c%c%c / %d ; add %d",
                 d2mask[1] ? 8'd32 : { 4'd3, d2digits[7:4] },
                 d2mask[0] ? 8'd32 : { 4'd3, d2digits[3:0] },
                 d6mask[5] ? 8'd32 : { 4'd3, d6digits[23:20] },
                 d6mask[4] ? 8'd32 : { 4'd3, d6digits[19:16] },
                 d6mask[3] ? 8'd32 : { 4'd3, d6digits[15:12] },
                 d6mask[2] ? 8'd32 : { 4'd3, d6digits[11:8] },
                 d6mask[1] ? 8'd32 : { 4'd3, d6digits[7:4] },
                 d6mask[0] ? 8'd32 : { 4'd3, d6digits[3:0] },
                 accum, add);
endmodule
`endif // TEST_DIGITS
