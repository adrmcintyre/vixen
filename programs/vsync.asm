;; This demonstrates the various handler vectors

def RESET_VECTOR 0x0000
def TRAP_VECTOR  0x0004
def SWI_VECTOR   0x0008
def IRQ_VECTOR   0x000c

def SUPER_STACK  0x8000

def IOCTL_BASE 0xfd00
def IOCTL_ENABLED 0x00
def IOCTL_PENDING 0x02

alias r15 pc

org .RESET_VECTOR
    ldw pc, [pc]
    dw .reset_handler

org .TRAP_VECTOR
    hlt
    hlt

org .SWI_VECTOR
    hlt
    hlt

org .IRQ_VECTOR
    mov r13, #hi(.SUPER_STACK)
    add r13, #lo(.SUPER_STACK)
    sub r13, #4
    stw r1, [r13, #0]
    stw r2, [r13, #2]

    mov r1, #hi(.IOCTL_BASE)
    add r1, #lo(.IOCTL_BASE)
    ldw r2, [r1, #.IOCTL_PENDING]
    tst r2, #bit 0                  ; was it vsync?
    preq
    bra .irq_done
    mov r2, #bit 0
    stw r2, [r1, #.IOCTL_PENDING]   ; clear the interrupt
    add r0, #1

.irq_done
    ldw r1, [r13, #0]
    ldw r2, [r13, #2]
    add r13, #4                     ; redundant as r13 is not preserved between supervisor switches
    rtu r14

.reset_handler
    mov r1, #hi(.IOCTL_BASE)
    add r1, #lo(.IOCTL_BASE)
    mov r2, #bit 0                  ; vsync
    orr r2, #bit 15                 ; enable
    stw r2, [r1, #.IOCTL_ENABLED]

    mov r0, #0
    mov r1, #0
    mov r2, #0
    mrs r14, uflags
    orr r14, #bit 0      ;; enable interrupts
    msr uflags, r14
    mov r14, #.program
    rtu r14

.trap_handler
    hlt

org 0x0100
.program
    mov r0, #0
.self
    bra .self

