module dmac_write_req_gen # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                           clk,
    input                           rst,

    input                           cmd_in_valid,
    output logic                    cmd_in_ready,
    input [$clog2(ADDR_WD/8)-1:0]   cmd_in_src_offset,
    input [ADDR_WD-1:0]             cmd_in_dst_addr,
    input [1:0]                     cmd_in_burst,
    input [ADDR_WD-1:0]             cmd_in_len,
    input [2:0]                     cmd_in_size,

    output                              wr_req_valid,
    input                               wr_req_ready,
    output [ADDR_WD-1:0]                wr_req_addr,
    output [axi4_pkg::BURST_BITS-1:0]   wr_req_burst,
    output [axi4_pkg::LEN_BITS-1:0]     wr_req_len,
    output [$clog2(ADDR_WD/8)-1:0]      wr_req_data_offset, // src_addr %ADDR_WD_BYTES
    output [axi4_pkg::SIZE_BITS-1:0]    wr_req_size
);

    assign cmd_in_ready = 1;

endmodule : dmac_write_req_gen
