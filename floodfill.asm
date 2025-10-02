.start
        LDX #0           ; 

        LDA #<(&5800)    ; Load low byte of screen address
        STA &70
        LDA #>(&5800)    ; Load high byte of screen address
        STA &71

.loop
        LDY #0
        LDA checker      
        STA (&70), Y     
        LDA checker+1
        LDY #1
        STA (&70), Y     

        ; add 2 to the screen address
        CLC
        LDA &70
        ADC #2
        STA &70
        BCC nextrow
        INC &71
.nextrow
        LDA &71
        CMP #&80
        BNE loop

.exit
        RTS

.checker
        EQUB &A5          ; Alternating pixels (10100101)
        EQUB &5A          ; Opposite pattern (01011010)

.end