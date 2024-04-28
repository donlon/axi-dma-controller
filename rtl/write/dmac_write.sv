module dmac_write # (
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

    input                           data_in_valid,
    output                          data_in_ready,
    input  [DATA_WD-1:0]            data_in,
    input                           data_in_last,

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

    logic                               wr_req_valid;
    logic                               wr_req_ready;
    logic [ADDR_WD-1:0]                 wr_req_addr;
    logic [axi4_pkg::BURST_BITS-1:0]    wr_req_burst;
    logic [axi4_pkg::LEN_BITS-1:0]      wr_req_len;
    logic [$clog2(ADDR_WD/8)-1:0]       wr_req_data_offset;
    logic [axi4_pkg::SIZE_BITS-1:0]     wr_req_size;

    dmac_write_req_gen # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_req_gen (
        .clk,
        .rst,
        .cmd_in_valid,
        .cmd_in_ready,
        .cmd_in_src_offset,
        .cmd_in_dst_addr,
        .cmd_in_burst,
        .cmd_in_len,
        .cmd_in_size,
        .wr_req_valid,
        .wr_req_ready,
        .wr_req_addr,
        .wr_req_burst,
        .wr_req_len,
        .wr_req_data_offset,
        .wr_req_size
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
        .wr_req_ready,
        .wr_req_addr,
        .wr_req_burst,
        .wr_req_len,
        .wr_req_data_offset,
        .wr_req_size,
        .data_in_valid,
        .data_in_ready,
        .data_in,
        .data_in_last,
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