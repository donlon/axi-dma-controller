module dmac_write # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                       clk,
    input                       rst,

    input                               wr_req_valid,
    input [ADDR_WD-1:0]                 wr_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    wr_req_burst,
    input [ADDR_WD-1:0]                 wr_req_length,
    input [$clog2(ADDR_WD/8)-1:0]       wr_req_data_offset, // src_addr % ADDR_WD_BYTES
    input [axi4_pkg::SIZE_BITS-1:0]     wr_req_size,
    output                              wr_req_ack,
    output [ADDR_WD-1:0]                wr_req_next_addr,
    output [ADDR_WD-1:0]                wr_req_next_length,
    output                              wr_req_done,

    input                               data_in_valid,
    output                              data_in_ready,
    input  [DATA_WD-1:0]                data_in,
    output                              buf_dec_usage_valid,
    output [$clog2(MAX_BURST_LEN)+1:0]  buf_dec_usage_count,

    // Write Address Channel
    output wire                 m_axi_awvalid,
    output wire [ADDR_WD-1:0]   m_axi_awaddr,
    output wire [7:0]           m_axi_awlen,
    output wire [2:0]           m_axi_awsize,
    output wire [1:0]           m_axi_awburst,
    input wire                  m_axi_awready,
    // Write Data Channel
    output wire                 m_axi_wvalid,
    output wire [DATA_WD-1:0]   m_axi_wdata,
    output wire [STRB_WD-1:0]   m_axi_wstrb,
    output wire                 m_axi_wlast,
    input wire                  m_axi_wready,
    // Write Response Channel
    input wire                  m_axi_bvalid,
    input wire [1:0]            m_axi_bresp,
    output wire                 m_axi_bready
);

    dmac_write_initiator # (
        .ADDR_WD(32),
        .DATA_WD(32),
        .CHANNEL_COUNT(8), /// 8 channels
        .MAX_BURST_LEN(16) /// 16 beats
    ) i_initiator (
        .clk,
        .rst,
        .wr_req_valid,
        .wr_req_addr,
        .wr_req_burst,
        .wr_req_length,
        .wr_req_data_offset,
        .wr_req_size,
        .wr_req_ack,
        .wr_req_next_addr,
        .wr_req_next_length,
        .wr_req_done,
        .data_in_valid,
        .data_in_ready,
        .data_in,
        .buf_dec_usage_valid,
        .buf_dec_usage_count,
        // Write Address Channel
        .m_axi_awvalid,
        .m_axi_awaddr,
        .m_axi_awlen,
        .m_axi_awsize,
        .m_axi_awburst,
        .m_axi_awready,
        // Write Data Channel
        .m_axi_wvalid,
        .m_axi_wdata,
        .m_axi_wstrb,
        .m_axi_wlast,
        .m_axi_wready
    );

    dmac_write_handler # (
        .ADDR_WD(32),
        .DATA_WD(32),
        .CHANNEL_COUNT(8), /// 8 channels
        .MAX_BURST_LEN(16) /// 16 beats
    ) i_handler (
        .clk,
        .rst,
        // Write Response Channel
        .m_axi_bvalid,
        .m_axi_bresp,
        .m_axi_bready
    );


endmodule : dmac_write