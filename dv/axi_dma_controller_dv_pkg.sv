`timescale 1ns/1ps

package axi_dma_controller_dv_pkg;

    class cmd_item # (
        parameter int ADDR_WD = 32
    );
        logic [ADDR_WD-1:0]     src_addr; // input
        logic [ADDR_WD-1:0]     dst_addr; // input
        logic [1:0]             burst;    // input
        logic [ADDR_WD-1:0]     len;      // input
        logic [2:0]             size;     // input
    endclass : cmd_item

    class cmd_if_driver # (
        parameter int ADDR_WD = 32
    );
        typedef cmd_item#(ADDR_WD) cmd_item_t;

        virtual axi_dma_controller_cmd_if#(ADDR_WD) cmd_if;
        mailbox #(cmd_item_t) mon_mbx_out;

        function new(virtual axi_dma_controller_cmd_if#(ADDR_WD) cmd_if);
            this.cmd_if = cmd_if;
        endfunction : new

        task start_dma (
            input logic [ADDR_WD-1:0] src_addr,
            input logic [ADDR_WD-1:0] dst_addr,
            input logic [1:0]         burst,
            input logic [ADDR_WD-1:0] len,
            input logic [2:0]         size
        );
            cmd_item_t item = new();
            item.src_addr = src_addr;
            item.dst_addr = dst_addr;
            item.burst = burst;
            item.len = len;
            item.size = size;
            drive_cmd_if(item);
            mon_mbx_out.put(item);
        endtask : start_dma
        
        task drive_cmd_if (input cmd_item_t item);
            cmd_if.valid <= 1;
            cmd_if.src_addr <= item.src_addr;
            cmd_if.dst_addr <= item.dst_addr;
            cmd_if.burst <= item.burst;
            cmd_if.len <= item.len;
            cmd_if.size <= item.size;
            @(posedge cmd_if.clk iff cmd_if.ready);

            cmd_if.valid <= 0;
        endtask : drive_cmd_if

    endclass : cmd_if_driver

    class axi4_item # (
        parameter int ADDR_WD = 32,
        parameter int DATA_WD = 32
    );
        int                     req_time;
        logic                   is_read;
        logic [ADDR_WD-1:0]     address;
        logic [1:0]             burst;
        logic [2:0]             size;
        logic [7:0]             trans;
        int                     length; // bytes
        int                     data_offset; // bytes
        byte                    data[];
        logic [ADDR_WD/8-1:0]   strb[];
    endclass : axi4_item

    class axi4_wr_responder # (
        parameter int ADDR_WD = 32,
        parameter int DATA_WD = 32
    );
        typedef axi4_item#(ADDR_WD, DATA_WD) item_t;

        local int cycle = 0;

        virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if;

        int awready_throttling = 0;
        int wready_throttling = 0;

        mailbox #(item_t) mon_mbx_out;
        item_t wr_queue[$];
        int wr_queue_base = 0;
        int wr_queue_wptr = 0;
        int wr_queue_awptr = 0;

        function new(virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if);
            this.axi_if = axi_if;
        endfunction : new

        task automatic drive();
            axi_if.awready = 0;
            axi_if.wready = 1;
            axi_if.bvalid = 0;
            //
            @(posedge axi_if.clk iff axi_if.rst);
            fork
                drive_aw_channel();
                drive_w_channel();
                drive_b_channel();
                forever begin
                    @(posedge axi_if.clk);
                    cycle++;
                end
            join
        endtask : drive

        function item_t get_trans_item(input bit is_aw_channel);
            item_t item;
            int ptr = is_aw_channel ? wr_queue_awptr : wr_queue_wptr;
            if (ptr - wr_queue_base >= wr_queue.size()) begin
                item = new();
                item.data = new [256 * ADDR_WD / 8];
                item.strb = new [256];
                wr_queue.push_back(item);
            end else begin
                item = wr_queue[ptr - wr_queue_base];
            end
            return item;
        endfunction : get_trans_item

        function void incr_wr_queue_ptr(input bit is_aw_channel);
            if (is_aw_channel) wr_queue_awptr++;
            else wr_queue_wptr++;
        endfunction : incr_wr_queue_ptr

        local task automatic drive_aw_channel();
            item_t axi_item;
            forever begin
                // @(posedge axi_if.clk iff axi_if.awvalid)
                if (!axi_if.awvalid) @(posedge axi_if.clk iff axi_if.awvalid);
                repeat ($urandom_range(0, awready_throttling)) @(posedge axi_if.clk);
                axi_item = get_trans_item(1);

                axi_if.awready <= 1;
                @(posedge axi_if.clk);

                axi_item.req_time = cycle;
                axi_item.is_read = 0;
                axi_item.address = axi_if.awaddr;
                axi_item.burst = axi_if.awburst;
                axi_item.size = axi_if.awsize;
                axi_item.trans = axi_if.awlen + 1;
                axi_item.data_offset = axi_item.address & ((1 << axi_item.size) - 1);
                // axi_item.data = new [axi_item.trans * (1 << axi_item.size)];
                axi_item.length = axi_item.trans * (1 << axi_item.size) - axi_item.data_offset; // bytes
                // $info("axi_item.data_offset = ", axi_item.data_offset, ", length = ", axi_item.length);
                // rd_queue.push_back(axi_item);
                axi_if.awready <= 0;
                // $info("aw done");
                incr_wr_queue_ptr(1);

                @(posedge axi_if.clk); // wait awvalid
            end
        endtask : drive_aw_channel

        local task automatic drive_w_channel();
            item_t axi_item;
            int data_ptr;

            forever begin
                axi_item = get_trans_item(0);

                data_ptr = 0;
                for (int i = 0; i < 256; i++) begin
                    axi_if.wready <= 0;
                    repeat ($urandom_range(0, wready_throttling)) @(posedge axi_if.clk);
                    axi_if.wready <= 1;

                    @(posedge axi_if.clk iff axi_if.wvalid && axi_if.wready);

                    for (int j = 0; j < DATA_WD / 8; j++) begin
                        axi_item.data[data_ptr] = axi_if.wdata >> (j * 8);
                        axi_item.strb[i] = axi_if.wstrb;
                        data_ptr++;
                    end
                    if (axi_if.wlast) break;
                    if (i == 255) $error("Burst too long");
                end
                // $info("w done");
                incr_wr_queue_ptr(0);
            end
        endtask : drive_w_channel

        local task automatic drive_b_channel();
            item_t axi_item;
            forever begin
                #1step;
                if (wr_queue_wptr - wr_queue_base == 0 || wr_queue_awptr - wr_queue_base == 0) begin
                    @(posedge axi_if.clk);
                    continue;
                end
                wr_queue_base++;
                axi_item = wr_queue.pop_front();

                axi_if.bvalid <= 1;
                axi_if.bresp  <= axi4_pkg::OKAY;
                @(posedge axi_if.clk iff axi_if.bready);
                axi_if.bvalid <= 0;
                // $info("b done");
                mon_mbx_out.put(axi_item);
            end
        endtask : drive_b_channel

    endclass : axi4_wr_responder


    class axi4_rd_responder # (
        parameter int ADDR_WD = 32,
        parameter int DATA_WD = 32
    );
        typedef axi4_item#(ADDR_WD, DATA_WD) item_t;

        local int cycle = 0;

        bit random_data = 1;
        int max_outstanding = 4;

        int arready_throttling = 0;
        int rvalid_throttling = 0;
        int resp_delay_latency_min = 0;
        int resp_delay_latency_max = 0;

        virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if;

        mailbox #(item_t) mon_mbx_out;
        item_t rd_queue[$];

        function new(virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if);
            this.axi_if = axi_if;
        endfunction : new

        task automatic drive();
            //
            axi_if.arready = 0;
            axi_if.rvalid = 0;
            @(posedge axi_if.clk iff axi_if.rst);
            fork
                drive_ar_channel();
                drive_r_channel();
                forever begin
                    @(posedge axi_if.clk);
                    cycle++;
                end
            join
        endtask : drive

        local task automatic drive_ar_channel();
            item_t axi_item;

            forever begin
                forever begin
                    if (rd_queue.size() >= max_outstanding) begin
                        axi_if.arready <= 0;
                        @(posedge axi_if.clk);
                    end else begin
                        axi_if.arready <= 1;
                        break;
                    end
                end
                @(posedge axi_if.clk iff axi_if.arvalid);

                // $info("asserted");
                axi_item = new;
                axi_item.req_time = cycle;
                axi_item.is_read = 1;
                axi_item.address = axi_if.araddr;
                axi_item.burst = axi_if.arburst;
                axi_item.size = axi_if.arsize;
                axi_item.trans = axi_if.arlen + 1;
                axi_item.data_offset = axi_item.address & ((1 << axi_item.size) - 1);
                axi_item.data = new [axi_item.trans * (1 << axi_item.size)];
                axi_item.length = axi_item.trans * (1 << axi_item.size) - axi_item.data_offset; // bytes
                // $info("axi_item.data_offset = ", axi_item.data_offset, ", length = ", axi_item.length);
                rd_queue.push_back(axi_item);
                // $info("enqueue");
                axi_if.arready <= 0;
                repeat ($urandom_range(0, arready_throttling)) @(posedge axi_if.clk);
            end
        endtask : drive_ar_channel

        local task automatic drive_r_channel();
            item_t axi_item;
            int resp_latency;
            forever begin
                if (rd_queue.size() == 0) begin
                    @(posedge axi_if.clk);
                    continue;
                end
                axi_item = rd_queue[0];
                // $info("peek");
                resp_latency = $urandom_range(resp_delay_latency_min, resp_delay_latency_max);

                if (cycle < axi_item.req_time + resp_latency) begin
                    repeat (axi_item.req_time + resp_latency - cycle) @(posedge axi_if.clk);
                end
                void'(rd_queue.pop_front());
                // $info("dequeue");
                // std::randomize(axi_item.data);
                foreach (axi_item.data[i]) begin
                    if (random_data) begin
                        axi_item.data[i] = $urandom();
                    end else begin
                        axi_item.data[i] = i - axi_item.data_offset;
                    end
                end
                drive_resp_pkt(axi_item); 
                // $info("rd put");
                mon_mbx_out.put(axi_item);
            end
        endtask : drive_r_channel

        local task automatic drive_resp_pkt(input item_t item);
            // int rvalid_delay;
            bit [DATA_WD-1:0] resp_data;
            int narrow_offset = (item.address % (ADDR_WD / 8)) & ((1 << item.size) - 1);
            int data_offset = item.data_offset;
            int ret_offset;
            // $info("item.trans = ", item.trans);
            // $info("narrow_offset = ", narrow_offset);
            for (int i = 0; i < item.trans; i++) begin
                if (i > 0) begin
                    axi_if.rvalid <= 0;
                    repeat ($urandom_range(0, rvalid_throttling)) @(posedge axi_if.clk);
                    axi_if.rvalid <= 1;
                end

                resp_data = 0;
                ret_offset = i == 0 ? item.data_offset : narrow_offset;
                // $info("ret_offset: ", ret_offset, "data_offset: ", data_offset);
                for (int j = 0; j < (1 << item.size)/*DATA_WD / 8*/; j++) begin
                    resp_data[(ret_offset + j)*8+:8] = item.data[data_offset];
                    data_offset++;
                end

                narrow_offset = (narrow_offset + (1 << item.size)) % (ADDR_WD / 8);

                axi_if.rvalid <= 1;
                axi_if.rdata  <= resp_data;
                axi_if.rresp  <= axi4_pkg::OKAY;
                axi_if.rlast  <= i == item.trans - 1;

                @(posedge axi_if.clk iff axi_if.rvalid && axi_if.rready);
                if (i == item.trans - 1) begin
                    axi_if.rvalid <= 0;
                end
            end
        endtask : drive_resp_pkt


    endclass : axi4_rd_responder

    class axi4_responder # (
        parameter int ADDR_WD = 32,
        parameter int DATA_WD = 32
    );
        virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if;

        axi4_wr_responder # (ADDR_WD, DATA_WD) wr_resp;
        axi4_rd_responder # (ADDR_WD, DATA_WD) rd_resp;

        function new(virtual axi_dma_controller_axi_if#(ADDR_WD, DATA_WD) axi_if);
            this.wr_resp = new (axi_if);
            this.rd_resp = new (axi_if);
            this.axi_if = axi_if;
        endfunction : new

        task automatic drive();
            fork
                wr_resp.drive();
                rd_resp.drive();
            join
        endtask : drive
    endclass : axi4_responder

    class scoreboard # (
        parameter int ADDR_WD = 32,
        parameter int DATA_WD = 32
    );
        typedef axi4_item#(ADDR_WD, DATA_WD) axi_item_t;
        typedef cmd_item#(ADDR_WD) cmd_item_t;

        mailbox #(cmd_item_t) cmd_mbx;
        mailbox #(axi_item_t) axi_rd_mbx;
        mailbox #(axi_item_t) axi_wr_mbx;

        int max_burst_len = 0;

        function new();
        endfunction : new

        task automatic run();
            cmd_item_t cmd_item;
            forever begin
                cmd_mbx.get(cmd_item);
                check_cmd(cmd_item);
                // $info("cmd check done");
            end
        endtask : run

        task automatic check_cmd(input cmd_item_t cmd_item);
            int cmd_len = cmd_item.len;
            bit [ADDR_WD-1:0] src_ptr = cmd_item.src_addr;
            bit [ADDR_WD-1:0] dst_ptr = cmd_item.dst_addr;
            int rd_remaining_len = cmd_len;
            int wr_remaining_len = cmd_len;
            byte rdata_buf[] = new [cmd_len];
            int rd_buf_ptr = 0;
            axi_item_t axi_item;

            while (rd_remaining_len > 0) begin
                axi_rd_mbx.get(axi_item);
                check_burst_common(src_ptr, rd_remaining_len, cmd_item, axi_item);
                for (int i = axi_item.data_offset; i < axi_item.length; i++) begin
                    rdata_buf[rd_buf_ptr] = axi_item.data[i];
                    rd_buf_ptr++; // TODO: unaligned
                end
            end
            rd_buf_ptr = 0;
            while (wr_remaining_len > 0) begin
                int err_count = 0;
                axi_wr_mbx.get(axi_item);
                check_burst_common(dst_ptr, wr_remaining_len, cmd_item, axi_item);
                for (int i = axi_item.data_offset; i < axi_item.length; i++) begin
                    if (err_count < 4) begin
                        assert (rdata_buf[rd_buf_ptr] == axi_item.data[i]) else begin
                            $error("Write data mismatch (sa: 0x%08x, 0x%02x, da: 0x%08x, 0x%02x)",
                                cmd_item.src_addr + rd_buf_ptr, rdata_buf[rd_buf_ptr],
                                cmd_item.dst_addr + rd_buf_ptr, axi_item.data[i]);
                            err_count++;
                        end
                    end
                    rd_buf_ptr++; // TODO: unaligned
                end
                // strb
            end
        endtask : check_cmd

        function automatic void check_burst_common (
            inout bit [ADDR_WD-1:0] addr_ptr, int remaining_len,
            input cmd_item_t cmd_item, axi_item_t axi_item
        );
            int max_burst_bytes = max_burst_len * (ADDR_WD / 8);
            int burst_bits = $clog2(max_burst_bytes);

            int aligned_len_bytes = (1 << burst_bits) - (addr_ptr & ((1 << burst_bits) - 1));
            int expected_burst_len_bytes = aligned_len_bytes > remaining_len ? remaining_len : aligned_len_bytes;

            bit [ADDR_WD-1:0] aligned_req_addr = addr_ptr & ~((1 << cmd_item.size) - 1);
            bit [ADDR_WD-1:0] burst_len_trans = (addr_ptr + expected_burst_len_bytes + ((1 << cmd_item.size) - 1) - aligned_req_addr) >> cmd_item.size;

            assert (axi_item.address == addr_ptr)      else $error("addr 0x%08x: unexpected a%saddr, expected: 0x%0x",  axi_item.address, axi_item.is_read ? "r" : "w", axi_item.is_read ? cmd_item.src_addr : cmd_item.dst_addr);
            assert (axi_item.burst == cmd_item.burst)  else $error("addr 0x%08x: unexpected a%sburst, expected: 0x%0x", axi_item.address, axi_item.is_read ? "r" : "w", cmd_item.burst);
            assert (axi_item.size == cmd_item.size)    else $error("addr 0x%08x: unexpected a%ssize, expected: 0x%0x",  axi_item.address, axi_item.is_read ? "r" : "w", cmd_item.size);
            assert (axi_item.trans == burst_len_trans) else $error("addr 0x%08x: unexpected a%slen, expected: 0x%0x",   axi_item.address, axi_item.is_read ? "r" : "w", burst_len_trans - 1);

            addr_ptr += aligned_len_bytes;
            remaining_len -= expected_burst_len_bytes;
        endfunction : check_burst_common
    endclass : scoreboard

endpackage : axi_dma_controller_dv_pkg
