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

---

## Datapath Architecture

The design was decomposed into a sequence of functional stages:

<p align="center">
  <img src="schematics/system_decomposition_diagram.svg" alt="Floating-point datapath decomposition" width="430">
</p>

Development was incremental. I first focused on obtaining correct basic floating-point addition and subtraction, then added rounding and IEEE-754 special-case handling.

The internal datapath separates the stored IEEE-754 fields from the representation used during arithmetic. In particular, the significands are extended to preserve the **guard, round and sticky (GRS) bits** required for correct rounding.

---

## Schematic Implementation

The first implementation was constructed schematically. This made the intermediate operations explicit and forced each part of floating-point addition/subtraction to be considered as hardware rather than as a software arithmetic expression.

The schematic was organised around the same functional stages shown above. Significant blocks included:

- exponent comparison and alignment;
- extended right shifting with sticky-bit generation;
- operand ordering and effective subtraction;
- leading-one detection for normalisation;
- round-to-nearest-even logic;
- post-round renormalisation;
- IEEE-754 special-case classification and output selection.

The complete top-level schematic is shown below. More detailed block-level schematic images are stored in the [`schematics/`](schematics/) directory.

<p align="center">
  <img src="schematics/full_datapath_schematic.png" alt="Full floating-point datapath schematic" width="1000">
</p>

### Schematic Verification

The schematic design was verified using directed test cases before the SystemVerilog port was developed.

<p align="center">
  <img src="schematics/schematic_verification_setup.png" alt="Schematic verification setup" width="900">
</p>

### Pipelining Approach

The schematic implementation was also used to explore timing-driven pipelining. Pipeline boundaries were chosen from the combinational structure and measured critical paths rather than by dividing the datapath into arbitrary equal stages. The resulting timing-optimised schematic is included in the synthesis comparison below.


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

### Example 1 — Normalisation Path


#### 1A — Leading-One Detection

The schematic normalisation logic used an explicit priority-encoder hierarchy to identify the position of the first `1` in the significand.

<p align="center">
  <img src="schematics/priority_encoder_4.png" alt="Four-input priority encoder schematic" width="650">
</p>

<p align="center">
  <img src="schematics/priority_encoder_6.png" alt="Six-input priority encoder schematic" width="750">
</p>

In RTL, the required behaviour can instead be expressed directly as a priority chain:

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

The RTL describes the required priority behaviour directly rather than reproducing the exact hierarchy of schematic encoder components.


#### 1B — Bounded Normalisation

The schematic normalisation stage combined leading-one detection with logic that limited the left shift so that the exponent could not be decremented below the subnormal boundary.

<p align="center">
  <img src="schematics/normalisation_extended_subnormal.png" alt="Normalisation and subnormal handling schematic" width="950">
</p>

The shift amount was bounded separately using the current exponent:

<p align="center">
  <img src="schematics/actual_shift_calculator.png" alt="Actual normalisation shift calculator schematic" width="700">
</p>

In the RTL port, these behaviours are represented directly using a leading-one position, a calculated maximum legal shift, and combinational selection logic rather than reproducing the original schematic hierarchy exactly.

### Example 2 — Alignment and Sticky-Bit Generation

Floating-point addition requires the smaller significand to be right-shifted until the operand exponents are aligned. Bits discarded during this shift cannot simply be ignored because they contribute to the sticky bit used during rounding.

The schematic implementation used separate shifting and mask-generation logic:

<p align="center">
  <img src="schematics/lsr_extended.png" alt="Extended logical shift-right schematic" width="850">
</p>

<p align="center">
  <img src="schematics/mask_generator.png" alt="Sticky-bit mask generator schematic" width="750">
</p>

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

The current directed suite contains **40 tests, all of which pass**.

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

---

## Pipelining and Timing Optimisation

After completing the combinational RTL implementation, I used timing measurements from Quartus to choose pipeline boundaries rather than placing registers arbitrarily.

### Block-Level Timing Characterisation

The major combinational blocks were first synthesised individually between input and output registers. This gave an approximate critical-path delay for each functional region of the datapath:

| Component | Critical path (ns) |
|---|---:|
| `unpack` | 1.664 |
| `exponent_diff` | 3.373 |
| `lsr_extended` | 7.832 |
| `operand_negation_extended` | 7.677 |
| `significand_arithmetic` | 3.941 |
| `normalise_extended_subnormal` | 10.205 |
| `round` | 3.572 |
| `renormalise` | 2.619 |
| `pack` | 3.009 |
| `handle_special_cases` | 3.600 |

Subcomponents already contained within these blocks were omitted to avoid double-counting their delay.

These measurements are only an approximation of the behaviour of the complete design. When the blocks are synthesised together, Quartus can optimise across module boundaries and routing delays can also change. The measurements were therefore used to choose an initial pipeline structure, with the final design evaluated using post-fit timing.

### Pipeline Partition Search

I wrote a small Python script to search possible pipeline boundaries automatically.

For a datapath containing \(m\) ordered functional blocks and a pipeline containing \(n\) stages, the script enumerates every possible set of \(n-1\) register boundaries. For each candidate partition, the estimated delay of each stage is calculated by summing the measured delays of its constituent blocks.

The objective is to minimise the estimated delay of the slowest stage:

$$
T_{\text{crit}} = \max(T_1,T_2,\ldots,T_n)
$$

and hence maximise the estimated operating frequency:

$$
F_{\max} \approx \frac{1}{T_{\text{crit}}}
$$

Since there were only nine possible cut locations, exhaustive search was sufficiently small and avoided the need for a more complicated optimisation algorithm.

### Initial Throughput/Latency Heuristic

I initially considered selecting the pipeline depth using a single heuristic score:

$$
S = \frac{F_{\max}}{L}
$$

where $L$ is the total pipeline latency.

This appeared to capture the trade-off that deeper pipelines can increase throughput while also increasing the number of cycles required for one operation. However, considering an ideal pipeline shows why this is not a suitable general optimisation criterion.

Assume an unpipelined combinational path has delay $k$, and that it can be divided perfectly across $n$ pipeline stages. The delay of each stage would then be:

$$
T_{\text{stage}} = \frac{k}{n}
$$

giving:

$$
F_{\max} = \frac{1}{T_{\text{stage}}}
          = \frac{n}{k}
$$

The total latency of an $n$-stage pipeline would be:

$$
L = nT_{\text{stage}}
  = n\frac{k}{n}
  = k
$$

Therefore the proposed score becomes:

$$
S = \frac{F_{\max}}{L} = \frac{n/k}{k} = \frac{n}{k^2}
$$

For an ideal pipeline, this increases linearly with the number of stages. It would therefore always favour adding more stages and does not produce a meaningful optimum.

A finite optimum only appeared with the measured data because the real system is non-ideal. Functional blocks cannot always be divided further, pipeline stages are not perfectly balanced, and additional registers introduce setup, clock-to-Q and routing overheads. These non-idealities eventually cause the improvement in $F_{\max}$ to flatten while latency and register count continue to increase.

I therefore used **diminishing returns in predicted Fmax**, rather than the throughput/latency score, as the main criterion for selecting the initial pipeline depth.

### Predicted Pipeline Behaviour

The exhaustive partition search produced the following results:

| Pipeline stages | Estimated worst-stage delay (ns) | Estimated Fmax (MHz) | Estimated latency (ns) |
|---:|---:|---:|---:|
| 1 | 47.492 | 21.06 | 47.49 |
| 2 | 24.487 | 40.84 | 48.97 |
| 3 | 20.546 | 48.67 | 61.64 |
| 4 | 12.869 | 77.71 | 51.48 |
| 5 | 12.800 | 78.13 | 64.00 |

The predicted improvement from four to five stages is only approximately **0.5%**, despite requiring another pipeline stage. This indicated that the design had reached a natural limit under the chosen functional decomposition.

The predicted four-stage partition was:

| Stage | Functional blocks | Estimated delay (ns) |
|---:|---|---:|
| 1 | `unpack` → `exponent_diff` → `lsr_extended` | 12.869 |
| 2 | `operand_negation_extended` → `significand_arithmetic` | 11.618 |
| 3 | `normalise_extended_subnormal` | 10.205 |
| 4 | `round` → `renormalise` → `pack` → `handle_special_cases` | 12.800 |

This partition is both relatively well balanced and aligned with natural functional boundaries in the datapath. It was therefore selected as the initial RTL pipeline architecture.

The resulting pipelined RTL was then re-synthesised and analysed using Quartus post-fit timing. These measured results, rather than the additive block-delay model, are used for the final performance comparison.

### Pipelined RTL Implementation

The four-stage partition selected above was then implemented directly in the SystemVerilog datapath. The main implementation challenge was not the placement of the arithmetic registers themselves, but preserving all transaction state required by downstream stages.

### Pipeline Register Design

Implementing the pipeline required more than simply placing registers between the major arithmetic blocks.

Each pipeline boundary must preserve all information required by later stages. This includes both the main datapath and **sideband information** such as operand signs, the selected exponent, and the original operands required for special-case handling.

Some signals are produced in an early stage but are not consumed until several stages later. These therefore need to be propagated through multiple pipeline registers even if intermediate stages do not modify them.

For example:

| Signal | Produced | Consumed | Required propagation |
|---|---|---|---|
| Aligned significand | Stage 1 | Stage 2 | S1 → S2 |
| Arithmetic exponent | Stage 1 | Stage 3 | S1 → S2 → S3 |
| Arithmetic sign | Stage 2 | Stage 4 | S2 → S3 → S4 |
| `a`, `b`, effective B sign | Input / Stage 1 | Stage 4 | propagated through all intermediate stages |
| Normalised exponent/significand | Stage 3 | Stage 4 | S3 → S4 |

This was an important practical distinction between a block-level timing partition and an actual pipeline implementation: a pipeline stage must maintain the complete transaction context, not just the most obvious arithmetic result.

### Fourth Output Register

Three internal register boundaries separate the four combinational stages, but an additional output register is required after Stage 4:

```text
Stage 1 → R1 → Stage 2 → R2 → Stage 3 → R3 → Stage 4 → R4
```

Without the final register, Stage 4 would terminate at a combinational output and the design would not behave as a true four-stage pipeline.

The fourth register gives four-cycle input-to-output latency, one-result-per-cycle throughput once the pipeline is full, and a register-to-register timing endpoint for Stage 4. The testbench was updated by delaying the expected result and a validity signal through the same four-cycle pipeline.

### Post-Fit Timing Results

After implementation, the pipelined RTL was compiled in Quartus for the same MAX 10 target used for the earlier experiments.

The critical path reported by Quartus was **10.810 ns**. It began at the Stage-1 `aligned_significand_s1` register, passed through `operand_negation_extended` and `significand_arithmetic`, and terminated at the Stage-2 `arithmetic_result_s2` register.

This means the final implementation was limited by **Stage 2**, rather than Stage 1 as predicted by the simple additive timing model.

The predicted Stage-2 delay was:

$$
T_{\text{S2,predicted}} = 11.618\text{ ns}
$$

while Quartus produced:

$$
T_{\text{S2,actual}} = 10.810\text{ ns}
$$

giving a difference of approximately:

$$
\frac{11.618 - 10.810}{11.618}\times 100
\approx 7.0\%
$$

Thus, the isolated-block timing model predicted the eventual critical stage to within approximately **7%**.

Comparing against the predicted overall worst-stage delay:

$$
\frac{12.869 - 10.810}{12.869}\times 100
\approx 16.0\%
$$

so the implemented pipeline achieved a critical-path delay approximately **16% lower** than the conservative pre-implementation estimate.

For consistency with the other implementations, the characterised Fmax was calculated as the reciprocal of the Quartus-reported critical-path data delay:

$$
F_{\max} = \frac{1000}{10.810} = 92.507\text{ MHz}
$$

This is approximately **19% higher** than the 77.7 MHz estimate from the additive timing model.

### Interpretation

The additive timing model was deliberately approximate:

$$
T_{\text{stage}} \approx \sum_i T_i
$$

Quartus can optimise across module boundaries and change mapping and routing when the blocks are integrated, so the post-fit result is not expected to match the isolated measurements exactly. Even so, the model identified the same expensive region that became critical after implementation: operand selection / conditional negation followed by significand arithmetic.

The main implementation lessons were:

- pipeline design must preserve **sideband and control information**, not only the main arithmetic datapath;
- signals may need to cross several pipeline boundaries before being consumed;
- a four-stage combinational partition requires a fourth output register to provide true four-cycle pipeline behaviour;
- isolated timing measurements are useful for architectural decisions, but the integrated post-fit result is the final reference.


## Synthesis Comparison

The implementations were synthesised on the same MAX 10 target to compare timing and logic usage directly:

| Implementation | Characterised Fmax (MHz) | Logic resources (LEs) | Notes |
|---|---:|---:|---|
| Initial combinational schematic | 24.449 | 857 | Baseline schematic |
| Pipelined / timing-optimised schematic | 59.880 | 769 | Timing-driven pipeline |
| Combinational RTL | 26.527 | 779 | Idiomatic RTL port |
| Functionally pipelined RTL | 92.507 | 951 | RTL pipeline |

**Timing convention:** characterised Fmax is calculated as $1000/T_{\text{crit}}$ using the Quartus-reported post-fit critical-path data delay in nanoseconds. Combinational implementations were placed between timing-only input and output registers so that their datapath delay could be characterised in the same way.

---

## Lessons Learned

Building the schematic implementation first forced me to understand the floating-point datapath at a lower level, including exponent alignment, effective subtraction, normalisation and the propagation of information required for rounding.

Porting the same behaviour to SystemVerilog highlighted a different design skill: choosing the correct level of abstraction. RTL does not need to reproduce every mux, encoder or arithmetic component from a schematic. Instead, the required behaviour can be expressed directly and the synthesis tool can determine the lower-level implementation.

The main sources of subtle implementation bugs were:

- signal-width mismatches;
- preserving the correct intermediate width during arithmetic;
- handling guard, round and sticky information correctly;
- distinguishing stored IEEE-754 fields from the internal representation used by the datapath;
- choosing between explicit structural logic and clearer behavioural RTL;
- keeping sideband state aligned with the main datapath when introducing pipeline boundaries.

---
