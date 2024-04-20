module dmac_read_cmd_fifo # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    output                              rd_cmd_i_valid,
    input                               rd_cmd_i_ready,
    input [axi4_pkg::BURST_BITS-1:0]    rd_cmd_burst_i,
    input [axi4_pkg::SIZE_BITS-1:0]     rd_cmd_size_i,
    input [$clog2(ADDR_WD/8)-1:0]       rd_cmd_data_offset_i,

    output                              rd_cmd_o_valid,
    input                               rd_cmd_o_ready,
    output [axi4_pkg::BURST_BITS-1:0]   rd_cmd_burst_o,
    output [axi4_pkg::SIZE_BITS-1:0]    rd_cmd_size_o,
    output [$clog2(ADDR_WD/8)-1:0]      rd_cmd_data_offset_o
);



endmodule : dmac_read_cmd_fifo