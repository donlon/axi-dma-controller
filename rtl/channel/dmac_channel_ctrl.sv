module dmac_channel_ctrl # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    parameter int RD_MAX_OUTSTANDING = 8,

    localparam int STRB_WD = DATA_WD / 8
) (
    input clk,
    input rst,

    // DMA Command
    input                               cmd_valid,
    output logic                        cmd_ready,
    input [ADDR_WD-1:0]                 cmd_src_addr,
    input [ADDR_WD-1:0]                 cmd_dst_addr,
    input [1:0]                         cmd_burst,
    input [ADDR_WD-1:0]                 cmd_len,
    input [2:0]                         cmd_size,

    // input                               buf_burst_ready,
    input [$clog2(MAX_BURST_LEN)+1:0]   buf_usage,
  
    output                              rd_req_valid,
    input                               rd_req_ack,
    output [ADDR_WD-1:0]                rd_req_addr,
    output [axi4_pkg::BURST_BITS-1:0]   rd_req_burst,
    output [ADDR_WD-1:0]                rd_req_length,
    output [axi4_pkg::SIZE_BITS-1:0]    rd_req_size,
    input  [ADDR_WD-1:0]                rd_req_next_addr,
    input  [ADDR_WD-1:0]                rd_req_next_length,
    input                               rd_req_done,

    input                               rd_resp_valid,

    // input    wr_channel_sel
    output logic                        wr_req_valid,
    input                               wr_req_ack,
    output [ADDR_WD-1:0]                wr_req_addr,
    output [axi4_pkg::BURST_BITS-1:0]   wr_req_burst,
    output [ADDR_WD-1:0]                wr_req_length,
    output [$clog2(ADDR_WD/8)-1:0]      wr_req_data_offset, // src_addr % ADDR_WD_BYTES
    output [axi4_pkg::SIZE_BITS-1:0]    wr_req_size,
    input  [ADDR_WD-1:0]                wr_req_next_addr,
    input  [ADDR_WD-1:0]                wr_req_next_length,
    input                               wr_req_done
);

    logic               channel_active;
    logic [ADDR_WD-1:0] channel_src_addr;
    logic [ADDR_WD-1:0] channel_dst_addr;
    axi4_pkg::burst_t   channel_burst;
    axi4_pkg::size_t    channel_size;

    logic [ADDR_WD-1:0] channel_rd_ptr;
    logic [ADDR_WD-1:0] channel_rd_remaing_len;
    logic               channel_rd_req_done;
    logic [$clog2(RD_MAX_OUTSTANDING)-1:0] channel_rd_outstanding_ctr;

    logic [ADDR_WD-1:0] channel_wr_ptr;
    logic [ADDR_WD-1:0] channel_wr_remaing_len;
    logic               channel_wr_req_done;


    // wire allocate_channel = !channel_active && cmd_valid;
    wire allocate_channel = cmd_valid && cmd_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_active   <= 0;
            channel_src_addr <= 'x;
            channel_dst_addr <= 'x;
            channel_burst    <= axi4_pkg::burst_t'('x);
            channel_size     <= axi4_pkg::size_t'('x);
        end else begin
            if (allocate_channel) begin
                channel_active <= 1;
                channel_src_addr <= cmd_src_addr;
                channel_dst_addr <= cmd_dst_addr;
                channel_burst <= axi4_pkg::burst_t'(cmd_burst);
                channel_size <= axi4_pkg::size_t'(cmd_size);
            end else if (wr_req_ack && wr_req_done/*channel_wr_req_done*/) begin
                channel_active <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_ready <= 0;
        end else begin
            if (cmd_valid && cmd_ready)
                cmd_ready <= 0;
            else
            if (!channel_active)
                cmd_ready <= 1;
        end
    end

    /// Read control

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_rd_req_done <= 0;
        end else begin
            if (allocate_channel) begin
                channel_rd_req_done <= 0;
            end else if (rd_req_ack && rd_req_done) begin
                channel_rd_req_done <= 1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_rd_ptr <= 'x;
            channel_rd_remaing_len <= 'x;
        end else begin
            if (allocate_channel) begin
                channel_rd_ptr <= cmd_src_addr;
                channel_rd_remaing_len <= cmd_len;
            end else if (rd_req_ack) begin
                channel_rd_ptr <= rd_req_next_addr;
                channel_rd_remaing_len <= rd_req_next_length;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_rd_outstanding_ctr <= 0;
        end else begin
            if ((rd_req_valid && rd_req_ack) != rd_resp_valid) begin
                if (rd_resp_valid) begin
                    channel_rd_outstanding_ctr <= channel_rd_outstanding_ctr - 1;
                end else begin
                    channel_rd_outstanding_ctr <= channel_rd_outstanding_ctr + 1;
                end
            end
        end
    end

    assign rd_req_valid   = channel_active && !channel_rd_req_done && channel_rd_outstanding_ctr != '1;
    assign rd_req_addr    = channel_rd_ptr;
    assign rd_req_burst   = channel_burst;
    assign rd_req_length  = channel_rd_remaing_len;
    assign rd_req_size    = channel_size;

    /// Write control

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_wr_req_done <= 0;
        end else begin
            if (allocate_channel) begin
                channel_wr_req_done <= 0;
            end else if (wr_req_ack && wr_req_done) begin
                channel_wr_req_done <= 1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            channel_wr_ptr <= 'x;
            channel_wr_remaing_len <= 'x;
        end else begin
            if (allocate_channel) begin
                channel_wr_ptr <= cmd_dst_addr;
                channel_wr_remaing_len <= cmd_len;
            end else if (wr_req_ack) begin
                channel_wr_ptr <= wr_req_next_addr;
                channel_wr_remaing_len <= wr_req_next_length;
            end
        end
    end

    // assign wr_req_valid       = channel_active && (buf_usage >= MAX_BURST_LEN || channel_rd_req_done && channel_rd_outstanding_ctr == 0) && !channel_wr_req_done;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            wr_req_valid <= 0;
        end else begin
            // TODO: buf_usage > nex_burst_len
            if (channel_active && (buf_usage >= MAX_BURST_LEN || channel_rd_req_done && channel_rd_outstanding_ctr == 0) && !(wr_req_ack && wr_req_done || channel_wr_req_done)) begin
                wr_req_valid <= 1;
            end else if (wr_req_ack) begin
                wr_req_valid <= 0;
            end
        end
    end
    assign wr_req_addr        = channel_wr_ptr;
    assign wr_req_burst       = channel_burst;
    assign wr_req_length      = channel_wr_remaing_len;
    assign wr_req_data_offset = channel_src_addr[$clog2(ADDR_WD/8)-1:0]; // src_addr % ADDR_WD_BYTES
    assign wr_req_size        = channel_size;

endmodule : dmac_channel_ctrl
