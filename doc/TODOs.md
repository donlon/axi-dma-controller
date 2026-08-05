# Known Issues and Fix Plan

Findings from a full review of `rtl/` and `dv/`. Ordered by severity.
Each entry lists the affected code, the observable symptom, the root cause, and a
fix plan (plan only — no implementation here).

Legend for priority:

- **P0** — data corruption or bus protocol violation, must fix before any use
- **P1** — silently wrong behaviour under a supported configuration
- **P2** — correctness gap only outside the documented supported range
- **P3** — hygiene, maintainability, verification coverage

---

## Issue 1 — `m_axi_wvalid` can deassert without a handshake (P0)

**Where:** `rtl/write/dmac_write_initiator.sv:180-192`

```systemverilog
end else if (wr_active) begin
    m_axi_wvalid <= data_in_valid;
end
```

### Symptom

- AXI protocol violation: `WVALID` is asserted in cycle *k+1*, `WREADY` is low, and
  `WVALID` is deasserted in cycle *k+2* before the beat was ever accepted.
  Any AXI protocol checker (or a real interconnect) will flag or hang on this.
- One data beat is popped from the buffer FIFO but never transmitted on the bus,
  so the destination memory receives shifted/garbage data from that point on.
- Because the lost word is consumed from the shared FIFO, the read stream and the
  write stream desynchronize permanently: **every subsequent DMA command is also
  corrupted**, not just the one that hit the glitch.
- `wr_counter` only decrements on real handshakes, so `WLAST` still lands on the
  correct beat index — the burst looks structurally legal and the corruption is
  silent.

### Reproduction conditions

Mid-burst (`wr_active == 1`, not the first beat), in the same cycle:

1. `m_axi_wvalid == 1` and `m_axi_wready == 0` (slave back-pressure), **and**
2. `data_in_valid == 0` (data FIFO momentarily empty).

Both are independent inputs, so the combination is reachable. Issue 2 makes it
likely rather than rare.

### Root cause

The next-state equation for `m_axi_wvalid` ignores the AXI stall rule: once
`VALID` is asserted it must be held until `READY` is seen. The `wr_active` branch
recomputes `WVALID` from the upstream valid every cycle instead of holding it.

### Fix plan

- [ ] Add the stall guard: while `m_axi_wvalid && !m_axi_wready`, `m_axi_wvalid`,
      `m_axi_wdata`, `m_axi_wstrb` and `m_axi_wlast` must all hold their values.
- [ ] Restructure the W-channel output stage as a proper handshake stage. Two
      options, pick one and apply it consistently:
      - reuse `axis_bits_pipeline` in `FORWARD` or `FORWARD_BACKWARD` mode as the
        output register for `{wdata, wstrb, wlast}`, or
      - keep the hand-rolled register but derive `data_in_ready` from
        `(!m_axi_wvalid || m_axi_wready)` instead of directly from `m_axi_wready`.
- [ ] Re-derive `data_in_ready` (`dmac_write_initiator.sv:125-132`) against the new
      structure — the three-way procedural override there is what currently makes
      the pop condition and the valid condition disagree.
- [ ] Add a concurrent assertion on the W channel:
      `m_axi_wvalid && !m_axi_wready |=> m_axi_wvalid && $stable({m_axi_wdata, m_axi_wstrb, m_axi_wlast})`.
- [ ] Add the same style of assertion on AW, AR and R for completeness.
- [ ] Add a directed test with aggressive, uncorrelated `wready` throttling and
      read-side starvation so this window is actually hit (see Issue 11).

---

## Issue 2 — Write burst starts before data is buffered; no mid-burst underrun handling (P0)

**Where:** `rtl/write/dmac_write_req_gen.sv:115-124`, `rtl/write/dmac_write_initiator.sv:170-178`

### Symptom

- `AWVALID` and the write burst are launched as soon as a command pops out of the
  command FIFO, with no check that enough read data has been buffered.
- The data FIFO therefore runs dry in the middle of a burst whenever the read side
  is slower than the write side (read latency, `arready`/`rvalid` throttling, a
  slow source slave). This is the normal case, not a corner case.
- On its own this only costs bus efficiency (`WVALID` gaps stall the slave's write
  channel and block other masters). Combined with Issue 1 it turns into data
  corruption.
- Long stalls with `AWVALID` already accepted can deadlock a slave that expects
  the write data to follow within a bounded time.

### Root cause

`wr_req_valid` is set from `cmd_in_valid` alone. The buffer-occupancy gate that
this design clearly intended exists only in the **dead** module
`rtl/channel/dmac_channel_ctrl.sv:187`:

```systemverilog
channel_active && (buf_usage >= MAX_BURST_LEN || channel_rd_req_done && channel_rd_outstanding_ctr == 0) && ...
```

That module is instantiated nowhere, so the live path has no gate at all.
Separately, `wr_waiting_data` in the initiator only updates on request-fire or
while already waiting, so it covers start-of-burst underrun only and never
re-arms mid-burst.

### Fix plan

- [ ] Expose `data_count` from the data FIFO in `rtl/buffer/dmac_buffer.sv` (it is
      currently tied off at line 76) as a `buf_usage` output.
- [ ] Plumb `buf_usage` into `dmac_write_req_gen` and gate `wr_req_valid` on
      `buf_usage >= (next burst beat count)`.
- [ ] Handle the tail case: the final burst of a command is shorter than
      `MAX_BURST_LEN`, so the gate must compare against the *actual* upcoming
      `burst_len + 1`, not a constant. `dmac_addr_gen` already computes this.
- [ ] Handle the drain case: if the read side has finished issuing and has no
      outstanding responses, release the gate regardless of occupancy so a short
      final burst is not held forever. This requires read-side completion
      tracking — see Issue 7.
- [ ] Size the data FIFO so the gate cannot deadlock: it must hold at least
      `MAX_BURST_LEN` beats. Current depth is `2**($clog2(MAX_BURST_LEN)+1)`
      entries (`dmac_buffer.sv:64`) — verify this stays true for all legal
      `MAX_BURST_LEN`, and add an elaboration-time check.
- [ ] Either revive `dmac_channel_ctrl` as the real control path or delete it and
      migrate its occupancy logic into `dmac_write_req_gen` — do not leave two
      divergent copies (see Issue 9).

---

## Issue 3 — `dmac_write.sv` hardcodes child module parameters (P1)

**Where:** `rtl/write/dmac_write.sv:80-83` and `rtl/write/dmac_write.sv:115-118`

```systemverilog
dmac_write_initiator # (.ADDR_WD(32), .DATA_WD(32), .CHANNEL_COUNT(8), .MAX_BURST_LEN(16))
dmac_write_handler   # (.ADDR_WD(32), .DATA_WD(32), .CHANNEL_COUNT(8), .MAX_BURST_LEN(16))
```

### Symptom

- The module's own `ADDR_WD` / `DATA_WD` / `CHANNEL_COUNT` / `MAX_BURST_LEN`
  parameters are ignored by both children.
- Instantiating the core with anything other than 32/32/8/16 silently truncates
  or zero-extends `m_axi_awaddr`, `m_axi_wdata` and `m_axi_wstrb` at the module
  boundary, and gives the initiator the wrong burst-splitting constant.
- Most simulators emit only a width-mismatch warning, not an error, so this fails
  quietly. Nothing in the current testbench catches it because the TB only ever
  elaborates the default configuration.
- The read side (`rtl/read/dmac_read.sv:88-93`) is correct, so the two halves of
  the core disagree about their geometry — the failure mode is a mangled write
  path against a correct read path.

### Fix plan

- [ ] Replace the four hardcoded values in both instantiations with the enclosing
      module's parameters.
- [ ] Sweep the whole `rtl/` tree for other literal parameter overrides on
      submodule instantiations.
- [ ] Add a lint rule / CI check rejecting numeric literals in submodule parameter
      overrides where a parameter of the same name exists in the parent.
- [ ] Add elaboration-time width assertions in `dmac_write_initiator` (e.g. check
      `$bits(m_axi_wdata) == DATA_WD`) so a future mismatch errors instead of
      warning.
- [ ] Add a multi-configuration elaboration smoke test (see Issue 12).

---

## Issue 4 — `ADDR_WD` used where `DATA_WD` is meant, throughout the byte-lane logic (P1)

**Where (RTL):**
`rtl/axi_dma_controller.sv:54,61` ·
`rtl/read/dmac_read.sv:24` ·
`rtl/read/dmac_read_req_gen.sv:31,169` ·
`rtl/buffer/dmac_buffer.sv:13,26,38` ·
`rtl/write/dmac_write.sv:15,50` ·
`rtl/write/dmac_write_req_gen.sv:15,26,44` ·
`rtl/write/dmac_write_initiator.sv:18,42,78,79,81,86,87,199` ·
`rtl/channel/dmac_channel_ctrl.sv:45,197`

**Where (DV):** `dv/axi_dma_controller_dv_pkg.sv:71,119,275,456`

### Symptom

- A byte-lane index within the data bus is being computed from the **address**
  width instead of the **data** width. The two are only equal by coincidence in
  the default configuration, which is why simulation currently passes.
- With `ADDR_WD = 64, DATA_WD = 32` the `src_offset` field, the shifter control
  and the beat counter are all one bit too wide.
- The concrete break is the barrel shifter at
  `rtl/write/dmac_write_initiator.sv:221`:
  `{data_in, data_in_q} >> (data_shift_bytes_reg << 3)`. The concatenation is
  `2*DATA_WD` bits wide but the shift amount can reach `ADDR_WD/8` bytes. When the
  shift equals or exceeds the concat width the result is all zeros — the DMA
  writes zeros to the destination.
- `MAX_BURST_BYTES = MAX_BURST_LEN * (ADDR_WD / 8)`
  (`dmac_write_initiator.sv:42`) mis-sizes `wr_counter`, so with a narrow data bus
  and a wide address bus the beat counter is wider than needed, and with the
  reverse it can be too narrow and wrap mid-burst.
- The DV code repeats the same confusion, so the scoreboard would mis-check rather
  than fail loudly on a non-square configuration.

### Fix plan

- [ ] Define shared localparams once, in `rtl/axi4_pkg.sv` or a new
      `dmac_pkg.sv`: `DATA_BYTES = DATA_WD/8`, `LANE_BITS = $clog2(DATA_BYTES)`,
      `ADDR_BYTES = ADDR_WD/8`.
- [ ] Audit every `$clog2(ADDR_WD/8)` occurrence in the list above and classify it
      as either "index into the data bus" (→ `LANE_BITS`) or "index into an
      address" (→ keep). Every one in the list is believed to be the former, but
      confirm case by case rather than blanket-replacing.
- [ ] Fix `MAX_BURST_BYTES` to use `DATA_WD/8`, and rename `wr_counter` /
      re-derive its width from the beat count (`$clog2(MAX_BURST_LEN+1)`), since it
      counts beats and not bytes.
- [ ] Fix the same confusion in `dv/axi_dma_controller_dv_pkg.sv` — notably the
      `strb[]` element width (line 71), the `item.data` allocation (line 119),
      `data_offset` (line 275) and `max_burst_bytes` (line 456).
- [ ] Add elaboration assertions in `dmac_write_initiator` that the shift amount
      cannot exceed the concatenation width.
- [ ] Add non-square configurations to the regression matrix (see Issue 12):
      at minimum `ADDR_WD=64/DATA_WD=32`, `ADDR_WD=32/DATA_WD=64`,
      `ADDR_WD=64/DATA_WD=128`.

---

## Issue 5 — `WSTRB` is hardwired to all-ones (P2)

**Where:** `rtl/write/dmac_write_initiator.sv:194-206`

```systemverilog
// intended logic is commented out
m_axi_wstrb <= '1;
```

### Symptom

- Every write beat asserts all byte strobes, including the first and last beats of
  a transfer.
- Any transfer whose destination address is not bus-word aligned, or whose length
  is not a multiple of `DATA_WD/8`, **writes past the requested range and clobbers
  neighbouring memory**. There is no error, no truncation, no warning.
- The README documents the alignment restriction, but nothing in the RTL enforces
  it — an out-of-spec command silently corrupts memory rather than being rejected.
- During reset `m_axi_wstrb` is driven to `'x` (the reset branch assigns `'x`),
  which propagates X into any downstream checker or slave model that samples it
  during reset.
- The scoreboard never checks strobes — `dv/axi_dma_controller_dv_pkg.sv:448` is a
  bare `// strb` comment — so this is invisible in simulation today.

### Fix plan

- [ ] Short term (make the restriction enforceable rather than silent):
      - [ ] Add an assertion in `dmac_write_req_gen` / `dmac_read_req_gen` that
            `cmd_src_addr`, `cmd_dst_addr` and `cmd_len` are all multiples of
            `DATA_WD/8` while unaligned support is incomplete.
      - [ ] Document the failure mode (memory clobber, not truncation) in the
            README Limitations section.
      - [ ] Fix the reset value so `m_axi_wstrb` is not `'x` during reset.
- [ ] Full fix (real partial-strobe support), which pairs with Issue 6 and the
      architectural note below:
      - [ ] First beat strobe: mask off bytes below `dst_addr[LANE_BITS-1:0]`.
      - [ ] Last beat strobe: mask off bytes at and above
            `(dst_addr + len)[LANE_BITS-1:0]`.
      - [ ] Handle the single-beat case where both masks apply simultaneously.
      - [ ] Handle the case where first and last beat coincide with a burst
            boundary produced by `dmac_addr_gen`.
      - [ ] Carry the end-of-command byte offset through the command FIFO — it is
            derivable from `dst_addr + len` but is not currently propagated.
- [ ] Add `WSTRB` checking to the scoreboard and have the write responder apply
      strobes when reconstructing memory (see Issue 11).

---

## Issue 6 — `cmd_len == 0` issues a 256-beat burst (P2)

**Where:** `rtl/utils/dmac_addr_gen.sv:21-26`

```systemverilog
wire [ADDR_WD-1:0] burst_len_trans = (req_addr + burst_len_bytes + ((1 << req_size) - 1) - aligned_req_addr) >> req_size;
assign burst_len = burst_len_trans - 1;
```

### Symptom

- With `req_length == 0`: `burst_len_bytes = 0` → `burst_len_trans = 0` →
  `burst_len = 8'hFF`.
- A zero-length DMA command therefore issues a **full 256-beat `AR` and `AW`
  burst** at the source and destination addresses: 1 KB of spurious reads and
  1 KB of spurious writes (at 32-bit width), the latter with all strobes set
  (Issue 5), corrupting 1 KB of memory.
- `req_last` is also asserted immediately (`next_length == 0`), so the state
  machines think the command completed while a 256-beat burst is still on the bus
  — likely leaving the write initiator and the FIFO desynchronized afterwards.
- Never observed because the testbench constrains `len > 0`
  (`dv/axi_dma_controller_tb.sv:119`).

### Fix plan

- [ ] Decide the intended semantics for `cmd_len == 0`. Recommended: treat it as a
      no-op that completes immediately, since "zero bytes" is a natural thing for
      software to pass.
- [ ] Implement the chosen semantics in the command-acceptance path, before
      `dmac_addr_gen` ever sees the command — do not try to special-case it inside
      the combinational address generator.
- [ ] Add an assertion in `dmac_addr_gen` that `req_length != 0` whenever its
      outputs are consumed, to catch regressions.
- [ ] Add a directed test for `len == 0` plus `len == 1` and
      `len == DATA_WD/8 - 1` (the latter two also exercise Issue 5).
- [ ] Review the related rounding: `burst_len_trans` rounds *up* to whole beats,
      so a `len` that is not a multiple of `1 << size` already produces a burst
      that transfers more bytes than requested. Same class of problem; fix
      together with Issue 5.

---

## Issue 7 — Error responses discarded, no completion signal (P1)

**Where:** `rtl/read/dmac_read_handler.sv:24,35` · `rtl/read/dmac_read.sv:123` ·
`rtl/write/dmac_write_handler.sv:19`

```systemverilog
// dmac_write_handler.sv, in its entirety:
assign m_axi_bready = 1;
```

### Symptom

- `m_axi_rresp` is an input to `dmac_read_handler` and is never read. A `SLVERR`
  or `DECERR` on the read channel is treated as valid data and copied to the
  destination.
- `m_axi_bresp` is likewise discarded. A failed write is indistinguishable from a
  successful one.
- `rd_resp_valid` is computed in `dmac_read_handler.sv:35` but the port is left
  unconnected at `dmac_read.sv:123` — the read-completion information the design
  computes is thrown away. This is the same signal Issue 2's drain case needs.
- The command interface has **no done/status output at all**: a requester issues a
  command and has no way to know when the data has landed, or whether it landed
  correctly. `cmd_ready` only indicates the command was *accepted*, not completed.
- `BREADY` tied high means write responses are accepted unconditionally with no
  outstanding-transaction accounting, so there is no back-pressure limiting how
  many writes are in flight.

### Fix plan

- [ ] Add a DMA completion interface to the top level: at minimum
      `done_valid` / `done_ready` (or a level `busy` + pulse `done`), plus a
      2-bit or wider `status` field carrying sticky `RRESP`/`BRESP` errors.
- [ ] Track per-command completion: count `B` responses against `AW` requests
      issued for the command, and signal done when the count balances and the
      command's last burst has been issued.
- [ ] Latch sticky error flags for `RRESP != OKAY` and `BRESP != OKAY`, clear on
      command start or on an explicit clear.
- [ ] Decide and document the error policy: abort the remainder of the transfer,
      or complete it and report. Recommended for a first cut: complete and report,
      since aborting mid-burst requires draining the FIFO cleanly.
- [ ] Connect `rd_resp_valid` (`dmac_read.sv:123`) into the read-completion
      tracking rather than leaving it dangling — Issue 2's drain gate needs
      "read side idle and no outstanding responses".
- [ ] Add an outstanding-transaction limiter on both `AR` and `AW` with a
      parameterizable maximum (`RD_MAX_OUTSTANDING` already exists as a parameter
      in the dead `dmac_channel_ctrl.sv:8` — reuse the name).
- [ ] Extend the testbench responders to inject `SLVERR`/`DECERR` and add tests
      asserting the error is reported.
- [ ] Update the README Ports table with the new completion/status signals.

---

## Issue 8 — Self-referencing continuous assignment on `data_shift_bytes` (P3)

**Where:** `rtl/write/dmac_write_initiator.sv:86-87`

```systemverilog
assign data_shift_bytes[$clog2(ADDR_WD/8)]     = data_shift_bytes[$clog2(ADDR_WD/8)-1:0] == 0;
assign data_shift_bytes[$clog2(ADDR_WD/8)-1:0] = wr_req_data_offset - wr_req_addr[$clog2(ADDR_WD/8)-1:0];
```

### Symptom

- The MSB of `data_shift_bytes` is assigned from the low bits of the *same net*.
- There is no true combinational cycle (the low bits do not depend on the MSB), so
  it resolves correctly in simulation, but many linters and synthesis front-ends
  report a combinational loop on the vector and some will refuse to optimize
  across it.
- The intent — "a zero byte-offset difference means shift by a whole word" — is
  not readable from the code, and the encoding is easy to break during the
  `ADDR_WD`→`DATA_WD` cleanup in Issue 4.

### Fix plan

- [ ] Split into two named wires: a `shift_lo` for the byte difference and an
      explicit `shift_is_full_word` flag, then concatenate them into
      `data_shift_bytes`.
- [ ] Add a comment explaining the full-word-shift encoding and why it is correct
      (shifting `{data_in, data_in_q}` by a whole word selects `data_in`).
- [ ] Re-derive the widths from `LANE_BITS` as part of Issue 4.
- [ ] Run lint (Verilator `--lint-only -Wall`, or Spyglass) and confirm the loop
      warning is gone; add lint to CI (see Issue 12).

---

## Issue 9 — Dead logic and dead files (P3)

### Symptom

Registers that are written every cycle but never read — they consume flops, they
survive synthesis only until the optimizer removes them, and they mislead anyone
reading the code into thinking a hazard is being handled when it is not:

- `rtl/read/dmac_read_req_gen.sv:38` `cmd_blocking`
- `rtl/read/dmac_read_req_gen.sv:39` `cmd_out_blocking`
- `rtl/read/dmac_read_req_gen.sv:40` `rd_req_fired`
- `rtl/read/dmac_read_req_gen.sv:54` `rd_req_last_reg` (shadowed by the
  combinational `assign rd_req_last = req_last;` on line 135)
- `rtl/write/dmac_write_req_gen.sv:31` `cmd_blocking`
- `rtl/write/dmac_write_req_gen.sv:32` `wr_req_fired`

Unused ports:

- `rtl/write/dmac_write_initiator.sv:25` `data_in_last` — the per-command "last"
  marker is carried through the whole datapath and then silently discarded. This
  is exactly the resynchronization hook the architectural note below needs.

Unreferenced modules (instantiated nowhere):

- `rtl/channel/dmac_channels.sv` — empty file, 0 lines
- `rtl/channel/dmac_channel_requester.sv` — empty module body
- `rtl/channel/dmac_channel_ctrl.sv` — 200 lines of control logic, including the
  buffer-occupancy gate the live design is missing (Issue 2)
- `rtl/utils/axis_bits_pipeline.sv` — four handshake-stage variants, one of which
  is the right fix for Issue 1

Commented-out dead code blocks: `dmac_read_req_gen.sv:51,116,119,125,130,142`,
`dmac_write_req_gen.sv:43,46,96,99,105,109`,
`dmac_write_initiator.sv:20,126,198-203`, `dmac_channel_ctrl.sv:24,39,68,181,186`.

### Fix plan

- [ ] Delete the six dead registers and their `always_ff` blocks.
- [ ] Decide the fate of `dmac_channel_ctrl.sv`: either wire it in as the real
      multi-channel control path (it is the only place `CHANNEL_COUNT` would
      become meaningful) or delete it and migrate its occupancy gate into
      `dmac_write_req_gen` as part of Issue 2. Do not leave two divergent copies
      of the request-generation logic.
- [ ] Delete `dmac_channels.sv` and `dmac_channel_requester.sv`, or fill them in.
- [ ] Keep `axis_bits_pipeline.sv` and actually use it for Issue 1; if it stays
      unused, delete it. Note its `FORWARD` mode asserts `out_tvalid` from
      `in_tvalid` alone (line 31) and `FORWARD_BACKWARD` writes its memories
      without checking `in_tvalid` (lines 114-117) — both are benign today but
      must be re-verified before the module is relied on.
- [ ] Remove the commented-out code blocks; the history is in git.
- [ ] Add a CI check for unreferenced modules and unread signals.

---

## Issue 10 — Architectural: no per-command resynchronization between read and write (P1)

**Where:** `rtl/read/dmac_read_req_gen.sv` + `rtl/write/dmac_write_req_gen.sv` +
`rtl/buffer/dmac_buffer.sv`

### Symptom

- The read side splits bursts on **source** address boundaries and the write side
  splits on **destination** address boundaries, using two independent instances of
  `dmac_addr_gen`. Between them sits a plain FIFO with no framing.
- This is only safe while both sides consume exactly the same total word count.
  That holds for fully word-aligned commands, and fails as soon as:
  - `src_addr` and `dst_addr` have different sub-word byte offsets, or
  - `cmd_len` is not a multiple of `DATA_WD/8`.
- When the counts differ, the FIFO is left with a leftover (or short) word at the
  end of the command. The next command then reads its data at the wrong offset —
  **the corruption is unbounded and affects every following command**, so a single
  malformed command poisons the channel until reset.
- This is the real root cause behind the "unaligned transfers not supported"
  limitation in the README. The current behaviour for an unaligned command is not
  "unsupported and rejected", it is "accepted and silently corrupts all later
  traffic".
- The `last` marker needed to detect and recover from this is already carried
  through the FIFO (`dmac_buffer.sv:70,74`) and then discarded (Issue 9).

### Fix plan

- [ ] Short term: enforce the documented restriction in hardware — assert or
      reject commands that are not word-aligned in address and length, so an
      out-of-spec command fails loudly instead of poisoning the channel
      (shares the assertion work with Issue 5).
- [ ] Use `data_in_last` in `dmac_write_initiator` to realign at each command
      boundary: on `last`, flush any residual partial word and reset the shifter
      state. This contains the damage to the offending command even before full
      unaligned support exists.
- [ ] Medium term, for real unaligned support:
      - [ ] Make the read side fetch `ceil((src_offset + len) / DATA_BYTES)` words
            and the write side emit `ceil((dst_offset + len) / DATA_BYTES)` words,
            and reconcile the two counts explicitly rather than implicitly.
      - [ ] Extend the shifter to handle the leading partial word (prefetch one
            word before the first beat when `dst_offset > src_offset`) and the
            trailing partial word (drain one extra beat when the tail spills into
            an additional destination word).
      - [ ] Pair with partial `WSTRB` (Issue 5) — unaligned transfers are not
            correct without it.
- [ ] Add an assertion that the data FIFO is empty at each command boundary in the
      aligned case — this catches desync directly.
- [ ] Add the unaligned tests that `dv/axi_dma_controller_tb.sv:217-241` currently
      stubs out (`send_unaligned_cmd` still forces `len % ADDR_WD_BYTES == 0` at
      line 223, marked `// FIXME`, so it does not actually test unaligned lengths).

---

## Issue 11 — Verification gaps that hide the above (P3)

**Where:** `dv/axi_dma_controller_tb.sv` · `dv/axi_dma_controller_dv_pkg.sv`

### Symptom

- `dv/axi_dma_controller_tb.sv:253` calls `$finish` immediately after the stimulus
  tasks return. In-flight commands are never drained and the scoreboard's pending
  comparisons are silently dropped — the last N commands are effectively
  unchecked. The `// TODO: wait write request and check scoreboard` on line 252
  acknowledges this.
- The scoreboard never checks `WSTRB` (`dv_pkg.sv:448` is a bare `// strb`
  comment), so Issue 5 cannot be detected.
- `dv_pkg.sv:176-180` reconstructs write data ignoring `wstrb` entirely, so even
  if strobes were checked the reference model would not reflect them.
- There is no memory model — the scoreboard compares the byte stream returned on
  `R` against the byte stream sent on `W`. That catches data mangling but not
  address errors, over-writes past the destination, or writes to the wrong place.
- No AXI protocol checker is bound to the interface, so Issue 1's `VALID` drop
  produces no error.
- Only the default 32/32/8/16 configuration is ever elaborated, so Issues 3 and 4
  cannot be detected.
- `dv_pkg.sv:71,119,275,456` repeat the `ADDR_WD`/`DATA_WD` confusion from
  Issue 4, so the checker would itself be wrong in a non-square configuration.
- The write responder's `drive_b_channel` (`dv_pkg.sv:189-207`) always returns
  `OKAY`; the read responder always returns `OKAY`. Error paths are never
  exercised (Issue 7).

### Fix plan

- [ ] Add an end-of-test drain: wait until the command mailbox and both AXI
      mailboxes are empty and the DUT is idle, with a timeout, before `$finish`.
      Report a pass/fail summary with the number of commands actually checked.
- [ ] Add a real memory model to the responders: a sparse associative array
      written by the `W` channel under `WSTRB` and read by the `R` channel. Check
      the destination range byte-by-byte after each command, **and** check that
      bytes immediately outside the destination range are untouched (this is what
      catches Issue 5).
- [ ] Bind an AXI4 protocol checker (or hand-write the `VALID`-stability and
      `WLAST`-count assertions) to `axi_dma_controller_axi_if`.
- [ ] Fix the `ADDR_WD`/`DATA_WD` confusion in the DV package (shares work with
      Issue 4).
- [ ] Add error-injection knobs to both responders (`RRESP`/`BRESP` = `SLVERR` /
      `DECERR` with a configurable rate) and tests that check the reported status
      (Issue 7).
- [ ] Add directed tests for the corner cases identified above:
      - [ ] `len == 0`, `len == 1`, `len` not a multiple of `DATA_WD/8` (Issue 6)
      - [ ] uncorrelated aggressive `wready` throttling plus read starvation, to
            hit the Issue 1 window
      - [ ] `src_addr` and `dst_addr` with differing sub-word offsets (Issue 10)
      - [ ] back-to-back commands with no gap, and commands separated by long
            idle periods
- [ ] Remove the `// FIXME` constraint at `dv/axi_dma_controller_tb.sv:223` once
      unaligned support lands.
- [ ] Add functional coverage on burst length, alignment combinations, and
      throttling patterns so gaps are visible rather than assumed.

---

## Issue 12 — No build/regression infrastructure (P3)

### Symptom

- The repository has no simulation makefile, script, or CI configuration — only a
  ModelSim project directory (`modelsim/`) with checked-in build artifacts
  (`work/`, `*.wlf`, `*.vcd`, `vsim.wlf`, transcript temp files). The build is not
  reproducible outside one person's GUI session.
- There is no lint step, so Issue 8's combinational loop and Issue 3's width
  mismatches produce warnings nobody sees.
- There is no multi-configuration elaboration, so Issues 3 and 4 are structurally
  undetectable.

### Fix plan

- [ ] Add a `Makefile` (or `.f` filelist + script) that compiles and runs the
      testbench headlessly, returning a non-zero exit code on any `$error`.
      Support at least one open-source simulator (Verilator or Icarus) in addition
      to ModelSim so CI does not need a licensed tool.
- [ ] Add a lint target: `verilator --lint-only -Wall` over `rtl/`.
- [ ] Add a parameter sweep target that at minimum *elaborates* the core for:
      `(32,32)`, `(32,64)`, `(64,32)`, `(64,64)`, `(64,128)`, and
      `MAX_BURST_LEN` in `{1, 16, 256}`.
- [ ] Add CI running lint + the regression on every push.
- [ ] Extend `.gitignore` to cover `modelsim/work/`, `*.wlf`, `*.vcd`,
      `wlft*`, `*.cr.mti`, and remove the currently tracked build artifacts.

---

## Suggested order of work

1. Issue 3 (one-line fix, unblocks any non-default configuration)
2. Issue 1 (P0 data corruption, small and self-contained)
3. Issue 12 (headless regression + lint, so everything after this is verifiable)
4. Issue 11 memory model + drain + protocol checker (makes the remaining bugs
   observable before fixing them)
5. Issue 2 (needs the FIFO occupancy plumbing and the read-idle signal from
   Issue 7)
6. Issue 7 (completion and error reporting)
7. Issue 4 (mechanical but wide-reaching; do it after CI exists to catch fallout)
8. Issue 6, Issue 5 short-term assertions, Issue 10 short-term enforcement
9. Issue 8, Issue 9 (cleanup)
10. Issue 5 full partial-strobe support + Issue 10 full unaligned support
    (these two must land together)
