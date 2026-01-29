; debug.asm
; Small in-game debug helpers.

DEBUG_FLAG_BOXES = 1

DEBUG_BOX_CHELL_COL  = &0F    ; logical colour 1 (red)
DEBUG_BOX_RETICLE_COL= &FF    ; logical colour 3 (yellow)


; Draw a simple 4px-thick outline around Chell's 16x32 footprint.
; Uses screen_ptr as the top-left (same as save/draw routines).
; No-op unless debug_flags bit0 is set.
; Clobbers: A,X,Y,temp_sprite_ptr,temp_mask_ptr
.debug_draw_chell_box
    LDA debug_flags
    AND #DEBUG_FLAG_BOXES
    BEQ dcb_done

    ; Debug draw touches screen memory; keep it atomic like our blitters.
    PHP
    SEI

    ; temp_sprite_ptr := base screen_ptr
    LDA screen_ptr
    STA temp_sprite_ptr
    LDA screen_ptr+1
    STA temp_sprite_ptr+1

    LDA #DEBUG_BOX_CHELL_COL

    ; Top horizontal (stripe 0, scanline 0)
    LDY #0
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y

    ; Bottom horizontal (stripe 3, scanline 7 => offset 28)
    LDA temp_sprite_ptr
    STA temp_mask_ptr
    LDA temp_sprite_ptr+1
    CLC
    ADC #3
    STA temp_mask_ptr+1

    LDA #DEBUG_BOX_CHELL_COL
    LDY #28
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y

    ; Vertical edges: 4 stripes x 8 scanlines.
    LDA temp_sprite_ptr
    STA temp_mask_ptr
    LDA temp_sprite_ptr+1
    STA temp_mask_ptr+1

    LDA #DEBUG_BOX_CHELL_COL
    LDX #4
  .dcb_stripe_loop
    LDY #0
    ; 8 scanlines, 4 bytes per scanline. Left=edge byte0, right=edge byte3.
    ; Within each stripe the 32 bytes are contiguous.
    LDA #DEBUG_BOX_CHELL_COL
    ; Use row_counter as the line counter to avoid clobbering X.
    LDY #0
    LDA #8
    STA row_counter
  .dcb_line_loop
    LDA #DEBUG_BOX_CHELL_COL
    STA (temp_mask_ptr),Y
    INY
    INY
    INY
    STA (temp_mask_ptr),Y
    INY

    DEC row_counter
    BNE dcb_line_loop

    INC temp_mask_ptr+1
    DEX
    BNE dcb_stripe_loop

    PLP
  .dcb_done
    RTS


; Draw a simple 4px-thick outline around the reticle's 16x16 footprint.
; Uses screen_ptr as the top-left.
; No-op unless debug_flags bit0 is set.
; Clobbers: A,X,Y,row_counter,temp_sprite_ptr,temp_mask_ptr
.debug_draw_reticle_box
    LDA debug_flags
    AND #DEBUG_FLAG_BOXES
    BEQ drb_done

    PHP
    SEI

    ; temp_sprite_ptr := base screen_ptr
    LDA screen_ptr
    STA temp_sprite_ptr
    LDA screen_ptr+1
    STA temp_sprite_ptr+1

    LDA #DEBUG_BOX_RETICLE_COL

    ; Top horizontal (stripe 0, scanline 0)
    LDY #0
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y
    INY
    STA (temp_sprite_ptr),Y

    ; Bottom horizontal (stripe 1, scanline 7 => offset 28)
    LDA temp_sprite_ptr
    STA temp_mask_ptr
    LDA temp_sprite_ptr+1
    CLC
    ADC #1
    STA temp_mask_ptr+1

    LDA #DEBUG_BOX_RETICLE_COL
    LDY #28
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y
    INY
    STA (temp_mask_ptr),Y

    ; Vertical edges: 2 stripes x 8 scanlines.
    LDA temp_sprite_ptr
    STA temp_mask_ptr
    LDA temp_sprite_ptr+1
    STA temp_mask_ptr+1

    LDX #2
  .drb_stripe_loop
    LDY #0
    LDA #8
    STA row_counter
  .drb_line_loop
    LDA #DEBUG_BOX_RETICLE_COL
    STA (temp_mask_ptr),Y
    INY
    INY
    INY
    STA (temp_mask_ptr),Y
    INY
    DEC row_counter
    BNE drb_line_loop

    INC temp_mask_ptr+1
    DEX
    BNE drb_stripe_loop

    PLP
  .drb_done
    RTS
