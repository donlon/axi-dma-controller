module dmac_read_initiator # (
    parameter integer ADDR_WD = 32,
    parameter integer DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam integer STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    input                               rd_req_valid,
    output                              rd_req_ready,
    input [ADDR_WD-1:0]                 rd_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    rd_req_burst,
    input [axi4_pkg::LEN_BITS-1:0]      rd_req_len,
    input [axi4_pkg::SIZE_BITS-1:0]     rd_req_size,

    // Read Address Channel
    output logic                        m_axi_arvalid,
    input                               m_axi_arready,
    output logic [ADDR_WD-1:0]          m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst
);

    assign m_axi_arvalid = rd_req_valid;
    assign rd_req_ready  = m_axi_arready;
    assign m_axi_araddr  = rd_req_addr;
    assign m_axi_arlen   = rd_req_len;
    assign m_axi_arsize  = rd_req_size;
    assign m_axi_arburst = rd_req_burst;

endmodule : dmac_read_initiator
