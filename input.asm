.input_start
; input.asm
; Keyboard sampling and small helpers.

; --- Input sampling ---
;
; keys_held bits (this repo conventions):
;   bit0: left        (Z or cursor left)
;   bit1: right       (X or cursor right)
;   bit2: jump        (RETURN)
;   bit3: reticle     (SHIFT held)
;   bit4: reticle up  (':' / cursor up)
;   bit5: reticle down('/' / cursor down)
;   bit6: portal A    ('A')
;   bit7: portal B    ('S')
;
; Sample keyboard once this frame and build:
;   keys_held    = held bits
;   keys_pressed = newly pressed this frame (edge)
;   keys_prev    = last frame's keys_held
.sample_keys
     ; Safety: OSBYTE input polling expects IRQs enabled.
     CLI

     ; Start with no bits set.
     LDA #0
     STA keys_held

     ; Jump (RETURN)
     LDX #&B6            ; INKEY(-74) = RETURN
     JSR is_key_pressed
     BCC sample_no_jump
     LDA keys_held
     ORA #4
     STA keys_held
 .sample_no_jump

    ; Left (cursor left or Z)
    LDX #&E6            ; INKEY(-26) = Left
    JSR is_key_pressed
    BCS sample_set_left
    LDX #&9E            ; INKEY(-98) = 'Z'
    JSR is_key_pressed
    BCC sample_no_left
.sample_set_left
    LDA keys_held
    ORA #1
    STA keys_held
.sample_no_left

     ; Right (cursor right or X)
     LDX #&86            ; INKEY(-122) = Right
     JSR is_key_pressed
     BCS sample_set_right
     LDX #&BD            ; INKEY(-67) = 'X'
     JSR is_key_pressed
     BCC sample_no_right
 .sample_set_right
     LDA keys_held
     ORA #2
     STA keys_held
 .sample_no_right

     ; SHIFT (reticle mode)
     JSR is_shift_pressed
     BCC sample_no_shift
     LDA keys_held
     ORA #8
     STA keys_held
 .sample_no_shift

     ; Reticle up (':' or cursor up)
     ; ':' = INKEY(-73)
     LDX #&B7
     JSR is_key_pressed
     BCS sample_set_reticle_up

     ; cursor up = 138 => INKEY(-118)
     LDX #&8A
     JSR is_key_pressed
     BCC sample_no_reticle_up
 .sample_set_reticle_up
     LDA keys_held
     ORA #16
     STA keys_held
 .sample_no_reticle_up

      ; Reticle down ('/' or cursor down)
      ; '/' = INKEY(-105)
      LDX #&97
      JSR is_key_pressed
      BCS sample_set_reticle_down

     ; cursor down = 139 => INKEY(-117)
     LDX #&8B
     JSR is_key_pressed
     BCC sample_no_reticle_down
 .sample_set_reticle_down
     LDA keys_held
      ORA #32
      STA keys_held
  .sample_no_reticle_down

      ; Portal A ('A')
      LDX #&BE            ; INKEY(-66) = 'A'
      JSR is_key_pressed
      BCC sample_no_portal_a
      LDA keys_held
      ORA #64
      STA keys_held
  .sample_no_portal_a

      ; Portal B ('S')
      LDX #&AE            ; INKEY(-82) = 'S'
      JSR is_key_pressed
      BCC sample_no_portal_b
      LDA keys_held
      ORA #&80
      STA keys_held
  .sample_no_portal_b
  

      ; Edge-triggered keys (accumulate until update consumes).
      LDA keys_held
      STA temp
      LDA keys_prev
      EOR #&FF
      AND temp
      ORA keys_pressed
      STA keys_pressed
      LDA temp
      STA keys_prev

       ; --- Action button (SPACE) ---
      ; Keep separate from keys_held (we've run out of bits).
      LDA #0
      STA action_held

      ; SPACE = INKEY(-99)
      LDX #&9D
      JSR is_key_pressed
      BCC sample_no_action
      LDA #1
      STA action_held
 .sample_no_action

      ; Edge-triggered action (accumulate until update consumes).
      LDA action_prev
      EOR #&FF
      AND action_held
      ORA action_pressed
      STA action_pressed
      LDA action_held
      STA action_prev

       ; --- Aim sampling ---
     ; aim_held: 0=none, 1=up, 2=down
     ; While SHIFT is held (reticle mode), aim keys are repurposed.
     LDA #0
     STA aim_held

     LDA keys_held
     AND #8
     BNE sample_aim_done

     ; Prefer up if both held.
     ; ':' = INKEY(-73)
     LDX #&B7
     JSR is_key_pressed
     BCS sample_set_aim_up

     ; cursor up = 138 (see BBC User Guide sample)
     ; => INKEY(-118)
     LDX #&8A
     JSR is_key_pressed
     BCC sample_check_aim_down

 .sample_set_aim_up
     LDA #1
     STA aim_held
     JMP sample_aim_done

 .sample_check_aim_down
     ; '/' = INKEY(-105)
     LDX #&97
     JSR is_key_pressed
     BCS sample_set_aim_down

     ; cursor down = 139 (see BBC User Guide sample)
     ; => INKEY(-117)
     LDX #&8B
     JSR is_key_pressed
     BCC sample_aim_done

 .sample_set_aim_down
     LDA #2
     STA aim_held

 .sample_aim_done
     RTS


; Input: X = negative INKEY number (as 8-bit value)
; Output: C=1 if pressed
.is_key_pressed
     LDY #&FF
     LDA #129
     JSR OSBYTE
     CPX #&FF
     BNE key_not_pressed
     SEC
     RTS
.key_not_pressed
     CLC
     RTS


; Return C=1 if SHIFT key is held.
; Uses OSBYTE &CA (202) "keyboard status byte".
; Returned status (old value) is in X:
; - bit 3 set if SHIFT is pressed.
.is_shift_pressed
    LDA #&CA
    LDX #0
    LDY #&FF
    JSR OSBYTE

    TXA
    AND #8
    BEQ shift_not_pressed
    SEC
    RTS
.shift_not_pressed
    CLC
    RTS
