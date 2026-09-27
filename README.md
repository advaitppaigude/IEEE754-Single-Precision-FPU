# IEEE754-Single-Precision-FPU

## Overview

This project implements a **32-bit IEEE-754 floating-point addition/subtraction datapath** with support for:

- round-to-nearest, ties-to-even;
- NaN handling;
- positive and negative infinity;
- signed zero;
- subnormal numbers.

The project was developed in two stages. I first implemented the datapath schematically to refresh and strengthen my digital-design understanding at the block and signal level. I then ported the combinational datapath to **SystemVerilog**, using the port as an opportunity to move from explicit schematic structures towards more idiomatic synthesizable RTL.

A further aim of the project is to compare the synthesised characteristics of the schematic and RTL implementations, including resource use and maximum operating frequency.

> **Image placeholder — overall datapath / project overview**
>
> Insert a high-level diagram showing the main floating-point stages.

---

## Datapath Architecture

The design was decomposed into a sequence of functional stages:

```text
Unpack
  ↓
Exponent difference
  ↓
Significand alignment
  ↓
Sign handling / effective subtraction
  ↓
Significand arithmetic
  ↓
Normalisation
  ↓
Rounding
  ↓
Post-round renormalisation
  ↓
Packing / special-case handling
```

Development was incremental. I first focused on obtaining correct basic floating-point addition and subtraction, then added support for rounding and IEEE-754 special cases.

The internal datapath separates the stored IEEE-754 fields from the representation used during arithmetic. In particular, the significands are extended to preserve the **guard, round and sticky (GRS) bits** required for correct rounding.

> **Image placeholder — full schematic datapath**
>
> Insert one overall schematic screenshot here. Detailed block-level schematics can be kept separately under `docs/schematics/`.

---

## Schematic Implementation

The first implementation was constructed schematically. This made the intermediate operations explicit and forced each part of floating-point addition/subtraction to be considered as hardware rather than as a software arithmetic expression.

The schematic was organised around the same functional stages used in the final RTL design. Some of the more significant blocks included:

- exponent comparison and alignment;
- extended right shifting with sticky-bit generation;
- operand ordering and effective subtraction;
- leading-one detection for normalisation;
- round-to-nearest-even logic;
- post-round renormalisation;
- IEEE-754 special-case classification and output selection.

Rather than placing screenshots of every internal block in this README, the main schematic is shown above and the individual block schematics can be stored separately in the repository.

### Schematic Verification

The schematic design was verified using directed test cases before the SystemVerilog port was developed.

> **Image placeholder — schematic verification setup**
>
> Insert a screenshot or diagram showing the schematic test/verification setup.

### Pipelining Approach

The schematic implementation was also used to explore timing-driven pipelining. The intention was to place pipeline boundaries based on the combinational structure and critical paths rather than simply splitting the design into an arbitrary number of equal stages.

> **Image placeholder — timing / netlist / pipeline stages**
>
> Insert the relevant netlist or timing screenshots here once the final comparison is complete.

The final synthesis comparison is discussed later in this README.

---

## SystemVerilog Port

The SystemVerilog implementation was **not intended to be a mechanical gate-for-gate translation** of the schematic.

Instead, I used the port to identify structures that could be expressed at a more appropriate RTL abstraction level while preserving the same datapath behaviour. This included blocks such as:

- `lsr_extended`;
- `normalise_extended_subnormal`;
- `renormalise`;
- `operand_negation_extended`;
- exponent comparison;
- mux networks and arithmetic blocks.

This allowed the RTL to describe the intended hardware behaviour more directly and leave lower-level implementation choices to synthesis.

### Example 1 — Leading-One Detection

The schematic normalisation logic used an explicit priority-encoder structure to identify the position of the first `1` in the significand.

> **Image placeholder — schematic priority encoder**
>
> Insert the corresponding schematic crop here.

In RTL, the same behaviour can be expressed directly as a priority chain:

```systemverilog
module find_first_one_position(
    input  logic [23:0] significand,
    output logic [7:0]  first_one_position
);

    always_comb begin
        if      (significand[23]) first_one_position = 8'd0;
        else if (significand[22]) first_one_position = 8'd1;
        else if (significand[21]) first_one_position = 8'd2;
        else if (significand[20]) first_one_position = 8'd3;
        else if (significand[19]) first_one_position = 8'd4;
        else if (significand[18]) first_one_position = 8'd5;
        else if (significand[17]) first_one_position = 8'd6;
        else if (significand[16]) first_one_position = 8'd7;
        else if (significand[15]) first_one_position = 8'd8;
        else if (significand[14]) first_one_position = 8'd9;
        else if (significand[13]) first_one_position = 8'd10;
        else if (significand[12]) first_one_position = 8'd11;
        else if (significand[11]) first_one_position = 8'd12;
        else if (significand[10]) first_one_position = 8'd13;
        else if (significand[9])  first_one_position = 8'd14;
        else if (significand[8])  first_one_position = 8'd15;
        else if (significand[7])  first_one_position = 8'd16;
        else if (significand[6])  first_one_position = 8'd17;
        else if (significand[5])  first_one_position = 8'd18;
        else if (significand[4])  first_one_position = 8'd19;
        else if (significand[3])  first_one_position = 8'd20;
        else if (significand[2])  first_one_position = 8'd21;
        else if (significand[1])  first_one_position = 8'd22;
        else if (significand[0])  first_one_position = 8'd23;
        else                      first_one_position = 8'd24;
    end

endmodule
```

The RTL describes the priority behaviour directly rather than reproducing the exact hierarchy of schematic encoder components.

### Example 2 — Alignment and Sticky-Bit Generation

Floating-point addition requires the smaller significand to be right-shifted until the operand exponents are aligned. Bits discarded during this shift cannot simply be ignored because they contribute to the sticky bit used during rounding.

The schematic implementation used separate shifting and mask-generation logic.

> **Image placeholder — schematic `LSR_EXTENDED` and mask generator**
>
> Insert the schematic implementation beside or above the RTL version.

The RTL version combines these operations:

```systemverilog
module lsr_extended(
    input  logic [23:0] significand,
    input  logic [7:0]  shift,
    output logic [26:0] shifted_extended
);

    logic [26:0] shifted;
    logic [23:0] mask;

    always_comb begin
        if (shift < 8'd27) begin
            shifted = {significand, 3'b000} >> shift;
            shifted_extended[26:1] = shifted[26:1];
        end
        else begin
            shifted = 27'd0;
            shifted_extended[26:1] = 26'd0;
        end

        if (shift <= 8'd2) begin
            mask = 24'd0;
        end
        else if (shift >= 8'd26) begin
            mask = 24'hFFFFFF;
        end
        else begin
            mask = (24'd1 << (shift - 8'd2)) - 24'd1;
        end

        shifted_extended[0] = |(significand & mask);
    end

endmodule
```

The reduction-OR of the masked discarded bits generates the sticky bit while the shifted result retains the bits required for subsequent guard/round handling.

### Other RTL Transformations

Other parts of the port followed the same approach:

| Function | Schematic-style implementation | RTL representation |
|---|---|---|
| Exponent / magnitude comparison | Explicit arithmetic and selection logic | Direct comparison and subtraction |
| Effective subtraction | Adder/XOR-style arithmetic structure | Arithmetic expressed directly in RTL where appropriate |
| Selection networks | Explicit mux blocks | `if`, ternary expressions and `case` statements |
| Leading-one detection | Priority-encoder hierarchy | Priority `if`/`else if` chain |
| Sticky-bit generation | Separate mask-generation structure | Mask expression plus reduction OR |
| Post-round carry | Explicit arithmetic / mux handling | Widened addition followed by renormalisation |

These changes are intended to express the required behaviour more clearly at RTL level. Any claims about differences in area or timing are left to the synthesis results rather than inferred from source-code appearance alone.

---

## RTL Verification

The combinational RTL design is verified using a **self-checking SystemVerilog testbench**.

Each directed test is represented using a packed test-vector structure containing:

- operand `a`;
- operand `b`;
- add/subtract control `op`;
- expected 32-bit IEEE-754 result.

For each vector, the testbench applies the inputs, allows the combinational design to settle, compares the DUT output against the expected bit pattern, and reports any mismatch with the input operands, expected output and actual output.

The current directed suite contains **40 tests**, all of which pass.

### Directed Test Coverage

| Test(s) | Category | Purpose |
|---:|---|---|
| 0–1 | Basic addition | Establish correct normal addition |
| 2–4 | Basic subtraction | Check subtraction and result-sign selection |
| 5–6 | Negative operands | Check arithmetic involving negative values |
| 7–8 | Cancellation / zero | Check exact cancellation and zero outputs |
| 9 | Exponent alignment | Check alignment of operands with different exponents |
| 10–11 | Basic rounding | Check representable increments and ties-to-even behaviour |
| 12–19 | Infinities | Check finite/infinite combinations and invalid infinity arithmetic |
| 20–25 | Signed zero | Check IEEE-754 signed-zero combinations and cancellation |
| 26–27 | Large exponent differences | Exercise alignment when the smaller operand is shifted substantially |
| 28–30 | Rounding edge cases | Exercise sticky-driven rounding, ties-to-even and post-round carry |
| 31–34 | Subnormals | Check subnormal arithmetic and the normal/subnormal boundary |
| 35–36 | NaN handling | Check NaN special-case output handling |
| 37–39 | Overflow | Check results that overflow to positive or negative infinity |

> **Image placeholder — RTL testbench result**
>
> Insert a terminal/simulator screenshot showing all 40 directed tests passing.

The directed tests are deliberately grouped by datapath function so that a failure gives useful information about which part of the implementation is likely to be responsible.

---

## Synthesis Comparison

One of the aims of the project is to compare the hardware produced from the schematic and RTL implementations rather than assuming that a more concise RTL description necessarily produces a better result.

The intended comparison includes:

| Implementation | Maximum frequency | Logic resources | Registers | Notes |
|---|---:|---:|---:|---|
| Initial combinational schematic | **TODO** | **TODO** | **TODO** | Baseline schematic |
| Pipelined / timing-optimised schematic | **TODO** | **TODO** | **TODO** | Timing-driven pipeline |
| Combinational RTL | **TODO** | **TODO** | **TODO** | Idiomatic RTL port |
| Functionally pipelined RTL | **TODO** | **TODO** | **TODO** | RTL pipeline |

> **Image placeholder — synthesis / timing comparison**
>
> Insert the final synthesis or timing comparison figure here.

This section will be completed once the implementations have been synthesised under comparable conditions.

---

## Lessons Learned

Building the schematic implementation first forced me to understand the floating-point datapath at a lower level, including exponent alignment, effective subtraction, normalisation and the propagation of information required for rounding.

Porting the same behaviour to SystemVerilog highlighted a different design skill: choosing the correct level of abstraction. RTL does not need to reproduce every mux, encoder or arithmetic component from a schematic. Instead, the designer can express the required behaviour clearly and allow synthesis to determine the lower-level implementation.

The main sources of subtle implementation bugs were:

- signal-width mismatches;
- preserving the correct intermediate width during arithmetic;
- handling guard, round and sticky information correctly;
- distinguishing stored IEEE-754 fields from the internal representation used by the datapath;
- choosing between explicit structural logic and clearer behavioural RTL.

---

## Repository Structure

> **Placeholder — update paths to match the final repository**

```text
.
├── README.md
├── src/
│   └── <SystemVerilog source files>
├── tb/
│   └── <self-checking testbench>
└── docs/
    └── schematics/
        └── <detailed schematic screenshots>
```

---

## Current Status

- [x] Combinational schematic floating-point add/sub datapath
- [x] SystemVerilog port of the combinational datapath
- [x] Round-to-nearest, ties-to-even
- [x] NaN and infinity handling
- [x] Signed-zero handling
- [x] Subnormal handling
- [x] Self-checking RTL testbench
- [x] 40 directed RTL tests passing
- [ ] Add final README images
- [ ] Complete synthesis comparison
- [ ] Document final pipelining and timing results
