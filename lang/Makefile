.PHONY: all
all: lang

lang: lang.c vm.c stmts.c float.c
	gcc -o $@ $^ -I.

.PHONY: clean
clean:
	rm -f lang

.PHONY: run
run: lang
	./lang
