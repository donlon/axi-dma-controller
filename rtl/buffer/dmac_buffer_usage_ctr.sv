module dmac_buffer_usage_ctr # (
    parameter int MAX_ELEMENTS = 16
) (
    input clk,
    input rst,

    input                               inc,
    input                               dec,
    input  [$clog2(MAX_ELEMENTS+1)-1:0] dec_count,

    output [$clog2(MAX_ELEMENTS+1)-1:0] usage
);

    logic [$clog2(MAX_ELEMENTS+1)-1:0] usage_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            usage_reg <= 0;
        end else begin
            usage_reg <= usage_reg + (dec ? -dec_count : 0) + inc;
        end
    end

    assign usage = usage_reg;

endmodule : dmac_buffer_usage_ctr
