; Portal placement, erase/redraw, and stamping.

; Place a portal by updating the current room's static-object entry.
; This updates global portal state (one A + one B per level).
;
; Input:
; - A = 0 for Portal A (red)
; - A = 1 for Portal B (yellow)
;
.place_portal_from_reticle
     STA portal_kind

      ; Snapshot old portal state (for erase).
     LDA portal_kind
     BEQ ppr_snap_a
      ; B
      LDA portal_b_enabled
      STA portal_old_enabled
      LDA portal_b_room
      STA portal_old_room
      LDA portal_b_x
      STA portal_old_x
      LDA portal_b_y
      STA portal_old_y
      LDA portal_b_orient
      STA portal_old_orient
      JMP ppr_compute_new
    .ppr_snap_a
      LDA portal_a_enabled
      STA portal_old_enabled
      LDA portal_a_room
      STA portal_old_room
      LDA portal_a_x
      STA portal_old_x
      LDA portal_a_y
      STA portal_old_y
      LDA portal_a_orient
      STA portal_old_orient

   .ppr_compute_new
      ; Compute new x.
      ; Wall portal can snap to either the left or right 8px column within the
      ; 16px reticle span. reticle_debug_reason distinguishes:
      ;   2 = left column match
      ;   3 = right column match
     LDA reticle_debug_reason
     AND #&7F
     CMP #3
     BNE ppr_x_left
     LDA reticle_cell_x
     CLC
     ADC #1
     JMP ppr_x_store
   .ppr_x_left
     LDA reticle_cell_x
   .ppr_x_store
     STA temp

      ; y (clamp away from final row only for 2-tile-tall portals)
      LDA reticle_cell_y
      STA temp_y

      ; Orientation computed by reticle validation.
      ; 0..4 (wall_l, wall_r, floor, ceil, back)
      LDA reticle_wall_orient
      STA row_counter

      ; For floor/ceiling portals, the surface tiles are solid.
      ; Store the portal's rect in the adjacent empty space so overlap can occur:
      ; - floor surface at y => portal rect at y-1
      ; - ceiling surface at y => portal rect at y+1
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE ppr_not_floor
      LDA temp_y
      BEQ ppr_reject_oob
      DEC temp_y
      JMP ppr_y_ok
  .ppr_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE ppr_not_ceil
      LDA temp_y
      CMP #15
      BEQ ppr_reject_oob
      INC temp_y
      JMP ppr_y_ok
  .ppr_not_ceil

      ; Wall/back-wall stamps are 2 tiles tall; clamp y so y+1 stays in range.
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_y_ok
      LDA temp_y
      CMP #15
      BNE ppr_y_ok
      LDA #14
      STA temp_y
    .ppr_y_ok

      JMP ppr_overlap_check

  .ppr_reject_oob
      RTS

   .ppr_overlap_check

       ; Prevent overlapping portals (red and yellow cannot overlap).
       ; Disallow placement if tile footprints intersect.
      ; new footprint dims (tile units) into col_counter(w) and screen_ptr(h)
      LDA row_counter
      CMP #PORTAL_ORIENT_BACK
      BEQ ppr_new_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_new_fc
      ; wall (1x2)
      LDA #1
      STA col_counter
      LDA #2
      STA screen_ptr
      JMP ppr_overlap_have_new
   .ppr_new_fc
      ; floor/ceiling (2x1)
      LDA #2
      STA col_counter
      LDA #1
      STA screen_ptr
      JMP ppr_overlap_have_new
   .ppr_new_back
      ; back wall (2x2)
      LDA #2
      STA col_counter
      STA screen_ptr

   .ppr_overlap_have_new
      ; Determine other portal (the one we're not placing).
      LDA portal_kind
      BEQ ppr_check_vs_b

      ; Placing B: check against A
      LDA portal_a_enabled
      BEQ ppr_no_overlap
      LDA portal_a_room
      CMP current_room
      BNE ppr_no_overlap
      LDA portal_a_x
      STA screen_ptr+1          ; other_x
      LDA portal_a_y
      STA temp_mask_ptr         ; other_y
      LDA portal_a_orient
      JMP ppr_overlap_have_other

   .ppr_check_vs_b
      ; Placing A: check against B
      LDA portal_b_enabled
      BEQ ppr_no_overlap
      LDA portal_b_room
      CMP current_room
      BNE ppr_no_overlap
      LDA portal_b_x
      STA screen_ptr+1          ; other_x
      LDA portal_b_y
      STA temp_mask_ptr         ; other_y
      LDA portal_b_orient

   .ppr_overlap_have_other
      ; other dims into temp_mask_ptr+1(w) and temp_sprite_ptr(h)
      CMP #PORTAL_ORIENT_BACK
      BEQ ppr_other_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_other_fc
      ; wall (1x2)
      LDA #1
      STA temp_mask_ptr+1
      LDA #2
      STA temp_sprite_ptr
      JMP ppr_overlap_test
   .ppr_other_fc
      ; floor/ceiling (2x1)
      LDA #2
      STA temp_mask_ptr+1
      LDA #1
      STA temp_sprite_ptr
      JMP ppr_overlap_test
   .ppr_other_back
      ; back wall (2x2)
      LDA #2
      STA temp_mask_ptr+1
      STA temp_sprite_ptr

   .ppr_overlap_test
      ; X overlap:
      ; if (new_x + new_w) <= other_x => no overlap
      LDA temp
      CLC
      ADC col_counter
      CMP screen_ptr+1
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; if (other_x + other_w) <= new_x => no overlap
      LDA screen_ptr+1
      CLC
      ADC temp_mask_ptr+1
      CMP temp
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; Y overlap:
      ; if (new_y + new_h) <= other_y => no overlap
      LDA temp_y
      CLC
      ADC screen_ptr
      CMP temp_mask_ptr
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; if (other_y + other_h) <= new_y => no overlap
      LDA temp_mask_ptr
      CLC
      ADC temp_sprite_ptr
      CMP temp_y
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; Intersects => reject placement.
      RTS

    .ppr_no_overlap

      ; Commit new state.
      LDA portal_kind
      BEQ ppr_set_a
      ; B
     LDA #1
     STA portal_b_enabled
     LDA current_room
     STA portal_b_room
     LDA temp
     STA portal_b_x
     LDA temp_y
     STA portal_b_y
     LDA row_counter
     STA portal_b_orient
     JMP ppr_done
   .ppr_set_a
     LDA #1
     STA portal_a_enabled
     LDA current_room
     STA portal_a_room
     LDA temp
     STA portal_a_x
     LDA temp_y
     STA portal_a_y
     LDA row_counter
     STA portal_a_orient
   .ppr_done

     LDA #1
     STA portal_pending
     RTS


; Apply a pending portal update without redrawing the whole room.
; This erases the old portal stamp by re-rendering the underlying tiles, then
; stamps the updated portal entry.
;
; Safe to call unconditionally; returns quickly if portal_pending=0.
.apply_pending_portal_update
     LDA portal_pending
     BNE apu_go
     RTS

  .apu_go
      ; Erase old stamp if it was previously enabled AND visible in this room.
      LDA portal_old_enabled
      BNE apu_old_enabled
      JMP apu_stamp_new
  .apu_old_enabled
      LDA portal_old_room
      CMP current_room
      BEQ apu_old_visible
      JMP apu_stamp_new
  .apu_old_visible

      ; Redraw underlying tiles for the old portal footprint.
      LDA portal_old_orient
      CMP #PORTAL_ORIENT_BACK
      BEQ apu_erase_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS apu_erase_fc

      ; Wall: 1x2 tiles at (x,y) and (x,y+1)
      LDX portal_old_x
      LDA portal_old_y
      JSR redraw_tile_xy

      LDA portal_old_y
      CMP #15
      BNE apu_wall_redraw2
      JMP apu_stamp_new
  .apu_wall_redraw2
      CLC
      ADC #1
      LDX portal_old_x
      JSR redraw_tile_xy
      JMP apu_stamp_new

  .apu_erase_fc
      ; Floor/ceiling: 2x1 tiles at (x,y) and (x+1,y)
      ; Stored y is the collision rect (in empty space). Drawn portal lives on the
      ; surface tile row, so adjust Y for redraw.
      LDA portal_old_orient
      LDX portal_old_x
      LDY portal_old_y
      CMP #PORTAL_ORIENT_FLOOR
      BNE apu_erase_fc_not_floor
      INY
      JMP apu_erase_fc_have_y
  .apu_erase_fc_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE apu_erase_fc_have_y
      DEY
  .apu_erase_fc_have_y
       ; Preserve adjusted Y across redraw_tile_xy (it clobbers Y).
       STY temp_y
       ; Redraw both tiles in the 2x1 footprint.
       LDX portal_old_x
       LDA temp_y
       JSR redraw_tile_xy

       LDX portal_old_x
       CPX #15
       BEQ apu_stamp_new
       INX
       LDA temp_y
       JSR redraw_tile_xy

       JMP apu_stamp_new

  .apu_erase_back
      ; Back wall: 2x2 tiles at (x,y),(x+1,y),(x,y+1),(x+1,y+1)
      LDA portal_old_y
      STA temp_y

      ; top row
      LDX portal_old_x
      LDA temp_y
      JSR redraw_tile_xy
      LDX portal_old_x
      CPX #15
      BEQ apu_back_skip_topx
      INX
      LDA temp_y
      JSR redraw_tile_xy
  .apu_back_skip_topx

      ; bottom row
      LDA temp_y
      CMP #15
      BEQ apu_stamp_new
      CLC
      ADC #1
      STA temp_y
      LDX portal_old_x
      LDA temp_y
      JSR redraw_tile_xy
      LDX portal_old_x
      CPX #15
      BEQ apu_stamp_new
      INX
      LDA temp_y
      JSR redraw_tile_xy

      LDX portal_old_x
      CPX #15
      BEQ apu_stamp_new
      INX
      LDA temp_y
      JSR redraw_tile_xy

  .apu_stamp_new
      ; Stamp the newly placed portal if it is visible in this room.
     LDA portal_kind
     BEQ apu_try_a
     ; B
     LDA portal_b_enabled
     BEQ apu_done
     LDA portal_b_room
     CMP current_room
     BNE apu_done
       LDA portal_b_orient
       STA row_counter
       LDA #1
       PHA
       LDX portal_b_x
       LDY portal_b_y
       ; Adjust draw Y for floor/ceiling (stored y is collision rect).
       LDA row_counter
       CMP #PORTAL_ORIENT_FLOOR
      BNE apu_stamp_b_not_floor
      INY
      JMP apu_stamp_b_y_ok
  .apu_stamp_b_not_floor
       CMP #PORTAL_ORIENT_CEIL
       BNE apu_stamp_b_y_ok
       DEY
   .apu_stamp_b_y_ok
       PLA
       JSR stamp_portal_xy
       JMP apu_done
  .apu_try_a
     LDA portal_a_enabled
     BEQ apu_done
      LDA portal_a_room
      CMP current_room
      BNE apu_done
        LDA portal_a_orient
        STA row_counter
        LDA #0
        PHA
         LDX portal_a_x
         LDY portal_a_y
        ; Adjust draw Y for floor/ceiling (stored y is collision rect).
        LDA row_counter
        CMP #PORTAL_ORIENT_FLOOR
       BNE apu_stamp_a_not_floor
       INY
       JMP apu_stamp_a_y_ok
  .apu_stamp_a_not_floor
        CMP #PORTAL_ORIENT_CEIL
        BNE apu_stamp_a_y_ok
        DEY
   .apu_stamp_a_y_ok
        PLA
         JSR stamp_portal_xy

  .apu_done
     LDA #0
     STA portal_pending
     RTS


; Redraw a single 8x16 tile from the tilemap.
; Inputs:
; - A = tile_y (0..15)
; - X = tile_x (0..15)
; Clobbers: A,X,Y,temp,row_counter,temp_y,screen_ptr
.redraw_tile_xy
     STA temp_y
     STX row_counter

     ; Fetch tile id: idx = y*16 + x
     LDY temp_y
     LDA times16_table,Y
     CLC
     ADC row_counter
     TAY
     LDA (tilemap_ptr),Y
     STA temp

     ; screen_ptr := base of tile row
     LDA temp_y
     ASL A
     TAY
     LDA tile_row_screen_table,Y
     STA screen_ptr
     LDA tile_row_screen_table+1,Y
     STA screen_ptr+1

     ; + x*16
     LDY row_counter
     LDA times16_table,Y
     CLC
     ADC screen_ptr
     STA screen_ptr
     BCC rtx_x_ok
     INC screen_ptr+1
  .rtx_x_ok

     LDA temp
     JSR render_cell8x16
     RTS


; Stamp portal sprite at tile coordinates.
; Inputs:
; - A = kind (0=red, 1=yellow)
; - X = tile_x (0..15)
; - Y = tile_y (0..15)
; - row_counter = orient (0=left wall, 1=right wall)
; Uses fixed stamp geometry: 8x32 (1 tile wide x 2 tiles tall).
  .stamp_portal_xy
       ; Preserve kind.
       STA temp

     ; screen_ptr := &5800 + y*512 + x*16
     LDA #<(&5800)
     STA screen_ptr
     LDA #>(&5800)
     STA screen_ptr+1

     ; y*512 => add (y*2) to high byte
     TYA
     ASL A
     CLC
     ADC screen_ptr+1
     STA screen_ptr+1

     ; x*16 => add to low byte
     TXA
     TAY
     LDA times16_table,Y
     CLC
     ADC screen_ptr
     STA screen_ptr
     BCC spx_ok
     INC screen_ptr+1
  .spx_ok

       ; sprite_ptr/mask_ptr
       ; Choose based on portal kind + orientation.
      ; Note: our source CSVs are the "(Right)" wall variant, so:
      ; - *_r_* = right-wall portal art (tile id 5)
      ; - *_l_* = left-wall portal art, generated by flip_x
      ;
      ; Flipped inputs synthesize x0..x3 shifts; x3 corresponds to the
      ; unshifted variant when flip_x is enabled.
      ; When the portal pixels live in the *right* half of the 16px sprite, we
      ; start 16 bytes into each stripe.
      ; Floor/ceiling: 16x16 (2 stripes, 32 bytes/stripe).
      ; Back wall: 16x32 (4 stripes, 32 bytes/stripe).
      ;
      ; Note: sprite+mask bytes live in object SWRAM; page it in for reads.
      SEI
      LDA ROMSEL
      STA saved_romsel
      LDA obj_bank
      STA ROMSEL

       LDA row_counter
       CMP #PORTAL_ORIENT_BACK
       BEQ spx_is_back
       CMP #PORTAL_ORIENT_FLOOR
       BCS spx_not_wall
       JMP spx_is_wall
 .spx_not_wall

      LDA temp
      BEQ spx_fc_red

      ; Yellow floor/ceiling
      LDA row_counter
      CMP #PORTAL_ORIENT_CEIL
      BEQ spx_fc_yel_ceil
       ; floor
        LDA #<portal_h_yel_floor_x0
        STA sprite_ptr
        LDA #>portal_h_yel_floor_x0
        STA sprite_ptr+1
        LDA #<portal_h_yel_floor_x0_mask
        STA mask_ptr
        LDA #>portal_h_yel_floor_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp
  .spx_fc_yel_ceil
        LDA #<portal_h_yel_ceil_x0
        STA sprite_ptr
        LDA #>portal_h_yel_ceil_x0
        STA sprite_ptr+1
        LDA #<portal_h_yel_ceil_x0_mask
        STA mask_ptr
        LDA #>portal_h_yel_ceil_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp

 .spx_fc_red
      LDA row_counter
      CMP #PORTAL_ORIENT_CEIL
      BEQ spx_fc_red_ceil
       ; floor
        LDA #<portal_h_red_floor_x0
        STA sprite_ptr
        LDA #>portal_h_red_floor_x0
        STA sprite_ptr+1
        LDA #<portal_h_red_floor_x0_mask
        STA mask_ptr
        LDA #>portal_h_red_floor_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp
  .spx_fc_red_ceil
        LDA #<portal_h_red_ceil_x0
        STA sprite_ptr
        LDA #>portal_h_red_ceil_x0
        STA sprite_ptr+1
        LDA #<portal_h_red_ceil_x0_mask
        STA mask_ptr
        LDA #>portal_h_red_ceil_x0_mask
        STA mask_ptr+1

  .spx_fc_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #2
       LDX #32
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

 .spx_is_back
      LDA temp
      BEQ spx_back_red

       ; Yellow back wall
        LDA #<portal_b_yel_x0
        STA sprite_ptr
        LDA #>portal_b_yel_x0
        STA sprite_ptr+1
        LDA #<portal_b_yel_x0_mask
        STA mask_ptr
        LDA #>portal_b_yel_x0_mask
        STA mask_ptr+1
       JMP spx_back_stamp

  .spx_back_red
        LDA #<portal_b_red_x0
        STA sprite_ptr
        LDA #>portal_b_red_x0
        STA sprite_ptr+1
        LDA #<portal_b_red_x0_mask
        STA mask_ptr
        LDA #>portal_b_red_x0_mask
        STA mask_ptr+1

  .spx_back_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #4
       LDX #32
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

 .spx_is_wall
      LDA temp
      BEQ spx_red

      ; Yellow
      LDA row_counter
      BEQ spx_yel_leftwall
       ; right wall: use authored right-wall sprite
        LDA #<portal_v_yel_r_x0
        STA sprite_ptr
        LDA #>portal_v_yel_r_x0
        STA sprite_ptr+1
        LDA #<portal_v_yel_r_x0_mask
        STA mask_ptr
        LDA #>portal_v_yel_r_x0_mask
        STA mask_ptr+1
       JMP spx_stamp
    .spx_yel_leftwall
       ; left wall: use flipped sprite, unshifted = x3
        LDA #<portal_v_yel_l_x3
        STA sprite_ptr
        LDA #>portal_v_yel_l_x3
        STA sprite_ptr+1
        LDA #<portal_v_yel_l_x3_mask
        STA mask_ptr
        LDA #>portal_v_yel_l_x3_mask
        STA mask_ptr+1

      ; Offset into right half (columns 2+3) of each 16x32 stripe.
      LDA sprite_ptr
      CLC
      ADC #16
      STA sprite_ptr
      BCC spx_yel_ptr_ok
      INC sprite_ptr+1
   .spx_yel_ptr_ok
      LDA mask_ptr
      CLC
      ADC #16
      STA mask_ptr
      BCC spx_yel_mask_ok
      INC mask_ptr+1
   .spx_yel_mask_ok
      JMP spx_stamp

  .spx_red
      ; Red
      LDA row_counter
      BEQ spx_red_leftwall
       ; right wall: use authored right-wall sprite
        LDA #<portal_v_red_r_x0
        STA sprite_ptr
        LDA #>portal_v_red_r_x0
        STA sprite_ptr+1
        LDA #<portal_v_red_r_x0_mask
        STA mask_ptr
        LDA #>portal_v_red_r_x0_mask
        STA mask_ptr+1
       JMP spx_stamp
    .spx_red_leftwall
       ; left wall: use flipped sprite, unshifted = x3
        LDA #<portal_v_red_l_x3
        STA sprite_ptr
        LDA #>portal_v_red_l_x3
        STA sprite_ptr+1
        LDA #<portal_v_red_l_x3_mask
        STA mask_ptr
        LDA #>portal_v_red_l_x3_mask
        STA mask_ptr+1

      ; Offset into right half (columns 2+3) of each 16x32 stripe.
      LDA sprite_ptr
      CLC
      ADC #16
      STA sprite_ptr
      BCC spx_red_ptr_ok
      INC sprite_ptr+1
   .spx_red_ptr_ok
      LDA mask_ptr
      CLC
      ADC #16
      STA mask_ptr
      BCC spx_red_mask_ok
      INC mask_ptr+1
   .spx_red_mask_ok

  .spx_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #4
       LDX #16
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

  .spx_done
      ; Restore ROMSEL and re-enable IRQs.
      LDA saved_romsel
      STA ROMSEL
      CLI
      RTS



; Stamp portals that belong to current_room.
.stamp_portals_for_current_room
     ; Portal A
     LDA portal_a_enabled
     BEQ spcr_b
     LDA portal_a_room
     CMP current_room
     BNE spcr_b
      LDA portal_a_orient
      STA row_counter
      LDA #0
      PHA
      LDX portal_a_x
      LDY portal_a_y
      ; Adjust draw Y for floor/ceiling (stored y is collision rect).
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE spcr_a_not_floor
      INY
      JMP spcr_a_y_ok
  .spcr_a_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE spcr_a_y_ok
      DEY
  .spcr_a_y_ok
      PLA
      JSR stamp_portal_xy

  .spcr_b
     ; Portal B
     LDA portal_b_enabled
     BEQ spcr_done
     LDA portal_b_room
     CMP current_room
     BNE spcr_done
      LDA portal_b_orient
      STA row_counter
      LDA #1
      PHA
      LDX portal_b_x
      LDY portal_b_y
      ; Adjust draw Y for floor/ceiling (stored y is collision rect).
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE spcr_b_not_floor
      INY
      JMP spcr_b_y_ok
  .spcr_b_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE spcr_b_y_ok
      DEY
  .spcr_b_y_ok
      PLA
      JSR stamp_portal_xy

  .spcr_done
      RTS
