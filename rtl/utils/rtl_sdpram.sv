///< Simple dual-port RAM
module rtl_sdpram # (
    parameter AWIDTH = 16,
    parameter DWIDTH = 64,
    parameter RAM_STYLE = "auto",
    parameter DOUTB_PIPELINE = 1
) (
    // Port A, wo
    input                   clka,
    input                   ena,
    input  [AWIDTH-1:0]     addra,
    input  [DWIDTH-1:0]     dina,

    // Port B, ro
    input                   clkb,
    input                   enb,
    input  [AWIDTH-1:0]     addrb,
    output [DWIDTH-1:0]     doutb
);
    localparam CASCADE_HEIGHT = 5;

    logic [DWIDTH-1:0]  doutb_int;
    logic [DWIDTH-1:0]  doutb_o;
    (* ram_style = RAM_STYLE, cascade_height = CASCADE_HEIGHT *)
    logic [DWIDTH-1:0]  memory[2**AWIDTH];

    always_ff @(posedge clka) begin
        if (ena)
            memory[addra] <= dina;
    end

    always_ff @(posedge clkb) begin
        if (enb)
            doutb_int <= memory[addrb];
    end

    if (DOUTB_PIPELINE) begin : gen_doutb_pipeline

        always_ff @(posedge clkb) begin
            doutb_o <= doutb_int;
        end    

    end else begin : gen_doutb_nopipeline

        assign doutb_o = doutb_int;

    end

    assign doutb = doutb_o;
    
endmodule : rtl_sdpram
