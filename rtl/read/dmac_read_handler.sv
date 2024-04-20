module dmac_read_handler # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    output                              data_out_valid,
    input                               data_out_ready,
    output [DATA_WD-1:0]                data_out,
    output                              data_out_last,

    output                              rd_resp_valid,

    // Read Response Channel
    input wire                          m_axi_rvalid,
    output wire                         m_axi_rready,
    input wire [DATA_WD-1:0]            m_axi_rdata,
    input wire [1:0]                    m_axi_rresp,
    input wire                          m_axi_rlast
);

    // TODO: narrow burst

    assign data_out_valid = m_axi_rvalid;
    assign m_axi_rready = data_out_ready;
    assign data_out_last = m_axi_rlast;
    assign data_out = m_axi_rdata;

    assign rd_resp_valid = m_axi_rvalid && m_axi_rready && m_axi_rlast;

endmodule : dmac_read_handler