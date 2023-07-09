; unit tests

    def N bit 15
    def Z bit 14
    def C bit 13
    def V bit 12

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY READ / WRITE FLAGS

    mov r1, #.N|.Z|.C|.V
    wrf r1
    mov r2, #0
    rdf r2
    cmp r1, r2
    prne
    bl .fail

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY PREDICATION

    ; First check with all flags clear
    mov r1, #0
    wrf r1
    prmi
    bl .fail
    preq
    bl .fail
    prcs
    bl .fail
    prvs
    bl .fail

    ; Check with each flag set in turn
    mov r1, #.N
    wrf r1
    prpl
    bl .fail
    mov r1, #.Z
    wrf r1
    prne
    bl .fail
    mov r1, #.C
    wrf r1
    prcc
    bl .fail
    mov r1, #.V
    wrf r1
    prvc
    bl .fail

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY REGISTER MOVES

    ; verify mov reg
    mov r0, #0x5f00
    mov r1, r0
    cmp r0, r1
    prne
    bl .fail

    ; verify mvn (move not)
    mov r0, #0xff00
    mvn r0, r0
    mov r1, #0x00ff
    cmp r0, r1
    prne
    bl .fail

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY ADD/ADC + SUB/SBC CARRY IN/OUT

    ; verify add ignores carry in
    mov r0, #0xe600
    mov r1, #0x1900
    mov r2, #0xff00
    mov r4, #.C
    wrf r4
    add r0, r1
    prcs
    bl .fail
    cmp r0, r2
    prne
    bl .fail

    ; verify add sets carry out
    mov r0, #0xe600
    mov r1, #0x1a00
    mov r2, #0x0000
    mov r4, #.C      ; set carry - add should ignore it
    wrf r4
    add r0, r1      ; 32 bit add
    prcc
    bl .fail
    cmp r0, r2
    prne
    bl .fail

    ; verify adc without carry in
    mov r0, #0xe600
    mov r1, #0x1900
    add r1, #0x00ff
    mov r2, #0
    mvn r2, r2      ; ffff
    mov r4, #0       ; clear carry
    wrf r4
    adc r0, r1      ; 32 bit add
    prcs
    bl .fail
    cmp r0, r2
    prne
    bl .fail

    ; verify adc with carry in
    mov r0, #0xe600
    mov r1, #0x1900
    add r1, #0x00ff
    mov r2, #0
    mov r4, #.C      ; set carry
    wrf r4
    adc r0, r1      ; 32 bit add
    prcc
    bl .fail
    cmp r0, r2
    prne
    bl .fail

    ; verify sub, sbc
    mov r0, #0x0006  ; r0,r1 = 0x00063000
    mov r1, #0x3000
    mov r2, #0x0003  ; r2,r3 = 0x00035000
    mov r3, #0x5000
    mov r4, #0       ; clear carry (i.e. set borrow) - sub should ignore it
    wrf r4
    sub r1, r3      ; 32 bit subtract
    sbc r0, r2
    mov r2, #0x0002  ; should equal 0x0002e000
    mov r3, #0xe000
    cmp r0, r2
    prne
    bl .fail
    cmp r1, r3
    prne
    bl .fail
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY ADD/SUB SET Z, N, V FLAGS CORRECTLY

    ; flags are .Z.. after 0+0
    mov r1, #0
    add r1, #0
    rdf r2
    mov r3, #.Z
    cmp r2, r3
    prne
    bl .fail

    ; flags are .... after 0x7f00 + 0x80
    mov r1, #0x7f00
    add r1, #0x80
    rdf r2
    mov r3, #0
    cmp r2, r3
    prne
    bl .fail

    ; flags are N..V after 0x7f80 + 0x80 (overflow)
    mov r1, #0x7f00
    add r1, #0x80
    add r1, #0x80
    rdf r2
    mov r3, #.N|.V
    cmp r2, r3
    prne
    bl .fail

    ; flags are N... after 0 + -1
    mov r0, #0
    mvn r1, r0
    add r0, r1
    rdf r2
    mov r3, #.N
    cmp r2, r3
    prne
    bl .fail

    ; flags are N... after 0 - 1
    mov r0, #0
    mov r1, #1
    nop
    sub r0, r1
    rdf r2
    mov r3, #.N
    cmp r2, r3
    prne
    bl .fail

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY LOGIC OPS

    ; logical not is correct
    mov r0, #0xa600
    add r0, #0x0031
    mov r1, #0x5900
    add r1, #0x00ce
    mvn r0, r0
    cmp r0, r1
    prne
    bl .fail

    ;; TODO verify remaining logic ops
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY SHIFT OPS

    ; verify asr preserves sign
    mov r0, #hi(0xffff)
    add r0, #lo(0xffff)
    asr r0, #1
    mov r1, #hi(0xffff)
    add r1, #lo(0xffff)
    cmp r0, r1
    prne
    bl .fail

    mov r0, #hi(0xfffc)
    add r0, #lo(0xfffc)
    asr r0, #1
    mov r1, #hi(0xfffe)
    add r1, #lo(0xfffe)
    cmp r0, r1
    prne
    bl .fail

    mov r0, #0x8000
    asr r0, #1
    mov r1, #0xc000
    cmp r0, r1
    prne
    bl .fail

    mov r0, #0x4000
    asr r0, #1
    mov r1, #0x2000
    cmp r0, r1
    prne
    bl .fail

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY COMPARISON OPS

    ;; TODO

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY BL / MOV R15, R14
    
    mov r0, #1       ; true
    mov r1, #0       ; set if instruction after bl executed
    mov r2, #0       ; set if call occurred
    mov r3, #0       ; set if instruction after return executed
    bl .bl_call
    mov r1, r0
    cmp r1, r0
    prne
    bl .fail        ; instruction after bl did not execute!
    cmp r2, r0
    prne
    bl .fail        ; call did not occur!
    cmp r3, r0
    preq
    bl .fail        ; instruction after return executed!
    bra .bl_passed

    .bl_call
    mov r2, r0
    mov r15, r14
    mov r3, r0
    bl .fail        ; should be unreachable!

    ; skip to here if all tests passed
    .bl_passed

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; VERIFY LOAD / STORE

    mov r0, #0xab00  ; r0 = 0xab00  ; test patterns
    mov r1, #0x00ab  ; r2 = 0x00ab
    mov r2, #0x00cd  ; r1 = 0x00cd
    mov r3, r0
    add r3, r2      ; r3 = 0xabcd

    mov r4, #0x8000  ; test addr
    stw r3, [r4]
    ldw r5, [r4]
    cmp r5, r3      ; verify aligned word read
    prne
    bl .fail

    mov r5, #0x0000
    ldb r5, [r4]    ; verify aligned byte read equals high byte
    cmp r5, r1
    prne
    bl .fail

    mov r5, #0x0000
    ldb r5, [r4,#1]  ; verify unaligned byte read equals low byte
    cmp r5, r2
    prne
    bl .fail

    add r4, #0x11    ; 0x8011 - generate unaligned address
    stw r3, [r4]
    ldb r5, [r4]
    cmp r5, r1      ; verify high byte
    prne
    bl .fail

    ldb r5, [r4,#1]
    cmp r5, r2      ; verify low byte
    prne
    bl .fail

    ldw r5, [r4]    ; verify unaligned word read
    cmp r5, r3
    prne
    bl .fail


    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; SUCCESS!
    ; Halts with r14=0 on success
.pass       
    mov r14, #0
    hlt

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; FAILURE!
    ; Halts with r14=address of failed test on failure
.fail       
    rdf r13
    sub r14, #2
    wrf r13
    hlt
