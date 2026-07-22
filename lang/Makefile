.PHONY: all
all: lang

lang: *.c *.h
	gcc -g -o $@ *.c -I.

.PHONY: clean
clean:
	rm -f lang

.PHONY: run
run: lang
	./lang
