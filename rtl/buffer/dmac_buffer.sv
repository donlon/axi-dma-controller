module dmac_buffer # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16 /// 16 beats
) (
    input clk,
    input rst,

    output [$clog2(MAX_BURST_LEN):0]    buf_fill_level,

    input                   data_in_valid,
    output                  data_in_ready,
    input [DATA_WD-1:0]     data_in,
    input                   data_in_last,

    output                  data_out_valid,
    input                   data_out_ready,
    output [DATA_WD-1:0]    data_out,
    output                  data_out_last
);

    // assign data_out_valid = data_in_valid;
    // assign data_in_ready = data_out_ready;
    // assign data_out = data_in;
    // assign data_out_last = data_in_last;

    // ctrl_out_ready

    generic_sync_fifo # (
        .DWIDTH(DATA_WD),
        .AWIDTH($clog2(MAX_BURST_LEN))
    ) i_buf (
        .clk,
        .rst,
        .wvalid(data_in_valid),
        .wready(data_in_ready),
        .wdata (data_in),
        .walmost_full(),
        .rvalid(data_out_valid),
        .rready(data_out_ready),
        .rdata (data_out),
        .ralmost_empty(),
        .data_count(buf_fill_level)
    );


endmodule : dmac_buffer
