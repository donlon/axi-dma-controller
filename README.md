# AXI DMA Controller

An easy-to-use and high-performance Direct Memory Access (DMA) Controller for AXI4 bus, written in synthesizable SystemVerilog.

## Features

- **AXI4-based DMA**, which copies arbitary length of data on the memory-mapped bus from one place to another

- **Outstanding transactions**, and decoupled read & write module. Allow to perform multiple DMA transfers at the same time

- **Word-aligned burst mode transfers** (Note: unaligned transfers are not yet fully supported but will be fixed in the future)

- **Back-to-back transfers**. Guarentee to utilize 100% of bus capacity, **even when transfer length is equal to or less than the bus data width**

## Using the Core

The top module of the DMA controller core is `axi_dma_controller`, which is implemented in [axi_dma_controller.sv](rtl/axi_dma_controller.sv).

### Parameters

| Name          | Default Value | Description                                               |
|---------------|---------------|-----------------------------------------------------------|
| ADDR_WD       | 32            | Address width of the AXI bus                              |
| DATA_WD       | 32            | Data width of the AXI bus                                 |
| CHANNEL_COUNT | 8             | Unused.                                                   |
| MAX_BURST_LEN | 16            | Max burst length of each split AXI transaction, in cycles |

### Ports

- Clock and Reset Interface

| Type  | Name | Description                                                  |
|-------|------|--------------------------------------------------------------|
| input | clk  | Clock signal for the whole core                              |
| input | rst  | Asynchrounous active-high reset signal for the whole core    |

- DMA Command Interface

| Type                | Name         | Description                                                  |
|---------------------|--------------|--------------------------------------------------------------|
| input               | cmd_valid    | Command handshake signal from requester (user) side |
| output              | cmd_ready    | Command handshake signal from responder (the core) side |
| input [ADDR_WD-1:0] | cmd_src_addr | Source address of DMA transfer |
| input [ADDR_WD-1:0] | cmd_dst_addr | Destination address of DMA transfer |
| input [1:0]         | cmd_burst    | Burst type, corresponding to `M_AXI_AR/AWBURST`. Currently only `INCR` (`2'b01`) is supported |
| input [ADDR_WD-1:0] | cmd_len      | Length of DMA transfer in bytes |
| input [2:0]         | cmd_size     | Narrow transfer size used in AXI bus, corresponding to `M_AXI_AR/AWSIZE`. Keep the input to constant `$clog2(DATA_WD/8)` (i.e. `3'd2` for 32-bit width bus and `3'b3` for 64-bit) |

- AXI Bus Interface

| Type                     | Name          | Description                                                  |
|--------------------------|---------------|--------------------------------------------------------------|
| output                   | M_AXI_ARVALID |                                                              |
| input                    | M_AXI_ARREADY |                                                              |
| output [ADDR_WD-1:0]     | M_AXI_ARADDR  |                                                              |
| output [7:0]             | M_AXI_ARLEN   |                                                              |
| output [2:0]             | M_AXI_ARSIZE  |                                                              |
| output [1:0]             | M_AXI_ARBURST |                                                              |
| input                    | M_AXI_RVALID  |                                                              |
| output                   | M_AXI_RREADY  |                                                              |
| input [DATA_WD-1:0]      | M_AXI_RDATA   |                                                              |
| input [1:0]              | M_AXI_RRESP   |                                                              |
| input                    | M_AXI_RLAST   |                                                              |
| output                   | M_AXI_AWVALID |                                                              |
| input                    | M_AXI_AWREADY |                                                              |
| output [ADDR_WD-1:0]     | M_AXI_AWADDR  |                                                              |
| output [7:0]             | M_AXI_AWLEN   |                                                              |
| output [2:0]             | M_AXI_AWSIZE  |                                                              |
| output [1:0]             | M_AXI_AWBURST |                                                              |
| output                   | M_AXI_WVALID  |                                                              |
| input                    | M_AXI_WREADY  |                                                              |
| output [DATA_WD-1:0]     | M_AXI_WDATA   |                                                              |
| output [STRB_WD-1:0]     | M_AXI_WSTRB   |                                                              |
| output                   | M_AXI_WLAST   |                                                              |
| input                    | M_AXI_BVALID  |                                                              |
| output                   | M_AXI_BREADY  |                                                              |
| input [1:0]              | M_AXI_BRESP   |                                                              |

## Limitations

- Narrow transfers are not supported yet

- Unaligned transfers are not supported yet (therefore `cmd_src_addr`, `cmd_dst_addr` and `cmd_len` are required to be multiple of data width in bytes (`ADDR_WD / 8`))

- Interleaved and out-of-order transfers are not supported yet

## Simulation Results

- [example_waveform.vcd](doc/example_waveform.vcd)

