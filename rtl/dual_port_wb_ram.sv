`timescale 1ns/1ps
module dual_port_wb_ram (
    input           clk_i,
    input           rst_i,
    `ifdef USE_POWER_PINS
    input VPWR,
    input VGND,
    `endif

    // Port A Wishbone
    input           pA_wb_cyc_i,
    input           pA_wb_stb_i,
    input   [3:0]   pA_wb_we_i,
    input   [10:0]  pA_wb_addr_i,
    input   [31:0]  pA_wb_data_i,
    output  [31:0]  pA_wb_data_o,
    output logic    pA_wb_ack_o,
    output logic    pA_wb_stall_o,

    // Port B Wishbone
    input           pB_wb_cyc_i,
    input           pB_wb_stb_i,
    input   [3:0]   pB_wb_we_i,
    input   [10:0]  pB_wb_addr_i,
    input   [31:0]  pB_wb_data_i,
    output  [31:0]  pB_wb_data_o,
    output logic    pB_wb_ack_o,
    output logic    pB_wb_stall_o
);
    
    logic conflict, turn, allow_A, allow_B;
    reg pA_ack, pB_ack;
    // Check for conflicts where both ports access same RAM
    assign conflict = (pA_wb_cyc_i && pA_wb_stb_i && pB_wb_cyc_i && pB_wb_stb_i && (pA_wb_addr_i[10] == pB_wb_addr_i[10]));
    
    // Fair turn-based access (toggles on conflict)
    // 0 = Port A's turn, 1 = Port B's turn
    assign allow_A = (pA_wb_cyc_i & pA_wb_stb_i) & (conflict ~& turn);
    assign allow_B = (pB_wb_cyc_i & pB_wb_stb_i) & (conflict ~& (~turn));

    assign pA_wb_ack_o = pA_ack;
    assign pB_wb_ack_o = pB_ack;

    // Stall outputs
    assign pA_wb_stall_o = (conflict & turn);
    assign pB_wb_stall_o = (conflict & (~turn));

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pA_ack <= 0;
            pB_ack <= 0;
            turn <= 0;
        end else begin
            pA_ack <= pA_wb_cyc_i & pA_wb_stb_i & allow_A; // If the current cycle's access is allowed, ack next
            pB_ack <= pB_wb_cyc_i & pB_wb_stb_i & allow_B;
            if (conflict) begin
                turn <= ~turn;
            end
        end
    end

    // DFFRAM specific stuff, use 0 and 1 instead of A and B to differentiate
    // For DFFRAM0 (sel == 0)
    wire [7:0] addr_0 = (pA_wb_addr_i[10] == 0 && allow_A) ? pA_wb_addr_i[9:2] : pB_wb_addr_i[9:2];

    wire [31:0] din_0 = (pA_wb_addr_i[10] == 0 && allow_A) ? pA_wb_data_i : pB_wb_data_i;

    wire [3:0] we_0  = (pA_wb_addr_i[10] == 0 && allow_A) ? pA_wb_we_i : pB_wb_we_i;

    // For DFFRAM1 (sel == 1)
    wire [7:0] addr_1 = (pA_wb_addr_i[10] == 1 && allow_A) ? pA_wb_addr_i[9:2] : pB_wb_addr_i[9:2];

    wire [31:0] din_1 = (pA_wb_addr_i[10] == 1 && allow_A) ? pA_wb_data_i : pB_wb_data_i;

    wire [3:0] we_1  = (pA_wb_addr_i[10] == 1 && allow_A) ? pA_wb_we_i : pB_wb_we_i;

    // Enables
    wire en_0 = ((~pA_wb_addr_i[10]) && pA_wb_cyc_i && pA_wb_stb_i && allow_A) ||
                ((~pB_wb_addr_i[10]) && pB_wb_cyc_i && pB_wb_stb_i && allow_B);

    wire en_1 = ((pA_wb_addr_i[10]) && pA_wb_cyc_i && pA_wb_stb_i && allow_A) ||
                ((pB_wb_addr_i[10]) && pB_wb_cyc_i && pB_wb_stb_i && allow_B);


    // Data outputs
    wire [31:0] dout_0, dout_1;
    assign pA_wb_data_o = (pA_wb_addr_i[10]) ? dout_1 : dout_0;
    assign pB_wb_data_o = (pB_wb_addr_i[10]) ? dout_1 : dout_0;

    // Instantiate two DFFRAMs
    DFFRAM256x32 DFFRAM0 (
        // `ifdef USE_POWER_PINS
        // .VPWR(VPWR),
        // .VGND(VGND),
        // `endif
        .CLK(clk_i),
        .WE0(we_0),
        .EN0(en_0),
        .A0(addr_0),
        .Di0(din_0),
        .Do0(dout_0)
    );

    DFFRAM256x32 DFFRAM1 (
        // `ifdef USE_POWER_PINS
        // .VPWR(VPWR),
        // .VGND(VGND),
        // `endif
        .CLK(clk_i),
        .WE0(we_1),
        .EN0(en_1),
        .A0(addr_1),
        .Di0(din_1),
        .Do0(dout_1)
    );

endmodule