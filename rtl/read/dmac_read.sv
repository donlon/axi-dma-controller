module dmac_read # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    input                               rd_req_valid,
    input [ADDR_WD-1:0]                 rd_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    rd_req_burst,
    input [ADDR_WD-1:0]                 rd_req_length,
    input [axi4_pkg::SIZE_BITS-1:0]     rd_req_size,
    output                              rd_req_ack,
    output [ADDR_WD-1:0]                rd_req_next_addr,
    output [ADDR_WD-1:0]                rd_req_next_length,
    output                              rd_req_done,

    output                              rd_resp_valid,

    // output                              ctrl_out_valid,
    // output [ADDR_WD-1:0]                ctrl_out_dst_addr,
    // output [$clog2(ADDR_WD)-1:0]        ctrl_out_rd_offset,
    // output [ADDR_WD-1:0]                ctrl_out_length, // bytes

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

    dmac_read_initiator # (
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_initiator (
        .clk,
        .rst,
        .rd_req_valid,
        .rd_req_addr,
        .rd_req_burst,
        .rd_req_length,
        .rd_req_size,
        .rd_req_ack,
        .rd_req_next_addr,
        .rd_req_next_length,
        .rd_req_done,
        // .ctrl_out_valid,
        // .ctrl_out_dst_addr,
        // .ctrl_out_rd_offset,
        // .ctrl_out_length, // bytes
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
        .rd_resp_valid,
        .data_out_valid,
        .data_out_ready,
        .data_out,
        .data_out_last,
        // Read Response Channel
        .m_axi_rvalid,
        .m_axi_rdata,
        .m_axi_rresp,
        .m_axi_rlast,
        .m_axi_rready
    );

endmodule : dmac_read
