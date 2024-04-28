module dmac_addr_gen # (
    parameter int ADDR_WD = 32,
    parameter int MAX_BURST_LEN = 16 /// 16 beats
) (
    input [ADDR_WD-1:0]             req_addr,
    input [ADDR_WD-1:0]             req_length,
    input [axi4_pkg::SIZE_BITS-1:0] req_size,

    output [ADDR_WD-1:0]            next_addr,
    output [ADDR_WD-1:0]            next_length,
    output [axi4_pkg::LEN_BITS-1:0] burst_len,
    output                          req_last
);

    // Align to MAX_BURST_LEN * (2 ** size) bytes
    wire [ADDR_WD-1:0] aligned_len_bytes = (1 << ($clog2(MAX_BURST_LEN) + req_size)) - (req_addr & ((1 << ($clog2(MAX_BURST_LEN) + req_size)) - 1));
    wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > req_length ? req_length : aligned_len_bytes;

    wire [ADDR_WD-1:0] aligned_req_addr = req_addr & ~((1 << req_size) - 1);
    // wire [ADDR_WD-1:0] burst_len_bytes = aligned_len_bytes > req_length ? req_length : aligned_len_bytes;
    wire [ADDR_WD-1:0] burst_len_trans = (req_addr + burst_len_bytes + ((1 << req_size) - 1) - aligned_req_addr) >> req_size;

    assign next_addr = req_addr + aligned_len_bytes;
    assign next_length = req_length - burst_len_bytes;
    assign req_last = next_length == 0;
    assign burst_len = burst_len_trans - 1;

endmodule : dmac_addr_gen
