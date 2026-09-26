// Self-checking LFSR period + Fibonacci/Galois basin check
`timescale 1ns/1ps

module tb_lfsr_period;
    reg nclk, rst_n, tick_en, form, seit, white;
    wire [14:0] state;
    wire noise_bit;

    sn76489_lfsr dut (
        .nclk(nclk), .rst_n(rst_n), .tick_en(tick_en),
        .form(form), .seit(seit), .white(white),
        .state(state), .noise_bit(noise_bit)
    );

    initial nclk = 0;
    always #5 nclk = ~nclk;

    task automatic run_period(input form_i, output integer period, output reg ok);
        integer i;
        reg [14:0] start;
        begin
            form = form_i;
            seit = 0;
            white = 1;
            tick_en = 0;
            rst_n = 0;
            repeat (2) @(posedge nclk);
            rst_n = 1;
            @(posedge nclk);
            start = state;
            period = 0;
            ok = 0;
            for (i = 0; i < 40000; i = i + 1) begin
                tick_en = 1;
                @(posedge nclk);
                tick_en = 0;
                @(posedge nclk);
                period = period + 1;
                if (state == start) begin
                    ok = (period == 32767);
                    disable run_period;
                end
            end
        end
    endtask

    integer pf, pg;
    reg okf, okg;
    initial begin
        $display("tb_lfsr_period: start");
        run_period(0, pf, okf);
        $display("Fibonacci period=%0d %s", pf, okf ? "PASS" : "FAIL");
        run_period(1, pg, okg);
        $display("Galois period=%0d %s", pg, okg ? "PASS" : "FAIL");
        if (okf && okg) $display("RESULT: PASS");
        else $display("RESULT: FAIL");
        $finish;
    end
endmodule
