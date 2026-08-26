; trampoline.asm
;
; Below-&3000 trampoline for ACCCON X-bit operations.
;
; The BBC Master's ACCCON X bit (bit 2 of &FE34) remaps CPU access at
; &3000-&7FFF to shadow RAM (LYNNE).  This affects BOTH data AND
; instruction fetches, so any code that sets X=1 must itself reside
; below &3000.
;
; This used to be a separate TRAMPLN file loaded to &0900.  That was wrong:
; the OS stores ENVELOPE definitions at &08C0 upwards, 16 bytes each, so
; envelopes 5..16 land in &0900-&09BF.  Defining envelope 5 silently
; overwrote lynne_osfile, and the next level-card disc load jumped into
; envelope data.  It is now assembled inline in the main binary's
; below-&3000 zone (see mode5/render.asm), which has no such conflict.
;
; The OSFILE control block and filename stay in page 9 at &09C0/&09D2 --
; that is just past envelope 16 (&09B0-&09BF), so it is safe.


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

.trampoline_code_end
