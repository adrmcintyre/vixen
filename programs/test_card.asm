def COLS 64
def ROWS 40
def VIDEO 0x10000 - (.ROWS * .COLS)

alias r0  video
alias r1  ch
alias r2  n
alias r3  x
alias r4  y
alias r5  dx
alias r6  dy
alias r12 tmp
alias r13 sp
alias r14 link
alias r15 pc

    org 0x0000
.init
    ; setup registers
    mov video, hi(.VIDEO)
    add video, lo(.VIDEO)
    mov sp, video

.main
    mov ch, 0xa4
    bl .clear
    bl .draw_table
    bl .draw_ascii
    bl .draw_row_nums
    bl .draw_col_nums
    hlt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .draw_table()
.draw_table
    sub sp, 2
    stw link, [sp]
    mov tmp, hi(.table)
    add tmp, lo(.table)
.draw_table_loop
    ldb ch, [tmp, 0]
    orr ch, ch
    preq
    bra .exit_draw_table
    ldb n,  [tmp, 1]
    ldb x,  [tmp, 2]
    ldb y,  [tmp, 3]
    ldb dx, [tmp, 4]
    ldb dy, [tmp, 5]
    add tmp, 6
    bl .draw
    bra .draw_table_loop
.exit_draw_table
    ldw link, [sp]
    add sp, 2
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE draw_row_nums()

.draw_row_nums
    sub sp, 2
    stw link, [sp]

    mov x, 8
    mov y, 0
    mov ch, '0'
.draw_row_nums_loop
    bl .char_at
    add ch, 1
    mov tmp, '9'+1
    cmp ch, tmp
    preq
    mov ch, '0'
    add y, 1
    mov tmp, .ROWS
    cmp y, tmp
    prne
    bra .draw_row_nums_loop
.draw_row_nums_exit
    ldw link, [sp]
    add sp, 2
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE draw_col_nums()

.draw_col_nums
    sub sp, 2
    stw link, [sp]

    mov x, 0
    mov y, 8
    mov ch, '0'
.draw_col_nums_loop
    bl .char_at
    add ch, 1
    mov tmp, '9'+1
    cmp ch, tmp
    preq
    mov ch, '0'
    add x, 1
    mov tmp, .COLS
    cmp x, tmp
    prne
    bra .draw_col_nums_loop
.draw_col_nums_exit
    ldw link, [sp]
    add sp, 2
    mov pc, link



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE draw_ascii()
.draw_ascii
    sub sp, 2
    stw link, [sp]
    mov ch, 0

.draw_ascii_loop
    mov tmp, 0x0f
    mov x, ch
    and x, tmp
    add x, (.COLS-16) / 2

    mov y, ch
    lsr y, 4
    add y, (.ROWS-16) / 2

    bl .char_at
    add ch, 1
    tst ch, bit 8
    preq
    bra .draw_ascii_loop

.exit_draw_ascii
    ldw link, [sp]
    add sp, 2
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .clear(ch)
.clear
    stw tmp, [sp]
    sub sp, 2

    mov tmp, ch
    lsl ch, 8
    orr ch, tmp
    mov tmp, video
.clear_loop
    stw ch, [tmp,0]
    stw ch, [tmp,2]
    stw ch, [tmp,4]
    stw ch, [tmp,6]
    stw ch, [tmp,8]
    stw ch, [tmp,10]
    stw ch, [tmp,12]
    stw ch, [tmp,14]
    add tmp, 16
    prcc
    bra .clear_loop
.exit_clear_loop
    add sp, 2
    ldw tmp, [sp]
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .draw(ch, n, x, y, dx, dy)
.draw
    sub sp, 2
    stw link, [sp]
.draw_loop
    bl .char_at
    sub n, 1
    preq
    bra .exit_draw_loop
    add x, dx
    add y, dy
    bra .draw_loop
.exit_draw_loop
    ldw link, [sp]
    add sp, 2
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .char_at(ch, x, y)
.char_at
    sub sp, 2
    stw tmp, [sp]

    ; sanity check (x,y)
    mov tmp, .ROWS
    cmp y, tmp
    prhs
    bra .exit_char_at
    mov tmp, .COLS
    cmp x, tmp
    prhs
    bra .exit_char_at

    mov tmp, y
    lsl tmp, 6
    add tmp, x
    add tmp, video
    stb ch, [tmp]

.exit_char_at
    ldw tmp, [sp]
    add sp, 2
    mov pc, link

.table
    ; vertical lines, first col
    ;  ch    n  x  y   dx dy
    db 0x80, 4, 0, 4,  0, 1
    db 0x81, 4, 0, 8,  0, 1
    db 0x82, 4, 0, 12, 0, 1
    db 0x83, 4, 0, 16, 0, 1
    db 0x84, 4, 0, 20, 0, 1
    db 0x85, 4, 0, 24, 0, 1
    db 0x86, 4, 0, 28, 0, 1
    db 0x87, 4, 0, 32, 0, 1
    db 0xa2, 1, 2, 4,  0, 1
    db 0xa2, 1, 2, 35, 0, 1

    ; vertical lines, last col
    ;  ch    n  x  y   dx dy
    db 0x80, 4, 63, 4,  0, 1
    db 0x81, 4, 63, 8,  0, 1
    db 0x82, 4, 63, 12, 0, 1
    db 0x83, 4, 63, 16, 0, 1
    db 0x84, 4, 63, 20, 0, 1
    db 0x85, 4, 63, 24, 0, 1
    db 0x86, 4, 63, 28, 0, 1
    db 0x87, 4, 63, 32, 0, 1
    db 0xa3, 1, 61, 4,  0, 1
    db 0xa3, 1, 61, 35, 0, 1

    ; horiz lines, first row
    ;  ch    n  x   y   dx dy
    db 0x88, 7, 4,  0,  1, 0
    db 0x89, 7, 11, 0,  1, 0
    db 0x8a, 7, 18, 0,  1, 0
    db 0x8b, 7, 25, 0,  1, 0
    db 0x8c, 7, 32, 0,  1, 0
    db 0x8d, 7, 39, 0,  1, 0
    db 0x8e, 7, 46, 0,  1, 0
    db 0x8f, 7, 53, 0,  1, 0
    db 0xa0, 1, 4,  2,  1, 0
    db 0xa0, 1, 59, 2,  1, 0

    ; horiz lines, last row
    ;  ch    n  x   y   dx dy
    db 0x88, 7, 4,  39, 1, 0
    db 0x89, 7, 11, 39, 1, 0
    db 0x8a, 7, 18, 39, 1, 0
    db 0x8b, 7, 25, 39, 1, 0
    db 0x8c, 7, 32, 39, 1, 0
    db 0x8d, 7, 39, 39, 1, 0
    db 0x8e, 7, 46, 39, 1, 0
    db 0x8f, 7, 53, 39, 1, 0
    db 0xa1, 1, 4,  37, 1, 0
    db 0xa1, 1, 59, 37, 1, 0

    db 0x00
