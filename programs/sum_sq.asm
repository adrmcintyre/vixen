;; Compute sum of squares in r0, r1: result in r3
;;
;; 0x52**2 + 0xe7**2 = 0xeab5
;;
        mov r0, 0x52
        mov r1, 0xe7

        mov r4, r1  ; save r1
        mov r1, r0
        bl  .mul
        mov r3, r2
        mov r0, r4  ; restore
        mov r1, r0
        bl  .mul
        add r3, r2
        hlt

.mul    mov r2, 0
.loop   tst r0, bit 0
        prne
        add r2, r1
.skip   lsl r1, 1
        lsr r0, 1
        prne
        bra .loop
        mov r15, r14


