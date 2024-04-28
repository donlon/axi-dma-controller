module dmac_read_req_gen # (
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

    output logic                        rd_req_valid,
    input                               rd_req_ready,
    output [ADDR_WD-1:0]                rd_req_addr,
    output [axi4_pkg::BURST_BITS-1:0]   rd_req_burst,
    output [axi4_pkg::LEN_BITS-1:0]     rd_req_len,
    output [axi4_pkg::SIZE_BITS-1:0]    rd_req_size,

    output                              cmd_out_valid,
    input                               cmd_out_ready,
    output [$clog2(ADDR_WD/8)-1:0]      cmd_out_src_offset,
    output [ADDR_WD-1:0]                cmd_out_dst_addr,
    output [1:0]                        cmd_out_burst,
    output [ADDR_WD-1:0]                cmd_out_len,
    output [2:0]                        cmd_out_size
);

    logic cmd_blocking;
    logic rd_req_fired;
    logic cmd_out_fired;

    logic [ADDR_WD-1:0] next_addr;
    logic [ADDR_WD-1:0] next_length;
    logic [axi4_pkg::LEN_BITS-1:0] burst_len;
    logic               req_last;

    logic [ADDR_WD-1:0]                 rd_req_addr_reg;
    logic [ADDR_WD-1:0]                 rd_req_length_reg;
    logic [axi4_pkg::BURST_BITS-1:0]    rd_req_burst_reg;
    // logic [2:0]                         rd_req_len_reg;
    logic [axi4_pkg::SIZE_BITS-1:0]     rd_req_size_reg;
    logic                               rd_req_last;

    dmac_addr_gen # (
        .ADDR_WD(ADDR_WD),
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_addr_gen (
        .req_addr(rd_req_addr_reg),
        .req_length(rd_req_length_reg),
        .req_size(rd_req_size_reg),
        .next_addr,
        .next_length,
        .burst_len,
        .req_last
    );

    assign cmd_ready = ((rd_req_ready && rd_req_last) || !rd_req_valid) && cmd_out_ready;

    /// read req

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_blocking <= 0;
        end else begin
            if (cmd_valid && !cmd_ready) begin
                cmd_blocking <= 1;
            end else if (cmd_ready) begin
                cmd_blocking <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_req_fired <= 0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                rd_req_fired <= 0;
            end else if (rd_req_valid && rd_req_ready) begin
                rd_req_fired <= 1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_req_addr_reg <= 'x;
            rd_req_length_reg <= 'x;
            rd_req_burst_reg <= 'x;
            rd_req_size_reg <= 'x;
            // rd_req_last <= 0;
        end else begin
            // if (cmd_valid && !rd_req_valid) begin
            // if (cmd_valid && !cmd_blocking) begin // load
            if (cmd_valid && cmd_ready || cmd_valid && !rd_req_valid/* && !cmd_blocking*/) begin
                rd_req_addr_reg   <= cmd_src_addr;
                rd_req_length_reg <= cmd_len;
                rd_req_burst_reg  <= cmd_burst;
                rd_req_size_reg   <= cmd_size;
                // rd_req_last       <= req_last;
            end else if (rd_req_valid && rd_req_ready) begin // next
                rd_req_addr_reg   <= next_addr;
                rd_req_length_reg <= next_length;
                // rd_req_last       <= req_last;
            end
        end
    end
    assign rd_req_last = req_last;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_req_valid <= 0;
        end else begin
            if (cmd_valid)
                rd_req_valid <= 1;
            else if (rd_req_valid /*rm*/&& rd_req_ready && rd_req_last)
                rd_req_valid <= 0;
        end
    end

    assign rd_req_addr  = rd_req_addr_reg;
    assign rd_req_burst = rd_req_burst_reg;
    assign rd_req_len   = burst_len;
    assign rd_req_size  = rd_req_size_reg;

    /// cmd out

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_out_fired <= 0;
        end else begin
            if (cmd_valid && cmd_ready)
                cmd_out_fired <= 0;
            else if (cmd_out_valid && cmd_out_ready)
                cmd_out_fired <= 1;
        end
    end

    assign cmd_out_valid = cmd_valid && !cmd_out_fired;
    assign cmd_out_src_offset = cmd_src_addr[$clog2(ADDR_WD/8)-1:0];
    assign cmd_out_dst_addr = cmd_dst_addr;
    assign cmd_out_burst = cmd_burst;
    assign cmd_out_len = cmd_len;
    assign cmd_out_size = cmd_size;

endmodule : dmac_read_req_gen
