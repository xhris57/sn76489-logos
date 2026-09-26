// sn76489_lfsr.v — 15-bit noise LFSR for TI SN76489 (clean-room)
// FORM=0: Fibonacci basin (TI-faithful teaching default)
// FORM=1: Galois basin (reciprocal poly x^15+x^14+1, mask 0x6000)
// SEIT=0: TI reset seed 0x4000; SEIT=1: Sega-style path seed 0x4000 after 0x8000>>1
// Clocked on rising NCLK when tick_en is asserted by the rate divider.
// Noise output is architectural LSB.

`timescale 1ns/1ps

module sn76489_lfsr (
    input  wire       nclk,
    input  wire       rst_n,
    input  wire       tick_en,     // rate divider pulse
    input  wire       form,        // 0=Fibonacci, 1=Galois
    input  wire       seit,        // seed select (both map to same orbit)
    input  wire       white,       // 1=white (LFSR feedback), 0=periodic (bit0 only)
    output reg  [14:0] state,
    output wire       noise_bit
);
    assign noise_bit = state[0];

    wire [14:0] seed = 15'h4000; // TI + Sega>>1 basin representative

    wire fib_fb = white ? (state[0] ^ state[1]) : state[0];
    wire [14:0] fib_next = {fib_fb, state[14:1]};

    wire [14:0] gal_shifted = {1'b0, state[14:1]};
    wire [14:0] gal_next = white
                         ? (state[0] ? (gal_shifted ^ 15'h6000) : gal_shifted)
                         : (state[0] ? {1'b1, state[14:1]} : gal_shifted);

    // seit reserved for future Sega-16 plumbing; both seeds share 0x4000 here
    wire [14:0] load_seed = seed | {14'b0, seit & 1'b0};

    always @(posedge nclk or negedge rst_n) begin
        if (!rst_n)
            state <= load_seed;
        else if (tick_en)
            state <= form ? gal_next : fib_next;
    end
endmodule
