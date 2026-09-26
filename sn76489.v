// sn76489.v — TI SN76489 PSG skeleton (clean-room)
// Public behaviour from TI SN76489 datasheet + well-known host protocol.
// Defaults: FORM=0 (Fibonacci), SEIT=0 (TI seed basin).
// Proven in-repo: 15-bit LFSR maximal period + Fib/Gal intertwiner (see artifacts/).
// Tone/attenuator/mixer paths are a teaching skeleton — not silicon-timed yet.

`timescale 1ns/1ps

module sn76489 #(
    parameter FORM = 1'b0,
    parameter SEIT = 1'b0
) (
    input  wire       nclk,
    input  wire       rst_n,
    input  wire       ce_n,
    input  wire       we_n,
    input  wire [7:0] data_in,
    output wire [7:0] mix_out
);
    reg [9:0] tone_period [0:2];
    reg [3:0] tone_att    [0:2];
    reg [3:0] noise_att;
    reg [2:0] noise_ctrl; // [2]=white, [1:0]=rate
    reg [1:0] tone_latch; // which tone gets data-byte high bits

    integer i;

    // Rising-edge write detect (CE and WE active low)
    reg ce_n_d, we_n_d;
    always @(posedge nclk or negedge rst_n) begin
        if (!rst_n) begin
            ce_n_d <= 1'b1;
            we_n_d <= 1'b1;
        end else begin
            ce_n_d <= ce_n;
            we_n_d <= we_n;
        end
    end
    wire wr = (~ce_n) & (~we_n) & (we_n_d | ce_n_d);

    always @(posedge nclk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                tone_period[i] <= 10'd0;
                tone_att[i]    <= 4'hF;
            end
            noise_att  <= 4'hF;
            noise_ctrl <= 3'b100;
            tone_latch <= 2'd0;
        end else if (wr) begin
            if (data_in[7]) begin
                // Latch byte: 1 RR R DDDD
                case (data_in[6:4])
                    3'b000: begin tone_period[0][3:0] <= data_in[3:0]; tone_latch <= 2'd0; end
                    3'b010: begin tone_period[1][3:0] <= data_in[3:0]; tone_latch <= 2'd1; end
                    3'b100: begin tone_period[2][3:0] <= data_in[3:0]; tone_latch <= 2'd2; end
                    3'b001: tone_att[0] <= data_in[3:0];
                    3'b011: tone_att[1] <= data_in[3:0];
                    3'b101: tone_att[2] <= data_in[3:0];
                    3'b110: noise_ctrl  <= data_in[2:0];
                    3'b111: noise_att   <= data_in[3:0];
                    default: ;
                endcase
            end else begin
                // Data byte: 0 x DDDDDD -> tone period [9:4]
                case (tone_latch)
                    2'd0: tone_period[0][9:4] <= data_in[5:0];
                    2'd1: tone_period[1][9:4] <= data_in[5:0];
                    2'd2: tone_period[2][9:4] <= data_in[5:0];
                    default: ;
                endcase
            end
        end
    end

    // Tone square engines (period counts on NCLK; flip on reload)
    reg [9:0] tone_cnt [0:2];
    reg [2:0] tone_out;
    always @(posedge nclk or negedge rst_n) begin
        if (!rst_n) begin
            tone_out <= 3'b000;
            for (i = 0; i < 3; i = i + 1) tone_cnt[i] <= 10'd0;
        end else begin
            for (i = 0; i < 3; i = i + 1) begin
                if (tone_period[i] == 10'd0) begin
                    tone_out[i] <= 1'b1;
                end else if (tone_cnt[i] <= 10'd1) begin
                    tone_cnt[i] <= tone_period[i];
                    tone_out[i] <= ~tone_out[i];
                end else begin
                    tone_cnt[i] <= tone_cnt[i] - 10'd1;
                end
            end
        end
    end

    // Noise rate: 0:/512 1:/1024 2:/2048 3:tone2 edge
    reg  [10:0] noise_div;
    reg         noise_tick;
    reg         tone2_d;
    wire        tone2_edge = tone_out[2] & ~tone2_d;
    wire [1:0]  rate = noise_ctrl[1:0];
    wire        white = noise_ctrl[2];

    always @(posedge nclk or negedge rst_n) begin
        if (!rst_n) begin
            noise_div  <= 11'd0;
            noise_tick <= 1'b0;
            tone2_d    <= 1'b0;
        end else begin
            tone2_d    <= tone_out[2];
            noise_tick <= 1'b0;
            if (rate == 2'd3) begin
                noise_tick <= tone2_edge;
            end else if (noise_div == 11'd0) begin
                case (rate)
                    2'd0: noise_div <= 11'd511;
                    2'd1: noise_div <= 11'd1023;
                    default: noise_div <= 11'd2047;
                endcase
                noise_tick <= 1'b1;
            end else begin
                noise_div <= noise_div - 11'd1;
            end
        end
    end

    wire [14:0] lfsr_state;
    wire        noise_bit;
    sn76489_lfsr u_lfsr (
        .nclk     (nclk),
        .rst_n    (rst_n),
        .tick_en  (noise_tick),
        .form     (FORM[0]),
        .seit     (SEIT[0]),
        .white    (white),
        .state    (lfsr_state),
        .noise_bit(noise_bit)
    );

    function automatic [7:0] att_to_amp;
        input [3:0] att;
        input       on;
        begin
            if (!on || att == 4'hF) att_to_amp = 8'd0;
            else begin
                // Teaching approximation of -2dB steps, not datasheet µA table
                att_to_amp = 8'd15 - {4'd0, att};
                att_to_amp = {att_to_amp[3:0], 4'd0}; // *16
            end
        end
    endfunction

    wire [7:0] a0 = att_to_amp(tone_att[0], tone_out[0]);
    wire [7:0] a1 = att_to_amp(tone_att[1], tone_out[1]);
    wire [7:0] a2 = att_to_amp(tone_att[2], tone_out[2]);
    wire [7:0] an = att_to_amp(noise_att,  noise_bit);
    assign mix_out = a0 + a1 + a2 + an;

    wire _unused = &{1'b0, lfsr_state};
endmodule
