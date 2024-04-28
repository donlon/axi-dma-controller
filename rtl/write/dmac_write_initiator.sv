module dmac_write_initiator # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                               clk,
    input                               rst,

    input                               wr_req_valid,
    output                              wr_req_ready,
    input [ADDR_WD-1:0]                 wr_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    wr_req_burst,
    input [axi4_pkg::LEN_BITS-1:0]      wr_req_len,
    input [$clog2(ADDR_WD/8)-1:0]       wr_req_data_offset, // src_addr % ADDR_WD_BYTES
    input [axi4_pkg::SIZE_BITS-1:0]     wr_req_size,

    input                               data_in_valid,
    output                              data_in_ready,
    input  [DATA_WD-1:0]                data_in,
    input                               data_in_last,

    // Write Address Channel
    output logic                m_axi_awvalid,
    input wire                  m_axi_awready,
    output logic [ADDR_WD-1:0]  m_axi_awaddr,
    output logic [7:0]          m_axi_awlen,
    output logic [2:0]          m_axi_awsize,
    output logic [1:0]          m_axi_awburst,
    // Write Data Channel
    output logic                m_axi_wvalid,
    input wire                  m_axi_wready,
    output logic [DATA_WD-1:0]  m_axi_wdata,
    output logic [STRB_WD-1:0]  m_axi_wstrb,
    output logic                m_axi_wlast
);

    assign m_axi_awvalid = 0;
    assign m_axi_wvalid = 0;
    assign data_in_ready = 1;

endmodule : dmac_write_initiator