interface axi_dma_controller_axi_if # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    localparam int STRB_WD = DATA_WD / 8
) (
    input clk, rst
);

    // Read Address Channel
    logic                   arvalid; // output
    logic [ADDR_WD-1:0]     araddr; // output
    logic [7:0]             arlen; // output
    logic [2:0]             arsize; // output
    logic [1:0]             arburst; // output
    logic                   arready; // input

    // Read Response Channel
    logic                   rvalid; // input
    logic [DATA_WD-1:0]     rdata; // input
    logic [1:0]             rresp; // input
    logic                   rlast; // input
    logic                   rready; // output

    // Write Address Channel
    logic                   awvalid; // output
    logic [ADDR_WD-1:0]     awaddr; // output
    logic [7:0]             awlen; // output
    logic [2:0]             awsize; // output
    logic [1:0]             awburst; // output
    logic                   awready; // input

    // Write Data Channel
    logic                   wvalid; // output
    logic [DATA_WD-1:0]     wdata; // output
    logic [STRB_WD-1:0]     wstrb; // output
    logic                   wlast; // output
    logic                   wready; // input

    // Write Response Channel
    logic                   bvalid; // input
    logic [1:0]             bresp; // input
    logic                   bready; // output

    // TODO: modports

    assert property (@(posedge clk) !$isunknown(rst)) else $error("rst is unknown");
    assert property (@(posedge clk) !$isunknown(arvalid)) else $error("arvalid is unknown");
    assert property (@(posedge clk) !$isunknown(arready)) else $error("arready is unknown");
    assert property (@(posedge clk) !$isunknown(rvalid)) else $error("rvalid is unknown");
    assert property (@(posedge clk) !$isunknown(rready)) else $error("rready is unknown");
    assert property (@(posedge clk) !$isunknown(awvalid)) else $error("awvalid is unknown");
    assert property (@(posedge clk) !$isunknown(awready)) else $error("awready is unknown");
    assert property (@(posedge clk) !$isunknown(wvalid)) else $error("wvalid is unknown");
    assert property (@(posedge clk) !$isunknown(wready)) else $error("wready is unknown");
    assert property (@(posedge clk) !$isunknown(bvalid)) else $error("bvalid is unknown");
    assert property (@(posedge clk) !$isunknown(bready)) else $error("bready is unknown");

endinterface : axi_dma_controller_axi_if
