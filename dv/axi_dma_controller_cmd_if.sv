interface axi_dma_controller_cmd_if # (
    parameter int ADDR_WD = 32
) (
    input clk, rst
);

    // DMA Command
    logic                   valid;    // input
    logic                   ready;    // output

    logic [ADDR_WD-1:0]     src_addr; // input
    logic [ADDR_WD-1:0]     dst_addr; // input
    logic [1:0]             burst;    // input
    logic [ADDR_WD-1:0]     len;      // input
    logic [2:0]             size;     // input

endinterface : axi_dma_controller_cmd_if
