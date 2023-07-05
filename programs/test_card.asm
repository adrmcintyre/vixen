def MEM_TOP 0xfc00
def IO_BASE 0xfc00

def VREG .IO_BASE + 0x000
def VGA_WIDTH 640
def VGA_HEIGHT 480
def VGA_HBACK 44
def VGA_VBACK 31

def VZOOM_1 0<<4
def VZOOM_2 1<<4
def VZOOM_3 2<<4
def VZOOM_4 3<<4

def HZOOM_1 0<<2
def HZOOM_2 1<<2
def HZOOM_3 2<<2
def HZOOM_4 3<<2

def MODE_TEXT 0<<0
def MODE_1BPP 1<<0
def MODE_2BPP 2<<0
def MODE_4BPP 3<<0

def TEXT_COLS 64
def TEXT_ROWS 40
def TEXT_BASE .MEM_TOP - .TEXT_COLS*.TEXT_ROWS

def GFX_BASE .MEM_TOP - 512*400/8

; well below video for safety
def STACK_BASE 0x1000-2

;; global aliases
alias r12 tmp
alias r13 sp
alias r14 link
alias r15 pc

    org 0x0000
.init
    mov sp, #hi(.STACK_BASE)
    add sp, #lo(.STACK_BASE)

   ;bl .text_test_card   ; display text test-card
    bl .gfx_test_card2   ; display graphics test-card

    hlt

.text_test_card {
    stw link, [sp]
    sub sp, #2

    ; set 64x40 text
    mov r0, #0
    bl .video_set_mode

    mov r0, #0xc0
    bl .text_clear
    bl .text_card_table
    bl .text_card_ascii
    bl .text_card_rows
    bl .text_card_cols

    add sp, #2
    ldw pc, [sp]
}

.gfx_test_card1 {
    alias r0 color
    alias r1 x
    alias r2 y
    alias r3 count
    alias r4 video
    alias r5 dx
    alias r6 dy

    stw link, [sp]
    sub sp, #8
    stw r4, [sp,#2]
    stw r5, [sp,#4]
    stw r6, [sp,#6]

    ; set 512x400 1bpp
    mov r0, #1
    bl .video_set_mode
    bl .gfx_clear

    mov color, #0xf000     ; mode1: 8080; mode2: c0c0; mode3: f0f0
    add color, #0x00f0
    mov x, #0
    mov y, #0
    mov count, #hi(200)    ; mode1: 400; mode2: 200; mode3: 200
    add count, #lo(200)    ; mode1: 400; mode2: 200; mode3: 200

    mov video, #hi(.GFX_BASE)
    add video, #lo(.GFX_BASE)

.loop
    ; clumsily plot a point
    mov tmp, video
    mov dy, y
    lsl dy, #7          ; mode1: 6; mode2: 6; mode3: 7
    add tmp, dy
    mov dx, x
    lsr dx, #1          ; mode1: 3; mode2: 2; mode3: 1
    add tmp, dx
    stb color, [tmp]

    ror color, #4          ; mode2: 1; mode3: 2; mode4: 4
    add x, #1
    add y, #1
    sub count, #1
    prne
    bra .loop

    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    ldw r6, [sp,#6]
    add sp, #8
    ldw pc, [sp]
}

.gfx_test_card2 {
    def centre_x 255
    def centre_y 200

    alias r4 px
    alias r5 py
    alias r6 count

    stw link, [sp]
    sub sp, #8
    stw r4, [sp,#2]
    stw r5, [sp,#4]
    stw r6, [sp,#6]

    ; set 512x400 1bpp
    mov r0, #1
    bl .video_set_mode
    bl .gfx_clear

    mov px, #20<<8
    mov py, #0
    mov count, #50

.loop
    mov r0, #.centre_x
    mov tmp, px
    asr tmp, #5
    mov r2, r0
    add r2, tmp     ; x2 = centre_x + px>>5
    asr tmp, #2
    add r0, tmp     ; x1 = centre_x + px>>7

    mov r1, #.centre_y
    mov tmp, py
    asr tmp, #5
    mov r3, r1
    add r3, tmp     ; y2 = centre_y + py>>5
    asr tmp, #2
    add r1, tmp     ; y1 = centre_y + py>>7

    bl .gfx_line

    sub count, #1
    preq
    bra .done

    mov r0, px
    asr r0, #3
    add py, r0

    mov r1, py
    asr r1, #3
    sub px, r1

    bra .loop

.done
    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    ldw r6, [sp,#6]
    add sp, #8
    ldw pc, [sp]
}

;; .gfx_clear()
;;
;; Clear video memory to zero.
;;
.gfx_clear {
    alias r0 zero
    alias r1 count

    mov tmp, #hi(.GFX_BASE)
    add tmp, #lo(.GFX_BASE)
    mov zero, #0x0000
    mov count, #hi(512*400/8)
    add count, #lo(512*400/8)
.loop
    stw zero, [tmp]
    stw zero, [tmp,#2]
    stw zero, [tmp,#4]
    stw zero, [tmp,#6]
    stw zero, [tmp,#8]
    stw zero, [tmp,#10]
    stw zero, [tmp,#12]
    stw zero, [tmp,#14]
    add tmp, #16
    sub count, #16
    prne
    bra .loop
    mov pc, link
}

;; .gfx_line(r0=x0, r1=y0, r2=x1, r3=y1, r4=mask, r5=color)
;;
;; TODO - clipping; other video modes; mask / color / dot-dash
;;
;; Draw a line from (x0,y0)->(x1,y1), clearing the bits in mask,
;; and xoring the bits in color:
;;
;;      mask=0 color=0 => clear bit
;;      mask=0 color=1 => set bit
;;      mask=1 color=0 => transparent
;;      mask=1 color=1 => invert
;;
.gfx_line {
    alias r0 x
    alias r1 y      ; only used during init
    alias r2 x2     ; only used during init
    alias r3 y2     ; only used during init
    alias r1 addr
    alias r2 count
    alias r3 err
    alias r4 ystep
    alias r5 dx
    alias r6 dy
    alias r7 addr
    alias r8 mask
    alias r9 pattern
    ; r10 unused
    ; r11 unused
    ; r12 tmp

    ;;   Slope <= 45         |          slope > 45
    ;; ----------------------+--------------------------
    ;;                       |
    ;;   l->r ...            |   top->bot             :
    ;;           ''...       |       :               :
    ;;                ''...  |        :             :
    ;;                       |         :           :
    ;;                  ...  |          :         :
    ;;             ...''     |           :       :
    ;;   l->r ...''          |            :  bot->top
    ;;


    sub sp, #12
    stw r4, [sp,#2]
    stw r5, [sp,#4]
    stw r6, [sp,#6]
    stw r7, [sp,#8]
    stw r8, [sp,#10]
    stw r9, [sp,#12]

    mov pattern, #0xff00
    add pattern, #0x00ff
    mov ystep, #512/8       ;; TODO stride
    mov tmp, #0

    mov dy, y2
    sub dy, y
    asl dy, #1          ;; dy = (y2-y)*2

    mov dx, x2
    sub dx, x
    asl dx, #1          ;; dx = (x2-x)*2

    prpl
    bra .pos_dx
    mov x, x2
    mov y, y2
    rsb dx, tmp
    rsb dy, tmp
.pos_dx
    cmp dy, tmp
    prpl
    bra .pos_dy
    rsb dy, tmp
    rsb ystep, tmp
.pos_dy
    mov tmp, #1<<7
    mov mask, tmp
    lsl mask, #8
    orr mask, tmp
    mov tmp, #7
    and tmp, x
    lsr mask, tmp

    mov addr, #hi(.MEM_TOP-512*400/8)
    add addr, #lo(.MEM_TOP-512*400/8)
    mov tmp, #512/8     ;; TODO - stride
    mul tmp, y
    add addr, tmp
    mov tmp, x
    lsr tmp, #3
    add addr, tmp   ;; addr = video_base + y*stride + x>>3

    cmp dx, dy
    prlo
    bra .steep

.shallow {
    mov count, dx
    lsr count, #1
    mov err, count

.loop
    ror pattern, #1
    prcc
    bra .skip
    ldb tmp, [addr]
    orr tmp, mask
    stb tmp, [addr]
.skip
    sub count, #1
    prmi
    bra .done

    sub err, dy
    prpl
    bra .no_ystep
    add err, dx
    add addr, ystep

.no_ystep
    add x, #1
    mov tmp, #7
    and tmp, x
    preq
    add addr, #1
    ror mask, #1

    bra .loop
}

.steep {
    mov count, dy
    lsr count, #1
    mov err, count

.loop
    ror pattern, #1
    prcc
    bra .skip
    ldb tmp, [addr]
    orr tmp, mask
    stb tmp, [addr]
.skip
    sub count, #1
    prmi
    bra .done

    sub err, dx
    prpl
    bra .no_xstep
    add err, dy
    add x, #1
    mov tmp, #7
    and tmp, x
    preq
    add addr, #1
    ror mask, #1

.no_xstep
    add addr, ystep
    bra .loop
}

.done
    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    ldw r6, [sp,#6]
    ldw r7, [sp,#8]
    ldw r8, [sp,#10]
    ldw r9, [sp,#12]
    add sp, #12
    mov pc, link
}


;; .video_set_mode(r0=mode)
;;
;; Set video mode 0..3
;;
.video_set_mode {
    alias r0 mode

    ; validate
    mov tmp, #4
    cmp mode, tmp
    prhs
    mov pc, link

    lsl mode, #1
    mov tmp, #hi(.mode_ptrs)
    add tmp, #lo(.mode_ptrs)
    add tmp, mode

    alias r0 entry
    alias r1 vreg
    alias r2 count

    ldw entry, [tmp]       ; point to data

.control {
    mov vreg, #hi(.VREG)
    add vreg, #lo(.VREG)
    mov count, #11          ; 11 registers
.loop
    ldb tmp, [entry]
    stb tmp, [vreg]
    add entry, #1
    add vreg, #1
    sub count, #1
    prne
    bra .loop
}

.palette {
    ldb count, [entry]        ; number of colours
    add entry, #1
    mov vreg, #hi(.VREG + 0x10) ; red palette
    add vreg, #lo(.VREG + 0x10)
.loop
    ldb tmp, [entry]
    stb tmp, [vreg]

    add vreg, #0x10         ; green palette
    ldb tmp, [entry,#1]
    stb tmp, [vreg]         

    add vreg, #0x10         ; blue palette
    ldb tmp, [entry,#2]
    stb tmp, [vreg]

    add entry, #3
    sub vreg, #0x20-1       ; back to red, but next entry

    sub count, #1
    prne
    bra .loop
}
    mov pc, link

.mode_ptrs {
    dw .mode_0
    dw .mode_1
    dw .mode_2
    dw .mode_3

.mode_0
    ; text 64x40
    dw .MEM_TOP - .TEXT_COLS * .TEXT_ROWS               ; base addr
    dw (.VGA_WIDTH  - .TEXT_COLS * 8) / 2 + .VGA_HBACK  ; vp_left
    dw (.VGA_WIDTH  + .TEXT_COLS * 8) / 2 + .VGA_HBACK  ; vp_right
    dw (.VGA_HEIGHT - .TEXT_ROWS * 8) / 2 + .VGA_VBACK  ; vp_top
    dw (.VGA_HEIGHT + .TEXT_ROWS * 8) / 2 + .VGA_VBACK  ; vp_bottom
    db .MODE_TEXT | .HZOOM_1 | .VZOOM_1
    db 2                    ; 2 colour palette
    db 0xff, 0xaa, 0xaa     ; 0=pink
    db 0x00, 0x00, 0xcc     ; 1=dark blue
    align

.mode_1
    ; 512x400, 1-bpp graphics
    dw .MEM_TOP - 512*400/8
    dw (.VGA_WIDTH  - 512) / 2 + .VGA_HBACK  ; vp_left
    dw (.VGA_WIDTH  + 512) / 2 + .VGA_HBACK  ; vp_right
    dw (.VGA_HEIGHT - 400) / 2 + .VGA_VBACK  ; vp_top
    dw (.VGA_HEIGHT + 400) / 2 + .VGA_VBACK  ; vp_bottom
    db .MODE_1BPP | .HZOOM_1 | .VZOOM_1
    db 2                    ; 2-colour palette
    db 0x00, 0x33, 0x00     ; 0=dark green
    db 0x22, 0xff, 0x22     ; 1=bright green
    align

.mode_2
    ; 256x400, 2-bpp graphics
    dw .MEM_TOP - 256*400/8 * 2
    dw (.VGA_WIDTH  - 256*2) / 2 + .VGA_HBACK  ; vp_left
    dw (.VGA_WIDTH  + 256*2) / 2 + .VGA_HBACK  ; vp_right
    dw (.VGA_HEIGHT - 400) / 2 + .VGA_VBACK  ; vp_top
    dw (.VGA_HEIGHT + 400) / 2 + .VGA_VBACK  ; vp_bottom
    db .MODE_2BPP | .HZOOM_2 | .VZOOM_1
    db 4                    ; 4-colour palette
    db 0x00, 0x00, 0x00     ; 0=black
    db 0xff, 0x00, 0x00     ; 1=red
    db 0x00, 0xff, 0x00     ; 2=green
    db 0xff, 0xff, 0xff     ; 3=white
    align

.mode_3
    ; 256x200, 4-bpp graphics
    dw .MEM_TOP - 256*200/8 * 4
    dw (.VGA_WIDTH  - 256*2) / 2 + .VGA_HBACK  ; vp_left
    dw (.VGA_WIDTH  + 256*2) / 2 + .VGA_HBACK  ; vp_right
    dw (.VGA_HEIGHT - 200*2) / 2 + .VGA_VBACK  ; vp_top
    dw (.VGA_HEIGHT + 200*2) / 2 + .VGA_VBACK  ; vp_bottom
    db .MODE_4BPP | .HZOOM_2 | .VZOOM_2
    db 16                   ; 16-colour palette
    db 0x00, 0x00, 0x00     ; 0=black
    db 0x7f, 0x00, 0x00     ; 1=dark-red
    db 0x00, 0x7f, 0x00     ; 2=dark-green
    db 0x7f, 0x7f, 0x00     ; 3=dark-yellow
    db 0x00, 0x00, 0x7f     ; 4=dark-blue
    db 0x7f, 0x00, 0x7f     ; 5=dark-magenta
    db 0x00, 0x7f, 0x7f     ; 6=dark-cyan
    db 0x7f, 0x7f, 0x7f     ; 7=light-grey
    db 0x55, 0x55, 0x55     ; 8=dark-grey
    db 0xff, 0x00, 0x00     ; 9=red
    db 0x00, 0xff, 0x00     ; 10=green
    db 0xff, 0xff, 0x00     ; 11=yellow
    db 0x00, 0x00, 0xff     ; 12=blue
    db 0xff, 0x00, 0xff     ; 13=magenta
    db 0x00, 0xff, 0xff     ; 14=cyan
    db 0xff, 0xff, 0xff     ; 15=white
    align
}
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_card_table()
.text_card_table {
    alias r0 ch     ; as used by text_draw
    alias r1 x      ; as used by text_draw
    alias r2 y      ; as used by text_draw
    alias r3 dx     ; as used by text_draw
    alias r4 dy     ; as used by text_draw
    alias r5 count  ; as used by text_draw
    alias r6 entry

    stw link, [sp]
    sub sp, #8
    stw r4, [sp,#2]
    stw r5, [sp,#4]
    stw r6, [sp,#6]

    mov entry, #hi(.text_card_data)
    add entry, #lo(.text_card_data)

.loop
    ldb ch, [entry, #0]
    orr ch, ch
    preq
    bra .done
    ldb x,    [entry, #1]
    ldb y,    [entry, #2]
    ldb dx,   [entry, #3]
    ldb dy,   [entry, #4]
    ldb count,[entry, #5]
    add entry, #6
    bl .text_draw
    bra .loop

.done
    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    ldw r6, [sp,#6]
    add sp, #8
    ldw pc, [sp]
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_rows()

.text_card_rows {
    alias r0 ch     ; as used by text_char_at
    alias r1 x      ; as used by text_char_at
    alias r2 y      ; as used by text_char_at

    stw link, [sp]
    sub sp, #2

    mov x, #8
    mov y, #0
    mov ch, #'0'

.loop
    bl .text_char_at

    add ch, #1
    mov tmp, #'9'+1
    cmp ch, tmp
    preq
    mov ch, #'0'
    add y, #1
    mov tmp, #.TEXT_ROWS
    cmp y, tmp
    prne
    bra .loop

.done
    add sp, #2
    ldw pc, [sp]
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_cols()

.text_card_cols {
    alias r0 ch     ; as used by text_char_at
    alias r1 x      ; as used by text_char_at
    alias r2 y      ; as used by text_char_at

    stw link, [sp]
    sub sp, #2

    mov x, #0
    mov y, #8
    mov ch, #'0'

.loop
    bl .text_char_at

    add ch, #1
    mov tmp, #'9'+1
    cmp ch, tmp
    preq
    mov ch, #'0'
    add x, #1
    mov tmp, #.TEXT_COLS
    cmp x, tmp
    prne
    bra .loop

.done
    add sp, #2
    ldw pc, [sp]
}



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_ascii()
.text_card_ascii {
    alias r0 ch     ; as used by text_char_at
    alias r1 x      ; as used by text_char_at
    alias r2 y      ; as used by text_char_at

    stw link, [sp]
    sub sp, #2

    mov ch, #0

.loop
    mov tmp, #0x0f
    mov x, ch
    and x, tmp
    add x, #(.TEXT_COLS-16) / 2

    mov y, ch
    lsr y, #4
    add y, #(.TEXT_ROWS-16) / 2

    mov r0, ch
    mov r1, x
    mov r2, y
    bl .text_char_at

    add ch, #1
    tst ch, #bit 8
    preq
    bra .loop

.done
    add sp, #2
    ldw pc, [sp]
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_clear(r0=ch)
.text_clear {
    alias r0 ch
    alias r1 count

    mov tmp, ch
    lsl ch, #8
    orr ch, tmp
    mov tmp, #hi(.TEXT_BASE)
    add tmp, #lo(.TEXT_BASE)
    mov count, #hi(.TEXT_ROWS*.TEXT_COLS/16)
    add count, #lo(.TEXT_ROWS*.TEXT_COLS/16)

.loop
    stw ch, [tmp,#0]
    stw ch, [tmp,#2]
    stw ch, [tmp,#4]
    stw ch, [tmp,#6]
    stw ch, [tmp,#8]
    stw ch, [tmp,#10]
    stw ch, [tmp,#12]
    stw ch, [tmp,#14]
    add tmp, #16
    sub count, #1
    prne
    bra .loop

.done
    mov pc, link
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_draw(ch, x, y, dx, dy, count)
.text_draw {
    alias r0 ch     ; as used by text_char_at
    alias r1 x      ; as used by text_char_at
    alias r2 y      ; as used by text_char_at
    alias r3 dx
    alias r4 dy
    alias r5 count

    stw link, [sp]
    sub sp, #6
    stw r4, [sp,#2]
    stw r5, [sp,#4]

.loop
    bl .text_char_at

    sub count, #1
    preq
    bra .done
    add x, dx
    add y, dy
    bra .loop

.done
    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    add sp, #6
    ldw pc, [sp]
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_char_at(ch, x, y)
;;
;; Guarantees not to corrupt ch, x, y.
;;
.text_char_at {
    alias r0 ch
    alias r1 x
    alias r2 y
    alias r4 video

    sub sp, #2
    stw video, [sp,#2]

    mov video, #hi(.TEXT_BASE)
    add video, #lo(.TEXT_BASE)

    ; sanity check (x,y)
    mov tmp, #.TEXT_ROWS
    cmp y, tmp
    prhs
    bra .done
    mov tmp, #.TEXT_COLS
    cmp x, tmp
    prhs
    bra .done

    mov tmp, y
    lsl tmp, #6
    add tmp, x
    add tmp, video
    stb ch, [tmp]

.done
    ldw video, [sp,#2]
    add sp, #2
    mov pc, link
}

.text_card_data
    ; vertical lines, first col
    ;  ch    x  y  dx dy  n
    db 0x80, 0, 4,  0, 1, 4
    db 0x81, 0, 8,  0, 1, 4
    db 0x82, 0, 12, 0, 1, 4
    db 0x83, 0, 16, 0, 1, 4
    db 0x84, 0, 20, 0, 1, 4
    db 0x85, 0, 24, 0, 1, 4
    db 0x86, 0, 28, 0, 1, 4
    db 0x87, 0, 32, 0, 1, 4
    db 0xa2, 2, 4,  0, 1, 1
    db 0xa2, 2, 35, 0, 1, 1

    ; vertical lines, last col
    ;  ch    x  y   dx dy  n
    db 0x80, 63, 4,  0, 1, 4
    db 0x81, 63, 8,  0, 1, 4
    db 0x82, 63, 12, 0, 1, 4
    db 0x83, 63, 16, 0, 1, 4
    db 0x84, 63, 20, 0, 1, 4
    db 0x85, 63, 24, 0, 1, 4
    db 0x86, 63, 28, 0, 1, 4
    db 0x87, 63, 32, 0, 1, 4
    db 0xa3, 61, 4,  0, 1, 1
    db 0xa3, 61, 35, 0, 1, 1

    ; horiz lines, first row
    ;  ch    x   y   dx dy n
    db 0x88, 4,  0,  1, 0, 7
    db 0x89, 11, 0,  1, 0, 7
    db 0x8a, 18, 0,  1, 0, 7
    db 0x8b, 25, 0,  1, 0, 7
    db 0x8c, 32, 0,  1, 0, 7
    db 0x8d, 39, 0,  1, 0, 7
    db 0x8e, 46, 0,  1, 0, 7
    db 0x8f, 53, 0,  1, 0, 7
    db 0xa0, 4,  2,  1, 0, 1
    db 0xa0, 59, 2,  1, 0, 1

    ; horiz lines, last row
    ;  ch    x   y  dx dy  n
    db 0x88, 4,  39, 1, 0, 7
    db 0x89, 11, 39, 1, 0, 7
    db 0x8a, 18, 39, 1, 0, 7
    db 0x8b, 25, 39, 1, 0, 7
    db 0x8c, 32, 39, 1, 0, 7
    db 0x8d, 39, 39, 1, 0, 7
    db 0x8e, 46, 39, 1, 0, 7
    db 0x8f, 53, 39, 1, 0, 7
    db 0xa1, 4,  37, 1, 0, 1
    db 0xa1, 59, 37, 1, 0, 1

    ; corners
    db 0xa4, 0,  0,  1, 0, 1
    db 0xa5, 63, 0,  1, 0, 1
    db 0xa6, 0,  39, 1, 0, 1
    db 0xa7, 63, 39, 1, 0, 1

    db 0x00
