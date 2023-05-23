;; Compute sum of squares
;;
;; 0x30 * 0x30 + 0x40 * 0x40 = 0x1900
;;
        mov r0, 0x30
        mov r1, 0x30
        bl  .mul
        mov r3, r2
        mov r0, 0x40
        mov r1, 0x40
        bl  .mul
        add r3, r2
        hlt

.mul    mov r2, 0
.loop   tst r0, bit 15
        beq .skip
        add r2, r1
.skip   lsl r1, 1
        lsr r0, 1
        bne .loop
        mov r15, r14


