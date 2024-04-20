package axi4_pkg;
  
    localparam LEN_BITS = 8;
    localparam SIZE_BITS = 3;
    localparam BURST_BITS = 2;
    localparam RESP_BITS = 2;
    
    typedef bit [LEN_BITS-1]    len_t;
    typedef bit [SIZE_BITS-1]   size_t;

    typedef enum logic [BURST_BITS-1:0] {
        FIXED = 0,
        INCR = 1,
        WRAP = 2
    } burst_t;

    typedef enum logic [RESP_BITS-1:0] {
        OKAY   = 0,
        EXOKAY = 1,
        SLVERR = 2,
        DECERR = 3
    } resp_t;

endpackage : axi4_pkg
