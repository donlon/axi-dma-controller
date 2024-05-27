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
    input                               wr_req_last, // will drain the last unaligned word

    input                               data_in_valid,
    output logic                        data_in_ready,
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

    localparam MAX_BURST_BYTES = MAX_BURST_LEN * (ADDR_WD / 8);

    logic wr_req_blocking;

    wire  aw_active = m_axi_awvalid;
    logic wr_active;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_req_blocking <= 0;
        end else begin
            if (wr_req_valid && !wr_req_ready) begin
                wr_req_blocking <= 1;
            end else if (wr_req_ready) begin
                wr_req_blocking <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            wr_active <= 0;
        end else begin
            if (wr_req_valid && wr_req_ready) begin
                wr_active <= 1;
            end else if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                wr_active <= 0;
            end
        end
    end

    assign wr_req_ready = !(aw_active && !m_axi_awready) && !(wr_active && !(m_axi_wvalid && m_axi_wready && m_axi_wlast));

    // Shifter
    logic               data_in_q_valid;
    logic [DATA_WD-1:0] data_in_q;
    logic [$clog2(ADDR_WD/8):0] data_shift_bytes;
    logic [$clog2(ADDR_WD/8):0] data_shift_bytes_reg;

    wire  wr_delay = wr_req_data_offset > wr_req_addr[$clog2(ADDR_WD/8)-1:0]; // TODO: reg
    logic wr_delay_reg;
    wire  wr_delay_all = !wr_req_blocking ? wr_delay : wr_delay_reg;
    logic wr_delay_done;

    assign data_shift_bytes[$clog2(ADDR_WD/8)]     = data_shift_bytes[$clog2(ADDR_WD/8)-1:0] == 0;
    assign data_shift_bytes[$clog2(ADDR_WD/8)-1:0] = wr_req_data_offset - wr_req_addr[$clog2(ADDR_WD/8)-1:0];

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            data_in_q_valid <= 0;
            data_in_q <= 'x;
        end else begin
            if (data_in_valid && data_in_ready) begin
                data_in_q_valid <= 1;
            end else if (m_axi_wvalid && m_axi_wready) begin
                data_in_q_valid <= data_in_valid;
            end
            if (data_in_valid && data_in_ready) begin
                data_in_q <= data_in;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_shift_bytes_reg <= 'x;
        end else begin
            if (wr_req_valid && !wr_req_blocking) begin
                data_shift_bytes_reg <= data_shift_bytes;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_delay_reg <= 0;
        end else begin
            if (wr_req_valid && !wr_req_blocking) begin
                wr_delay_reg <= wr_delay;
            end
        end
    end

    always_comb begin
        data_in_ready = /*wr_req_valid && !wr_req_blocking*/ m_axi_wready;
        if (!wr_active || m_axi_wvalid && m_axi_wlast && (m_axi_awvalid && !m_axi_awready)) begin
            data_in_ready = 0;
        end
        if (wr_req_valid && wr_req_ready)
            data_in_ready = 1;
    end

    // AXI write address
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            m_axi_awvalid <= 0;
            m_axi_awlen <= 'x;
        end else begin
            if (wr_req_valid && wr_req_ready) begin
                m_axi_awvalid <= 1;
                m_axi_awaddr  <= wr_req_addr;
                m_axi_awlen   <= wr_req_len;
                m_axi_awsize  <= wr_req_size;
                m_axi_awburst <= wr_req_burst;
            end else if (m_axi_awready) begin
                m_axi_awvalid <= 0;
            end
        end
    end

    // AXI write

    logic [$clog2(MAX_BURST_BYTES)-1:0] wr_counter;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            wr_counter <= 'x;
        end else begin
            if (wr_req_valid && wr_req_ready) begin
                wr_counter <= wr_req_len;
            end else if (m_axi_wvalid && m_axi_wready && !m_axi_wlast) begin
                wr_counter <= wr_counter - 1;
            end
        end
    end

    logic wr_waiting_data = 0; // waiting data_in

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_waiting_data <= 0;
        end else begin
            if (wr_req_valid && wr_req_ready || wr_waiting_data) begin
                wr_waiting_data <= !(data_in_valid && (wr_delay_all ? data_in_q_valid : 1));
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wvalid <= 0;
        end else begin
            if (wr_req_valid && wr_req_ready || wr_waiting_data) begin
                m_axi_wvalid <= data_in_valid && (wr_delay_all ? data_in_q_valid : 1);
            end else if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_wvalid <= 0;
            end else if (wr_active) begin
                m_axi_wvalid <= data_in_valid;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wstrb <= 'x;
        end else begin
            // if (wr_start) begin
            //     m_axi_wstrb <= (1 << (ADDR_WD / 8)) - (1 << wr_req_addr[$clog2(ADDR_WD / 8)-1:0]);
            // end else if (m_axi_wvalid && m_axi_wready) begin
            //     m_axi_wstrb <= '1; // TODO: dst_addr + len is not aligned
            //     // wr_counter == 1
            // end
            m_axi_wstrb <= '1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            m_axi_wlast <= 0;
        end else begin
            if (wr_req_valid && wr_req_ready) begin
                m_axi_wlast <= wr_req_len == 0;
            end else if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wlast <= wr_counter == 1;
            end
        end
    end
    always_ff @(posedge clk) begin
        if (data_in_valid && data_in_ready) begin
            m_axi_wdata <= {data_in, data_in_q} >> ({3'b0, data_shift_bytes_reg} << 3);
        end
    end

endmodule : dmac_write_initiator
