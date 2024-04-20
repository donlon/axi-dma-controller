module axis_bits_pipeline # (
    parameter int DATA_WIDTH = 64,
    parameter string PIPELINE_MODE = "PASSTHROUGH"
) (
    input clk,
    input rst,

    input  logic in_tvalid,
    output logic in_tready,
    input  logic [DATA_WIDTH-1:0] in_databits,

    output logic out_tvalid,
    input  logic out_tready,
    output logic [DATA_WIDTH-1:0] out_databits
);

    if (PIPELINE_MODE == "PASSTHROUGH") begin : gen_pipeline_passthrough

        assign out_tvalid = in_tvalid;
        assign in_tready  = out_tready;
        assign out_databits = in_databits;

    end else if (PIPELINE_MODE == "FORWARD") begin : gen_pipeline_fwd
        // Forward pipeline only, 100% throughput

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                out_tvalid <= 0;
                out_databits <= 'x;
            end else begin
                if (in_tvalid) begin
                    out_tvalid <= 1;
                end else if (out_tready) begin
                    out_tvalid <= 0;
                end
                if (in_tvalid && in_tready) begin
                    out_databits <= in_databits;
                end
            end
        end
        assign in_tready = (out_tready || !out_tvalid) && !rst;

    end else if (PIPELINE_MODE == "BACKWARD") begin : gen_pipeline_bkw
        // Backward pipeline only, 100% throughput

        logic prefetchEnable;
        logic prefetchValid;
        logic [DATA_WIDTH-1:0] prefetchedBits;

        always_comb begin        
            if ((in_tvalid && in_tready) && !out_tready) begin
              prefetchEnable = 1;
            end else if (!(in_tvalid && in_tready) && out_tready && prefetchValid) begin
              prefetchEnable = 0;
            end else begin
              prefetchEnable = prefetchValid;
            end 
        end

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                in_tready <= 0;
                prefetchValid <= 0;
                prefetchedBits <= 'x;
            end else begin
                in_tready <= out_tready || !prefetchEnable;
                prefetchValid <= prefetchEnable;
                if (in_tvalid && in_tready) begin
                    prefetchedBits <= in_databits;
                end
            end
        end

        assign out_tvalid = in_tvalid || prefetchValid;
        assign out_databits = prefetchValid ? prefetchedBits : in_databits;

    end else if (PIPELINE_MODE == "FORWARD_BACKWARD") begin : gen_pipeline_fwd_bkw
        // Forward pipeline and backward pipeline, 100% throughput (skid buffer)

        logic [DATA_WIDTH-1:0] mem_a;
        logic [DATA_WIDTH-1:0] mem_b;

        logic [1:0] wptr;
        logic [1:0] rptr;
        logic [1:0] wptr_next;
        logic [1:0] rptr_next;

        assign out_databits = rptr[0] == 0 ? mem_a : mem_b;

        always_comb begin
            wptr_next = wptr;
            rptr_next = rptr;
            if (in_tvalid && in_tready) begin
                wptr_next = wptr + 1'b1;
            end
            if (out_tvalid && out_tready) begin
                rptr_next = rptr + 1'b1;
            end
        end

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                wptr <= 0;
                rptr <= 0;
                in_tready  <= 0;
                out_tvalid <= 0;
                mem_a <= 'x;
                mem_b <= 'x;
            end else begin
                wptr       <= wptr_next;
                rptr       <= rptr_next;
                in_tready  <= {~wptr_next[1], wptr_next[0]} != rptr_next; // not full
                out_tvalid <= wptr_next != rptr_next; // not empty
                if (wptr[0] == 0 && /*in_tvalid &&*/ in_tready)
                    mem_a <= in_databits;
                if (wptr[0] == 1 && /*in_tvalid &&*/ in_tready)
                    mem_b <= in_databits;
            end
        end

    end else begin
        $error("Configuration is not supported.");    
    end

endmodule : axis_bits_pipeline