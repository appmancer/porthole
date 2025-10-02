; BBC Micro OS API Entry Points
OSWRCH  = &FFEE    ; Output a character
OSNEWL  = &FFE7    ; New line
OSBYTE  = &FFF4    ; Read or set system byte
OSWORD  = &FFF1    ; General-purpose system call
OSCLI   = &FFF7    ; Command line interpreter

; File handling routines
OSFILE  = &FFDD    ; File operations (load, save, delete, etc.)
OSFIND  = &FFCE    ; Open a file channel
OSBGET  = &FFCF    ; Get a byte from a file
OSBPUT  = &FFD0    ; Put a byte into a file
OSGBPB  = &FFD1    ; General block transfer

; Memory and string routines
OSARGS  = &FFDA    ; Get/set file parameters
OSRDCH  = &FFE0    ; Read a character from the input
OSASCI  = &FFE3    ; ASCII character to output
