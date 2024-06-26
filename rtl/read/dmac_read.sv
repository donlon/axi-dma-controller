module dmac_read # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    // DMA Command
    input                               cmd_valid,
    output logic                        cmd_ready,
    input [ADDR_WD-1:0]                 cmd_src_addr,
    input [ADDR_WD-1:0]                 cmd_dst_addr,
    input [1:0]                         cmd_burst,
    input [ADDR_WD-1:0]                 cmd_len,
    input [2:0]                         cmd_size,

    output                              cmd_out_valid,
    input                               cmd_out_ready,
    output [$clog2(ADDR_WD/8)-1:0]      cmd_out_src_offset,
    output [ADDR_WD-1:0]                cmd_out_dst_addr,
    output [1:0]                        cmd_out_burst,
    output [ADDR_WD-1:0]                cmd_out_len,
    output [2:0]                        cmd_out_size,

    output                              data_out_valid,
    input                               data_out_ready,
    output [DATA_WD-1:0]                data_out,
    output                              data_out_last,

    // Read Address Channel
    output wire                         m_axi_arvalid,
    output wire [ADDR_WD-1:0]           m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    input wire                          m_axi_arready,
    // Read Response Channel
    input wire                          m_axi_rvalid,
    input wire [DATA_WD-1:0]            m_axi_rdata,
    input wire [1:0]                    m_axi_rresp,
    input wire                          m_axi_rlast,
    output wire                         m_axi_rready
);

    logic                               rd_req_valid;
    logic                               rd_req_ready;
    logic [ADDR_WD-1:0]                 rd_req_addr;
    logic [axi4_pkg::BURST_BITS-1:0]    rd_req_burst;
    logic [axi4_pkg::LEN_BITS-1:0]      rd_req_len;
    logic [axi4_pkg::SIZE_BITS-1:0]     rd_req_size;

    dmac_read_req_gen # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_req_gen (
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
        .rd_req_valid,
        .rd_req_ready,
        .rd_req_addr,
        .rd_req_burst,
        .rd_req_len,
        .rd_req_size,
        .cmd_out_valid,
        .cmd_out_ready,
        .cmd_out_src_offset,
        .cmd_out_dst_addr,
        .cmd_out_burst,
        .cmd_out_len,
        .cmd_out_size
    );

    dmac_read_initiator # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_initiator (
        .clk,
        .rst,
        .rd_req_valid,
        .rd_req_ready,
        .rd_req_addr,
        .rd_req_burst,
        .rd_req_len,
        .rd_req_size,
        // Read Address Channel
        .m_axi_arvalid,
        .m_axi_araddr,
        .m_axi_arlen,
        .m_axi_arsize,
        .m_axi_arburst,
        .m_axi_arready
    );

    dmac_read_handler # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_handler (
        .clk,
        .rst,
        .data_out_valid,
        .data_out_ready,
        .data_out,
        .data_out_last,
        .rd_resp_valid(),
        // Read Response Channel
        .m_axi_rvalid,
        .m_axi_rdata,
        .m_axi_rresp,
        .m_axi_rlast,
        .m_axi_rready
    );

endmodule : dmac_read
