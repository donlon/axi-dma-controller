module dmac_write_req_gen # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,

    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16, /// 16 beats

    localparam int STRB_WD = DATA_WD / 8
) (
    input                           clk,
    input                           rst,

    input                           cmd_in_valid,
    output logic                    cmd_in_ready,
    input [$clog2(ADDR_WD/8)-1:0]   cmd_in_src_offset,
    input [ADDR_WD-1:0]             cmd_in_dst_addr,
    input [1:0]                     cmd_in_burst,
    input [ADDR_WD-1:0]             cmd_in_len,
    input [2:0]                     cmd_in_size,

    output logic                        wr_req_valid,
    input                               wr_req_ready,
    output [ADDR_WD-1:0]                wr_req_addr,
    output [axi4_pkg::BURST_BITS-1:0]   wr_req_burst,
    output [axi4_pkg::LEN_BITS-1:0]     wr_req_len,
    output [$clog2(ADDR_WD/8)-1:0]      wr_req_data_offset, // src_addr %ADDR_WD_BYTES
    output [axi4_pkg::SIZE_BITS-1:0]    wr_req_size,
    output                              wr_req_last
);

    logic cmd_blocking;
    logic wr_req_fired;
    logic cmd_out_fired;

    logic [ADDR_WD-1:0] next_addr;
    logic [ADDR_WD-1:0] next_length;
    logic [axi4_pkg::LEN_BITS-1:0] burst_len;
    logic               req_last;

    logic [ADDR_WD-1:0]                 wr_req_addr_reg;
    logic [ADDR_WD-1:0]                 wr_req_length_reg;
    logic [axi4_pkg::BURST_BITS-1:0]    wr_req_burst_reg;
    // logic [2:0]                         wr_req_len_reg;
    logic [$clog2(ADDR_WD/8)-1:0]       wr_req_data_offset_reg;
    logic [axi4_pkg::SIZE_BITS-1:0]     wr_req_size_reg;
    // logic                               wr_req_last;

    dmac_addr_gen # (
        .ADDR_WD(ADDR_WD),
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    ) i_addr_gen (
        .req_addr(wr_req_addr_reg),
        .req_length(wr_req_length_reg),
        .req_size(wr_req_size_reg),
        .next_addr,
        .next_length,
        .burst_len,
        .req_last
    );

    assign cmd_in_ready = (wr_req_ready && wr_req_last) || !wr_req_valid;

    /// read req

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_blocking <= 0;
        end else begin
            if (cmd_in_valid && !cmd_in_ready) begin
                cmd_blocking <= 1;
            end else if (cmd_in_ready) begin
                cmd_blocking <= 0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_req_fired <= 0;
        end else begin
            if (cmd_in_valid && cmd_in_ready) begin
                wr_req_fired <= 0;
            end else if (wr_req_valid && wr_req_ready) begin
                wr_req_fired <= 1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_req_addr_reg <= 'x;
            wr_req_length_reg <= 'x;
            wr_req_burst_reg <= 'x;
            wr_req_data_offset_reg <= 'x;
            wr_req_size_reg <= 'x;
            // wr_req_last <= 0;
        end else begin
            if (cmd_in_valid && cmd_in_ready || cmd_in_valid && !wr_req_valid/* && !cmd_blocking*/) begin
            // if (cmd_in_valid && !cmd_blocking) begin // load
                wr_req_addr_reg   <= cmd_in_dst_addr;
                wr_req_length_reg <= cmd_in_len;
                wr_req_burst_reg  <= cmd_in_burst;
                wr_req_data_offset_reg <= cmd_in_src_offset;
                wr_req_size_reg   <= cmd_in_size;
                // wr_req_last       <= req_last;
            end else if (wr_req_valid && wr_req_ready) begin // next
                wr_req_addr_reg   <= next_addr;
                wr_req_length_reg <= next_length;
                // wr_req_last       <= req_last;
            end
        end
    end
    assign wr_req_last = req_last;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_req_valid <= 0;
        end else begin
            if (cmd_in_valid)
                wr_req_valid <= 1;
            else if (wr_req_valid /*rm*/&& wr_req_ready && wr_req_last)
                wr_req_valid <= 0;
        end
    end

    assign wr_req_addr  = wr_req_addr_reg;
    assign wr_req_burst = wr_req_burst_reg;
    assign wr_req_len   = burst_len;
    assign wr_req_data_offset = wr_req_data_offset_reg;
    assign wr_req_size  = wr_req_size_reg;

endmodule : dmac_write_req_gen
