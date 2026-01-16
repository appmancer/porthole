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
    JSR render_cell8x16
    
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
    LDA (screen_ptr),Y
    AND (mask_ptr),Y
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y

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
    LDA (screen_ptr),Y
    AND (mask_ptr),Y
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
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
    LDA (screen_ptr),Y
    AND (mask_ptr),Y
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
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

    RTS

; Restore 16x32 from CHELL_SAVE_UNDER_BASE to chell_prev_ptr.
.restore_chell_under
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

    RTS

; Save 16x16 under screen_ptr into RETICLE_SAVE_UNDER_BASE.
.save_reticle_under
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

    RTS

; Restore 16x16 from RETICLE_SAVE_UNDER_BASE to reticle_prev_ptr.
.restore_reticle_under
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

; Return C=1 if solid at pixel (X,Y).
; Uses the prebuilt solid-tile plane (8x16 tiles).
.is_solid
    ; tile_x = X >> 3
    TXA
    LSR A
    LSR A
    LSR A
    STA temp

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
    ADC temp
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
    STA temp

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
    ADC temp
    TAY

    LDA (portalmap_ptr),Y
    BEQ portal_clear
    SEC
    RTS
.portal_clear
    CLC
    RTS


 .tile_material_flags
    ; 0..3: non-solid (bootstrap default)
    EQUB 0,0,0,0
    ; 4..12: solid
    EQUB 2,2,2,2,2,2,2,2,2
    ; Fill remaining entries with 0.
    SKIP 256-13

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

