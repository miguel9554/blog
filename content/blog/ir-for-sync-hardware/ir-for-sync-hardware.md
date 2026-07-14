---js
const title = "An IR for Synthesizable RTL";
const date = "2026-06-27";
---

Pick any two open source HDL tools today, say a Verilog simulator and a
synthesizer, and there's a good chance they each parse and interpret RTL
semantics slightly differently. Multiply that by the growing list of HDLs
being developed today and the handful of consumers each one needs to support
(simulators, synthesizers, linters, formal tools), and you get an MxN
integration problem that the ecosystem keeps solving by brute force, one
adapter at a time.

There's a second, subtler problem underneath this: SystemVerilog and VHDL
were never designed as hardware description languages in the first place.
They're discrete-event simulation languages that happen to also describe
synthesizable hardware, if you're careful. "Careful" is doing a lot of work
in that sentence, and it's why unsynthesizable constructs slip through
simulation undetected, showing up only as synthesis warnings buried in
noise.

I've been working on [Mate IR 🧉](https://github.com/miguel9554/mateIR), an
open source IR for Synthesizable RTL, to address both problems at once. It
includes the IR itself, a compiler from SystemVerilog to it, and a couple
of consumers (a static analyzer and a simulator).

There are two main reasons this is beneficial to the EDA ecosystem:

* Bridging together the many HDL languages and the tools that consume them
* Giving that intermediate layer true Synthesizable RTL semantics, so both
  writing RTL and building tools against it become easier

The rest of this post covers the MxN problem in more detail, then digs into
what a semantic IR for synchronous hardware actually looks like.

## The MxN problem

A growing number of HDLs now coexist in the open-source ecosystem:

* Chisel
* Clash
* Veryl
* Amaranth
* SpinalHDL
* Spade
* Pipeline-C
* CppHDL

All of these provide superior characteristics over the current industry standard
languages which are SystemVerilog and VHDL: better semantics (incorporating
registers and combo logic at the language level), better language features,
better code reuse capabilities.

Alongside these languages, the most prominent open-source EDA tools have
undergone major development and are now capable of carrying relatively large
designs through simulation, synthesis and place and route. Projects such as
OpenROAD are enabling the consistent tape-out of ASIC designs using entirely
open-source tooling, while F4PGA and nextpnr provide open-source FPGA flows
through place and route and bitstream generation.

There is however, a disconnect between the innovations in the _frontend_ aspect,
that is, HDLs, and the _backend_ tooling (simulators, synthesizers, etc).
Currently, most frontend open source tools support _only_ SystemVerilog, and
often not with full support. A synthesizer that handles SystemVerilog well
generally can't touch a Chisel or SpinalHDL design directly; that design first
has to be lowered back down to Verilog, losing whatever higher-level structure
the source language provided.

There is, however, a disconnect between the innovations in the *frontend*
aspect, the HDLs, and the *backend* tooling such as simulators,
synthesizers and static analyzers. Most new HDLs solve this today by compiling
down to Verilog or SystemVerilog, which acts as the ecosystem's de facto
interchange format.

This provides compatibility, but it is not a neutral intermediate
representation. The source language's explicit concepts are encoded again as
Verilog constructs and coding patterns. Every downstream tool must then parse,
elaborate and recover the hardware semantics from that generated code, often
losing some of the original structure in the process.

An IR for hardware replaces this language-shaped interchange layer with a
shared representation whose concepts directly describe the hardware:

![NxM problem](./nxm-problem.png)

Many languages compiling to the IR, and all the consumers working with the IR.
This decouples the job of designing a _HDL_ with the work of developing an EDA
tool.

* A simulator developer can focus on simulation speed
* A synthesizer developer can focus on PPA improvements
* An HDL designer can focus on ergonomics and reuse

And all can benefit of the work of the others! This is the classical improvement
an IR gives, in which N consumers can use M producers _without_ requiring NxM
adapters. It's the same advantage LLVM gives C, Rust, and Swift: one shared
code generation backend instead of each language reinventing it.

In the case of _synchronous hardware_, there is a second benefit to having an
IR, that is to have a _semantic_ IR.

## A semantic IR for Synthesizable RTL

The main industry languages (VHDL and SystemVerilog) carry over an original sin:
they were not thought of and designed as synchronous hardware design languages,
but rather as _simulation_ languages for logic circuits. They mixed a Hardware
Verification Language and a Hardware Design Language into one.

Because of this, the languages do not have native support for fundamental
concepts such as clocks, resets, combinational logic or power domains, while
having support for _many_ unsynthesizable behavioral modeling constructs like
time delays and floating-point arithmetic, and many other features clearly meant
for testbenches: file I/O, randomization, dynamic memory allocation.

Instead of _true_ synthesizable RTL languages we have *discrete-event simulation
languages*. Under the correct code constraints, we _can_ describe a pure
Synthesizable RTL system, but this puts heavy pressure on the source code: we
have to be careful _not_ to use the wrong constructs or code may not be
synthesizable into hardware. How early this happens in the design cycle depends
on the work methodology used.

Current RTL simulators treat both RTL and TB code the same, so offer no
guarantees about erroring out on unsynthesizable constructs: these are often
present in simulation without the user noticing. Synthesizers do lower this
behavioral code into structural networks as a first step, and can in principle
detect these invalid constructs there, but the result isn't always explicit,
some become hard errors, many are just warnings buried in noise.

Linters can catch these errors too, but they are opt-in, mixed in with
code-style warnings, and easy to waive without noticing.

An IR layer providing these semantic concepts, and erroring out on invalid code
by construction, solves all of these problems at once. By "semantic" here we
mean something specific: the IR's syntax directly _is_ its meaning. A register
in the IR is a register, not a pattern a compiler has to infer from an `always`
block. There's no gap between what's written and what it does.

### How does a Semantic IR for RTL look like?

Synthesizable RTL has a great advantage, and it's that, taken to its
fundamental representation, it is extremely simple. Any Synthesizable RTL
module, no matter its size or complexity, needs only two elements to be fully
specified:

* Registers: the set of memory elements holding the state of the system. These
  interact with two types of signals: async signals (clock and reset) and sync
  (data)
* Transfer function: the function relating the module inputs and outputs to its
  registers' inputs and outputs. This is a pure DAG which interacts _only_ with
  sync signals.

With just these two components we can describe any Synthesizable RTL block:
from a simple 4-bit counter to a fully fledged RISC-V core with custom hardware
accelerators. In the first case we have 4 registers and a small transfer
function, for the latter we may have hundreds of thousands of registers and a
massive transfer function. Same two elements, just scaled up.

Compare this to CIRCT, whose dialects give memories, FIFOs, and even instance
hierarchy their own dedicated operations. In MateIR none of that exists as a
separate concept: a FIFO is just registers and a DAG, hierarchy is just a
label, and a memory is an external block the RTL interfaces to. This means a
compiler or analysis pass targeting MateIR never needs special-case handling
for memories, FIFOs, or hierarchy, it's the same registers-plus-DAG logic every
time, regardless of what the source design represents.

This framing gives meaning to the RTL acronym: _Register Transfer Level_. The
following diagram illustrates this simple structure:

![Synchronous digital hardware](./sdh.png)

A good semantic IR _exploits_ this simplicity to facilitate the development of
tools consuming it, instead of making them fight the complex discrete-event
semantics of current HDLs. The job of any compiler becomes lowering the
high-level constructs into this simple structure, and the job of a consumer is
greatly simplified.

The transfer function DAG is built from a small set of synthesizable
word-level operators: arithmetic (SUB, ADD, MUL), muxing and slicing, and
bitwise ops (AND, OR, XOR). Restricting it to operators with obvious bit-level
lowering keeps the DAG compact and easy to analyze, while making the eventual
translation to bit-level synthesis straightforward.

Because clocks and sequential elements are explicit in the IR, a CDC tool does
not first need to infer clock domains and register boundaries from procedural
HDL semantics. It can directly identify signals crossing between domains and
then perform the harder analysis on top of that structure: recognizing
synchronizers and handshakes, checking multi-bit crossings and reconvergence,
and detecting unsafe asynchronous paths.

Compiling into this IR is then a two-part job for any frontend, regardless of
source language: identify all the registers (their type, clock and reset
ports, data ports), and construct the combinational DAG relating them. For
"classical" event-driven languages like VHDL and SystemVerilog this first part
is harder, since registers must be inferred from procedural code rather than
read off directly. But the target shape the compiler is building towards never
changes, whether the source is a 4-bit counter or a RISC-V core.

## Implications for Digital Design Flow

Having RTL compiled into this semantic IR, means that _only_ Synthesizable RTL
designs are valid to be simulated and carried over the whole digital design
flow.

![Synchronous digital hardware](./ddf.svg)

### Early generic synthesis

With a proper semantic IR, meaning, compiling IR into a timing-aware word-level
netlist, many tasks are pushed to the left of the flow, with the RTL
development. Unintended latches, unsynthesizable logic, combo loops, all become
blockers for IR compilation, thus blocking the _whole_ flow. They are no longer
something to be found buried among thousands of lines of linter output, or only
after the initial synthesis is done.

### Decoupling of RTL and TB

Another important point is the _decoupling_ of the RTL and TB development, and
thus, languages. We could have an RTL design in VHDL, compile it into the IR and
then simulate this from a SystemVerilog TB. More importantly, we decouple TB
development and coding from hardware semantics. TB design and development would
get into the purely software domain: it becomes the development of a program
that interacts with a clearly specified interface with a hardware model.

Currently, even though Verification is a pure software job, it is very hard to
introduce Software Engineers into Verification, because of the heavy coupling
between HDL and TB language. Defining a clear hardware IR with a clear timing
access model, reduces this complexity to understanding this interface:
everything communicating with it is pure software.

### Clear interface for simulation software

Alongside the decoupling of TB and RTL, the interface for simulation software
becomes much clearer. We have an IR block with its inputs, outputs and internal
state. The simulator advances its clocks and resets, applies synchronous input
changes at defined points, evaluates the combinational network and updates the
register state.

Scheduling may still be needed at the testbench boundary, particularly when
coordinating multiple clocks, asynchronous resets and software callbacks. But
the RTL block itself no longer needs to be interpreted through a general
discrete-event scheduler: it is evaluated as an explicit synchronous state
transition system.

### HLS-like analysis

Another gain is the lowering of HLS-like analysis and optimizations to the RTL
level. Given an RTL description compiled to the IR, we already know all the
flops and arithmetic operators we have. Analysis of time sharing or
parallelization architectures becomes possible given the knowledge of these
operators. With the current flow, for an RTL level analysis this information can
only be obtained after synthesis, which exposes these numbers but after boolean
and timing optimization, which brings noise to a purely architectural analysis.

### LLM assisted development

A major win of such a workflow in the age of AI, with LLMs producing thousands
of lines of code per day, is the guarantee that any RTL code compiling into the
IR is already synthesizable and valid for synchronous hardware.

On TB development, a good amount of effort needs to be invested "teaching" the
agent how to properly drive an RTL module: drive always on `posedge clk`, use
always `NBA`, rules which many times the LLM "forgets".

Using a semantic IR which by design allows only synthesizable designs, reduces
this complex rules to a reality enforced by the compiler. The agent itself will
conclude by the compilation failure that there are errors in the driving
methodology. We get the classical and massive advantage of converting run time
errors (most of the times not even reported) into compile errors (clearly
reported).

## Summary

We'll have later posts explaining the IR implementation in detail. The important
point to note here, is that the IR _must_ already incorporate the concepts of
clocks, resets, registers and combinational logic. This makes compiling from
languages without these concepts harder, but makes the work of _all_ consumers
much easier:

* For a simulator, it no longer needs to worry about scheduling or races: its only
  concern is advancing the state of the flops and computing the combinational
  network
* For a synthesizer, the first step of generic synthesis has already been done.
  Now its focus is to perform boolean synthesis from word-level operators and
  timing optimization.
* Any static tool targeting CDC/RDC analysis, power analysis, or formal
  verification has, like synthesis, half of the work done. The tools can focus
  on actual analysis of a word-level synchronous system and not on
  _interpreting_ a event-based pseudo-HDL

Any language with a proper compiler for the IR gets access to all of these
tools for free. That's the whole point: write your HDL once, and every
consumer built against MateIR just works.
