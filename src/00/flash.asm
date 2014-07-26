; TODO: Add routines to erase certificate sectors (or add this to eraseFlashSector?)
    rst 0 ; Prevent runaway code from unlocking flash

;; unlockFlash [Flash]
;;  Unlocks Flash and unlocks protected ports.
;; Notes:
;;  **Do not use this unless you know what you're doing.**
;;  
;;  Please call [[lockFlash]] when you finish what you're doing and don't spend too
;;  much time with Flash unlocked. Disable interrupts while Flash is unlocked.
unlockFlash:
    push af
    push bc
        getBankA
        push af
            setBankA(privledgedPage)
            ld b, 0x01
            ld c, 0x14
            call 0x4001
        pop af
        setBankA
    pop bc
    pop af
    ret

;; lockFlash [Flash]
;;  Locks Flash and locks protected ports.
lockFlash:
    push af
    push bc
        getBankA
        push af
            setBankA(privledgedPage)
            ld b, 0x00
            ld c, 0x14
            call 0x4004
        pop af
        setBankA
    pop bc
    pop af
    ret

;; writeFlashByte [Flash]
;;  Writes a single byte to Flash.
;; Inputs:
;;  HL: Destination
;;  A: Value
;; Notes:
;;  Flash must be unlocked. This can only *reset* bits of Flash.
writeFlashByte:
; The procedure is thus:
;    0xAA -> (0xAAA)
;    0x55 -> (0x555)
;    0x0A -> (0xAAA)
;    DATA -> (PDEST)
;    Poll:
;       A <- (PDEST)
;       Bit 7 == data, then return
;       Bit 5 == 0, then poll
;       A <- (PDEST)
;       Bit 7 == data, then return
;       Fail
    push hl
    push bc
    push de
    push af
        ld b, a
        ld a, i
        push af
            di
            ld a, b
            push hl
                ld hl, .ram
                ld de, flashFunctions
                ld bc, .ram_end - .ram
                ldir
            pop hl
            ld b, a
            jp flashFunctions
.return:
        pop af
        jp po, _
        ei
_:  pop af
    pop de
    pop bc
    pop hl
    ret
.ram:
    ld a, 0xAA
    ld (0xAAA), a
    ld a, 0x55
    ld (0x555), a
    ld a, 0xA0
    ld (0xAAA), a
    ld (hl), b
.poll:
    ld c, (hl)
    ld a, c
    xor b
    jp p, .return ; Bit 7 of A is set?
    bit 5, c
    jr z, .poll
    ld a, (hl)
    xor b
    jp p, .return
    ; Operation failed, abort
    ld a, 0xF0
    ld (0), a
    jp .return
.ram_end:

;; writeFlashBuffer [Flash]
;;  Writes several bytes of memory to Flash
;; Inputs:
;;  DE: Address to write to
;;  HL: Address to read from (in RAM)
;;  BC: Length of data to write
;; Notes:
;;  Flash must be unlocked. Do not attempt to read your source data
;;  from Flash, you must load any data to be written into RAM. This
;;  will only *reset* bits of Flash.
writeFlashBuffer:
    push hl
    push bc
    push de
    push af
        ld a, i
        push af
            di
            push hl
            push de
            push bc
                ld hl, .ram
                ld de, flashFunctions
                ld bc, .ram_end - .ram
                ldir
            pop bc
            pop de
            pop hl
            jp flashFunctions
.return:
        pop af
        jp po, _
        ei
_:  pop af
    pop de
    pop bc
    pop hl
    ret
.ram:
.loop:
    ld a, 0xAA
    ld (0x0AAA), a    ; Unlock
    ld a, 0x55
    ld (0x0555), a    ; Unlock
    ld a, 0xA0
    ld (0x0AAA), a    ; Write command
    ld a, (hl)
    ld (de), a        ; Data
    
_:  xor (hl)
    bit 7, a
    jr z, _
    bit 5, a
    jr z, -_
    ; Error, abort
    ld a, 0xF0
    ld (0), a
    jp .return
_:  ld a, 0xF0
    ld (de), a

    inc de
    inc hl
    dec bc

    xor a
    cp c
    jr nz, .loop
    cp b
    jr nz, .loop
    jp .return
.ram_end:

;; eraseSwapSector [Flash]
;;  Erases the swap sector.
;; Notes:
;;  Flash must be unlocked.
eraseSwapSector:
    push af
        ld a, swapSector
        call eraseFlashSector
    pop af
    ret

;; eraseFlashSector [Flash]
;;  Erases one sector of Flash (generally 4 pages of Flash, or 64K)
;;  by setting each byte to 0xFF.
;; Inputs:
;;  A: Any page within the target sector
;; Notes:
;;  Flash must be unlocked.
eraseFlashSector:
    push bc
    ld b, a
    push af
    ld a, i
    push af
    di
    ld a, b
    and 0b11111100
    push hl
    push de
    push bc
        ld hl, .ram
        ld de, flashFunctions
        ld bc, .ram_end - .ram
        ldir
    pop bc
    pop de
    pop hl
    jp flashFunctions
.return:
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    ret
    
.ram:
    setBankA
    ld a, 0xAA
    ld (0x0AAA), a ; Unlock
    ld a, 0x55
    ld (0x0555), a ; Unlock
    ld a, 0x80
    ld (0x0AAA), a ; Write command
    ld a, 0xAA
    ld (0x0AAA), a ; Unlock
    ld a, 0x55
    ld (0x0555), a ; Unlock
    ld a, 0x30
    ld (0x4000), a ; Erase
    ; Wait for chip
_:  ld a, (0)
    bit 7, a
    jp nz, .return
    bit 5, a
    jr z, -_
    ; Error, abort
    ld a, 0xF0
    ld (0x4000), a
    jp .return
.ram_end:

;; eraseFlashPage [Flash]
;;  Erases a single page of Flash.
;; Inputs:
;;  A: Target page
;; Notes:
;;  Flash must be unlocked. This is a very costly operation, and you
;;  may want to consider handling this logic yourself if you have to
;;  erase more than one page in a single sector
eraseFlashPage:
    push af
    push bc
        push af
            call copySectorToSwap
        pop af
        push af
            call eraseFlashSector
        pop af
        
        ld c, a
        and 0b1111100
        ld b, swapSector
        ; b is page in swap sector, a is page in target sector, c is target page
_:
        cp c
        jr z, .skipPage
        call copyFlashPage
.skipPage:
        inc b
        inc a
        push af
        ld a, b
        and 0b0000011
        or a
        jr z, .return
        pop af
        jr -_
.return:
        pop af
    pop bc
    pop af
    ret

;; copySectorToSwap [Flash]
;;  Copies a single sector of Flash to the swap sector.
;; Inputs:
;;  A: Any page within the sector to be copied
;; Notes:
;;  Flash must be unlocked.
copySectorToSwap:
    call eraseSwapSector

    push bc
    ld b, a
    push af
    ld a, i
    push af
    push de
    push hl
        di
        and 0b11111100
        push hl
        push bc
        push de
            ld hl, .ram
            ld de, flashFunctions
            ld bc, .ram_end - .ram
            ldir
        pop de
        pop bc
        pop hl
#ifdef CPU15
        ; We'll move flashFunctions into bank 3 so that we can put both
        ; pages involved into bank 1 and 2 for a while
        push af
            ld a, 1
            out (0x05), a
        pop af
        jp flashFunctions + 0x4000
#else
        jp flashFunctions
#endif
.return:
#ifdef CPU15
    ; Switch us back to normal, with R:00 in bank 3 and R:01 in bank 2
    xor a
    out (0x05), a
    setBankB(0x81)
#endif
    pop hl
    pop de
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    ret
; On 15 MHz calcs, we can do this faster with clever mapping
; This is not possible on the TI-73 and TI-83+
#ifdef CPU15
.ram:
    setBankB
    setBankA(swapSector)

.page_loop:
    ld hl, 0x8000
    ld de, 0x4000
    ld bc, 0x4000
.inner_loop:
    ld a, (hl)
    ex af, af'
    ld a, 0xF0
    ld (0), a
    ld a, 0xAA
    ld (0x0AAA), a
    ld a, 0x55
    ld (0x0555), a
    ld a, 0xA0
    ld (0x0AAA), a
    ex af, af'
    ld (de), a
    ex de, hl
.poll:
    xor (hl)
    bit 7, a
    jr z, _
    bit 5, a
    jr z, .poll
    ; Error, abort
    ld a, 0xF0
    ld (0), a
    jp .return
_:  ld a, 0xF0
    ld (hl), a
    ex de, hl
    
    inc de
    inc hl
    dec bc

    xor a
    cp c
    jr nz, .inner_loop
    cp b
    jr nz, .inner_loop

    getBankA
    inc a
    cp swapSector + 4
    jp z, .return
    setBankA
    getBankB
    inc a
    setBankB
    jr .page_loop
.ram_end:
#else ; TI-73, TI-83+
.ram:
    jr $
    ld d, a
    setBankA
    ld e, swapSector

.page_loop:
    ld hl, 0x4000
    ld bc, 0x4000
.inner_loop:
    ld a, (hl) ; source sector
    ex af, af'
    ld a, e ; swap sector
    setBankA
    ld a, 0xF0
    ld (0), a
    ld a, 0xAA
    ld (0x0AAA), a
    ld a, 0x55
    ld (0x0555), a
    ld a, 0xA0
    ld (0x0AAA), a
    ex af, af'
    ld (hl), a
.poll:
    xor (hl)
    bit 7, a
    jr z, _
    bit 5, a
    jr z, .poll
    ; Error, abort
    ld a, 0xF0
    ld (0), a
    jp .return
_:  ld a, 0xF0
    ld (hl), a
    
    inc hl
    dec bc

    ld a, d
    setBankA

    xor a
    cp c
    jr nz, .inner_loop
    cp b
    jr nz, .inner_loop

    inc d \ inc e
    ld a, d
    setBankA
    and 0b00000011
    jr nz, .page_loop
    jp .return
.ram_end:
#endif

;; copyFlashExcept [Flash]
;;  Copies all but the first 0x200 bytes of Flash from one page to another.
;; Inputs:
;;  A: Destination page
;;  B: Source page
;; Notes:
;;  Flash must be unlocked and the destination page must be cleared.
copyFlashExcept:
; TODO: Allow user to specify an arbituary address to omit, perhaps in 0x100 byte blocks
    push de
    push bc
    ld d, a
    push af
    ld a, i
    push af
    di
    ld a, d
    
    push hl
    push de
        push af
        push bc
        ld hl, .ram
#ifdef CPU15
        ld a, 1
        out (PORT_RAM_PAGING), a
        ; This routine can perform better on some models if we rearrange memory 
        ld de, flashFunctions + 0x4000
        ld bc, .ram_end - .ram
        ldir
#else
        ld de, flashFunctions
        ld bc, .ram_end - .ram
        ldir
#endif
        pop bc
        pop af
#ifdef CPU15
        jp flashFunctions + 0x4000
.return:
        xor a
        out (PORT_RAM_PAGING), a ; Restore correct memory mapping
#else
        jp flashFunctions
.retrurn:
#endif
    pop de
    pop hl
    
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    pop de
    ret
    
#ifdef CPU15
.ram:
    setBankA ; Destination
    ld a, b
    setBankB ; Source
    
.preLoop:    
    ld de, 0x8000 + 0x200
    ld hl, 0x4000 + 0x200
    ld bc, 0x4000 - 0x200
.loop:
    ld a, (de)
    ld (.smc - .ram + flashFunctions + 0x4000 + 1), a
    ld (_  - .ram + flashFunctions + 0x4000 + 1), a
    ld a, 0xAA
    ld (0x0AAA), a    ; Unlock
    ld a, 0x55
    ld (0x0555), a    ; Unlock
    ld a, 0xA0
    ld (0x0AAA), a    ; Write command
.smc:
    ld a, 0
    ld (hl), a
    
_:  ld a, 0
    xor (hl)
    bit 7, a
    jr z, _
    bit 5, a
    jr z, -_
    jr _ ; See note on copySectorToSwap
    ; Error, abort
    ld a, 0xF0
    ld (0), a
    setBankB(0x81)
    jp .return
_:
    inc de
    inc hl
    dec bc

    ld a, b
    or a
    jr nz, .loop
    ld a, c
    or a
    jr nz, .loop
    
    setBankB(0x81)
    jp .return
.ram_end:
#else ; Models that don't support placing RAM page 01 in bank 3 (much slower)
.ram:
    ld e, b
    
    ld (flashFunctions + flashFunctionSize - 1), a
.preLoop:
    ld hl, 0x4000
    ld bc, 0x4000
.loop:
    push af
        ld a, e
        setBankA ; The inefficiency on this model comes from swapping pages during the loop
        ld d, (hl)
    pop af
    setBankA
    ; copy D to (HL)
    ld a, 0xAA
    ld (0x0AAA), a    ; Unlock
    ld a, 0x55
    ld (0x0555), a    ; Unlock
    ld a, 0xA0
    ld (0x0AAA), a    ; Write command
    ld (hl), d        ; Data
    
    ld a, d
_:  cp (hl)
    jr nz, -_ ; Does this work?
    
    dec bc
    inc hl
    
    ld a, b
    or a
    ld a, (flashFunctions + flashFunctionSize - 1)
    jr nz, .loop
    ld a, c
    or a
    ld a, (flashFunctions + flashFunctionSize - 1)
    jr nz, .loop
    ret
.ram_end:
#endif

;; copyFlashPage [Flash]
;;  Copies one page of Flash to another.
;; Inputs:
;;  A: Destination page
;;  B: Source page
;; Notes:
;;  Flash must be unlocked and the desination page must be cleared.
copyFlashPage:
    push de
    push bc
    ld d, a
    push af
    ld a, i
    push af
    di
    ld a, d
    
    push hl
    push de
        push af
        push bc
        ld hl, .ram
#ifdef CPU15
            ld a, 1
            out (PORT_RAM_PAGING), a
            ; This routine can perform better on some models if we rearrange memory 
            ld de, flashFunctions + 0x4000
            ld bc, .ram_end - .ram
            ldir
#else
        ld de, flashFunctions
        ld bc, .ram_end - .ram
        ldir
#endif
        pop bc
        pop af
#ifdef CPU15
        jp flashFunctions + 0x4000
.return:
        xor a
        out (PORT_RAM_PAGING), a ; Restore correct memory mapping
#else
        jp flashFunctions
.retrurn:
#endif
    pop de
    pop hl
    
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    pop de
    ret
    
#ifdef CPU15
.ram:
    setBankA ; Destination
    ld a, b
    setBankB ; Source
    
.preLoop:    
    ld de, 0x8000
    ld hl, 0x4000
    ld bc, 0x4000
.loop:
    ld a, (de)
    ld (.smc - .ram + flashFunctions + 0x4000 + 1), a
    ld (_ + - .ram + flashFunctions + 0x4000 + 1), a
    ld a, 0xAA
    ld (0x0AAA), a    ; Unlock
    ld a, 0x55
    ld (0x0555), a    ; Unlock
    ld a, 0xA0
    ld (0x0AAA), a    ; Write command
.smc:
    ld a, 0
    ld (hl), a
    
_:  ld a, 0
    xor (hl)
    bit 7, a
    jr z, _
    bit 5, a
    jr z, -_
    jr _ ; See note on copySectorToSwap
    ; Error, abort
    ld a, 0xF0
    ld (0), a
    setBankB(0x81)
    jp .return
_:
    inc de
    inc hl
    dec bc

    ld a, b
    or a
    jr nz, .loop
    ld a, c
    or a
    jr nz, .loop
    
    setBankB(0x81)
    jp .return
.ram_end:
#else ; Models that don't support placing RAM page 01 in bank 3 (much slower)
.ram:
    ld e, b
    
    ld (flashFunctions + flashFunctionSize - 1), a
.preLoop:
    ld hl, 0x4000
    ld bc, 0x4000
.loop:
    push af
        ld a, e
        setBankA ; The inefficiency on this model comes from swapping pages during the loop
        ld d, (hl)
    pop af
    setBankA
    ; copy D to (HL)
    ld a, 0xAA
    ld (0x0AAA), a    ; Unlock
    ld a, 0x55
    ld (0x0555), a    ; Unlock
    ld a, 0xA0
    ld (0x0AAA), a    ; Write command
    ld (hl), d        ; Data
    
    ld a, d
_:  cp (hl)
    jr nz, -_ ; Does this work?
    
    dec bc
    inc hl
    
    ld a, b
    or a
    ld a, (flashFunctions + flashFunctionSize - 1)
    jr nz, .loop
    ld a, c
    or a
    ld a, (flashFunctions + flashFunctionSize - 1)
    jr nz, .loop
    ret
.ram_end:
#endif
