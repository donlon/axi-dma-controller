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
    input [ADDR_WD-1:0]                 rd_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    rd_req_burst,
    input [ADDR_WD-1:0]                 rd_req_length,
    input [axi4_pkg::SIZE_BITS-1:0]     rd_req_size,
    output                              rd_req_ack,
    output [ADDR_WD-1:0]                rd_req_next_addr,
    output [ADDR_WD-1:0]                rd_req_next_length,
    output                              rd_req_done,

    // Read Address Channel
    output logic                        m_axi_arvalid,
    input                               m_axi_arready,
    output logic [ADDR_WD-1:0]          m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst
);

    assign rd_req_ack = m_axi_arvalid && m_axi_arready;
    assign rd_req_done = rd_req_next_length == 0;

    // Align to MAX_BURST_LEN * (2 ** size) bytes
    wire [ADDR_WD-1:0] aligned_len_bytes = (1 << ($clog2(MAX_BURST_LEN) + rd_req_size)) - (rd_req_addr & ((1 << ($clog2(MAX_BURST_LEN) + rd_req_size)) - 1));
    wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > rd_req_length ? rd_req_length : aligned_len_bytes;

    wire [ADDR_WD-1:0] aligned_req_addr = rd_req_addr & ~((1 << rd_req_size) - 1);
    // wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > rd_req_length ? rd_req_length : aligned_len_bytes;
    wire [ADDR_WD-1:0] burst_len_trans = (rd_req_addr + burst_len_bytes + ((1 << rd_req_size) - 1) - aligned_req_addr) >> rd_req_size;

    assign rd_req_next_addr = rd_req_addr + aligned_len_bytes;
    assign rd_req_next_length = rd_req_length - burst_len_bytes;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            m_axi_arvalid <= 0;
            m_axi_araddr <= 0;
            m_axi_arlen <= 0;
        end else begin
            if (rd_req_valid /**/&& !m_axi_arready) begin
                m_axi_arvalid <= 1;
                m_axi_araddr <= rd_req_addr;
                m_axi_arlen <= burst_len_trans - 1;
            end else if (m_axi_arready) begin
                m_axi_arvalid <= 0;
            end
        end
    end
    assign m_axi_arsize = rd_req_size;
    assign m_axi_arburst = rd_req_burst;

endmodule : dmac_read_initiator
