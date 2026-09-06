
# C standard
CFLAGS=-std=c11

# all the warnings
CFLAGS+=-Wall -Wextra
CFLAGS+=-pedantic-errors 
#CFLAGS+=-Wshadow

# but disable these warnings
CFLAGS+=-Wno-gnu-flexible-array-initializer

# debug build
CFLAGS+=-g

.PHONY: all
all: lang

lang: *.c *.h
	gcc $(CFLAGS) -o $@ *.c -I.

.PHONY: clean
clean:
	rm -f lang
	rm -rf tests/tmp/

.PHONY: run
run: lang
	./lang

.PHONY: test
test: lang
	./run-tests.sh
