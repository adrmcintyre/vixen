.unit_test
{
    mov r13, #hi(.unit_test_data+2)
    add r13, #lo(.unit_test_data+2)

.loop
    ldw r0, [r13, #2]
    ldw r1, [r13, #4]
    bl .call
    ldw r3, [r13, #6]
    cmp r2, r3
    prne
    bra .failure
.continue
    add r13, #8
    mov r12, #hi(.unit_test_end)
    add r12, #lo(.unit_test_end)
    cmp r13, r12
    prne
    bra .loop
    bra .success

.success
    mov r13, #0
    mov r14, #0
    add r14, #0
    hlt

.failure
    ; On entry:
    ;       r2=got
    ;       r3=expected
    ;       r13=data pointer
    ;
    ;   Sets r14=ffff to indicate a failure, with:
    ;       r0=a
    ;       r1=b
    ;       r2=expected
    ;       r3=got
    ;       r4=test number
    mov r3, r2
    ldw r0, [r13, #2]
    ldw r1, [r13, #4]
    ldw r2, [r13, #6]
    ldw r4, [r13, #0]

    mov r14, #0
    sub r14, #1     ; signal that registers can error data
    mov r14, #0
    bra .continue
    hlt

.call
    mov r12, #hi(.unit_test_data)
    add r12, #lo(.unit_test_data)
    ldw r15, [r12]
}

org 0x1000
