---js
const title = "An IR for Synchronous Hardware";
const date = "2026-06-27";
const draft = true;
---

# Motivation for a IR

The last ~15 years, there has been a great surge in development of HDL languages
* Chisel
* Clash
* Verilog-TL
* Veryl
* Amaranth
* SpinalHDL
* Spade

All of these provide superior characteristics over the current industry standard
languages which are SystemVerilog and VHDL: better semantics (incorporating
registers and combo logic at the language level), better language features,
better code reuse capabilities.

Along these languages, during the same last past years, the most prominent
open-source EDA tools have recibed major development, being capable now of
simulating and synthesizing relatively large designs. Projects like tinytapeout
are consistenly taping out, albeit small, projects using 100% open-source
tooling.

There is however, a disconnect between the innovations in the _frontend_ aspect,
that is, HDLs, and the _backend_ tooling (simulators, synthesizers, etc).
Currenlty, most frontend open source tools support _only_ systemverilog, and not
with full support.

An IR for hardware can solve this issue. Following diagram shows the solution:

![NxM problem](./nxm-problem.png)

Many languages compiling to the IR, and all the consumers working with the IR.
This decouples the job of designing a _HDL_ with the work of developing an EDA
program.

* A simulator developer can focus on simulation speed
* A synthesizer developer can focus on PPA imprevements
* An HDL designer can focus on ergonomics and reuse

And all can benefit of the work of the others! This is the classical improvement
an IR gives, in which N consumers can use M producers _without_ requiring NxM
adapters. This has been the advantage given by LLVM with C, C++, Swift and Rust
languages (just to name a few) being able to reuse the same highly efficient
code generation for distinct targets like x86 or ARM.

In the case of _synchronous hardware_, there is a second benefit to having an
IR, that is to have a _semantic_ IR.

# A semantic IR for Synchronous Hardware

The main industry languages (VHDL and SystemVerilog) carry over an original sin:
they were not thought of and designed as synchronous hardware design languages,
but rather as _simulation_ languages for logic circuits. They mixed a Hardware
Verification Language and a Hardware Design Language into one.

Because of this, the languages do not have native support for fundamental
concepts such as Clocks, resets, combinational logic or power domains. What they
are is languages that work in terms of _events_. That is, they are more general
than a language focused at _just_ describing synchronous hardware. As we see in
this diagram, synchronous hardware circuits (the target design for _any_
ASIC/FPGA design) are a much smaller subset of what these event-based languages
allow to express:

![venn diagram](./event-based-systems.png)

This brings lots of problems and uncertainty to the design process:

* Synthesizable vs non-synthesizable constructs
* Synthesis and simulation mismatches
* Fundamental design aspects as CDC and RDC requiring complex programs

## How does a Semantic IR look like?

Any synchronous digital system is extremely simple _structurally_.  It is
defined by _just_ the following components:

* A set of inputs
* A set of outputs
* A set of flops
* A combinational network

Following image shows such a simple system:

![Synchrnous digital hardware](./sdh.png)

(We are purposively not including async resets, multiple clock domains or power
domains, but these concepts are just a simple build up upon this very simple
system. More on this later...)

What's powerful about DSH is that it can describe systems as complex as modern
TPU or GPUs based on this very simple structural definition.

It's important to note here we are not defining any _hierarchy_, something very
common in RTL design. We reduce the system to its simplest form by merging
everything into a single global module. Hierarchy still exists but simply as
metadata (this flop/gate belongs to this scope). More on why this is _necessary_
later...

Given this simple representation, for any Synchronous digital system, the IR
just holds information about the 4 components

* The list of inputs with their data types and clock domains (clock and reset
  included here)
* The list of outputs with their data types and clock domains
* All the flops with their info
* The combinational network, a DFG represented as a DAG of word-level operators

It's important to take into accout that the combo network is a set of word-level
operators, not bit-level. This makes the netlist simpler to anlayze and
eventually simulate. The list of operators is small and restricted to ones with
obvious bit-level lowering

* Arithmetic: SUB, ADD, MUL
* MUX and SLICE
* Bit-level: AND, OR, XOR, etc

## Implications for Digital Design Flow

Having RTL compiled into a semantic IR, means that _only_ RTL designs which
represent synchronous hardware are valid to be simulated and carry over the
whole digital design flow. 

![Synchrnous digital hardware](./ddf.svg)

With a proper semantic IR, many tasks are pushed to the left of the flow, with
the RTL development. Unintended latches, unsynthesizable logic, combo loops, all
become blockers for IR compilation, thus blocking the _whole_ flow. They are no
longer something to be catch with thousands of lines of linter code, or only
after the initial synthesis is done.

Another important point is the _decoupling_ of the RTL and TB development, and
thus, languages. We could have an RTL design in VHDL, compile it into the IR and
then simulate this from a SystemVerilog TB.

Another gain is the lowering of HLS-like analysis and optimizations to the RTL
level. Given an RTL description compiled to the IR, we already know all the
flops and arithmetic operators we have. Analysis of time sharing or
parallelization architectures become possible given the knowledge of these
operators. With the current flow, for an RTL level analysis this information can
only be obtained after synthesis, which exposes these numbers but after boolean
and timing optimization, which brings noise to a purely architectural analysis.

And a major win of such a workflow in the age of AI and LLMs producing thousand
of lines of code per day, is the guarantee that any compiling (into the IR) RTL
code is already synthesizable able and valid for synchronous hardware.

# Summary

We'll have later posts explaining the semantic IR in detail. The important point
to note here, is that the IR _must_ already incorporate the concepts of clocks,
resets, registers and combinational logic. This makes compiling from languages
without these concepts herders, but makes the work of _all_ consumers much
easier

* For a simulator, it must _not_ worry about scheduling or races: its only
  concern is advancing the state of the flops and computing the combinational
  network
* For a synthesizer, the first step of generic synthesis has already been done.
  Now its focus is to perform boolean synthesis from word-level operators and
  timing optimization.
* Any static tool targeting CDC/RDC analysis, power analysis, or formal
  verification has, like synthesis, half of the work done. The tools can focus
  on actual analysis of a word-level synchronous system and not on
  _interpreting_ an HDL

Plus, any language with a proper compiler for the IR can use any of these tools.
