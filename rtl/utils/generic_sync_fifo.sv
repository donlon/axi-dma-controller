module generic_sync_fifo # (
    parameter DWIDTH = 64,
    parameter AWIDTH = 10,
    parameter RAM_STYLE = "auto",
    parameter ALMOST_EMPTY_THRESH = 2,
    parameter ALMOST_FULL_THRESH = 2**AWIDTH-2,
    parameter EARLY_READ = 1,
    parameter OUTPUT_PIPELINE = 0
) (
    input  logic                clk,
    input  logic                rst,

    input  logic                wvalid,
    output logic                wready,
    input  logic [DWIDTH-1:0]   wdata,
    output logic                walmost_full,

    output logic                rvalid,
    input  logic                rready,
    output logic [DWIDTH-1:0]   rdata,
    output logic                ralmost_empty,

    output logic [AWIDTH:0]     data_count
);

    if (ALMOST_EMPTY_THRESH <= 0 || ALMOST_EMPTY_THRESH >= 2**AWIDTH) begin
        $error("ALMOST_EMPTY_THRESH is not valid");
    end

    if (ALMOST_FULL_THRESH <= 0 || ALMOST_FULL_THRESH >= 2**AWIDTH) begin
        $error("ALMOST_FULL_THRESH is not valid");
    end

    logic                       mem_wen;
    logic [AWIDTH:0]            mem_waddr;
    logic [AWIDTH:0]            mem_waddr_next;
    logic                       mem_ren;
    logic [AWIDTH:0]            mem_raddr;
    logic [AWIDTH:0]            mem_raddr_next;

    rtl_sdpram # (
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .RAM_STYLE(RAM_STYLE),
        .DOUTB_PIPELINE(0)
    ) i_ram (
        // Port A, wo
        .clka(clk),
        .ena(mem_wen),
        .addra(mem_waddr[AWIDTH-1:0]),
        .dina(wdata),
        // Port B, ro
        .clkb(clk),
        .enb(EARLY_READ ? 1'b1 : mem_ren),
        .addrb(EARLY_READ ? mem_raddr_next[AWIDTH-1:0] : mem_raddr[AWIDTH-1:0]),
        .doutb(rdata)
    );

    // write control
    logic                       wfull;
    assign                      wready = !wfull;
    assign                      mem_wen = wvalid && wready;
    assign                      mem_waddr_next = mem_wen ? mem_waddr + 1'b1 : mem_waddr;

    // read control
    logic                       rempty;
if (EARLY_READ) begin
    assign                      rvalid = !rempty;
    assign                      mem_ren = rvalid && rready;
end else begin
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rvalid <= 0;
        end else begin
            if (mem_ren) begin
                rvalid <= 1;
            end else if (rready) begin
                rvalid <= 0;
            end
        end
    end
    assign                      mem_ren = !rempty && !(rvalid && !rready);
end
    assign                      mem_raddr_next = mem_ren ? mem_raddr + 1'b1 : mem_raddr;

    assign                      data_count = mem_waddr - mem_raddr;

    // Write-full generate
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wfull <= 1;
            walmost_full <= 1;
        end else begin
            // TODO: support generating wfull with comb. logic for lower laterncy
            wfull <= {~mem_waddr_next[AWIDTH], mem_waddr_next[AWIDTH-1:0]} == mem_raddr;
            walmost_full <= data_count >= ALMOST_FULL_THRESH; // TODO: does this work correctly if clks' freq. diff. is too large?
        end
    end

    // Read-empty generate
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rempty <= 1;
            ralmost_empty <= 1;
        end else begin
            rempty <= mem_waddr == mem_raddr_next;
            ralmost_empty <= data_count < ALMOST_EMPTY_THRESH;
        end
    end

    // R/W address control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_waddr <= '0;
            mem_raddr <= '0;
        end else begin
            if (mem_wen) begin
                mem_waddr <= mem_waddr + 1'b1;
            end

            if (mem_ren) begin
                mem_raddr <= mem_raddr + 1'b1;
            end
        end
    end

    assert_almost_empty: assert property (@(posedge clk) disable iff (rst) rempty |-> ralmost_empty);
    assert_almost_full:  assert property (@(posedge clk) disable iff (rst) wfull  |-> walmost_full);

endmodule : generic_sync_fifo
