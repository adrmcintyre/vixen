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

; well below video for safety
def STACK_BASE 0x1000-2

alias r1  ch
alias r2  n
alias r3  x
alias r4  y
alias r5  dx
alias r6  dy
alias r10 video
alias r12 tmp
alias r13 sp
alias r14 link
alias r15 pc

    org 0x0000
.init
    mov sp, #hi(.STACK_BASE)
    add sp, #lo(.STACK_BASE)

   ;bra .text_test_card   ; display text test-card
    bra .gfx_test_card2   ; display graphics test-card

.text_test_card
    ; set 64x40 text
    mov r0, #0
    bl .video_set_mode
    mov video, #hi(.TEXT_BASE)
    add video, #lo(.TEXT_BASE)
    mov ch, #0xc0
    bl .text_clear
    bl .text_card_table
    bl .text_card_ascii
    bl .text_card_rows
    bl .text_card_cols
    hlt

.gfx_test_card1
    ; set 512x400 1bpp
    mov r0, #1
    bl .video_set_mode
    bl .gfx_clear
    mov ch, #0xf000     ; mode1: 8080; mode2: c0c0; mode3: f0f0
    add ch, #0x00f0
    mov x, #0
    mov y, #0
    mov n, #hi(200)     ; mode1: 400; mode2: 200; mode3: 200
    add n, #lo(200)     ; mode1: 400; mode2: 200; mode3: 200
.gfx_loop
    mov tmp, video
    mov dy, y
    lsl dy, #7          ; mode1: 6; mode2: 6; mode3: 7
    add tmp, dy
    mov dx, x
    lsr dx, #1          ; mode1: 3; mode2: 2; mode3: 1
    add tmp, dx

    stb ch, [tmp]
    ror ch, #4          ; mode2: 1; mode3: 2; mode4: 4
    add x, #1
    add y, #1
    sub n, #1
    prne
    bra .gfx_loop
    hlt

.gfx_test_card2
    ; set 512x400 1bpp
    mov r0, #1
    bl .video_set_mode
    bl .gfx_clear

    mov r0, #10
    mov r1, #10
    mov r2, #200
    mov r3, #43
    bl .gfx_line

    mov r0, #200
    mov r1, #50
    mov r2, #10
    mov r3, #70
    bl .gfx_line

    mov r0, #100
    mov r1, #10
    mov r2, #67
    mov r3, #200
    bl .gfx_line

    mov r0, #107
    mov r1, #10
    mov r2, #133
    mov r3, #200
    bl .gfx_line

    hlt

.gfx_clear
    mov video, #hi(.MEM_TOP-512*400/8)
    add video, #lo(.MEM_TOP-512*400/8)
    mov ch, #0x0000
    mov n, #hi(512*400/8)
    add n, #lo(512*400/8)
    mov tmp, video
.gfx_clear_loop
    stw ch, [tmp]
    stw ch, [tmp,#2]
    stw ch, [tmp,#4]
    stw ch, [tmp,#6]
    stw ch, [tmp,#8]
    stw ch, [tmp,#10]
    stw ch, [tmp,#12]
    stw ch, [tmp,#14]
    add tmp, #16
    sub n, #16
    prne
    bra .gfx_clear_loop
    mov pc, link

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
.gfx_line
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
    ; r9  unused
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


    ;; TODO save/restore working registers

    mov pattern, #0xc300
    add pattern, #0x00c3
    mov ystep, #512/8       ;; TODO stride
    mov tmp, #0

    mov dy, y2
    sub dy, y
    asl dy, #1          ;; dy = (y2-y)*2

    mov dx, x2
    sub dx, x
    asl dx, #1          ;; dx = (x2-x)*2

    prpl
    bra .gfx_line_pos_dx
    mov x, x2
    mov y, y2
    rsb dx, tmp
    rsb dy, tmp
.gfx_line_pos_dx
    cmp dy, tmp
    prpl
    bra .gfx_line_pos_dy
    rsb dy, tmp
    rsb ystep, tmp
.gfx_line_pos_dy
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
    bra .gfx_line_steep

    mov count, dx
    lsr count, #1
    mov err, count

.gfx_line_shallow_loop
    ror pattern, #1
    prcc
    bra .shallow_skip
    ldb tmp, [addr]
    orr tmp, mask
    stb tmp, [addr]
.shallow_skip
    sub count, #1
    prmi
    bra .gfx_line_done

    sub err, dy
    prpl
    bra .gfx_line_no_ystep
    add err, dx
    add addr, ystep

.gfx_line_no_ystep
    add x, #1
    mov tmp, #7
    and tmp, x
    preq
    add addr, #1
    ror mask, #1

    bra .gfx_line_shallow_loop

.gfx_line_steep
    mov count, dy
    lsr count, #1
    mov err, count

.gfx_line_steep_loop
    ror pattern, #1
    prcc
    bra .steep_skip
    ldb tmp, [addr]
    orr tmp, mask
    stb tmp, [addr]
.steep_skip
    sub count, #1
    prmi
    bra .gfx_line_done

    sub err, dx
    prpl
    bra .gfx_line_no_xstep
    add err, dy
    add x, #1
    mov tmp, #7
    and tmp, x
    preq
    add addr, #1
    ror mask, #1

.gfx_line_no_xstep
    add addr, ystep
    bra .gfx_line_steep_loop

.gfx_line_done
    ;; TODO - restore registers
    mov pc, link


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .video_set_mode(r0=mode)
.video_set_mode
    ; validate
    mov tmp, #4
    cmp r0, tmp
    prhs
    mov pc, link

    lsl r0, #1
    mov tmp, #hi(.video_mode_table)
    add tmp, #lo(.video_mode_table)
    add tmp, r0
    ldw r0, [tmp]       ; point to data

    mov r1, #hi(.VREG)
    add r1, #lo(.VREG)
    mov r2, #11          ; 11 registers
.video_set_mode_lp
    ldb tmp, [r0]
    stb tmp, [r1]
    add r0, #1
    add r1, #1
    sub r2, #1
    prne
    bra .video_set_mode_lp

    ldb r2, [r0]        ; number of colours
    add r0, #1
    mov r1, #hi(.VREG + 0x10)
    add r1, #lo(.VREG + 0x10)
.video_set_mode_pal_lp
    ldb tmp, [r0]
    stb tmp, [r1]

    add r1, #0x10
    ldb tmp, [r0,#1]
    stb tmp, [r1]

    add r1, #0x10
    ldb tmp, [r0,#2]
    stb tmp, [r1]

    add r0, #3
    sub r1, #0x20-1

    sub r2, #1
    prne
    bra .video_set_mode_pal_lp

    mov pc, link
    
.video_mode_table
    dw .video_mode_0
    dw .video_mode_1
    dw .video_mode_2
    dw .video_mode_3

.video_mode_0
    ; text 64x40
    dw .MEM_TOP - .TEXT_COLS * .TEXT_ROWS               ; base addr
    dw (.VGA_WIDTH  - .TEXT_COLS * 8) / 2 + .VGA_HBACK  ; vp_left
    dw (.VGA_WIDTH  + .TEXT_COLS * 8) / 2 + .VGA_HBACK  ; vp_right
    dw (.VGA_HEIGHT - .TEXT_ROWS * 8) / 2 + .VGA_VBACK  ; vp_top
    dw (.VGA_HEIGHT + .TEXT_ROWS * 8) / 2 + .VGA_VBACK  ; vp_bottom
    db .MODE_TEXT | .HZOOM_2 | .VZOOM_1
    db 2                    ; 2 colour palette
    db 0xff, 0xaa, 0xaa     ; 0=pink
    db 0x00, 0x00, 0xcc     ; 1=dark blue
    align

.video_mode_1
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

.video_mode_2
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

.video_mode_3
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_card_table()
.text_card_table
    stw link, [sp]
    sub sp, #2
    mov tmp, #hi(.text_card_table_data)
    add tmp, #lo(.text_card_table_data)
.text_card_table_lp
    ldb ch, [tmp, #0]
    orr ch, ch
    preq
    bra .text_card_table_exit
    ldb n,  [tmp, #1]
    ldb x,  [tmp, #2]
    ldb y,  [tmp, #3]
    ldb dx, [tmp, #4]
    ldb dy, [tmp, #5]
    add tmp, #6
    bl .text_draw
    bra .text_card_table_lp
.text_card_table_exit
    add sp, #2
    ldw pc, [sp]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_rows()

.text_card_rows
    stw link, [sp]
    sub sp, #2

    mov x, #8
    mov y, #0
    mov ch, #'0'
.text_card_rows_lp
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
    bra .text_card_rows_lp
.text_card_rows_exit
    add sp, #2
    ldw pc, [sp]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_cols()

.text_card_cols
    stw link, [sp]
    sub sp, #2

    mov x, #0
    mov y, #8
    mov ch, #'0'
.text_card_cols_lp
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
    bra .text_card_cols_lp
.text_card_cols_exit
    add sp, #2
    ldw pc, [sp]



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE text_card_ascii()
.text_card_ascii
    stw link, [sp]
    sub sp, #2
    mov ch, #0

.text_card_ascii_lp
    mov tmp, #0x0f
    mov x, ch
    and x, tmp
    add x, #(.TEXT_COLS-16) / 2

    mov y, ch
    lsr y, #4
    add y, #(.TEXT_ROWS-16) / 2

    bl .text_char_at
    add ch, #1
    tst ch, #bit 8
    preq
    bra .text_card_ascii_lp

.text_card_ascii_exit
    add sp, #2
    ldw pc, [sp]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_clear(ch)
.text_clear
    stw tmp, [sp]
    sub sp, #2

    mov tmp, ch
    lsl ch, #8
    orr ch, tmp
    mov tmp, video
    mov n, #hi(.TEXT_ROWS*.TEXT_COLS/16)
    add n, #lo(.TEXT_ROWS*.TEXT_COLS/16)
.text_clear_lp
    stw ch, [tmp,#0]
    stw ch, [tmp,#2]
    stw ch, [tmp,#4]
    stw ch, [tmp,#6]
    stw ch, [tmp,#8]
    stw ch, [tmp,#10]
    stw ch, [tmp,#12]
    stw ch, [tmp,#14]
    add tmp, #16
    sub n, #1
    prne
    bra .text_clear_lp
.text_clear_exit
    add sp, #2
    ldw tmp, [sp]
    mov pc, link

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_draw(ch, x, y, dx, dy, n)
.text_draw
    stw link, [sp]
    sub sp, #2
.text_draw_lp
    bl .text_char_at
    sub n, #1
    preq
    bra .text_draw_exit
    add x, dx
    add y, dy
    bra .text_draw_lp
.text_draw_exit
    add sp, #2
    ldw pc, [sp]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ROUTINE .text_char_at(ch, x, y)
.text_char_at
    stw tmp, [sp]
    sub sp, #2

    ; sanity check (x,y)
    mov tmp, #.TEXT_ROWS
    cmp y, tmp
    prhs
    bra .text_char_at_exit
    mov tmp, #.TEXT_COLS
    cmp x, tmp
    prhs
    bra .text_char_at_exit

    mov tmp, y
    lsl tmp, #6
    add tmp, x
    add tmp, video
    stb ch, [tmp]

.text_char_at_exit
    add sp, #2
    ldw tmp, [sp]
    mov pc, link

.text_card_table_data
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

    ; corners
    db 0xa4, 1, 0,  0,  1, 0
    db 0xa5, 1, 63, 0,  1, 0
    db 0xa6, 1, 0,  39, 1, 0
    db 0xa7, 1, 63, 39, 1, 0

    db 0x00
