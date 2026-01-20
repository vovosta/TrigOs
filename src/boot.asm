; src/boot/boot.asm
; Bootloader to load kernel, switch to 32-bit protected mode and execute kernel
; Build with
; # nasm -f bin boot.asm -o boot.bin

[BITS 16]                               ; 16-bit real mode
[ORG 0x7C00]                            ; Loaded into memory at 0x7C00

MOV [bootDrive], DL                     ; Store DL (boot drive number) in memory

MOV BP, 0x9000                          ; Move Base Pointer in free memory space, BP = Baise pointer
MOV SP, BP                              ; Move Stack Pointer to base of stack, SP=stack pointer

MOV BX, ADDR_KERNEL_OFFSET              ; ES:BX = Address to load kernel into
MOV DH, 0x01                            ; DH    = Number of sectors to load
MOV DL, [bootDrive]                     ; DL    = Drive number to load from
CALL disk_loadSectors                   ; Call disk load function

CLI                                     ; Disable interrupts in preperation for protected mode
LGDT [gdt_descriptor]                   ; Load global descriptor table for protected mode

MOV EAX, CR0                            ; Move CR0 to GP register
OR EAX, 0x1                             ; Set first bit to switch to protected mode
MOV CR0, EAX                            ; Update CR0 from GP register to complete switch

JMP gdt_codeSeg:start32                 ; Jump to start of 32-bit code

[BITS 32]                               ; 32-bit protected mode
start32:                                ; Jump target for start of protected mode code

MOV AX, gdt_dataSeg                     ; Update segments for protected mode as defined in GDT
MOV DS, AX
MOV SS, AX
MOV ES, AX
MOV FS, AX
MOV GS, AX

MOV EBP, 0x90000                        ; Set stack base at top of free space
MOV ESP, EBP                            ; Set stack pointer at base of stack

CALL ADDR_KERNEL_OFFSET                 ; Begin executing the kernel

; void disk_loadSectors ( char* addr , int disk , int num ) ;
;   BX = [addr]
;   DH = [num:disk]
; Load DH sectors from disk DL into address ES:BX
disk_loadSectors:
    PUSHA                               ; Preserve register values in stack
    
    PUSH DX                             ; Store [DH:DL], DH = number of sectors to load 
    
    MOV AH, 0x02                        ; BIOS sector load
    MOV AL, DH                          ; AL = DH = number of sectors to load
    MOV CH, 0x00                        ; CH = Cylinder = 0
    MOV DH, 0x00                        ; DH = Head = 0
    MOV CL, 0x02                        ; CL = Base Sector = 2
    
    INT 0x13                            ; BIOS interrupt
    
    JC disk_loadSectorsFail             ; Jump if error (carry flag)
    
    POP DX                              ; Restore [DH:DL], DH = number of sectors to load
    CMP DH, AL                          ; Compare number of actual loaded sectors
    JNE disk_loadSectorsFail            ; Jump if error (incorrect number of sectors)

    POPA                                ; Restore register values
    RET                                 ; Return function call

    ; Report disk_loadSectors failure
    disk_loadSectorsFail:
        MOV BX, disk_errorMsg           ; BX = pointer to disk fail string
        CALL msg_printStr               ; Print string
        JMP $                           ; Hang

; void msg_printStr ( char *str ) ;
;   BX = [str]
; Print string in real mode
msg_printStr:
    PUSHA                               ; Preserve registers on stack
    
    MOV AH, 0x0E                        ; BIOS TTY
    MOV SI, BX                          ; Move str to [SI]
    
    ; Loop through string printing characters
    msg_printStr_loopChar:
        LODSB                           ; Load new byte from SI into AX
        
        CMP AL, 0x00                    ; Check null-termination character
        JE msg_printStrEnd              ; Terminate loop
        
        INT 0x10                        ; Otherwise call BIOS interrupt
        JMP msg_printStr_loopChar       ; Print another character
     
    ; End printstring function
    msg_printStrEnd:
        POPA                            ; Restore registers from stack
        RET                             ; Return from function

; Strings
disk_errorMsg   db "Disk read error!",0

; Data
bootDrive db 0x00                       ; Get byte to store boot drive number
ADDR_KERNEL_OFFSET EQU 0x1000           ; Define location for kernel in memory

; Global descriptor table for 32-bit protected mode
gdt_start:                              ; Start of global descriptor table
    gdt_null:                           ; Null descriptor chunk
        dd 0x00
        dd 0x00
    gdt_code:                           ; Code descriptor chunk
        dw 0xFFFF
        dw 0x0000
        db 0x00
        db 0x9A
        db 0xCF
        db 0x00
    gdt_data:                           ; Data descriptor chunk
        dw 0xFFFF
        dw 0x0000
        db 0x00
        db 0x92
        db 0xCF
        db 0x00
    gdt_end:                            ; Bottom of table
gdt_descriptor:                         ; Table descriptor
    dw gdt_end - gdt_start - 1          ; Size of table
    dd gdt_start                        ; Start point of table
    
gdt_codeSeg equ gdt_code - gdt_start    ; Offset of code segment from start
gdt_dataSeg equ gdt_data - gdt_start    ; Offset of data segment from start

; Tail
times 510-($-$$) db 0x00                ; Fill bootloader to 512-bytes
dw 0xAA55                               ; Magic word signature
