PROGRAM = programs/hello_world.asm
YOSYS = yosys
NEXTPNR = nextpnr-ecp5
ECPPACK = ecppack
VERILATOR = verilator
ALL_SOURCES = $(wildcard *.v video/*.v)
SOURCES = $(filter-out harness.v, $(ALL_SOURCES))

.PHONY: all
all: out/output.bit

out/output.ys: $(SOURCES)
	./ysgen.sh $(SOURCES) > $@
	echo "hierarchy -top top" >> $@
	echo "synth_ecp5 -json out/output.json" >> $@
	echo "write_verilog -norename out/output.v" >> $@

out/mem.bin.0 out/mem.bin.1: $(PROGRAM)
	./asm.pl $(PROGRAM)

out/font.bin: font.asc
	./make-font.pl $< >$@

out/output.json: out/output.ys out/font.bin out/mem.bin.0 out/mem.bin.1
	$(YOSYS) -v2 out/output.ys

out/output.config: out/output.json
	$(NEXTPNR) --package CABGA381 --12k --json $< --lpf ulx3s.lpf --textcfg $@

out/output.bit: out/output.config
	$(ECPPACK) --input $< --bit $@

.PHONY: lint
lint: $(SOURCES)
	$(VERILATOR) --timing --timescale 1ns/1ns --lint-only $^ 2>&1 | tee out/lint.log

.PHONY: prog
prog: out/output.bit
	fujprog $<

.PHONY: clean
clean:
	rm -f out/*

.PHONY: test
test: $(ALL_SOURCES) out/font.bin
	./test.sh | tee out/test.log

