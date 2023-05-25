; unit tests

    def N 0x8000
    def Z 0x4000
    def C 0x2000
    def V 0x1000

    ; writing flags
    mov r1, .N
    wrf r1
    blpl .fail
    mov r1, .Z
    wrf r1
    blne .fail
    mov r1, .C
    wrf r1
    blcc .fail
    mov r1, .V
    wrf r1
    blvc .fail

    ; reading flags
    mov r1, 0xf000
    wrf r1
    rdf r2
    cmp r1, r2
    blne .fail

    ; verify mov reg
    mov r0, 0x5f00
    mov r1, r0
    cmp r0, r1
    blne .fail

    ; verify mvn
    mov r0, 0xff00
    mvn r0, r0
    mov r1, 0x00ff
    cmp r0, r1
    blne .fail

    ; verify add
    mov r0, 0xe600
    mov r1, 0x1900
    mov r2, 0xff00
    mov r4, .C      ; set carry - add should ignore it
    wrf r4
    add r0, r1      ; 32 bit add
    blcs .fail
    cmp r0, r2
    blne .fail

    ; verify carry out
    mov r0, 0xe600
    mov r1, 0x1a00
    mov r2, 0x0000
    mov r4, .C      ; set carry - add should ignore it
    wrf r4
    add r0, r1      ; 32 bit add
    blcc .fail
    cmp r0, r2
    blne .fail

    ; verify adc
    mov r0, 0xe600
    mov r1, 0x1900
    add r1, 0x00ff
    mov r2, 0
    mvn r2, r2      ; ffff
    mov r4, 0       ; clear carry
    wrf r4
    add r0, r1      ; 32 bit add
    blcs .fail
    cmp r0, r2
    blne .fail

    ;; ; verify adc with carry in
    ;; mov r0, 0xe600
    ;; mov r1, 0x1900
    ;; add r1, 0x00ff
    ;; mov r2, 0
    ;; mov r4, .C      ; clear carry
    ;; wrf r4
    ;; add r0, r1      ; 32 bit add
    ;; blcc .fail
    ;; cmp r0, r2
    ;; blne .fail

    ; verify carry out
    mov r0, 0xe600
    mov r1, 0x1a00
    mov r2, 0x0000
    mov r4, .C      ; set carry - add should ignore it
    wrf r4
    add r0, r1      ; 32 bit add
    blcc .fail
    cmp r0, r2
    blne .fail

    ; verify sub, sbc
    mov r0, 0x0006  ; r0,r1 = 0x00063000
    mov r1, 0x3000
    mov r2, 0x0003  ; r2,r3 = 0x00035000
    mov r3, 0x5000
    mov r4, 0       ; clear carry (i.e. set borrow) - sub should ignore it
    wrf r4
    sub r1, r3      ; 32 bit subtract
    sbc r0, r2
    mov r2, 0x0002  ; should equal 0x0002e000
    mov r3, 0xe000
    cmp r0, r2
    bne .fail
    cmp r1, r3
    bne .fail
    
    ; flags are .Z.. after 0+0
    mov r1, 0
    add r1, 0
    blmi .fail
    blne .fail
    blcs .fail
    blvs .fail

    ; flags are .... after 0x7f00 + 0x80
    mov r1, 0x7f00
    add r1, 0x80
    blmi .fail
    bleq .fail
    blcs .fail
    blvs .fail

    ; flags are N..V after 0x7f80 + 0x80 (overflow)
    mov r1, 0x7f00
    add r1, 0x80
    add r1, 0x80
    blpl .fail
    bleq .fail
    blcs .fail
    blvc .fail

    ; flags are N... after 0 + -1
    mov r0, 0
    mvn r1, r0
    add r0, r1
    blpl .fail
    bleq .fail
    blcs .fail
    blvs .fail

    ; flags are N... after 0 - 1
    mov r0, 0
    mov r1, 1
    nop
    sub r0, r1
    nop
    blpl .fail
    bleq .fail
    blcs .fail ;; fails here
    blvs .fail

    ; logical not is correct
    mov r0, 0xa600
    add r0, 0x0031
    mov r1, 0x5900
    add r1, 0x00ce
    mvn r0, r0
    cmp r0, r1
    blne .fail


;; r14 will be 0 on success
.succ       
    mov r14, 0
    hlt

;; r14 will be address of failure
.fail       
    rdf r13
    sub r14, 2
    wrf r13
    hlt
