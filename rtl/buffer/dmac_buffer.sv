module dmac_buffer # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16 /// 16 beats
) (
    input clk,
    input rst,

    input                               dec_usage_valid,
    input  [$clog2(MAX_BURST_LEN)+1:0]  dec_usage_count,
    output [$clog2(MAX_BURST_LEN)+1:0]  buf_usage,

    input                   data_in_valid,
    output                  data_in_ready,
    input [DATA_WD-1:0]     data_in,
    input                   data_in_last,

    output                  data_out_valid,
    input                   data_out_ready,
    output [DATA_WD-1:0]    data_out,
    output                  data_out_last
);

    generic_sync_fifo # (
        .DWIDTH(DATA_WD),
        .AWIDTH($clog2(MAX_BURST_LEN) + 1)
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
        .data_count()
    );

    dmac_buffer_usage_ctr # (
        .MAX_ELEMENTS(MAX_BURST_LEN * 2)
    ) i_usage_ctr (
        .clk,
        .rst,
        .inc(data_in_valid && data_in_ready),
        .dec(dec_usage_valid),
        .dec_count(dec_usage_count),
        .usage(buf_usage)
    );

endmodule : dmac_buffer
