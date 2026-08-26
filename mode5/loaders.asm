.loaders_start
; loaders.asm
; Shadow-screen, sideways-RAM, and level-pack loader utilities.
; (VSync/delay helpers live in timing.asm.)

; File handles must not live in MOS-clobbered ZP (e.g. &A0..).
; Keep them in main RAM.
.chelldata_fh     SKIP 1
.objdata_fh       SKIP 1
;
; Kept in its own file so `main.asm` stays navigable.

; --- Level pack constants ---
;
; Level pack data is pre-loaded into SWRAM bank 7 at boot time.
; No runtime disc I/O needed for level transitions.

PACK_OSFILE_BLK  = &09C0       ; 18-byte OSFILE control block (below &3000)
PACK_FNAME       = &09D2       ; filename string (below &3000), max 8 chars + CR
PACK_LOAD_ADDR   = &8000       ; Level data in SWRAM bank

; Enable Master shadow screen via direct ACCCON register writes.
;
; OSBYTE 114 does not set the ACCCON D+X bits in B2, so we write
; ACCCON (&FE34) directly:
;   D (bit 0) = 1: CRTC displays from LYNNE (shadow &3000-&7FFF)
;   X (bit 2) = 1: CPU reads/writes LYNNE at &3000-&7FFF
;
; We clear LYNNE to black before setting D=1 so there is no garbage flash.
; After init, X is cleared back to 0 (CPU sees main RAM).
.enable_shadow_acccon
    ; Clear LYNNE screen to black before switching display.
    ; clear_lynne_screen lives in the render-safe zone (below &3000)
    ; because it sets ACCCON X=1 — code above &3000 cannot do that safely.
    JSR clear_lynne_screen

    ; Set D=1 — CRTC now displays LYNNE.
    LDA ACCCON : ORA #&01 : STA ACCCON
    RTS


; Load portal stamp sprites+masks into sideways RAM.
;
; We cannot safely `*LOAD` straight into `&8000` because filing system ROM code
; also lives in the `&8000..&BFFF` paged ROM window.
;
; Instead we stream OBJDAT in 256-byte chunks into `CHELLDATA_BUF` and copy each
; chunk into the target SWRAM bank.
.load_obj_sprites
    ; Keep the OS/language ROM visible across filing-system calls.
    LDA ROMSEL
    STA saved_romsel

    ; Choose which ROMSEL value actually maps writable SWRAM in this environment.
    ; (Real Master: bank number alone; B2 may require bit 7.)
    JSR select_obj_romsel
    BCC obj_bank_ok

    LDX #<msg_no_swr
    LDY #>msg_no_swr
    JSR print_string_xy
 .objdat_hang
    JMP objdat_hang

 .obj_bank_ok
    ; Keep filing system ROM visible for OSFIND/OSGBPB.
    LDA saved_romsel
    STA ROMSEL

    ; Open OBJDAT for input.
    LDA #&40
    LDX #<fname_objdat
    LDY #>fname_objdat
    JSR OSFIND
    BNE objdat_open_ok
    JMP objdat_open_fail
 .objdat_open_ok
    STA objdata_fh

    ; dst := &8000 (in SWRAM bank)
    LDA #&00
    STA temp_mask_ptr
    LDA #&80
    STA temp_mask_ptr+1

    ; Use OSGBPB to read 256 bytes per page.
    LDA #&40
    STA row_counter
 .objdat_page_loop
    ; Build OSGBPB control block.
    LDA objdata_fh
    STA gpb_block+0

    LDA #<CHELLDATA_BUF
    STA gpb_block+1
    LDA #>CHELLDATA_BUF
    STA gpb_block+2
    LDA #0
    STA gpb_block+3
    STA gpb_block+4

    ; 256 bytes
    LDA #0
    STA gpb_block+5
    LDA #1
    STA gpb_block+6
    LDA #0
    STA gpb_block+7
    STA gpb_block+8

    ; seq pointer (ignored for A=4, but keep it 0)
    LDA #0
    STA gpb_block+9
    STA gpb_block+10
    STA gpb_block+11
    STA gpb_block+12

    ; Read bytes from media, ignoring new sequential pointer.
    LDA #4
    LDX #<gpb_block
    LDY #>gpb_block
    JSR OSGBPB
    BCS objdat_read_fail

    ; Copy into SWRAM page with ROMSEL held stable.
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA obj_bank
    STA ROMSEL

    LDA #<CHELLDATA_BUF
    STA temp_sprite_ptr
    LDA #>CHELLDATA_BUF
    STA temp_sprite_ptr+1

    LDY #0
 .objdat_copy_loop
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE objdat_copy_loop

    ; Sanity check against the page we just copied (checks &8000 writeability too).
    JSR sanity_check_chell_swrambank
    BCS objdat_copy_fail

    ; Restore ROMSEL for filing system.
    LDA saved_romsel
    STA ROMSEL
    PLP

    INC temp_mask_ptr+1
    DEC row_counter
    BNE objdat_page_loop

    ; Close file.
    LDA #0
    LDY objdata_fh
    JSR OSFIND

    ; Leave normal ROM selected.
    LDA saved_romsel
    STA ROMSEL
    RTS

 .objdat_open_fail
    LDX #<msg_objdat_open_fail
    LDY #>msg_objdat_open_fail
    JSR print_string_xy
    JMP objdat_hang

 .objdat_read_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    LDX #<msg_objdat_read_fail
    LDY #>msg_objdat_read_fail
    JSR print_string_xy
    JMP objdat_hang

 .objdat_copy_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    PLP
    LDX #<msg_swr_copy_fail
    LDY #>msg_swr_copy_fail
    JSR print_string_xy
    JMP objdat_hang


; Select a ROMSEL value for object SWRAM writes.
; Tries bank 5, then bank 5|&80 (B2 quirk).
;
; Output:
; - `obj_bank` set
; - ROMSEL set to `obj_bank`
; Returns: C=0 if ok, C=1 if no mapping worked.
.select_obj_romsel
    LDA #OBJ_SWRAM_BANK_DEFAULT
    JSR romsel_writable
    BCC obj_romsel_ok

    LDA #OBJ_SWRAM_BANK_DEFAULT
    ORA #&80
    JSR romsel_writable
    BCS obj_romsel_fail

  .obj_romsel_ok
    STA obj_bank
    STA ROMSEL
    CLC
    RTS

  .obj_romsel_fail
    SEC
    RTS


; Load Chell sprite+mask data into sideways RAM.
;
; We cannot safely `*LOAD` straight into `&8000` because filing system ROM code
; also lives in the `&8000..&BFFF` paged ROM window.
;
; Also, we cannot `*LOAD` into `&3000` anymore because the main program has grown
; past that address.
;
; Instead we stream CHDATA in 256-byte chunks into `CHELLDATA_BUF` and copy each
; chunk into the target SWRAM bank.
.load_chell_sprites
    ; Keep the OS/language ROM visible across filing-system calls.
    LDA ROMSEL
    STA saved_romsel

    ; Choose which ROMSEL value actually maps writable SWRAM in this environment.
    ; (Real Master: bank number alone; B2 may require bit 7.)
    JSR select_chell_romsel
    BCC chell_bank_ok

    LDX #<msg_no_swr
    LDY #>msg_no_swr
    JSR print_string_xy
.no_swr_hang
    JMP no_swr_hang

.chell_bank_ok
    ; Keep filing system ROM visible for OSFIND/OSGBPB.
    LDA saved_romsel
    STA ROMSEL

    ; Open CHDATA for input.
    LDA #&40
    LDX #<fname_chdata
    LDY #>fname_chdata
    JSR OSFIND
    BNE chdata_open_ok
    JMP chdata_open_fail
.chdata_open_ok
    STA chelldata_fh

    ; dst := &8000 (in SWRAM bank)
    LDA #&00
    STA temp_mask_ptr
    LDA #&80
    STA temp_mask_ptr+1

    ; Use OSGBPB to read 256 bytes per page.
    LDA #&40
    STA row_counter
.chdata_page_loop
    ; Build OSGBPB control block.
    LDA chelldata_fh
    STA gpb_block+0

    LDA #<CHELLDATA_BUF
    STA gpb_block+1
    LDA #>CHELLDATA_BUF
    STA gpb_block+2
    LDA #0
    STA gpb_block+3
    STA gpb_block+4

    ; 256 bytes
    LDA #0
    STA gpb_block+5
    LDA #1
    STA gpb_block+6
    LDA #0
    STA gpb_block+7
    STA gpb_block+8

    ; seq pointer (ignored for A=4, but keep it 0)
    LDA #0
    STA gpb_block+9
    STA gpb_block+10
    STA gpb_block+11
    STA gpb_block+12

    ; Read bytes from media, ignoring new sequential pointer.
    LDA #4
    LDX #<gpb_block
    LDY #>gpb_block
    JSR OSGBPB
    BCS chdata_read_fail

    ; Copy into SWRAM page with ROMSEL held stable.
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA chell_bank
    STA ROMSEL

    LDA #<CHELLDATA_BUF
    STA temp_sprite_ptr
    LDA #>CHELLDATA_BUF
    STA temp_sprite_ptr+1

    LDY #0
.chdata_copy_loop
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE chdata_copy_loop

    ; Sanity check against the page we just copied (checks &8000 writeability too).
    JSR sanity_check_chell_swrambank
    BCS chdata_copy_fail

    ; Restore ROMSEL for filing system.
    LDA saved_romsel
    STA ROMSEL
    PLP

    INC temp_mask_ptr+1
    DEC row_counter
    BNE chdata_page_loop

    ; Close file.
    LDA #0
    LDY chelldata_fh
    JSR OSFIND

    ; Leave normal ROM selected.
    LDA saved_romsel
    STA ROMSEL
    RTS

.chdata_open_fail
    LDX #<msg_chdata_open_fail
    LDY #>msg_chdata_open_fail
    JSR print_string_xy
.chdata_hang
    JMP chdata_hang

.chdata_read_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    LDX #<msg_chdata_read_fail
    LDY #>msg_chdata_read_fail
    JSR print_string_xy
    JMP chdata_hang

.chdata_copy_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    PLP
    LDX #<msg_swr_copy_fail
    LDY #>msg_swr_copy_fail
    JSR print_string_xy
    JMP chdata_hang

.fname_chdata
    EQUS "CHDATA",13

.fname_objdat
    EQUS "OBJDAT",13

.gpb_block
    SKIP 13


; Initialize SWRAM bank selectors for reads.
;
; PROGRAM (boot loader) loads OBJDAT/CHDATA into the default banks. Here we
; just need to choose the ROMSEL values that map those banks in this environment
; (B2 may require bit 7).
;
; We reuse the existing bank-selection logic used for SWRAM writes.
;
; Output:
; - `obj_bank` and `chell_bank` set
; - ROMSEL restored to its entry value
; Returns: C=0 if ok, C=1 if either bank couldn't be selected
.init_swr_banks
    LDA ROMSEL
    STA saved_romsel

    JSR select_obj_romsel
    BCS isb_fail
    JSR select_chell_romsel
    BCS isb_fail

    LDA saved_romsel
    STA ROMSEL
    CLC
    RTS

.isb_fail
    LDA saved_romsel
    STA ROMSEL
    SEC
    RTS


; Select a ROMSEL value for Chell SWRAM writes.
; Tries bank 4, then bank 4|&80 (B2 quirk).
;
; Output:
; - `chell_bank` set
; - ROMSEL set to `chell_bank`
; Returns: C=0 if ok, C=1 if no mapping worked.
.select_chell_romsel
    LDA #CHELL_SWRAM_BANK_DEFAULT
    JSR romsel_writable
    BCC romsel_ok

    LDA #CHELL_SWRAM_BANK_DEFAULT
    ORA #&80
    JSR romsel_writable
    BCS romsel_fail

.romsel_ok
    STA chell_bank
    STA ROMSEL
    CLC
    RTS

.romsel_fail
    SEC
    RTS


; Test whether current A (ROMSEL value) is writable at &8000.
; Returns: C=0 writable, C=1 not writable. Preserves A.
.romsel_writable
    PHA
    STA ROMSEL

    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    LDA #&5A
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    ; Restore original byte.
    LDA temp
    STA &8000

    PLA
    CLC
    RTS

.romsel_not_writable
    ; Best-effort restore.
    LDA temp
    STA &8000
    PLA
    SEC
    RTS


; Sanity check for the Chell SWRAM bank in B2.
; Preconditions:
; - `chell_bank` has been selected into ROMSEL.
; - `temp_sprite_ptr` points at the source page buffer.
; - `temp_mask_ptr` points at the destination page in SWRAM.
;
; Returns: C=0 if ok, C=1 if failed.
.sanity_check_chell_swrambank
    ; Confirm writes stick at &8000 (restore original byte afterwards).
    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE sanity_fail

    LDA #&5A
    STA &8000
    CMP &8000
    BNE sanity_fail

    ; Restore original byte.
    LDA temp
    STA &8000

    ; Confirm the first 16 bytes match what we just copied.
    LDY #0
.sanity_cmp_loop
    LDA (temp_sprite_ptr),Y
    CMP (temp_mask_ptr),Y
    BNE sanity_fail
    INY
    CPY #16
    BNE sanity_cmp_loop

    CLC
    RTS

.sanity_fail
    ; Best-effort restore of first byte.
    LDA temp
    STA &8000
    SEC
    RTS


; Print NUL-terminated string at XY using OSWRCH.
.print_string_xy
    STX temp_sprite_ptr
    STY temp_sprite_ptr+1

.print_loop
    LDY #0
    LDA (temp_sprite_ptr),Y
    BEQ print_done
    JSR OSWRCH

    INC temp_sprite_ptr
    BNE print_loop
    INC temp_sprite_ptr+1
    BNE print_loop

.print_done
    RTS

.msg_no_swr
    EQUS "NO SWRAM",13,0

.msg_chdata_open_fail
    EQUS "CHDATA OPEN FAIL",13,0

.msg_chdata_read_fail
    EQUS "CHDATA READ FAIL",13,0

.msg_objdat_open_fail
    EQUS "OBJDAT OPEN FAIL",13,0

.msg_objdat_read_fail
    EQUS "OBJDAT READ FAIL",13,0

.msg_swr_copy_fail
    EQUS "SWRAM COPY FAIL",13,0
