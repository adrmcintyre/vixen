
def COLS 64
def ROWS 40
def VIDEO 0x10000 - (.ROWS * .COLS)

alias r6 vaddr
alias r7 counter
alias r13 sp
alias r14 link
alias r15 pc

    mov vaddr, hi(.VIDEO)
    add vaddr, lo(.VIDEO)
    mov counter, .ROWS

.wrstr
    mov r0, vaddr       ; dst
    mov r1, hi(.GREET)  ; src
    add r1, lo(.GREET)
    bl .strcpy

    add vaddr, .COLS+1  ; down 1, right 1
    sub counter, 1
    prne
    bra .wrstr

    hlt

    ;; strcpy(dst, src)

alias r0 dst
alias r1 src
alias r2 tmp
alias r3 tmp2

.strcpy
    mov tmp2, 0xff
    ldb tmp, [src]
    and tmp, tmp2
    preq
    mov r15, r14
    stb tmp, [dst]
    add dst, 1
    add src, 1
    bra .strcpy

.GREET
    ds "Hello, world!"
    db 0
    db 0
    align
 
org .VIDEO+0*64
ds "Hello, world!"
org .VIDEO+1*64
ds "--Hello, brave new world!"
org .VIDEO+3*64
ds "------Greetings, UNIVERSE"
org .VIDEO+6*64
ds "------------Beep BOOP intergalactic beings #@%!"
org .VIDEO+7*64
ds "-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*"

org 0x10000-4*6
ds "HELLO-"
ds "world!"
ds "123456"
ds "#@$%^&"

