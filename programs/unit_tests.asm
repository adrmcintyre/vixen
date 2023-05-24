; unit tests

    mov r0, 0   ; keep r0 as zero

    ; writing flags
    mov r1, 0xf000  ; NZCV
    wrf r1
    blpl .fail   ; N should be set
    blne .fail   ; Z should be set
    blcc .fail   ; C should be set
    blvc .fail   ; V should be set

    ; reading flags
    rdf r2
    cmp r1, r2
    blne .fail
    
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
