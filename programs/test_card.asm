def MEM_TOP 0xfc00
def IO_BASE 0xfc00

; video workspace
def WS_VINFO 0x1000

; mode related data
def VINFO_BASE      0x00    ; 2 - base mem address
def VINFO_LEN       0x02    ; 2 - base mem address
def VINFO_WIDTH     0x04    ; 2 - width in pixels
def VINFO_HEIGHT    0x06    ; 2 - height in pixels
def VINFO_STRIDE    0x08    ; 2 - bytes to move 1 in y direction
def VINFO_XSHIFT    0x0a    ; 1 - bits to shift to convert x to byte offset
def VINFO_XMASK     0x0b    ; 1 - mask for lower bits of x for pixel index
def VINFO_BPP       0x0c    ; 1 - bits per pixel
; user context
def VINFO_X         0x10    ; 2 - current x co-ord
def VINFO_Y         0x12    ; 2 - current y co-ord
def VINFO_PATTERN   0x14    ; 2 - dot pattern   (initial: 0xffff)
def VINFO_COLOR     0x16    ; 1 - current color (initial: 1<<bpp)-1
def VINFO_MASK      0x17    ; 1 - current mask  (initial: 1<<bpp)-1

def VREG .IO_BASE + 0x000

def TEXT_COLS 64
def TEXT_ROWS 40
def TEXT_BASE .MEM_TOP - .TEXT_COLS*.TEXT_ROWS

; well below video for safety
def STACK_BASE 0x2000-2

; global aliases
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
    stw link, [sp]
    sub sp, #8
    stw r4, [sp,#2]
    stw r5, [sp,#4]
    stw r6, [sp,#6]

    ; set 256x200 4bpp
    mov r0, #1
    bl .video_set_mode
    bl .gfx_clear

    mov r0, #0
    mov r1, #0
    bl .gfx_move_to

    mov r0, #512
    mov r1, #hi(400)
    add r1, #lo(400)
    bl .gfx_line_to

    ldw r4, [sp,#2]
    ldw r5, [sp,#4]
    ldw r6, [sp,#6]
    add sp, #8
    ldw pc, [sp]
}

.gfx_test_card2 {
    ; TODO - stack
    alias r4 dx
    alias r5 dy
    alias r6 color

    def CX 128
    def CY 100
    def STEP 5

    mov r0, #3
    bl .video_set_mode
    bl .gfx_clear

    mov dx, #.STEP
    mov color, #0

.loop
    mov dy, #100
    sub dy, dx
    prle
    bra .exit

    add color, #1
    tst color, #16
    prne
    mov color, #1
    mov r0, color
    bl .gfx_set_color

    mov r0, #.CX
    sub r0, dx
    mov r1, #.CY
    bl .gfx_move_to

    mov r0, #.CX
    mov r1, #.CY
    sub r1, dy
    bl .gfx_line_to

    mov r0, #.CX
    add r0, dx
    mov r1, #.CY
    bl .gfx_line_to

    mov r0, #.CX
    mov r1, #.CY
    add r1, dy
    bl .gfx_line_to

    mov r0, #.CX
    sub r0, dx
    mov r1, #.CY
    bl .gfx_line_to

    add dx, #.STEP
    bra .loop

.exit
    hlt
}

; .gfx_clear()
;
; Clear video memory to zero.
;
.gfx_clear {
    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)
    ldw r0, [tmp, #.VINFO_BASE]
    mov r1, #0x00                       ; TODO background colour?
    ldw r2, [tmp, #.VINFO_LEN]
    bra .memset
}

; .memset(ptr, fill, bytes)
;
; TODO - could be made slightly more efficient by using a computed
; jump into the unrolled loop and some other cleverness
;
.memset {
    alias r0 ptr
    alias r1 fill
    alias r2 bytes
    alias r3 stride

    orr bytes, bytes
    preq
    mov pc, link

    mov tmp, fill
    lsl fill, #8
    orr fill, tmp

    mov stride, #16
    cmp bytes, stride
    prlt
    bra .trailing
.loop
    stw fill, [ptr, #0]
    stw fill, [ptr, #2]
    stw fill, [ptr, #4]
    stw fill, [ptr, #6]
    stw fill, [ptr, #8]
    stw fill, [ptr, #10]
    stw fill, [ptr, #12]
    stw fill, [ptr, #14]
    add ptr, stride
    sub bytes, stride
    cmp bytes, stride
    prhs
    bra .loop

    orr bytes, bytes
    preq
    mov pc, link

.trailing
    stb fill, [ptr]
    add ptr, #1
    sub bytes, #1
    prne
    bra .trailing

    mov pc, link
}

; gfx_set_color(r0=color)
;
; Set foreground colour.
;
.gfx_set_color {
    alias r0 color

    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)

    ; TODO - ensure valid in current mode
    stb color, [tmp, #.VINFO_COLOR]

    mov pc, link
}

; gfx_set_mask(r0=mask)
;
; Set draw mask.
;
.gfx_set_mask {
    alias r0 mask

    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)

    ; TODO - ensure valid in current mode
    stb mask, [tmp, #.VINFO_MASK]

    mov pc, link
}

; gfx_set_pattern(r0=pattern)
;
; Set dot-dash pattern.
;
.gfx_set_pattern {
    alias r0 pattern

    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)

    stw pattern, [tmp, #.VINFO_PATTERN]

    mov pc, link
}

; gfx_move(r0=dx, r1=dy)
;
; Move relative to current position.
;
.gfx_move {
    alias r0 dx
    alias r1 dy
    alias r2 vinfo

    mov vinfo, #hi(.WS_VINFO)
    add vinfo, #lo(.WS_VINFO)

    ldw tmp, [vinfo, #.VINFO_X]
    add tmp, dx
    stw tmp, [vinfo, #.VINFO_X]

    ldw tmp, [vinfo, #.VINFO_Y]
    add tmp, dy
    stw tmp, [vinfo, #.VINFO_Y]

    mov pc, link
}

; gfx_move_to(r0=x, r1=y)
;
; Move to specified position.
;
.gfx_move_to {
    alias r0 x
    alias r1 y

    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)

    stw r0, [tmp, #.VINFO_X]
    stw r1, [tmp, #.VINFO_Y]

    mov pc, link
}

; gfx_line(r0=dx, r1=dy)
;
; Draw a line relative to the current position.
;
.gfx_line {
    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)
    ldw r2, [tmp, #.VINFO_X]
    ldw r3, [tmp, #.VINFO_Y]
    add r0, r2                          ; line_to x+dx, y+dy
    add r1, r3

    bra .gfx_line_to
}
    
; .gfx_line_to(r0=x, r1=y)
.gfx_line_to {
    stw link, [sp]
    sub sp, #10
    stw r4, [sp, #2]
    stw r5, [sp, #4]
    stw r6, [sp, #6]
    stw r7, [sp, #8]

    mov tmp, #hi(.WS_VINFO)
    add tmp, #lo(.WS_VINFO)
    ldw r2, [tmp, #.VINFO_X]
    ldw r3, [tmp, #.VINFO_Y]
    stw r0, [tmp, #.VINFO_X]
    stw r1, [tmp, #.VINFO_Y]

    mov r4, #0                          ; clipping rectangle
    mov r5, #0
    ldw r6, [tmp, #.VINFO_WIDTH]
    ldw r7, [tmp, #.VINFO_HEIGHT]

    bl .gfx_clip                        ; visibility returned in tmp
    orr tmp, tmp
    preq
    bra .exit

    bl .gfx_line_unclipped

.exit
    ldw r4, [sp, #2]
    ldw r5, [sp, #4]
    ldw r6, [sp, #6]
    ldw r7, [sp, #8]
    add sp, #10
    ldw pc, [sp]
}

; .gfx_line_unclipped(r0=x1, r1=y1, r2=x2, r3=y2)
;
; Draw a line from (x0,y0)->(x1,y1), clearing the bits in VINFO_MASK
; and xoring the bits in VINFO_COLOR:
;
;      mask=0 color=0 => clear bit
;      mask=0 color=1 => set bit
;      mask=1 color=0 => transparent
;      mask=1 color=1 => invert
;
.gfx_line_unclipped {
    alias r0  x         ; used in inner loop
    alias r1  y         ; only used during init
    alias r2  x2        ; only used during init
    alias r3  y2        ; only used during init
    alias r4  shift     ; only used during init
    alias r1  count     ; used in inner loop
    alias r2  addr      ; used in inner loop
    alias r3  ystep     ; used in inner loop
    alias r4  err       ; used in inner loop
    alias r5  dx_by2    ; used in inner loop
    alias r6  dy_by2    ; used in inner loop
    alias r7  mask      ; used in inner loop
    alias r8  color     ; used in inner loop
    alias r9  pattern   ; used in inner loop
    alias r10 vinfo     ; used during init
    alias r10 bpp       ; used in inner loop
    alias r11 xmask     ; used in inner loop
    ; r12 tmp

    ;   Slope <= 45         |          slope > 45
    ; ----------------------+--------------------------
    ;                       |
    ;   l->r ...            |   top->bot             :
    ;           ''...       |       :               :
    ;                ''...  |        :             :
    ;                       |         :           :
    ;                  ...  |          :         :
    ;             ...''     |           :       :
    ;   l->r ...''          |            :  bot->top
    ;


    sub sp, #14
    stw r4,  [sp,#2]
    stw r5,  [sp,#4]
    stw r6,  [sp,#6]
    stw r7,  [sp,#8]
    stw r8,  [sp,#10]
    stw r9,  [sp,#12]
    stw r10, [sp,#14]

    mov vinfo, #hi(.WS_VINFO)
    add vinfo, #lo(.WS_VINFO)

    ; TODO - reverse bits if we switch line direction?
    ldw pattern, [vinfo, #.VINFO_PATTERN]   ;; the dot pattern - a 1 bit means plot, 0 means not

    mov dy_by2, y2
    sub dy_by2, y
    asl dy_by2, #1          ;; dy_by2 = (y2-y)*2

    mov dx_by2, x2
    sub dx_by2, x
    asl dx_by2, #1          ;; dx_by2 = (x2-x)*2

    prpl
    bra .pos_dx

    mov x, x2
    mov y, y2
    mov tmp, #0
    rsb dx_by2, tmp
    rsb dy_by2, tmp

.pos_dx
    ldw ystep, [vinfo, #.VINFO_STRIDE]
    orr dy_by2, dy_by2
    prpl
    bra .pos_dy
    mov tmp, #0
    rsb dy_by2, tmp
    rsb ystep, tmp

.pos_dy
    ; compute initial alignment for mask and color
    ldb tmp, [vinfo, #.VINFO_BPP]
    ldb shift, [vinfo, #.VINFO_XMASK]
    and shift, x
    add shift, #1
    mul shift, tmp

    ; replicate mask into high byte
    ldb mask, [vinfo, #.VINFO_MASK]
    mov tmp, mask
    lsl tmp, #8
    orr mask, tmp

    ; replicate color into high byte
    ldb color, [vinfo, #.VINFO_COLOR]
    mov tmp, color
    lsl tmp, #8
    orr color, tmp

    ; align
    ror mask, shift
    ror color, shift

    ldw addr, [vinfo, #.VINFO_BASE]
    ldw tmp, [vinfo, #.VINFO_STRIDE]
    mul tmp, y
    add addr, tmp       ; addr = video_base + y*stride

    ldb shift, [vinfo, #.VINFO_XSHIFT]
    mov tmp, x
    lsr tmp, shift
    add addr, tmp       ; addr = video_base + y*stride + x>>xshift

    ; order is important here because of aliasing
    ldb xmask, [vinfo, #.VINFO_XMASK]
    ldb bpp,   [vinfo, #.VINFO_BPP]

    ; NOTE vinfo is invalid beyond here as it is aliased by bpp

    cmp dx_by2, dy_by2
    prlo
    bra .steep

.shallow {
    mov count, dx_by2
    lsr count, #1
    mov err, count

.loop
    ror pattern, #1     ; do we plot or not?
    prcc
    bra .skip
    ldb tmp, [addr]
    bic tmp, mask
    eor tmp, color
    stb tmp, [addr]
.skip
    sub count, #1
    prmi
    bra .done

    sub err, dy_by2
    prpl
    bra .no_ystep
    add err, dx_by2
    add addr, ystep

.no_ystep
    add x, #1
    tst x, xmask
    preq
    add addr, #1
    ror mask, bpp
    ror color, bpp

    bra .loop
}

.steep {
    mov count, dy_by2
    lsr count, #1
    mov err, count

.loop
    ror pattern, #1
    prcc
    bra .skip
    ldb tmp, [addr]
    bic tmp, mask
    eor tmp, color
    stb tmp, [addr]
.skip
    sub count, #1
    prmi
    bra .done

    sub err, dx_by2
    prpl
    bra .no_xstep
    add err, dy_by2
    add x, #1
    tst x, xmask
    preq
    add addr, #1
    ror mask, bpp
    ror color, bpp

.no_xstep
    add addr, ystep
    bra .loop
}

.done
    ldw r4,  [sp,#2]
    ldw r5,  [sp,#4]
    ldw r6,  [sp,#6]
    ldw r7,  [sp,#8]
    ldw r8,  [sp,#10]
    ldw r9,  [sp,#12]
    ldw r10, [sp,#14]
    add sp, #14
    mov pc, link
}

; Assumes (rect_x1,rect_y1)-(rect_x2,rect_y2) is top-left to bottom-right
.gfx_clip {
    alias r0 line_x1 ; \  these are stashed on
    alias r1 line_y1 ;  | the stack as needed
    alias r2 line_x2 ;  | and used as returns
    alias r3 line_y2 ; /
    alias r4 rect_x1 ; \
    alias r5 rect_y1 ;  | these are preserved
    alias r6 rect_x2 ;  | throughout
    alias r7 rect_y2 ; /
    alias r8 px      ; \
    alias r9 py      ;  | these are used as working data
    alias r10 code1  ;  | preserved by gfx_clip, but not
    alias r11 code2  ; /  by internal recursion
    ; r12=tmp is set to 1 on return if clipped line is visible

    stw link, [sp]
    sub sp, #10
    stw r8,  [sp,#2]
    stw r9,  [sp,#4]
    stw r10, [sp,#6]
    stw r11, [sp,#8]

    mov px, line_x1
    mov py, line_y1
    bl .region_code
    mov code1, tmp

    mov px, line_x2
    mov py, line_y2
    bl .region_code
    mov code2, tmp

    bl .clip_recurse

    ldw r8,  [sp,#2]
    ldw r9,  [sp,#4]
    ldw r10, [sp,#6]
    ldw r11, [sp,#8]
    add sp, #10
    ldw pc, [sp]

.clip_recurse
    stw link, [sp]
    sub sp, #2

    mov tmp, code1  ; both endpoints in visible region?
    orr tmp, code2
    preq
    bra .accept

    mov tmp, code1  ; both endpoints share a non-visible region?
    and tmp, code2
    prne
    bra .reject

    ; compute midpoint
    mov px, line_x1
    add px, line_x2
    add px, #1
    asr px, #1

    mov py, line_y1
    add py, line_y2
    add py, #1
    asr py, #1

    cmp px, line_x1
    preq
    cmp py, line_y1
    preq
    bra .degenerate
    cmp px, line_x2
    preq
    cmp py, line_y2
    prne
    bra .split

.degenerate
    orr code1, code1        ; accept line1 if code1==0
    prne
    bra .maybe_line2
    mov line_x2, line_x1
    mov line_y2, line_y1
    bra .accept
.maybe_line2
    orr code2, code2        ; accept line2 if code2==0, otherwise reject
    prne
    bra .reject
    mov line_x1, line_x2
    mov line_y1, line_y2
    bra .accept

.split
    bl .region_code         ; px, py still contains midpoint here

    sub sp, #22             ; extra space for ok1, seg1
    stw px,      [sp, #2]   ; stash mid
    stw py,      [sp, #4]
    stw line_x2, [sp, #6]   ; stash p2
    stw line_y2, [sp, #8]
    stw tmp,     [sp, #10]  ; codem needed in second recursive call
    stw code2,   [sp, #12]  ; code2 needed in second recursive call

    ; line_x1, line_y1, code1 are already set
    mov line_x2, px
    mov line_y2, py
    mov code2, tmp          ; returned from region_code

    bl .clip_recurse        ; check p1...mid
    stw tmp, [sp, #14]      ; stash ok1
    stw line_x1, [sp, #16]  ; stash seg1
    stw line_y1, [sp, #18]  ;
    stw line_x2, [sp, #20]  ;
    stw line_y2, [sp, #22]  ;

    ldw line_x1, [sp, #2]   ; get mid
    ldw line_y1, [sp, #4]
    ldw line_x2, [sp, #6]   ; get p2
    ldw line_y2, [sp, #8]
    ldw code1,   [sp, #10]  ; retrieve codem
    ldw code2,   [sp, #12]  ; restore code2
    bl .clip_recurse        ; check mid..p2 -> tmp=ok2, line_*=seg2

    orr tmp, tmp            ; if ok2
    preq
    bra .maybe_seg1
    ldw tmp, [sp, #14]      ; get ok1
    orr tmp, tmp
    preq
    bra .choose_seg2
.both_clipped
    ldw line_x1, [sp, #16]  ; seg1.p1
    ldw line_y1, [sp, #18]
    add sp, #22
    bra .accept
.choose_seg2
    add sp, #22
    bra .accept

.maybe_seg1
    ldw tmp, [sp, #14]  ; ok1
    orr tmp, tmp
    preq
    bra .neither_seg
.choose_seg1
    ldw line_x1, [sp, #16]   ; seg1
    ldw line_y1, [sp, #18]
    ldw line_x2, [sp, #20]
    ldw line_y2, [sp, #22]
    add sp, #22
    bra .accept
.neither_seg
    add sp, #22
    bra .reject

.accept
    mov tmp, #1
    add sp, #2
    ldw pc, [sp]

.reject
    mov tmp, #0
    add sp, #2
    ldw pc, [sp]


; helper: px,py, rect_x1,rect_y1, rect_x2,rect_y2 -> tmp
.region_code
    def LEFT   1<<0
    def RIGHT  1<<1
    def TOP    1<<2
    def BOTTOM 1<<3

    mov tmp, #0
    cmp px, rect_x1
    prlt
    orr tmp, #.LEFT
    cmp px, rect_x2
    prge
    orr tmp, #.RIGHT
    cmp py, rect_y1
    prlt
    orr tmp, #.TOP
    cmp py, rect_y2
    prge
    orr tmp, #.BOTTOM
    mov pc, link
}



; .video_set_mode(r0=mode)
;
; Set video mode 0..3
;
.video_set_mode {
    ; TODO - optimise register usage here
    alias r0 mode
    alias r1 vinfo
    alias r2 xshift
    alias r3 bpp
    alias r4 mask
    alias r5 entry
    alias r6 vreg
    alias r7 count
    alias r8 width
    alias r9 height

    def VGA_WIDTH  640
    def VGA_HEIGHT 480
    def VGA_HBACK  44
    def VGA_VBACK  31

    def VREG_BASE   0x00
    def VREG_LEFT   0x02
    def VREG_RIGHT  0x04
    def VREG_TOP    0x06
    def VREG_BOTTOM 0x08
    def VREG_MODE   0x0A
    def VREG_RED    0x10
    def VREG_GREEN  0x20
    def VREG_BLUE   0x30

    ; validate
    mov tmp, #4
    cmp mode, tmp
    prhs
    mov pc, link

    add sp, #12
    stw r4, [sp, #2]
    stw r5, [sp, #4]
    stw r6, [sp, #6]
    stw r7, [sp, #8]
    stw r8, [sp, #10]
    stw r9, [sp, #12]

    lsl mode, #1
    mov tmp, #hi(.mode_ptrs)
    add tmp, #lo(.mode_ptrs)
    add mode, tmp
    ldw entry, [mode]                   ; point to data

    mov vinfo, #hi(.WS_VINFO)           ; in-memory info
    add vinfo, #lo(.WS_VINFO)

    mov vreg, #hi(.VREG)                ; display registers
    add vreg, #lo(.VREG)

    ldb mode, [entry, #.ENTRY_MODE]
    stb mode, [vreg, #.VREG_MODE]

    ldw width, [entry, #.ENTRY_WIDTH]
    stw width, [vinfo, #.VINFO_WIDTH]

    mov tmp, #.HZOOM_MASK
    and tmp, mode
    lsr tmp, #.HZOOM_SHIFT
    add tmp, #1
    mul width, tmp                      ; convert to physical width

    mov tmp, #hi(.VGA_WIDTH)            ; compute timing for left pixel
    add tmp, #lo(.VGA_WIDTH)
    sub tmp, width
    asr tmp, #1
    add tmp, #.VGA_HBACK

    ror tmp, #8                         ; move hi byte to bottom 8 bits
    stb tmp, [vreg, #.VREG_LEFT]
    ror tmp, #8                         ; restore (move lo byte)
    stb tmp, [vreg, #.VREG_LEFT+1]

    add tmp, width                      ; timing for right pixel

    ror tmp, #8                         ; move hi byte to bottom 8 bits
    stb tmp, [vreg, #.VREG_RIGHT]
    ror tmp, #8                         ; restore (move lo byte)
    stb tmp, [vreg, #.VREG_RIGHT+1]
    asr width, #1                       ; restore width

    ldw height, [entry, #.ENTRY_HEIGHT]
    stw height, [vinfo, #.VINFO_HEIGHT]

    mov tmp, #.VZOOM_MASK
    and tmp, mode
    lsr tmp, #.VZOOM_SHIFT
    add tmp, #1
    mul height, tmp                     ; convert to physical lines

    mov tmp, #hi(.VGA_HEIGHT)           ; compute timing for top line
    add tmp, #lo(.VGA_HEIGHT)
    sub tmp, height
    asr tmp, #1
    add tmp, #.VGA_VBACK

    ror tmp, #8
    stb tmp, [vreg, #.VREG_TOP]
    ror tmp, #8
    stb tmp, [vreg, #.VREG_TOP+1]

    add tmp, height                     ; compute timing for bottom line

    ror tmp, #8
    stb tmp, [vreg, #.VREG_BOTTOM]
    ror tmp, #8
    stb tmp, [vreg, #.VREG_BOTTOM+1]

    ldb xshift, [entry, #.ENTRY_XSHIFT]
    stb xshift, [vinfo, #.VINFO_XSHIFT]

    ldw tmp, [vinfo, #.VINFO_WIDTH]
    lsr tmp, xshift
    stw tmp, [vinfo, #.VINFO_STRIDE]

    ldw height, [vinfo, #.VINFO_HEIGHT]
    mul height, tmp                     ; height = stride*height = bytes
    stw height, [vinfo, #.VINFO_LEN]

    mov tmp, #hi(.MEM_TOP)
    add tmp, #lo(.MEM_TOP)
    sub tmp, height
    stw tmp, [vinfo, #.VINFO_BASE]
    ror tmp, #8
    stb tmp, [vreg, #.VREG_BASE]
    ror tmp, #8
    stb tmp, [vreg, #.VREG_BASE+1]

    mov tmp, #0
    stw tmp, [vinfo, #.VINFO_X]
    stw tmp, [vinfo, #.VINFO_Y]

    mov tmp, #1
    lsl tmp, xshift
    sub tmp, #1
    stb tmp, [vinfo, #.VINFO_XMASK]

    mov tmp, #3                         ; log2(bits_in_a_byte)
    sub tmp, xshift
    mov bpp, #1
    lsl bpp, tmp
    stb bpp, [vinfo, #.VINFO_BPP]

    mov tmp, #1
    lsl tmp, bpp
    sub tmp, #1
    stb tmp, [vinfo, #.VINFO_MASK]      ; all colour bits
    stb tmp, [vinfo, #.VINFO_COLOR]     ; last colour in palette

    ; solid pattern
    mov tmp, #0xff00
    add tmp, #0x00ff
    stw tmp, [vinfo, #.VINFO_PATTERN]

    ldb count, [entry, #.ENTRY_COLORS]  ; number of colours
    add entry, #.ENTRY_PALETTE

    add vreg, #.VREG_RED
.loop
    ldb tmp, [entry, #.PAL_RED]
    stb tmp, [vreg]

    add vreg, #0x10                     ; green palette
    ldb tmp, [entry, #.PAL_GREEN]
    stb tmp, [vreg]

    add vreg, #0x10                     ; blue palette
    ldb tmp, [entry, #.PAL_BLUE]
    stb tmp, [vreg]

    add entry, #3
    sub vreg, #0x20-1                   ; back to red, but next entry

    sub count, #1
    prne
    bra .loop
}

.exit
    ldw r4, [sp, #2]
    ldw r5, [sp, #4]
    ldw r6, [sp, #6]
    ldw r7, [sp, #8]
    ldw r8, [sp, #10]
    ldw r9, [sp, #12]
    sub sp, #12

    mov pc, link

    def VZOOM_SHIFT 4
    def VZOOM_1    0x00 << .VZOOM_SHIFT
    def VZOOM_2    0x01 << .VZOOM_SHIFT
    def VZOOM_3    0x02 << .VZOOM_SHIFT
    def VZOOM_4    0x03 << .VZOOM_SHIFT
    def VZOOM_MASK 0x03 << .VZOOM_SHIFT

    def HZOOM_SHIFT 2
    def HZOOM_1    0x00 << .HZOOM_SHIFT
    def HZOOM_2    0x01 << .HZOOM_SHIFT
    def HZOOM_3    0x02 << .HZOOM_SHIFT
    def HZOOM_4    0x03 << .HZOOM_SHIFT
    def HZOOM_MASK 0x03 << .HZOOM_SHIFT

    def MODE_TEXT 0x00 << 0
    def MODE_1BPP 0x01 << 0
    def MODE_2BPP 0x02 << 0
    def MODE_4BPP 0x03 << 0

    def ENTRY_WIDTH   0
    def ENTRY_HEIGHT  2
    def ENTRY_XSHIFT  4
    def ENTRY_MODE    5
    def ENTRY_COLORS  6
    def ENTRY_PALETTE 7

    def PAL_RED   0
    def PAL_GREEN 1
    def PAL_BLUE  2

.mode_ptrs {
    dw .mode_0
    dw .mode_1
    dw .mode_2
    dw .mode_3

    def VGA_WIDTH  640
    def VGA_HEIGHT 480
    def VGA_HBACK  44
    def VGA_VBACK  31

.mode_0
    ; TODO
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
    dw 512                  ; width
    dw 400                  ; height
    db 3                    ; xshift
    db .MODE_1BPP | .HZOOM_1 | .VZOOM_1
    db 2                    ; 2-colour palette
    db 0x00, 0x33, 0x00     ; 0=dark green
    db 0x22, 0xff, 0x22     ; 1=bright green
    align

.mode_2
    ; 256x400, 2-bpp graphics
    dw 256                  ; width
    dw 400                  ; height
    db 2                    ; xshift
    db .MODE_2BPP | .HZOOM_2 | .VZOOM_1
    db 4                    ; 4-colour palette
    db 0x00, 0x00, 0x00     ; 0=black
    db 0xff, 0x00, 0x00     ; 1=red
    db 0x00, 0xff, 0x00     ; 2=green
    db 0xff, 0xff, 0xff     ; 3=white
    align

.mode_3
    ; 256x200, 4-bpp graphics
    dw 256                  ; width
    dw 200                  ; height
    db 1                    ; xshift
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
