module dmac_write_handler # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                       clk,
    input                       rst,

    // Write Response Channel
    input wire                  m_axi_bvalid,
    input wire [1:0]            m_axi_bresp,
    output wire                 m_axi_bready
);

  assign m_axi_bready = 1;

endmodule : dmac_write_handler