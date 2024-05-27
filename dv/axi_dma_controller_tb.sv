`timescale 1ns/1ps

module axi_dma_controller_tb # (
    parameter int ADDR_WD = 32,
    parameter int DATA_WD = 32,
    parameter int CHANNEL_COUNT = 8, /// 8 channels
    parameter int MAX_BURST_LEN = 16 /// 16 beats
);
    import axi_dma_controller_dv_pkg::*;

    localparam integer STRB_WD = DATA_WD / 8;
    localparam integer ADDR_WD_BYTES = DATA_WD / 8;

    logic clk = 0; // input
    logic rst = 1; // input

    axi_dma_controller_cmd_if # (
        .ADDR_WD(32)
    ) cmd_if (
        .clk, .rst
    );

    axi_dma_controller_axi_if # (
        .ADDR_WD(32),
        .DATA_WD(32)
    ) axi_if (
        .clk, .rst
    );

    cmd_if_driver  # (.ADDR_WD(ADDR_WD)) cmd_if_drv = new (cmd_if);
    axi4_responder # (.ADDR_WD(ADDR_WD), .DATA_WD(DATA_WD)) axi4_resp = new(axi_if);
    scoreboard # (.ADDR_WD(ADDR_WD), .DATA_WD(DATA_WD)) scb = new();

    axi_dma_controller
`ifndef CHISEL_MODULE
    #(
        .ADDR_WD(ADDR_WD),
        .DATA_WD(DATA_WD),
        .CHANNEL_COUNT(CHANNEL_COUNT), /// 8 channels
        .MAX_BURST_LEN(MAX_BURST_LEN) /// 16 beats
    )
`endif
    dut (
        .clk,
        .rst,
        // DMA Command
        .cmd_valid    (cmd_if.valid),
        .cmd_src_addr (cmd_if.src_addr),
        .cmd_dst_addr (cmd_if.dst_addr),
        .cmd_burst    (cmd_if.burst),
        .cmd_len      (cmd_if.len),
        .cmd_size     (cmd_if.size),
        .cmd_ready    (cmd_if.ready),
        // Read Address Channel
        .M_AXI_ARVALID(axi_if.arvalid),
        .M_AXI_ARADDR (axi_if.araddr),
        .M_AXI_ARLEN  (axi_if.arlen),
        .M_AXI_ARSIZE (axi_if.arsize),
        .M_AXI_ARBURST(axi_if.arburst),
        .M_AXI_ARREADY(axi_if.arready),
        // Read Response Channel
        .M_AXI_RVALID (axi_if.rvalid),
        .M_AXI_RDATA  (axi_if.rdata),
        .M_AXI_RRESP  (axi_if.rresp),
        .M_AXI_RLAST  (axi_if.rlast),
        .M_AXI_RREADY (axi_if.rready),
        // Write Address Channel
        .M_AXI_AWVALID(axi_if.awvalid),
        .M_AXI_AWADDR (axi_if.awaddr),
        .M_AXI_AWLEN  (axi_if.awlen),
        .M_AXI_AWSIZE (axi_if.awsize),
        .M_AXI_AWBURST(axi_if.awburst),
        .M_AXI_AWREADY(axi_if.awready),
        // Write Data Channel
        .M_AXI_WVALID (axi_if.wvalid),
        .M_AXI_WDATA  (axi_if.wdata),
        .M_AXI_WSTRB  (axi_if.wstrb),
        .M_AXI_WLAST  (axi_if.wlast),
        .M_AXI_WREADY (axi_if.wready),
        // Write Response Channel
        .M_AXI_BVALID (axi_if.bvalid),
        .M_AXI_BRESP  (axi_if.bresp),
        .M_AXI_BREADY (axi_if.bready)
    );

    initial forever #0.5ns clk = !clk;

    initial begin
        #20ns;
        @(posedge clk);
        rst <= 0;
    end

    initial begin
        cmd_if.valid = 0;
        scb.max_burst_len = MAX_BURST_LEN;
        scb.cmd_mbx = new;
        scb.axi_rd_mbx = new;
        scb.axi_wr_mbx = new;
        cmd_if_drv.mon_mbx_out = scb.cmd_mbx;
        axi4_resp.rd_resp.mon_mbx_out = scb.axi_rd_mbx;
        axi4_resp.wr_resp.mon_mbx_out = scb.axi_wr_mbx;

        axi4_resp.rd_resp.random_data = 0;
        fork
            // cmd_if_drv.drive();
            axi4_resp.drive();
            scb.run();
        join
    end

    task automatic send_aligned_cmd(input int max_size);
        int src_addr;
        int dst_addr;
        int len;
        void'(std::randomize(src_addr, dst_addr, len) with {
            src_addr % ADDR_WD_BYTES == 0;
            dst_addr % ADDR_WD_BYTES == 0;
            len > 0 && len < max_size && len % ADDR_WD_BYTES == 0;
        });
        cmd_if_drv.start_dma (
            .src_addr(src_addr),
            .dst_addr(dst_addr),
            .burst(axi4_pkg::INCR),
            .len(len),
            .size($clog2(ADDR_WD_BYTES))
        );
    endtask : send_aligned_cmd

    task automatic test_all();
        axi4_resp.rd_resp.max_outstanding = 10;
        repeat (20) begin
            send_aligned_cmd(ADDR_WD_BYTES + 1);
            // repeat ($urandom_range(0, $urandom_range(0, 9) > 8 ? 60 : 0)) @(posedge clk);
        end
        #20ns;
        @(posedge clk);
        test_aligned_throttling();
        #20ns;
        @(posedge clk);
        test_unaligned();
    endtask : test_all

    task automatic test_demo();
        axi4_resp.rd_resp.max_outstanding = 10;
        repeat (20) begin
            send_aligned_cmd(ADDR_WD_BYTES * 3 + 1);
            // repeat ($urandom_range(0, $urandom_range(0, 9) > 8 ? 60 : 0)) @(posedge clk);
        end
        #20ns;
    endtask : test_demo

    task automatic test_aligned();
        repeat (40) send_aligned_cmd(ADDR_WD_BYTES * 3);
        repeat (40) send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES);
        repeat (20) begin // Fill FIFO
            send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 2);
            repeat ($urandom_range(0, MAX_BURST_LEN)) @(posedge clk);
        end
        repeat (20) begin // Drain FIFO
            send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 2);
            repeat ($urandom_range(MAX_BURST_LEN, MAX_BURST_LEN * 4)) @(posedge clk);
        end
        repeat (100) send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 4);
    endtask : test_aligned

    task automatic test_aligned_throttling();
        axi4_resp.rd_resp.max_outstanding = 3;
        // Read throttling
        axi4_resp.rd_resp.arready_throttling = 5;
        axi4_resp.rd_resp.rvalid_throttling  = 0;
        axi4_resp.rd_resp.resp_delay_latency_min = 0;
        axi4_resp.rd_resp.resp_delay_latency_max = 20;
        axi4_resp.wr_resp.awready_throttling = 0;
        axi4_resp.wr_resp.wready_throttling  = 0;
        repeat (20) send_aligned_cmd(ADDR_WD_BYTES * 3);
        repeat (40) send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 4);
        // Write throttling
        axi4_resp.rd_resp.arready_throttling = 4;
        axi4_resp.rd_resp.rvalid_throttling  = 4;
        axi4_resp.rd_resp.resp_delay_latency_min = 0;
        axi4_resp.rd_resp.resp_delay_latency_max = 5;
        axi4_resp.wr_resp.awready_throttling = 7;
        axi4_resp.wr_resp.wready_throttling  = 7;
        repeat (40) send_aligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 4);
    endtask : test_aligned_throttling

    task automatic send_narrow_cmd(input int max_size);
        int src_addr;
        int dst_addr;
        int len;
        int size;
        void'(std::randomize(src_addr, dst_addr, len) with {
            0 <= size && size < $clog2(ADDR_WD_BYTES);
            src_addr % (1 << size) == 0;
            dst_addr % (1 << size) == 0;
            len > 0 && len < max_size && len % (1 << size) == 0;
        });
        cmd_if_drv.start_dma (
            .src_addr(src_addr),
            .dst_addr(dst_addr),
            .burst(axi4_pkg::INCR),
            .len(len),
            .size(size)
        );
    endtask : send_narrow_cmd

    task automatic test_narrow();
        // repeat (10) send_narrow_cmd(MAX_BURST_LEN);
        // repeat (20) begin
        //     send_narrow_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 2);
        //     repeat ($urandom_range(10, 60)) @(posedge clk);
        // end
        repeat (20) send_narrow_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 2);
    endtask : test_narrow

    task automatic send_unaligned_cmd(input int max_size);
        int src_addr;
        int dst_addr;
        int len;
        void'(std::randomize(src_addr, dst_addr, len) with {
            len > 0 && len < max_size
                && len % ADDR_WD_BYTES == 0; // FIXME
        });
        cmd_if_drv.start_dma (
            .src_addr(src_addr),
            .dst_addr(dst_addr),
            .burst(axi4_pkg::INCR),
            .len(len),
            .size($clog2(ADDR_WD_BYTES))
        );
    endtask : send_unaligned_cmd

    task automatic test_unaligned();
        // repeat (10) send_unaligned_cmd(MAX_BURST_LEN);
        repeat (20) begin
            send_unaligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 2);
            repeat ($urandom_range(10, 60)) @(posedge clk);
        end
        repeat (20) send_unaligned_cmd(MAX_BURST_LEN * ADDR_WD_BYTES * 4);
    endtask : test_unaligned

    initial begin
        @(posedge clk iff !rst);
        // TODO: 
        test_all();
        // test_demo();
        // test_aligned();
        // test_aligned_throttling();
        // test_narrow();
        // test_unaligned();
        // TODO: wait write request and check scoreboard
        $finish;
    end

endmodule : axi_dma_controller_tb
