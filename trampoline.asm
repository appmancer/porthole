; trampoline.asm
;
; Below-&3000 trampolines for ACCCON X-bit operations.
;
; The BBC Master's ACCCON X bit (bit 2 of &FE34) remaps CPU access at
; &3000-&7FFF to shadow RAM (LYNNE).  This affects BOTH data AND
; instruction fetches, so any code that sets X=1 must itself reside
; below &3000.
;
; These routines are assembled at &0900 and saved as a separate DFS
; file ("TRAMPLN"), loaded by the boot loader before the game starts.
;
; Uses ZP pointers defined in main.asm:
;   temp            = &70
;   temp_sprite_ptr = &7D (source)
;   temp_mask_ptr   = &7F (destination)
;
; Memory layout at &0900:
;   &0900-&09BF  Trampoline code (192B max)
;   &09C0-&09D1  OSFILE control block (18B)
;   &09D2-&09DA  Pack filename (9B)
;   &0E00-&18FF  Staging buffer (2816B, in boot loader area)


; lynne_osfile: load a file to LYNNE via OSFILE with ACCCON X=1.
;
; The caller must populate the OSFILE control block at PACK_OSFILE_BLK
; and the filename at PACK_FNAME before calling.
;
; Clobbers: A,X,Y
.lynne_osfile
    ; Set ACCCON X=1 (CPU writes to &3000-&7FFF go to LYNNE).
    LDA ACCCON
    ORA #&04
    STA ACCCON

    ; OSFILE &FF = load file.
    LDA #&FF
    LDX #<PACK_OSFILE_BLK
    LDY #>PACK_OSFILE_BLK
    JSR OSFILE

    ; Restore ACCCON X=0.
    LDA ACCCON
    AND #&FB
    STA ACCCON
    RTS


; lynne_stage_level: copy one level's data from LYNNE to STAGING_BUF.
;
; Input: X = level_in_pack * 2 (byte offset into offset table)
;
; Reads the pack's offset table from LYNNE, computes source address and
; length, copies the level data from LYNNE (&3000+) to STAGING_BUF
; (main RAM below &3000), then restores ACCCON X=0.
;
; Output: temp_sprite_ptr = STAGING_BUF (ready for parser)
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.lynne_stage_level
    ; Set ACCCON X=1 (CPU reads &3000-&7FFF from LYNNE).
    LDA ACCCON
    ORA #&04
    STA ACCCON

    ; Read offset[level_in_pack] from LYNNE.
    ; Pack header at PACK_LOAD_ADDR: [count(1B)] [offsets(N+1)*2B]
    ; offset entry i is at PACK_LOAD_ADDR + 1 + i*2.
    ; X = level_in_pack*2, so address = &3001 + X.
    LDA PACK_LOAD_ADDR+1,X     ; offset[i] lo
    STA temp_sprite_ptr
    LDA PACK_LOAD_ADDR+2,X     ; offset[i] hi
    STA temp_sprite_ptr+1

    ; Read offset[i+1] (sentinel-safe).
    LDA PACK_LOAD_ADDR+3,X     ; offset[i+1] lo
    STA temp_mask_ptr
    LDA PACK_LOAD_ADDR+4,X     ; offset[i+1] hi
    STA temp_mask_ptr+1

    ; Compute length = offset[i+1] - offset[i].
    LDA temp_mask_ptr
    SEC
    SBC temp_sprite_ptr
    STA temp                    ; length lo
    LDA temp_mask_ptr+1
    SBC temp_sprite_ptr+1       ; length hi (0 or 1 — max ~512)
    PHA                         ; save length hi on stack

    ; Compute source = PACK_LOAD_ADDR + offset[i].
    LDA temp_sprite_ptr
    CLC
    ADC #<PACK_LOAD_ADDR
    STA temp_sprite_ptr
    LDA temp_sprite_ptr+1
    ADC #>PACK_LOAD_ADDR
    STA temp_sprite_ptr+1

    ; Set destination = STAGING_BUF.
    LDA #<STAGING_BUF
    STA temp_mask_ptr
    LDA #>STAGING_BUF
    STA temp_mask_ptr+1

    ; Copy `length` bytes from temp_sprite_ptr (LYNNE) to temp_mask_ptr (main RAM).
    ; With ACCCON X=1: reads at &3000+ come from LYNNE, writes below &3000
    ; go to main RAM.  length hi is on stack, length lo in temp.
    PLA                         ; length hi
    TAX                         ; X = full pages to copy

    ; Copy partial page (temp bytes).
    LDY #0
    LDA temp
    BEQ lsl_full_pages          ; skip if no partial bytes
.lsl_partial
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    CPY temp
    BNE lsl_partial

    ; If no full pages remain, we're done.
    CPX #0
    BEQ lsl_copy_done

    ; Advance pointers past the partial page.
    LDA temp_sprite_ptr
    CLC
    ADC temp
    STA temp_sprite_ptr
    BCC lsl_no_c1
    INC temp_sprite_ptr+1
.lsl_no_c1
    LDA temp_mask_ptr
    CLC
    ADC temp
    STA temp_mask_ptr
    BCC lsl_no_c2
    INC temp_mask_ptr+1
.lsl_no_c2

.lsl_full_pages
    ; Copy X full 256-byte pages.
    CPX #0
    BEQ lsl_copy_done
    LDY #0
.lsl_page
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE lsl_page
    INC temp_sprite_ptr+1
    INC temp_mask_ptr+1
    DEX
    BNE lsl_page

.lsl_copy_done
    ; Restore ACCCON X=0.
    LDA ACCCON
    AND #&FB
    STA ACCCON

    ; Set temp_sprite_ptr = STAGING_BUF for the parser.
    LDA #<STAGING_BUF
    STA temp_sprite_ptr
    LDA #>STAGING_BUF
    STA temp_sprite_ptr+1
    RTS

.trampoline_code_end
