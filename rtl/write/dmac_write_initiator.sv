module dmac_write_initiator # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                       clk,
    input                       rst,

    input                               wr_req_valid,
    output                              wr_req_ack,
    input [ADDR_WD-1:0]                 wr_req_addr,
    input [axi4_pkg::BURST_BITS-1:0]    wr_req_burst,
    input [ADDR_WD-1:0]                 wr_req_length,
    input [$clog2(ADDR_WD/8)-1:0]       wr_req_data_offset, // src_addr % ADDR_WD_BYTES
    input [axi4_pkg::SIZE_BITS-1:0]     wr_req_size,
    output [ADDR_WD-1:0]                wr_req_next_addr,
    output [ADDR_WD-1:0]                wr_req_next_length,
    output                              wr_req_done,

    input                               data_in_valid,
    output                              data_in_ready,
    input  [DATA_WD-1:0]                data_in,
    output                              buf_dec_usage_valid,
    output [$clog2(MAX_BURST_LEN+1):0]  buf_dec_usage_count,

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

    localparam MAX_BURST_BYTES = MAX_BURST_LEN * (ADDR_WD / 8);
    localparam BURST_BITS = $clog2(MAX_BURST_BYTES);

    wire  aw_active = m_axi_awvalid;
    logic wr_active;
    logic [$clog2(MAX_BURST_BYTES)-1:0] wr_counter;

    wire wr_start = wr_req_valid && !aw_active && (!wr_active || m_axi_wvalid && m_axi_wready && m_axi_wlast);
    wire aw_fire_last = m_axi_awvalid && m_axi_awready;
    wire w_fire_last  = m_axi_wvalid && m_axi_wready && m_axi_wlast;

    // Align to MAX_BURST_LEN * (2 ** size) bytes
    wire [ADDR_WD-1:0] aligned_len_bytes = (1 << ($clog2(MAX_BURST_LEN) + wr_req_size)) - (wr_req_addr & ((1 << ($clog2(MAX_BURST_LEN) + wr_req_size)) - 1));
    wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > wr_req_length ? wr_req_length : aligned_len_bytes;

    wire [ADDR_WD-1:0] aligned_req_addr = wr_req_addr & ~((1 << wr_req_size) - 1);
    // wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > wr_req_length ? wr_req_length : aligned_len_bytes;
    wire [ADDR_WD-1:0] burst_len_trans = (wr_req_addr + burst_len_bytes + ((1 << wr_req_size) - 1) - aligned_req_addr) >> wr_req_size;

    assign wr_req_next_addr = wr_req_addr + aligned_len_bytes;
    assign wr_req_next_length = wr_req_length - burst_len_bytes;
    assign buf_dec_usage_valid = wr_start;
    assign buf_dec_usage_count = burst_len_trans;

    wire [ADDR_WD-1:0] axi_awlen = burst_len_trans - 1;

    wire  wr_delay = wr_req_data_offset > wr_req_addr[$clog2(ADDR_WD/8)-1:0]; // TODO: reg
    logic wr_delay_done;

    // Shifter
    logic               data_in_q_valid;
    // logic               data_in_q_ready;
    logic [DATA_WD-1:0] data_in_q;
    logic [$clog2(ADDR_WD/8):0] data_shift_bytes;

    assign data_shift_bytes[$clog2(ADDR_WD/8)]     = data_shift_bytes[$clog2(ADDR_WD/8)-1:0] == 0;
    assign data_shift_bytes[$clog2(ADDR_WD/8)-1:0] = wr_req_data_offset - wr_req_addr[$clog2(ADDR_WD/8)-1:0];

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            m_axi_awvalid <= 0;
            m_axi_awlen <= 'x;
        end else begin
            if (wr_start) begin
                m_axi_awvalid <= 1;
                m_axi_awaddr <= wr_req_addr;
                m_axi_awlen <= axi_awlen;
            end else if (m_axi_awready) begin
                m_axi_awvalid <= 0;
            end
        end
    end
    assign m_axi_awsize = wr_req_size;
    assign m_axi_awburst = wr_req_burst;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            wr_active <= 0;
        end else begin
            if (wr_req_valid && !m_axi_awvalid) begin
                wr_active <= 1;
            end else if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                wr_active <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            wr_counter <= 'x;
        end else begin
            if (wr_start) begin
                wr_counter <= axi_awlen;
            end else if (m_axi_wvalid && m_axi_wready) begin
                wr_counter <= wr_counter - 1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wvalid <= 0;
        end else begin
            if (wr_start && (!wr_delay || data_in_q_valid)) begin
                m_axi_wvalid <= 1;
            end else if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_wvalid <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wstrb <= 'x;
        end else begin
            if (wr_start) begin
                m_axi_wstrb <= (1 << (ADDR_WD / 8)) - (1 << wr_req_addr[$clog2(ADDR_WD / 8)-1:0]);
            end else if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wstrb <= '1; // TODO: dst_addr + len is not aligned
                // wr_counter == 1
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            data_in_q <= 'x;
            data_in_q_valid <= 0;
        end else begin
            if (w_fire_last) begin
                data_in_q_valid <= 0;
                data_in_q <= 'x;
            end else if (m_axi_wvalid && m_axi_wready) begin
                data_in_q_valid <= 1;
                data_in_q <= data_in;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wlast <= 0;
        end else begin
            if (wr_start) begin
                m_axi_wlast <= axi_awlen == 0;
            end else if (m_axi_wvalid && m_axi_wready && wr_active) begin
                m_axi_wlast <= wr_counter == 1;
            end
        end
    end

    // assign m_axi_wvalid = wr_req_valid && data_in_valid && (!wr_delay || data_in_q_valid);
    assign data_in_ready = m_axi_wready && wr_active;
    assign m_axi_wdata = {data_in, data_in_q} >> (data_shift_bytes * 8);
    // assign m_axi_wstrb = 0;
    // assign m_axi_wlast = burst_len_trans == 0 || ;

    assign wr_req_ack = aw_fire_last;
    assign wr_req_done = wr_req_next_length == 0;

    assert property (@(posedge clk) disable iff (rst) wr_req_valid && !wr_req_ack |-> data_in_valid)
            else $error("Data is not ready");

endmodule : dmac_write_initiator