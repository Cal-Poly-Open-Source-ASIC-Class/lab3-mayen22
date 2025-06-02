`timescale 1ns/1ps

module tb_dual_port_wb_ram;
`ifdef USE_POWER_PINS
    wire VPWR;
    wire VGND;
    assign VPWR=1;
    assign VGND=0;
`endif
// Clocking and reset
logic clk_i;
logic rst_i;

// Port A Wishbone signals
logic         pA_wb_cyc_i, pA_wb_stb_i;
logic  [3:0]  pA_wb_we_i;
logic  [10:0] pA_wb_addr_i;
logic  [31:0] pA_wb_data_o, pA_wb_data_i;
logic         pA_wb_ack_o, pA_wb_stall_o;

// Port B Wishbone signals
logic         pB_wb_cyc_i, pB_wb_stb_i;
logic  [3:0]  pB_wb_we_i;
logic  [10:0] pB_wb_addr_i;
logic  [31:0] pB_wb_data_o, pB_wb_data_i;
logic         pB_wb_ack_o, pB_wb_stall_o;

localparam CLK_PERIOD = 10;

// Instantiate DUT
dual_port_wb_ram DUT (.*);

// Clock generation
always #(CLK_PERIOD/2) clk_i = ~clk_i;

initial #1000000 $error("Timeout");

// Waveform dump
initial begin
    $dumpfile("tb_dual_port_wb_ram.vcd");
    $dumpvars(2, tb_dual_port_wb_ram);
end

// Tasks
task automatic wb_write(input bit is_port_a, input [31:0] addr, input [31:0] data, input [3:0] we_mask);
    if (is_port_a) begin
        pA_wb_addr_i = addr[10:0];
        pA_wb_data_i = data;
        pA_wb_we_i   = we_mask;
        pA_wb_cyc_i  = 1;
        pA_wb_stb_i  = 1;
        #CLK_PERIOD;
        wait (!pA_wb_stall_o);
        wait (pA_wb_ack_o);
        @(posedge clk_i);
        pA_wb_cyc_i  = 0;
        pA_wb_stb_i  = 0;
        pA_wb_we_i   = 0;
    end else begin
        pB_wb_addr_i = addr[10:0];
        pB_wb_data_i = data;
        pB_wb_we_i   = we_mask;
        pB_wb_cyc_i  = 1;
        pB_wb_stb_i  = 1;
        #CLK_PERIOD;
        wait (!pB_wb_stall_o);
        wait (pB_wb_ack_o);
        @(posedge clk_i);
        pB_wb_cyc_i  = 0;
        pB_wb_stb_i  = 0;
        pB_wb_we_i   = 0;
    end
endtask


task automatic wb_read(input bit is_port_a, input [31:0] addr, output [31:0] data_out);
    if (is_port_a) begin
        pA_wb_addr_i = addr[10:0];
        pA_wb_we_i   = 4'b0000;
        pA_wb_cyc_i  = 1;
        pA_wb_stb_i  = 1;
        #CLK_PERIOD;
        wait (!pA_wb_stall_o);
        wait (pA_wb_ack_o);
        @(posedge clk_i);
        data_out = pA_wb_data_o;
        pA_wb_cyc_i  = 0;
        pA_wb_stb_i  = 0;
    end else begin
        pB_wb_addr_i = addr[10:0];
        pB_wb_we_i   = 4'b0000;
        pB_wb_cyc_i  = 1;
        pB_wb_stb_i  = 1;
        #CLK_PERIOD;
        wait (!pB_wb_stall_o);
        wait (pB_wb_ack_o);
        @(posedge clk_i);
        data_out = pB_wb_data_o;
        pB_wb_cyc_i  = 0;
        pB_wb_stb_i  = 0;
    end
endtask


// Main test
always begin
    logic [31:0] result, read_data_A, read_data_B;
    clk_i = 1;
    rst_i = 1;

    pA_wb_cyc_i = 0; pA_wb_stb_i = 0; pA_wb_we_i = 0; pA_wb_addr_i = 0; pA_wb_data_i = 0;
    pB_wb_cyc_i = 0; pB_wb_stb_i = 0; pB_wb_we_i = 0; pB_wb_addr_i = 0; pB_wb_data_i = 0;

    #CLK_PERIOD;
    rst_i = 0;
    #CLK_PERIOD;


    // Write to different RAMs
    wb_write(1, 32'h0000_0000, 32'hDEADBEEF, 4'b1111);
    wb_write(0, 32'h0000_0400, 32'hCAFEBABE, 4'b1111);

    // Read from different RAMs
    wb_read(1, 32'h0000_0000, result);
    assert (result == 32'hDEADBEEF) else $error("Port A read fail: %h", result);

    wb_read(0, 32'h0000_0400, result);
    assert (result == 32'hCAFEBABE) else $error("Port B read fail: %h", result);

    // Simultaneous writes to same macro, separated reads
    fork
        wb_write(1, 32'h0000_0010, 32'h11111111, 4'b1111);
        wb_write(0, 32'h0000_0020, 32'h22222222, 4'b1111);
    join

    wb_read(1, 32'h0000_0010, result);
    assert (result == 32'h11111111) else $error("Port A conflict read fail: %h", result);

    wb_read(0, 32'h0000_0020, result);
    assert (result == 32'h22222222) else $error("Port B conflict read fail: %h", result);

    // Simultaneous reads from separate macros
    wb_write(1, 32'h0000_0008, 32'hA0A0A0A0, 4'b1111); // DFFRAM0
    wb_write(0, 32'h0000_0408, 32'hB0B0B0B0, 4'b1111); // DFFRAM1

    fork
        wb_read(1, 32'h0000_0008, read_data_A);  // DFFRAM0
        wb_read(0, 32'h0000_0408, read_data_B);  // DFFRAM1
    join

    assert (read_data_A == 32'hA0A0A0A0) else $error("Port A mismatched read: %h", read_data_A);
    assert (read_data_B == 32'hB0B0B0B0) else $error("Port B mismatched read: %h", read_data_B);

    // Simultaneous from the same macro
    wb_write(1, 32'h0000_0010, 32'hCCCCCCCC, 4'b1111);
    wb_write(0, 32'h0000_0020, 32'hDDDDDDDD, 4'b1111);

    fork
        wb_read(1, 32'h0000_0010, read_data_A);  // DFFRAM0
        wb_read(0, 32'h0000_0020, read_data_B);  // DFFRAM0
    join

    assert (read_data_A == 32'hCCCCCCCC) else $error("Conflict A read mismatch: %h", read_data_A);
    assert (read_data_B == 32'hDDDDDDDD) else $error("Conflict B read mismatch: %h", read_data_B);


    
    $display("All tests passed.");
    $finish;
end

endmodule
