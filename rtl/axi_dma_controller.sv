module axi_dma_controller #(
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input wire                    clk,
    input wire                    rst,
    // DMA Command
    input wire                    cmd_valid,
    input wire [ADDR_WD-1:0]      cmd_src_addr,
    input wire [ADDR_WD-1:0]      cmd_dst_addr,
    input wire [1:0]              cmd_burst,
    input wire [ADDR_WD-1:0]      cmd_len,
    input wire [2:0]              cmd_size,
    output wire                   cmd_ready,
    // Read Address Channel
    output wire                   M_AXI_ARVALID,
    output wire [ADDR_WD-1:0]     M_AXI_ARADDR,
    output wire [7:0]             M_AXI_ARLEN,
    output wire [2:0]             M_AXI_ARSIZE,
    output wire [1:0]             M_AXI_ARBURST,
    input wire                    M_AXI_ARREADY,
    // Read Response Channel
    input wire                    M_AXI_RVALID,
    input wire [DATA_WD-1:0]      M_AXI_RDATA,
    input wire [1:0]              M_AXI_RRESP,
    input wire                    M_AXI_RLAST,
    output wire                   M_AXI_RREADY,
    // Write Address Channel
    output wire                   M_AXI_AWVALID,
    output wire [ADDR_WD-1:0]     M_AXI_AWADDR,
    output wire [7:0]             M_AXI_AWLEN,
    output wire [2:0]             M_AXI_AWSIZE,
    output wire [1:0]             M_AXI_AWBURST,
    input wire                    M_AXI_AWREADY,
    // Write Data Channel
    output wire                   M_AXI_WVALID,
    output wire [DATA_WD-1:0]     M_AXI_WDATA,
    output wire [STRB_WD-1:0]     M_AXI_WSTRB,
    output wire                   M_AXI_WLAST,
    input wire                    M_AXI_WREADY,
    // Write Response Channel
    input wire                    M_AXI_BVALID,
    input wire [1:0]              M_AXI_BRESP,
    output wire                   M_AXI_BREADY
);

    logic                           buf_cmd_in_valid;
    logic                           buf_cmd_in_ready;
    logic [$clog2(ADDR_WD/8)-1:0]   buf_cmd_in_src_offset;
    logic [ADDR_WD-1:0]             buf_cmd_in_dst_addr;
    logic [1:0]                     buf_cmd_in_burst;
    logic [ADDR_WD-1:0]             buf_cmd_in_len;
    logic [2:0]                     buf_cmd_in_size;
    logic                           buf_cmd_out_valid;
    logic                           buf_cmd_out_ready;
    logic [$clog2(ADDR_WD/8)-1:0]   buf_cmd_out_src_offset;
    logic [ADDR_WD-1:0]             buf_cmd_out_dst_addr;
    logic [1:0]                     buf_cmd_out_burst;
    logic [ADDR_WD-1:0]             buf_cmd_out_len;
    logic [2:0]                     buf_cmd_out_size;
    logic                           buf_data_in_valid;
    logic                           buf_data_in_ready;
    logic [DATA_WD-1:0]             buf_data_in;
    logic                           buf_data_in_last;
    logic                           buf_data_out_valid;
    logic                           buf_data_out_ready;
    logic [DATA_WD-1:0]             buf_data_out;
    logic                           buf_data_out_last;

    dmac_read # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_rd (
        .clk,
        .rst,
        // DMA Command
        .cmd_valid,
        .cmd_ready,
        .cmd_src_addr,
        .cmd_dst_addr,
        .cmd_burst,
        .cmd_len,
        .cmd_size,
        .cmd_out_valid(buf_cmd_in_valid),
        .cmd_out_ready(buf_cmd_in_ready),
        .cmd_out_src_offset(buf_cmd_in_src_offset),
        .cmd_out_dst_addr(buf_cmd_in_dst_addr),
        .cmd_out_burst(buf_cmd_in_burst),
        .cmd_out_len(buf_cmd_in_len),
        .cmd_out_size(buf_cmd_in_size),
        .data_out_valid(buf_data_in_valid),
        .data_out_ready(buf_data_in_ready),
        .data_out(buf_data_in),
        .data_out_last(buf_data_in_last),
        // Read Address Channel
        .m_axi_arvalid(M_AXI_ARVALID),
        .m_axi_araddr(M_AXI_ARADDR),
        .m_axi_arlen(M_AXI_ARLEN),
        .m_axi_arsize(M_AXI_ARSIZE),
        .m_axi_arburst(M_AXI_ARBURST),
        .m_axi_arready(M_AXI_ARREADY),
        // Read Response Channel
        .m_axi_rvalid(M_AXI_RVALID),
        .m_axi_rdata(M_AXI_RDATA),
        .m_axi_rresp(M_AXI_RRESP),
        .m_axi_rlast(M_AXI_RLAST),
        .m_axi_rready(M_AXI_RREADY)
    );

    dmac_buffer # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT)
    ) i_buf(
        .clk,
        .rst,
        .cmd_in_valid(buf_cmd_in_valid),
        .cmd_in_ready(buf_cmd_in_ready),
        .cmd_in_src_offset(buf_cmd_in_src_offset),
        .cmd_in_dst_addr(buf_cmd_in_dst_addr),
        .cmd_in_burst(buf_cmd_in_burst),
        .cmd_in_len(buf_cmd_in_len),
        .cmd_in_size(buf_cmd_in_size),
        .data_in_valid(buf_data_in_valid),
        .data_in_ready(buf_data_in_ready),
        .data_in(buf_data_in),
        .data_in_last(buf_data_in_last),
        .cmd_out_valid(buf_cmd_out_valid),
        .cmd_out_ready(buf_cmd_out_ready),
        .cmd_out_src_offset(buf_cmd_out_src_offset),
        .cmd_out_dst_addr(buf_cmd_out_dst_addr),
        .cmd_out_burst(buf_cmd_out_burst),
        .cmd_out_len(buf_cmd_out_len),
        .cmd_out_size(buf_cmd_out_size),
        .data_out_valid(buf_data_out_valid),
        .data_out_ready(buf_data_out_ready),
        .data_out(buf_data_out),
        .data_out_last(buf_data_out_last)
    );

    dmac_write # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_wr (
        .clk,
        .rst,
        .cmd_in_valid(buf_cmd_out_valid),
        .cmd_in_ready(buf_cmd_out_ready),
        .cmd_in_src_offset(buf_cmd_out_src_offset),
        .cmd_in_dst_addr(buf_cmd_out_dst_addr),
        .cmd_in_burst(buf_cmd_out_burst),
        .cmd_in_len(buf_cmd_out_len),
        .cmd_in_size(buf_cmd_out_size),
        .data_in_valid(buf_data_out_valid),
        .data_in_ready(buf_data_out_ready),
        .data_in(buf_data_out),
        .data_in_last(buf_data_out_last),
        // Write Address Channel
        .m_axi_awvalid(M_AXI_AWVALID),
        .m_axi_awaddr(M_AXI_AWADDR),
        .m_axi_awlen(M_AXI_AWLEN),
        .m_axi_awsize(M_AXI_AWSIZE),
        .m_axi_awburst(M_AXI_AWBURST),
        .m_axi_awready(M_AXI_AWREADY),
        // Write Data Channel
        .m_axi_wvalid(M_AXI_WVALID),
        .m_axi_wdata(M_AXI_WDATA),
        .m_axi_wstrb(M_AXI_WSTRB),
        .m_axi_wlast(M_AXI_WLAST),
        .m_axi_wready(M_AXI_WREADY),
        // Write Response Channel
        .m_axi_bvalid(M_AXI_BVALID),
        .m_axi_bresp(M_AXI_BRESP),
        .m_axi_bready(M_AXI_BREADY)
    );

    if (ADDR_WD % 8 != 0) $error("ADDR_WD is not multiple of 8");
    if (DATA_WD % 8 != 0) $error("DATA_WD is not multiple of 8");
    if (2 ** $clog2(ADDR_WD / 8) != ADDR_WD / 8) $error("ADDR_WD is not power of 2");
    if (2 ** $clog2(DATA_WD / 8) != DATA_WD / 8) $error("DATA_WD is not power of 2");
    if (2 ** $clog2(MAX_BURST_LEN) != MAX_BURST_LEN) $error("MAX_BURST_LEN is not power of 2");
    if (MAX_BURST_LEN <= 0 || MAX_BURST_LEN > 256)   $error("MAX_BURST_LEN is invalid");

endmodule : axi_dma_controller
