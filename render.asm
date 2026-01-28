; render.asm
; Routines to render a tilemap and sprites in MODE 5

; Screen memory notes:
; - Engine treats the playfield as a 16x16 grid of *cells*.
; - Each cell is 8x16 pixels (MODE 5, 128px-wide playfield).
; - Screen base is &5800.
; - Each cell row is 512 bytes apart (32 bytes/scanline × 16 scanlines; see tile_row_screen_table).
; - We do not use scrolling; we flick between screens.
; - We may use screen RAM *below the playfield* as scratch (not returned to BASIC).

.render_tilemap
    ; Clear playfield to cyan so tile id 0 can be skipped.
    JSR clear_playfield_cyan

    ; Set up initial pointers
    LDA #<(&5800)           ; Screen starts at &5800 in MODE 5
    STA screen_ptr                 ; screen_ptr_lo 
    LDA #>(&5800)
    STA screen_ptr+1                 ; screen_ptr_hi
    
    LDA #<(sprite_data)     ; Set up sprite pointer 
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA #>(sprite_data) 
    STA sprite_ptr                 ; sprite_ptr_hi
    
    ; Initialize row counter  
    LDA #0
    STA row_counter                 ; row_counter

.tilemap_row_loop
    ; Initialize column counter
    LDA #0
    STA col_counter                 ; col_counter
    
.tilemap_col_loop
    ; Calculate cell index: row_counter * 16 + col_counter  
    LDY row_counter                 ; row_counter as index
    LDA times16_table,Y     ; Get row_counter * 16 (2 cycles vs 8 for 4 ASLs)
    CLC
    ADC col_counter         ; + col_counter
    TAY
    
    ; Get cell value directly (8-bit format - no nibble extraction!)
    LDA (tilemap_ptr), Y            ; tilemap_ptr is in &79/&7A
    BEQ tilemap_skip_cell
    JSR render_cell8x16
  .tilemap_skip_cell
    
    ; Move to next cell column.
    ; Each 8x16 cell is 2 bytes wide per scanline.
    ; In MODE 5 screen-byte order that becomes +16 bytes for the next cell column.
    LDA screen_ptr
    CLC
    ADC #16
    STA screen_ptr
    BCC tilemap_col_loop_no_carry
    INC screen_ptr+1

.tilemap_col_loop_no_carry    
    ; Next column
    INC col_counter
    LDA col_counter
    CMP #16                 ; 16 columns total
    BNE tilemap_col_loop
    
.tilemap_end_of_row
    ; Move to next cell row (add 256 bytes = 8 scanlines)
    INC screen_ptr+1

    ; Next row
    INC row_counter
    LDA row_counter
    CMP #16                 ; 16 cell rows total
    BEQ tilemap_done
    JMP tilemap_row_loop
    
.tilemap_done
    RTS


 ; Render static tile-aligned objects.
 ;
 ; Objects are described by a small table so we can add new objects without
 ; changing code.
 .render_static_objects
    ; temp_sprite_ptr := per-room object table pointer
    LDA current_room
    ASL A
    TAX
    LDA static_objects_room_pointers,X
    STA temp_sprite_ptr
    LDA static_objects_room_pointers+1,X
    STA temp_sprite_ptr+1

  .rsobj_next
    ; End marker: stripes==0
    LDY #2
    LDA (temp_sprite_ptr),Y
    BNE rsobj_has_entry
    JMP rsobj_done
  .rsobj_has_entry

    ; screen_ptr := &5800 + y*512 + x*16
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1

    ; y*512 => add (y*2) to high byte
    LDY #1
    LDA (temp_sprite_ptr),Y
    ASL A
    CLC
    ADC screen_ptr+1
    STA screen_ptr+1

    ; x*16 => add to low byte
    LDY #0
    LDA (temp_sprite_ptr),Y
    TAY
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC rsobj_x_ok
    INC screen_ptr+1
  .rsobj_x_ok

    ; flags
    LDY #5
    LDA (temp_sprite_ptr),Y
    STA temp

    ; Skip disabled entries (bit7 clear)
    AND #&80
    BNE rsobj_enabled
    JMP rsobj_advance
  .rsobj_enabled

    ; Restore full flags byte (masked bit etc.)
    LDY #5
    LDA (temp_sprite_ptr),Y
    STA temp

    ; sprite_ptr
    LDY #6
    LDA (temp_sprite_ptr),Y
    STA sprite_ptr
    INY
    LDA (temp_sprite_ptr),Y
    STA sprite_ptr+1

    ; mask_ptr
    LDY #8
    LDA (temp_sprite_ptr),Y
    STA mask_ptr
    INY
    LDA (temp_sprite_ptr),Y
    STA mask_ptr+1

    ; masked/unmasked
    LDA temp
    AND #1
    BEQ rsobj_unmasked

    ; A=stripe_count, X=bytes_per_stripe, Y=stride
    LDY #2
    LDA (temp_sprite_ptr),Y
    STA temp_y
    LDY #3
    LDA (temp_sprite_ptr),Y
    TAX
    LDY #4
    LDA (temp_sprite_ptr),Y
    TAY
    LDA temp_y
    JSR stamp_striped_masked
    JMP rsobj_advance

  .rsobj_unmasked
    ; A=stripe_count, X=bytes_per_stripe, Y=stride
    LDY #2
    LDA (temp_sprite_ptr),Y
    STA temp_y
    LDY #3
    LDA (temp_sprite_ptr),Y
    TAX
    LDY #4
    LDA (temp_sprite_ptr),Y
    TAY
    LDA temp_y
    JSR stamp_striped_copy

  .rsobj_advance
    ; temp_sprite_ptr += STATIC_OBJ_ENTRY_SIZE
    LDA temp_sprite_ptr
    CLC
    ADC #STATIC_OBJ_ENTRY_SIZE
    STA temp_sprite_ptr
    BCC rsobj_adv_ok
    INC temp_sprite_ptr+1
  .rsobj_adv_ok
    JMP rsobj_next

  .rsobj_done
    RTS


; Note: object instance tables live in `objects.asm`.


; Generic unmasked stamper for tile-aligned objects.
;
; Inputs:
; - screen_ptr: destination top-left
; - sprite_ptr: source data (striped)
; - A: stripe count (1,2,4)
; - X: bytes to copy per stripe (16 for 8px-wide, 32 for 16px-wide)
; - Y: source stride per stripe (usually 16 or 32)
.stamp_striped_copy
    STA row_counter
    STX col_counter
    STY temp_y

    ; Preserve pointers.
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    LDA sprite_ptr
    PHA
    LDA sprite_ptr+1
    PHA

  .stamp_stripe
    LDY #0
  .stamp_byte
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    CPY col_counter
    BNE stamp_byte

    ; Next stripe on screen.
    INC screen_ptr+1

    ; Next stripe in sprite data.
    LDA sprite_ptr
    CLC
    ADC temp_y
    STA sprite_ptr
    BCC stamp_sprite_ptr_ok
    INC sprite_ptr+1
  .stamp_sprite_ptr_ok

    DEC row_counter
    BNE stamp_stripe

    ; Restore pointers.
    PLA
    STA sprite_ptr+1
    PLA
    STA sprite_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    RTS


; Generic masked stamper for tile-aligned objects.
;
; Inputs:
; - screen_ptr: destination top-left
; - sprite_ptr: source data (striped)
; - mask_ptr: mask data (striped)
; - A: stripe count (1,2,4)
; - X: bytes to process per stripe (16 for 8px-wide, 32 for 16px-wide)
; - Y: source stride per stripe (usually 16 or 32)
 .stamp_striped_masked
    ; Keep the blit atomic: MOS IRQ handlers may use/modify ZP.
    ; Preserve the caller's interrupt state so nested callers that already have
    ; IRQs disabled don't get re-enabled at the end.
    PHP
    SEI
    STA row_counter
    STX col_counter
    STY temp_y

    ; Preserve pointers.
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    LDA sprite_ptr
    PHA
    LDA sprite_ptr+1
    PHA
    LDA mask_ptr
    PHA
    LDA mask_ptr+1
    PHA

  .stampm_stripe
    LDY #0
  .stampm_byte
    LDA (mask_ptr),Y
    BEQ stampm_opaque
    CMP #&FF
    BEQ stampm_next

    STA temp
    LDA (screen_ptr),Y
    AND temp
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP stampm_next

  .stampm_opaque
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y

  .stampm_next
    INY
    CPY col_counter
    BNE stampm_byte

    ; Next stripe on screen.
    INC screen_ptr+1

    ; Next stripe in sprite/mask data.
    LDA sprite_ptr
    CLC
    ADC temp_y
    STA sprite_ptr
    BCC stampm_sprite_ptr_ok
    INC sprite_ptr+1
  .stampm_sprite_ptr_ok

    LDA mask_ptr
    CLC
    ADC temp_y
    STA mask_ptr
    BCC stampm_mask_ptr_ok
    INC mask_ptr+1
  .stampm_mask_ptr_ok

    DEC row_counter
    BNE stampm_stripe

    ; Restore pointers.
    PLA
    STA mask_ptr+1
    PLA
    STA mask_ptr
    PLA
    STA sprite_ptr+1
    PLA
    STA sprite_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    PLP
    RTS

; Fill the visible playfield (32 bytes x 256 scanlines = 8192 bytes) with cyan.
;
; With our palette mapping, colour index 2 is cyan. In MODE 5 (2bpp), a byte of
; four cyan pixels encodes as &F0.
.clear_playfield_cyan
    ; temp_mask_ptr := &5800
    LDA #<(&5800)
    STA temp_mask_ptr
    LDA #>(&5800)
    STA temp_mask_ptr+1

    ; 0x5800..0x77FF is 0x20 pages of 256 bytes.
    LDX #&20
    LDA #&F0
  .clear_page
    LDY #0
  .clear_byte
    STA (temp_mask_ptr),Y
    INY
    BNE clear_byte
    INC temp_mask_ptr+1
    DEX
    BNE clear_page
    RTS

.render_cell8x16
    ; Store tile type
    STA temp
    ; Preserve screen pointer
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Get sprite data pointer for this tile
    LDA temp
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA sprite_table+1,X
    STA sprite_ptr+1                 ; sprite_ptr_hi

    ; Plot first half (top 8 rows)
    JSR plot_cell_stripe8x8
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half
    INC sprite_ptr+1
    
.next_half
    ; Plot second half (bottom 8 rows)
    JSR plot_cell_stripe8x8
    
    ; Restore screen pointer
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    RTS

; Masked version of render_cell8x16 - for sprites with transparent black pixels
.render_masked_cell8x16
    ; Store tile type
    STA temp

    ; Preserve screen pointer
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Get sprite data pointer for this tile
    LDA temp                 ; temp
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA sprite_table+1,X
    STA sprite_ptr+1                 ; sprite_ptr_hi

    ; Plot first half (top 8 rows) with masking
    JSR plot_masked_cell_stripe8x8
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half_masked
    INC sprite_ptr+1
    
.next_half_masked
    ; Plot second half (bottom 8 rows) with masking  
    JSR plot_masked_cell_stripe8x8
    
    ; Restore screen pointer
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    RTS

; Plots one 8x8 stripe of an 8x16 cell.
; Stored as 16 bytes (2 bytes wide × 8 scanlines) in MODE 5 screen-byte order.
.plot_cell_stripe8x8
    ; Plot 16 bytes of sprite data consecutively
    LDY #0
.sprite_wide_row_loop
    LDA (sprite_ptr),Y             ; Get sprite row data from sprite_ptr
    STA (screen_ptr),Y             ; Plot to screen at screen_ptr
    INY
    CPY #16                 ; 16 bytes per row
    BNE sprite_wide_row_loop
    RTS

; Plots one 8x8 stripe of an 8x16 cell with masking (black pixels transparent).
; MODE 5 uses interleaved bits: pixel 0=bits 0+4, pixel 1=bits 1+5, pixel 2=bits 2+6, pixel 3=bits 3+7
.plot_masked_cell_stripe8x8
    LDY #0
.masked_sprite_byte_loop
    LDA (sprite_ptr),Y             ; Load sprite byte from sprite_ptr
    BEQ skip_sprite_byte    ; If entire byte is 0 (all black), skip it
    
    STA temp                 ; Store sprite byte in &70 (temp)
    LDA (screen_ptr),Y             ; Load current screen byte from screen_ptr
    STA temp_y                 ; Store screen byte in &75 (temp_y)
    
    ; Process pixel 0 (bits 0 and 4) - MSB bit 0 = bit 7, bit 4 = bit 3
    LDA temp
    AND #&88                ; Mask bits 7 and 3 (0 and 4 in MSB numbering)
    BEQ keep_screen_pixel0  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&77                ; Clear screen bits 7 and 3
    ORA temp                ; OR in sprite bits 7 and 3
    STA temp_y
.keep_screen_pixel0
    
    ; Process pixel 1 (bits 1 and 5) - MSB bit 1 = bit 6, bit 5 = bit 2
    LDA temp
    AND #&44                ; Mask bits 6 and 2 (1 and 5 in MSB numbering)
    BEQ keep_screen_pixel1  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&BB                ; Clear screen bits 6 and 2
    ORA temp                ; OR in sprite bits 6 and 2
    STA temp_y
.keep_screen_pixel1
    
    ; Process pixel 2 (bits 2 and 6) - MSB bit 2 = bit 5, bit 6 = bit 1
    LDA temp
    AND #&22                ; Mask bits 5 and 1 (2 and 6 in MSB numbering)
    BEQ keep_screen_pixel2  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&DD                ; Clear screen bits 5 and 1
    ORA temp                ; OR in sprite bits 5 and 1
    STA temp_y
.keep_screen_pixel2
    
    ; Process pixel 3 (bits 3 and 7) - MSB bit 3 = bit 4, bit 7 = bit 0
    LDA temp
    AND #&11                ; Mask bits 4 and 0 (3 and 7 in MSB numbering)
    BEQ keep_screen_pixel3  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&EE                ; Clear screen bits 4 and 0
    ORA temp                ; OR in sprite bits 4 and 0
    STA temp_y
.keep_screen_pixel3

    LDA temp_y
    STA (screen_ptr),Y             ; Write modified byte back to screen

.skip_sprite_byte
    INY
    CPY #16                 ; 16 bytes total
    BNE masked_sprite_byte_loop
    
    RTS; Render character sprite with mask - uses character_sprite_table and character_mask_table
.render_character_sprite
    ; preserve A
    STA temp
    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr +1
    PHA
    ; restore A
    LDA temp
    ; Input: A = character sprite index (0-based index for character_sprite_table)
    ASL A
    TAX
    LDA character_sprite_table,X
    STA sprite_ptr
    LDA character_sprite_table+1,X
    STA sprite_ptr+1
    
    ; Set up mask pointer from character_mask_table
    LDA character_mask_table,X
    STA mask_ptr
    LDA character_mask_table+1,X
    STA mask_ptr+1

    ; Plot full character sprite (32 scanlines) using Spycat-style masked blit
    JSR plot_sprite12x32_masked_striped

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; Render 16x16 overlay sprite (gun/box arms) with mask.
; Input: A = overlay index (0-based, matches overlay_*_table order).
; The overlay is drawn over the middle two stripes of the 16x32 body (stripes 1+2).
.render_overlay_sprite
    ; Preserve input index before clobbering A.
    STA temp

    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA

    ; screen_ptr += 1 stripe (8 scanlines)
    INC screen_ptr+1

    ; Restore our index (original A)
    LDA temp

    ASL A
    TAX

    LDA overlay_sprite_table,X
    STA sprite_ptr
    LDA overlay_sprite_table+1,X
    STA sprite_ptr+1

    LDA overlay_mask_table,X
    STA mask_ptr
    LDA overlay_mask_table+1,X
    STA mask_ptr+1

    JSR plot_sprite16x16_masked_striped

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr

    RTS

; Render a 16x16 reticle sprite with mask.
; Input: A = reticle state index (0=blocked/unportalable, 1=portalable).
; Drawn at `screen_ptr` with no built-in offset.
.render_reticle_sprite
    ; Preserve input index before clobbering A.
    STA temp

    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA

    ; Restore our index (original A)
    LDA temp

    ASL A
    TAX

    LDA reticle_sprite_table,X
    STA sprite_ptr
    LDA reticle_sprite_table+1,X
    STA sprite_ptr+1

    LDA reticle_mask_table,X
    STA mask_ptr
    LDA reticle_mask_table+1,X
    STA mask_ptr+1

    JSR plot_sprite16x16_masked_striped

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr

    RTS
 
 ; Sprite blit used by Spycat-format character sprites.
; Data: 4 stripes × 32 bytes/stripe (8 scanlines × 4 bytes/scanline).
; Screen: each stripe is 8 scanlines below the previous one.
;
; Debug version (no mask): dst = pix (hard overwrite)
; Requires: sprite_ptr = pix data, screen_ptr = top-left screen
.plot_sprite12x32_striped_copy
    ; Preserve base pointers so we can restore them.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1

    LDX #0
.copy_stripe_loop
    LDY #0
.copy_row_bytes
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    CPY #32
    BNE copy_row_bytes

    ; Next stripe: move down 8 scanlines on screen.
    INC screen_ptr+1

    ; Next stripe in data (+32 bytes)
    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC copy_sprite_ptr_ok
    INC sprite_ptr+1
.copy_sprite_ptr_ok

    INX
    CPX #4
    BNE copy_stripe_loop

    ; Restore screen_ptr (advanced 4 stripes)
    LDA screen_ptr+1
    SEC
    SBC #4
    STA screen_ptr+1

    ; Restore sprite_ptr
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1

    RTS

 ; Masked version (Spycat-style): dst = (dst & mask) | pix
 ; Requires: sprite_ptr = pix data, mask_ptr = mask data, screen_ptr = top-left screen
 .plot_sprite12x32_masked_striped
    ; Preserve base pointers so we can restore them.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1
    LDA mask_ptr
    STA temp_mask_ptr
    LDA mask_ptr+1
    STA temp_mask_ptr+1

    LDX #0
 .masked_stripe_loop
    LDY #0
 .masked_row_bytes
    ; Fast paths:
    ; - mask==&00: fully opaque -> dst=pix
    ; - mask==&FF and pix==&00: fully transparent -> skip
    LDA (mask_ptr),Y
    BEQ masked_opaque
    CMP #&FF
    BEQ masked_maybe_transparent

    STA temp
    LDA (screen_ptr),Y
    AND temp
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP masked_next_byte

  .masked_opaque
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP masked_next_byte

  .masked_maybe_transparent
    LDA (sprite_ptr),Y
    BEQ masked_next_byte
    ORA (screen_ptr),Y
    STA (screen_ptr),Y

  .masked_next_byte

    INY
    CPY #32
    BNE masked_row_bytes

    ; Next stripe: move down 8 scanlines on screen.
    INC screen_ptr+1

    ; Next stripe in data (+32 bytes)
    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC masked_sprite_ptr_ok
    INC sprite_ptr+1
.masked_sprite_ptr_ok

    LDA mask_ptr
    CLC
    ADC #32
    STA mask_ptr
    BCC masked_mask_ptr_ok
    INC mask_ptr+1
.masked_mask_ptr_ok

    INX
    CPX #4
    BNE masked_stripe_loop

    ; Restore screen_ptr (advanced 4 stripes)
    LDA screen_ptr+1
    SEC
    SBC #4
    STA screen_ptr+1

    ; Restore sprite/mask pointers
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1
    LDA temp_mask_ptr
    STA mask_ptr
    LDA temp_mask_ptr+1
    STA mask_ptr+1
 
    RTS

; Unmasked version: 16x16 (two stripes): dst = pix (hard overwrite)
; Requires: sprite_ptr = pix data, screen_ptr = top-left screen address for stripe 0
.plot_sprite16x16_striped_copy
    ; Preserve base sprite pointer so we can restore it.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1

    ; Stripe 0: copy 32 bytes
    LDY #0
.overlay_copy_bytes0
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    CPY #32
    BNE overlay_copy_bytes0

    ; Advance screen one stripe (8 scanlines) and data +32 bytes
    INC screen_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC overlay_copy_sprite_ptr_ok
    INC sprite_ptr+1
.overlay_copy_sprite_ptr_ok

    ; Stripe 1: copy 32 bytes
    LDY #0
.overlay_copy_bytes1
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    CPY #32
    BNE overlay_copy_bytes1

    ; Restore screen_ptr (advanced 1 stripe)
    DEC screen_ptr+1

    ; Restore sprite_ptr
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1

    RTS

 ; Masked version (Spycat-style): 16x16 (two stripes): dst = (dst & mask) | pix
 ; Requires: sprite_ptr = pix data, mask_ptr = mask data
 ;          screen_ptr = top-left screen address for stripe 0
 .plot_sprite16x16_masked_striped
    ; Preserve base pointers so we can restore them.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1
    LDA mask_ptr
    STA temp_mask_ptr
    LDA mask_ptr+1
    STA temp_mask_ptr+1

    ; Stripe 0: copy 32 bytes
    LDY #0
 .overlay_bytes0
    LDA (mask_ptr),Y
    BEQ overlay_opaque0
    CMP #&FF
    BEQ overlay_maybe_transparent0

    STA temp
    LDA (screen_ptr),Y
    AND temp
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP overlay_next0

  .overlay_opaque0
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP overlay_next0

  .overlay_maybe_transparent0
    LDA (sprite_ptr),Y
    BEQ overlay_next0
    ORA (screen_ptr),Y
    STA (screen_ptr),Y

  .overlay_next0
    INY
    CPY #32
    BNE overlay_bytes0

    ; Advance screen one stripe (8 scanlines) and data +32 bytes
    INC screen_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC sprite_ptr_ok1
    INC sprite_ptr+1
.sprite_ptr_ok1

    LDA mask_ptr
    CLC
    ADC #32
    STA mask_ptr
    BCC mask_ptr_ok1
    INC mask_ptr+1
.mask_ptr_ok1

    ; Stripe 1: copy 32 bytes
    LDY #0
 .overlay_bytes1
    LDA (mask_ptr),Y
    BEQ overlay_opaque1
    CMP #&FF
    BEQ overlay_maybe_transparent1

    STA temp
    LDA (screen_ptr),Y
    AND temp
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP overlay_next1

  .overlay_opaque1
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP overlay_next1

  .overlay_maybe_transparent1
    LDA (sprite_ptr),Y
    BEQ overlay_next1
    ORA (screen_ptr),Y
    STA (screen_ptr),Y

  .overlay_next1
    INY
    CPY #32
    BNE overlay_bytes1

    ; Restore screen_ptr (advanced 1 stripe)
    DEC screen_ptr+1

    ; Restore sprite/mask pointers
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1
    LDA temp_mask_ptr
    STA mask_ptr
    LDA temp_mask_ptr+1
    STA mask_ptr+1

    RTS
 
; Sprite pointer table lookup is now used for sprite selection.



; Dedicated save-under buffers in screen scratch.
; We avoid the general pool so we can restore/draw per object (and skip work
; entirely when an object hasn't moved).
CHELL_SAVE_UNDER_BASE     = &7800   ; 16x32 = 128 bytes
RETICLE_SAVE_UNDER_BASE   = &7880   ; 16x16 = 64 bytes

; 256-byte solid-tile plane (16x16 tiles) stored in screen scratch.
; 0 = empty, nonzero = solid.
SOLID_TILE_PLANE          = &7A00

; Save-under helpers.
;
; These copy raw screen bytes into a contiguous buffer and restore them later.
; This is intentionally separate from sprite masking.
;
; Chell: 16x32 -> 4 stripes x 32 bytes.
; Reticle: 16x16 -> 2 stripes x 32 bytes.

; Save 16x32 under screen_ptr into CHELL_SAVE_UNDER_BASE.
.save_chell_under
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    ; temp_mask_ptr := source screen
    LDA screen_ptr
    STA temp_mask_ptr
    LDA screen_ptr+1
    STA temp_mask_ptr+1

    ; sprite_ptr := dest buffer
    LDA #<(CHELL_SAVE_UNDER_BASE)
    STA sprite_ptr
    LDA #>(CHELL_SAVE_UNDER_BASE)
    STA sprite_ptr+1

    LDY #0
    STY temp
.save_chell_stripe
    LDY #0
.save_chell_bytes
    LDA (temp_mask_ptr),Y
    STA (sprite_ptr),Y
    INY
    CPY #32
    BNE save_chell_bytes

    INC temp_mask_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC save_chell_next
    INC sprite_ptr+1
.save_chell_next

    INC temp
    LDA temp
    CMP #4
    BNE save_chell_stripe

    PLP
    RTS

; Restore 16x32 from CHELL_SAVE_UNDER_BASE to chell_prev_ptr.
.restore_chell_under
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    ; temp_mask_ptr := dest screen
    LDA chell_prev_ptr
    STA temp_mask_ptr
    LDA chell_prev_ptr+1
    STA temp_mask_ptr+1

    ; sprite_ptr := src buffer
    LDA #<(CHELL_SAVE_UNDER_BASE)
    STA sprite_ptr
    LDA #>(CHELL_SAVE_UNDER_BASE)
    STA sprite_ptr+1

    LDY #0
    STY temp
.restore_chell_stripe
    LDY #0
.restore_chell_bytes
    LDA (sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    CPY #32
    BNE restore_chell_bytes

    INC temp_mask_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC restore_chell_next
    INC sprite_ptr+1
.restore_chell_next

    INC temp
    LDA temp
    CMP #4
    BNE restore_chell_stripe

    PLP
    RTS

; Save 16x16 under screen_ptr into RETICLE_SAVE_UNDER_BASE.
.save_reticle_under
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    ; temp_mask_ptr := source screen
    LDA screen_ptr
    STA temp_mask_ptr
    LDA screen_ptr+1
    STA temp_mask_ptr+1

    ; sprite_ptr := dest buffer
    LDA #<(RETICLE_SAVE_UNDER_BASE)
    STA sprite_ptr
    LDA #>(RETICLE_SAVE_UNDER_BASE)
    STA sprite_ptr+1

    LDY #0
    STY temp
.save_reticle_stripe
    LDY #0
.save_reticle_bytes
    LDA (temp_mask_ptr),Y
    STA (sprite_ptr),Y
    INY
    CPY #32
    BNE save_reticle_bytes

    INC temp_mask_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC save_reticle_next
    INC sprite_ptr+1
.save_reticle_next

    INC temp
    LDA temp
    CMP #2
    BNE save_reticle_stripe

    PLP
    RTS

; Restore 16x16 from RETICLE_SAVE_UNDER_BASE to reticle_prev_ptr.
.restore_reticle_under
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    ; temp_mask_ptr := dest screen
    LDA reticle_prev_ptr
    STA temp_mask_ptr
    LDA reticle_prev_ptr+1
    STA temp_mask_ptr+1

    ; sprite_ptr := src buffer
    LDA #<(RETICLE_SAVE_UNDER_BASE)
    STA sprite_ptr
    LDA #>(RETICLE_SAVE_UNDER_BASE)
    STA sprite_ptr+1

    LDY #0
    STY temp
.restore_reticle_stripe
    LDY #0
.restore_reticle_bytes
    LDA (sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    CPY #32
    BNE restore_reticle_bytes

    INC temp_mask_ptr+1

    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC restore_reticle_next
    INC sprite_ptr+1
.restore_reticle_next

    INC temp
    LDA temp
    CMP #2
    BNE restore_reticle_stripe

    PLP
    RTS

; Build a 16x16 solid-tile plane from the current room tilemap.
;
; Stores 256 bytes at `SOLID_TILE_PLANE`:
; - 0 = empty
; - 1 = solid
;
; Portalability is handled separately via a tile-layer (portalmap_ptr).
.build_material_planes_from_tilemap
    LDY #0
.build_solid_tile_plane_loop
    LDA (tilemap_ptr),Y
    TAX
    LDA tile_material_flags,X
    AND #2
    BEQ not_solid_tile
    LDA #1
.not_solid_tile
    STA SOLID_TILE_PLANE,Y
    INY
    BNE build_solid_tile_plane_loop
    RTS


; Rebuild the physics solidity plane (tiles + standable objects).
;
; Copies the world tile solidity (`SOLID_TILE_PLANE`) into `solid_phys_plane`,
; then stamps standable objects (cubes) into it.
;
; Must be called during update before any collision queries for the frame.
; Clobbers: A,X,Y
.rebuild_solid_phys_plane
    ; Copy 256 bytes: SOLID_TILE_PLANE -> solid_phys_plane
    LDY #0
  .rsp_copy
    LDA SOLID_TILE_PLANE,Y
    STA solid_phys_plane,Y
    INY
    BNE rsp_copy

    ; Stamp standable objects into the physics plane.
    ; Note: pads are triggers on the floor and should not raise Chell, so only
    ; cubes contribute to physics solidity.
    LDY #0
  .rsp_obj_loop
    LDA obj_room,Y
    CMP current_room
    BNE rsp_obj_next

    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE rsp_obj_next

    ; Carried cubes do not contribute to solidity.
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BNE rsp_obj_next

  .rsp_obj_stamp
    ; idx = obj_y*16 + obj_x
    LDA obj_y,Y
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAX
    LDA #1
    STA solid_phys_plane,X

    ; second tile (x+1) unless at right edge
    LDA obj_x,Y
    CMP #15
    BEQ rsp_obj_next
    INX
    LDA #1
    STA solid_phys_plane,X

  .rsp_obj_next
    INY
    CPY #OBJ_COUNT
    BNE rsp_obj_loop
    RTS


; Return C=1 if solid at pixel (X,Y) for physics.
; Uses `solid_phys_plane` (tiles + standable objects).
.is_solid_physics
    ; tile_x = X >> 3
    TXA
    LSR A
    LSR A
    LSR A
    STA col_counter

    ; tile_y = Y >> 4
    TYA
    LSR A
    LSR A
    LSR A
    LSR A
    TAY

    ; tilepos = tile_y*16 + tile_x
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY

    LDA solid_phys_plane,Y
    BEQ solid_phys_clear
    SEC
    RTS
  .solid_phys_clear
    CLC
    RTS

; Return C=1 if solid at pixel (X,Y).
; Uses the prebuilt solid-tile plane (8x16 tiles).
.is_solid
    ; tile_x = X >> 3
    TXA
    LSR A
    LSR A
    LSR A
    STA col_counter

    ; tile_y = Y >> 4
    TYA
    LSR A
    LSR A
    LSR A
    LSR A
    TAY

    ; tilepos = tile_y*16 + tile_x
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY

    LDA SOLID_TILE_PLANE,Y
    BEQ solid_clear
    SEC
    RTS
.solid_clear
    CLC
    RTS

; Return C=1 if portalable at (X,Y) using the portalable tile-layer.
; Tiles are 8x16 pixels (16 tiles across 128px).
.is_portalable
    ; tile_x = X >> 3
    TXA
    LSR A
    LSR A
    LSR A
    STA col_counter

    ; tile_y = Y >> 4
    TYA
    LSR A
    LSR A
    LSR A
    LSR A
    TAY

    ; tilepos = tile_y*16 + tile_x
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY

    LDA (portalmap_ptr),Y
    BEQ portal_clear
    SEC
    RTS
.portal_clear
    CLC
    RTS


 .tile_material_flags
    ; Tile ids:
    ; 0  = empty (background)
    ; 1+ = all current room tiles (bedrock/platform variants)
    ; For now, treat all non-zero tiles as solid.
    EQUB 0
    EQUB 2,2,2,2,2,2,2,2,2
    EQUB 2,2,2,2,2,2,2,2,2
    ; Fill remaining entries with 0.
    SKIP 256-19

; Legacy: redraw tiles behind the character (tilemap-based restore)
.redraw_background_area
    ; Save screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Character sprite is 2 tiles wide × 2 tiles tall (16x32).
    ; We redraw 4 tiles (2×2) to fully erase the previous frame.
    
    ; Calculate tile_y and tile_x from char_tile_pos for screen positioning only
    LDA char_tile_pos
    LSR A              ; Divide by 2
    LSR A              ; Divide by 4  
    LSR A              ; Divide by 8
    LSR A              ; Divide by 16 = tile_y
    STA temp_y         ; Store tile_y
    
    ; Calculate tile_x from char_tile_pos  
    LDA char_tile_pos
    AND #15            ; Keep only lower 4 bits = tile_x
    STA col_counter    ; Store tile_x
    
    ; Look up screen position from tile row table
    LDA temp_y         ; tile_y
    ASL A              ; * 2 for 16-bit table index
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1
    
    ; Add tile_x * 16 using lookup table
    LDY col_counter    ; tile_x
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC first_tile
    INC screen_ptr+1
    
.first_tile
    ; Top-left tile
    LDY char_tile_pos
    JSR get_tilemap_tile
    JSR render_cell8x16

    ; Top-right tile
    LDA screen_ptr
    CLC
    ADC #16
    STA screen_ptr
    BCC top_right_no_carry
    INC screen_ptr+1
.top_right_no_carry
    LDY char_tile_pos
    INY
    JSR get_tilemap_tile
    JSR render_cell8x16

    ; Move down one tile row (512 bytes)
    INC screen_ptr+1
    INC screen_ptr+1

    ; Bottom-right tile (char_tile_pos + 17)
    LDY char_tile_pos
    TYA
    CLC
    ADC #17
    TAY
    JSR get_tilemap_tile
    JSR render_cell8x16

    ; Bottom-left tile (move screen_ptr back 16 bytes; char_tile_pos + 16)
    LDA screen_ptr
    SEC
    SBC #16
    STA screen_ptr
    BCS bottom_left_no_borrow
    DEC screen_ptr+1
.bottom_left_no_borrow
    LDY char_tile_pos
    TYA
    CLC
    ADC #16
    TAY
    JSR get_tilemap_tile
    JSR render_cell8x16

    ; Restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
 
    RTS
