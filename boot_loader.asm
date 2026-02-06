; Boot loader (PROGRAM)
;
; Responsibilities:
; - Switch to MODE 2 and display the loading screen (LOADSCR).
; - Stream OBJDAT and CHDATA into sideways RAM banks.
; - Load and run the main game binary (PORTHLE).
;
; This runs before the game starts, so it may use main RAM freely.
; It is assembled to &0E00 so it can load the game to &1900 without self-overwrite.

; Uses ROMSEL symbol from main.asm.

; Loader-private ZP scratch (safe while running under BASIC).
; Keep below &70 so we don't disturb the game's fixed pointer block.
LOADER_ZP_SRC      = &50
LOADER_ZP_DST      = &52
LOADER_ZP_TEMP     = &54

LOADER_BUF_256     = &0900

; Progress markers in main RAM (peekable in B2):
; stage: 1=screen loaded, 2=objdat loaded, 3=chdata loaded, 4=game loaded, 5=jumping
; substage: per-loader internal checkpoints (primarily SWRAM load)
; err: nonzero error code if we hang
; page: current page countdown (64..0)
; bank: active ROMSEL value used for SWRAM
; fh: file handle from OSFIND
LOADER_STAGE_ADDR     = &0400
LOADER_SUBSTAGE_ADDR  = &0401
LOADER_ERR_ADDR       = &0402
LOADER_PAGE_ADDR      = &0403
LOADER_BANK_ADDR      = &0404
LOADER_FH_ADDR        = &0405

ORG &0E00

.loader_start
    LDA #0
    STA LOADER_STAGE_ADDR
    STA LOADER_SUBSTAGE_ADDR
    STA LOADER_ERR_ADDR
    STA LOADER_PAGE_ADDR
    STA LOADER_BANK_ADDR
    STA LOADER_FH_ADDR
    ; MODE 2
    LDA #22
    JSR OSWRCH
    LDA #2
    JSR OSWRCH

    ; Disable cursor so it can't scribble into screen RAM.
    LDX #0
.cur_loop
    LDA loader_cursor_vdu, X
    JSR OSWRCH
    INX
    CPX #10
    BNE cur_loop

    ; Load the MODE 2 screen file to &3000.
    JSR loader_osfile_loadscr
    LDA #1
    STA LOADER_STAGE_ADDR

    ; Load sprite banks while the loading screen stays visible.
    JSR loader_load_objdat_bank
    LDA #2
    STA LOADER_STAGE_ADDR
    JSR loader_load_chdata_bank
    LDA #3
    STA LOADER_STAGE_ADDR
    JSR loader_load_tildat_bank
    LDA #6
    STA LOADER_STAGE_ADDR

    ; Hide screen corruption during final game load.
    ; MODE 7 uses minimal screen RAM.
    LDA #22
    JSR OSWRCH
    LDA #7
    JSR OSWRCH

    ; Load and run the game.
    JSR loader_osfile_load_game
    LDA #4
    STA LOADER_STAGE_ADDR

    ; OS file calls may clobber ZP, so restore the SWRAM ROMSEL values that the
    ; game will use for sprite reads.
    LDA loader_obj_bank_sel
    STA obj_bank
    LDA loader_chell_bank_sel
    STA chell_bank
    LDA loader_tile_bank_sel
    STA tile_bank

    LDA #5
    STA LOADER_STAGE_ADDR
    JMP (loader_game_exec_ptr)


; --- OSFILE helpers ---

; OSFILE &FF loads. Control block:
;   +0  filename ptr
;   +2  load addr (4)
;   +6  exec addr (4)
;   +10 start/length (4)
;   +14 end/attrs (4)

.loader_osfile_loadscr
    ; exec low byte = 0 => use supplied load address (&3000)
    LDA #&FF
    LDX #<loader_osfile_blk_loadscr
    LDY #>loader_osfile_blk_loadscr
    JSR OSFILE
    RTS

.loader_osfile_load_game
    ; exec low byte != 0 => load to file's own load address.
    LDA #&FF
    LDX #<loader_osfile_blk_game
    LDY #>loader_osfile_blk_game
    JSR OSFILE

    ; Copy 16-bit exec address for JMP (abs).
    LDA loader_osfile_blk_game+6
    STA loader_game_exec_ptr
    LDA loader_osfile_blk_game+7
    STA loader_game_exec_ptr+1
    RTS


; --- Sideways RAM streaming loader (OSFIND/OSGBPB) ---

; Common: stream a 16KB file into SWRAM &8000..&BFFF.
; Input:
; - A = default bank number (0..15)
; - X/Y = filename (CR-terminated)
; - file handle stored in file_fh
;
; Uses BUF_256 for staging.

.loader_load_file_to_swr
    ; Preserve requested bank (A) across ROMSEL reads.
    PHA

    ; Save current ROMSEL for filing-system calls.
    LDA ROMSEL
    STA loader_saved_romsel

    PLA

    ; Select a writable SWRAM mapping for the target bank.
    ; Preserve requested bank in A across debug writes.
    PHA
    LDA #10
    STA LOADER_SUBSTAGE_ADDR
    PLA
    JSR loader_select_bank_romsel
    BCC loader_bank_ok
    LDA #1
    STA LOADER_ERR_ADDR
    JMP loader_swr_fail
.loader_bank_ok
    STA loader_active_bank
    STA LOADER_BANK_ADDR

    ; Ensure filing-system ROM is visible.
    JSR loader_fs_romsel

    ; Open file for input.
    LDA #11
    STA LOADER_SUBSTAGE_ADDR
    STX loader_fname_ptr
    STY loader_fname_ptr+1
    LDA #&40
    LDX loader_fname_ptr
    LDY loader_fname_ptr+1
    JSR OSFIND
    BEQ loader_open_fail
    STA loader_file_fh
    STA LOADER_FH_ADDR
    JMP loader_open_ok
.loader_open_fail
    LDA #2
    STA LOADER_ERR_ADDR
    JMP loader_swr_fail
.loader_open_ok

    ; Reset checksum for this file.
    LDA #0
    STA loader_cksum_file

    ; dst := &8000
    LDA #&00
    STA LOADER_ZP_DST
    LDA #&80
    STA LOADER_ZP_DST+1

    LDA #&40      ; 64 pages
    STA loader_pages_left
.loader_page_loop
    LDA loader_pages_left
    STA LOADER_PAGE_ADDR
    ; Read 256 bytes into BUF_256.
    JSR loader_fs_romsel
    LDA loader_file_fh
    STA loader_gpb_block+0

    LDA #<LOADER_BUF_256
    STA loader_gpb_block+1
    LDA #>LOADER_BUF_256
    STA loader_gpb_block+2
    LDA #0
    STA loader_gpb_block+3
    STA loader_gpb_block+4

    ; 256 bytes
    LDA #0
    STA loader_gpb_block+5
    LDA #1
    STA loader_gpb_block+6
    LDA #0
    STA loader_gpb_block+7
    STA loader_gpb_block+8

    ; sequential pointer (ignored for A=4)
    LDA #0
    STA loader_gpb_block+9
    STA loader_gpb_block+10
    STA loader_gpb_block+11
    STA loader_gpb_block+12

    LDA #4
    LDX #<loader_gpb_block
    LDY #>loader_gpb_block
    JSR OSGBPB
    BCS loader_swr_fail

    LDA #12
    STA LOADER_SUBSTAGE_ADDR

    ; Accumulate XOR checksum over the 256-byte page.
    LDY #0
.ck_loop
    LDA loader_cksum_file
    EOR LOADER_BUF_256,Y
    STA loader_cksum_file
    INY
    BNE ck_loop

    ; Copy BUF_256 to SWRAM page.
    PHP
    SEI

    LDA loader_active_bank
    STA ROMSEL

    LDA #<LOADER_BUF_256
    STA LOADER_ZP_SRC
    LDA #>LOADER_BUF_256
    STA LOADER_ZP_SRC+1

    LDY #0
.copy_loop
    LDA (LOADER_ZP_SRC), Y
    STA (LOADER_ZP_DST), Y
    INY
    BNE copy_loop

    ; Restore filing-system ROMSEL.
    JSR loader_fs_romsel
    PLP

    LDA #13
    STA LOADER_SUBSTAGE_ADDR

    INC LOADER_ZP_DST+1
    DEC loader_pages_left
    BEQ loader_pages_done
    JMP loader_page_loop
.loader_pages_done

    ; Verify full 16KB landed correctly.
    LDA #14
    STA LOADER_SUBSTAGE_ADDR
    JSR loader_verify_swr

    ; Verify returned.
    LDA #15
    STA LOADER_SUBSTAGE_ADDR

    ; Close file.
    JSR loader_fs_romsel
    LDA #16
    STA LOADER_SUBSTAGE_ADDR
    LDA #0
    LDX #0
    LDY loader_file_fh
    JSR OSFIND

    LDA #17
    STA LOADER_SUBSTAGE_ADDR

    ; Restore ROMSEL.
    JSR loader_fs_romsel
    RTS

.loader_swr_fail
.loader_swr_hang
    ; Stash current ROMSEL for debugging.
    LDA ROMSEL
    STA LOADER_BANK_ADDR
    JMP loader_swr_hang


; Full-bank checksum verification is currently disabled.
; (B2 ROMSEL quirks make this fragile; we rely on correctness of OSGBPB+copy.)
.loader_verify_swr
    RTS


; Select ROMSEL value that maps writable SWRAM for A=bank.
; Tries A and A|&80.
; Returns: C=0 and A=romsel value if ok, C=1 if none.
.loader_select_bank_romsel
    PHA
    JSR loader_romsel_writable
    BCC sb_ok

    PLA
    ORA #&80
    PHA
    JSR loader_romsel_writable
    BCC sb_ok

    PLA
    SEC
    RTS

.sb_ok
    PLA
    CLC
    RTS


; Test whether A (ROMSEL value) is writable at &8000.
; Returns C=0 writable, C=1 not writable. Preserves A.
.loader_romsel_writable
    PHA
    STA ROMSEL

    LDA &8000
    STA LOADER_ZP_TEMP

    LDA #&A5
    STA &8000
    CMP &8000
    BNE rw_no

    LDA #&5A
    STA &8000
    CMP &8000
    BNE rw_no

    ; Restore original byte.
    LDA LOADER_ZP_TEMP
    STA &8000

    PLA
    CLC
    RTS

.rw_no
    LDA LOADER_ZP_TEMP
    STA &8000
    PLA
    SEC
    RTS


; Restore filing-system-visible ROMSEL.
.loader_fs_romsel
    LDA loader_saved_romsel
    STA ROMSEL
    RTS


; --- Specific file loaders ---

.loader_load_objdat_bank
    LDA #OBJ_SWRAM_BANK_DEFAULT
    LDX #<loader_fname_objdat
    LDY #>loader_fname_objdat
    JSR loader_load_file_to_swr
    LDA loader_active_bank
    STA loader_obj_bank_sel
    RTS

.loader_load_chdata_bank
    LDA #CHELL_SWRAM_BANK_DEFAULT
    LDX #<loader_fname_chdata
    LDY #>loader_fname_chdata
    JSR loader_load_file_to_swr
    LDA loader_active_bank
    STA loader_chell_bank_sel
    RTS

.loader_load_tildat_bank
    LDA #TILE_SWRAM_BANK_DEFAULT
    LDX #<loader_fname_tildat
    LDY #>loader_fname_tildat
    JSR loader_load_file_to_swr
    LDA loader_active_bank
    STA loader_tile_bank_sel
    RTS


; --- Data ---

.loader_cursor_vdu
    EQUB 23,1,0,0,0,0,0,0,0,0

.loader_fname_loadscr
    EQUS "LOADSCR",13
.loader_fname_objdat
    EQUS "OBJDAT",13
.loader_fname_chdata
    EQUS "CHDATA",13
.loader_fname_tildat
    EQUS "TILDAT",13
.loader_fname_game
    EQUS "PORTHLE",13

.loader_osfile_blk_loadscr
    EQUW loader_fname_loadscr
    EQUB &00,&30,0,0        ; load &3000
    EQUB 0,0,0,0            ; exec low=0 => use supplied load
    EQUB 0,0,0,0            ; start/len (ignored)
    EQUB 0,0,0,0            ; end/attrs (ignored)

.loader_osfile_blk_game
    EQUW loader_fname_game
    EQUB 0,0,0,0            ; load (ignored)
    EQUB 1,0,0,0            ; exec low!=0 => use file's own load address
    EQUB 0,0,0,0
    EQUB 0,0,0,0

.loader_gpb_block
    SKIP 13

.loader_saved_romsel
    EQUB 0
.loader_active_bank
    EQUB 0
.loader_file_fh
    EQUB 0

.loader_pages_left
    EQUB 0

.loader_obj_bank_sel
    EQUB 0

.loader_chell_bank_sel
    EQUB 0

.loader_tile_bank_sel
    EQUB 0

.loader_cksum_file
    EQUB 0

.loader_cksum_swr
    EQUB 0

.loader_fname_ptr
    EQUB 0,0

.loader_game_exec_ptr
    EQUW &1900

.loader_end
