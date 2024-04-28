module dmac_buffer # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16 /// 16 beats
) (
    input clk,
    input rst,

    input                           cmd_in_valid,
    output logic                    cmd_in_ready,
    input [$clog2(ADDR_WD/8)-1:0]   cmd_in_src_offset,
    input [ADDR_WD-1:0]             cmd_in_dst_addr,
    input [1:0]                     cmd_in_burst,
    input [ADDR_WD-1:0]             cmd_in_len,
    input [2:0]                     cmd_in_size,

    input                           data_in_valid,
    output                          data_in_ready,
    input [DATA_WD-1:0]             data_in,
    input                           data_in_last,

    output                          cmd_out_valid,
    input                           cmd_out_ready,
    output [$clog2(ADDR_WD/8)-1:0]  cmd_out_src_offset,
    output [ADDR_WD-1:0]            cmd_out_dst_addr,
    output [1:0]                    cmd_out_burst,
    output [ADDR_WD-1:0]            cmd_out_len,
    output [2:0]                    cmd_out_size,

    output                          data_out_valid,
    input                           data_out_ready,
    output [DATA_WD-1:0]            data_out,
    output                          data_out_last
);

    localparam int CMD_WIDTH = $clog2(ADDR_WD/8) + ADDR_WD + 2 + ADDR_WD + 3;

    wire [CMD_WIDTH-1:0] cmd_in = {cmd_in_src_offset, cmd_in_dst_addr, cmd_in_burst, cmd_in_len, cmd_in_size};
    wire [CMD_WIDTH-1:0] cmd_out;

    assign {cmd_out_src_offset, cmd_out_dst_addr, cmd_out_burst, cmd_out_len, cmd_out_size} = cmd_out;

    generic_sync_fifo # (
        .DWIDTH(CMD_WIDTH),
        .AWIDTH(3)
    ) i_cmd_buf (
        .clk,
        .rst,
        .wvalid(cmd_in_valid),
        .wready(cmd_in_ready),
        .wdata (cmd_in),
        .walmost_full(),
        .rvalid(cmd_out_valid),
        .rready(cmd_out_ready),
        .rdata (cmd_out),
        .ralmost_empty(),
        .data_count()
    );

    generic_sync_fifo # (
        .DWIDTH(DATA_WD + 1),
        .AWIDTH($clog2(MAX_BURST_LEN) + 1)
    ) i_data_buf (
        .clk,
        .rst,
        .wvalid(data_in_valid),
        .wready(data_in_ready),
        .wdata ({data_in, data_in_last}),
        .walmost_full(),
        .rvalid(data_out_valid),
        .rready(data_out_ready),
        .rdata ({data_out, data_out_last}),
        .ralmost_empty(),
        .data_count()
    );

endmodule : dmac_buffer
