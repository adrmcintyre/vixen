.PHONY: all
all: lang

lang: *.c
	gcc -o $@ $^ -I.

.PHONY: clean
clean:
	rm -f lang

.PHONY: run
run: lang
	./lang
