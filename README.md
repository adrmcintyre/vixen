# vixen
This is "my first FPGA 16-bit computer" implemented in Verilog,
targetting the Radiona ULX3S dev board.

See https://github.com/YosysHQ/oss-cad-suite-build#installation
for the toolchain to be used to build this project.

It implements a 16-bit RISC style processor, with
an instruction set somewhat inspired by ARM, a
64K address space with memory mapped I/O, and a
video controller which can output both character
based and bit-plane video modes to VGA over DVI.

Video is currently the only I/O device, with
PS2 keyboard, and multi channel audio synthesis
to come later.

An assembler is provided to convert assembly
language programs to the required memory format
for verilog's `$loadmemh`.

See the `programs/` directory for examples.
