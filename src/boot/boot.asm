; src/boot/boot.asm
; Bootloader to load kernel, switch to 32-bit protected mode and execute kernel
; Build with
; # nasm -f bin boot.asm -o boot.bin
; Un offset = la distance par rapport à un point de départ
; Offset = “combien d’octets je suis loin du début d’un segment”
; Segment = “point de départ”
; Adresse physique = segment × 16 + offset
; DL = numéro du disque
; BX = adresse mémoire où mettre le kernel
; DH = nombre de secteurs à lire
; Mode réel = “tout est permis”
; Mode protégé = “il faut une carte d’accès pour chaque zone de mémoire”
; La GDT = la carte d’accès
; LGDT = dire au CPU où trouver la carte
; EAX = est un registre général du CPU en mode 32 bits
; CR0 = un registre spécial pour la CPU
; EBP = Extended Base Pointer, registre 32 bits utilisé pour la pile ou les appels de fonctions, seulement pour la 32 bit, PAS POUR LE 16 BIT, c'est SP POUR LE 16 BITS
; ESP = Stack Pointer 32 bits → indique le dessus actuel de la pile
; ADDR_KERNEL_OFFSET = l’adresse dans la RAM où ton kernel a été chargé

[BITS 16]
[ORG 0x7C00] ;0x7000 = est juste de la RAM « basse », utilisable par OS ou bootloader
; [ORG 0x7C00] dit à l’assembleur : “Mon code sera chargé par le BIOS à 0x7C00, donc écris les instructions et les variables en conséquence.”

MOV [bootDrive], DL ; bootdrive = nom de l'endroit où on stocke la variable
; Sauvegarde le numéro du disque de démarrage fourni par le BIOS (ex: 0x80), sda1, sda2 = faut mais pour imager les disques c'est mieux
; Nécessaire pour restaurer DL avant les appels INT 13h

MOV BP, 0x9000
; On met BP à 0x9000 pour créer un repère stable pour la pile
; SP (le dessus de la pile) sera mis au même endroit juste après
; BP sert à toujours savoir où commence notre pile, même si SP change, car SP n'est pa fiable alors il faut quelques choses de fiable.
; La pile est un "tiroir temporaire" pour stocker des données pendant que le code travaille
; SP = dessus du tiroir, BP = repère fixe pour savoir où commence la pile
; La pile = une partie de la RAM

MOV SP, BP
; Initialise la pile à 0x9000
; La pile descend vers le bas quand on fait PUSH, donc elle n’écrasera pas le bootloader

MOV BX, ADDR_KERNEL_OFFSET
; ES:BX = adresse où charger le kernel
; ADDR_KERNEL_OFFSET = offset dans la RAM pour le kernel
; Exemple : si ADDR_KERNEL_OFFSET = 0x1000
; alors le kernel sera chargé à l’adresse physique ES*16 + 0x1000

MOV DH, 0x01
; Nombre de secteurs à lire depuis le disque
; DX = registre de 16 bits utilisé par le BIOS pour passer des paramètres
; +--------+--------+
; |  DH    |  DL    |
; +--------+--------+
;   8 bits   8 bits
; DH = high = partie haute de DX (8 bits de gauche)
; DL = low  = partie basse de DX (8 bits de droite)


MOV DL, [bootDrive]                     ; DL    = Drive number to load from, Drive number = numéro du disque que le BIOS utilise pour démarrer ;n'est pas ultra nécéssaire, peut supprimer mais je ne vais pas le faire parceque flemme...

CALL disk_loadSectors                   ; Call disk load function

CLI                                     ; Disable interrupts in preperation for protected mode, pour éviter que le CPU prenne un autre tâche et qu'il se concentre seulement sur ce que l'on veut qu'il fasse

LGDT [gdt_descriptor]                   ; Load global descriptor table for protected mode
; = “Charge la table qui décrit les segments mémoire” GDT c'est juste une table en fait pour les autorisations et les écritures etc, comme sur linux avec r-w-x
; = nécessaire avant d’activer le mode protégé
; = sans ça, le CPU ne saura pas comment gérer la RAM en 32 bits

MOV EAX, CR0                            ; Move CR0 to GP register ;MOV EAX, CR0 → copie CR0 dans EAX pour pouvoir modifier certains bits
; Ensuite on peut mettre le bit PE = 1 pour passer en mode protégé

OR EAX, 0x1                             ; Set first bit to switch to protected mode, on met 1 bit pour passer en mode protéger

MOV CR0, EAX                            ; Update CR0 from GP register to complete switch, copier CR0 dans un registre général (EAX)


JMP gdt_codeSeg:start32
; Saute directement au début du code 32 bits
; gdt_codeSeg = sélecteur du segment de code défini dans la GDT
; start32 = adresse de départ de ton code en mode protégé
; Nécessaire après avoir activé le mode protégé pour exécuter du code 32 bits


[BITS 32]                               ; 32-bit protected mode
start32:                                ; Jump target for start of protected mode code

MOV AX, gdt_dataSeg                     ; Update segments for protected mode as defined in GDT, On met le sélecteur dans AX pour l’utiliser ensuite sur tous les segments
MOV DS, AX ; Ici on dit : “DS = segment de données défini dans la GDT”
MOV SS, AX ; On configure la pile pour qu’elle soit dans le même segment de données sécurisé
MOV ES, AX ; ES, FS, GS : autres segments de données supplémentaires Beaucoup de routines utilisent ces segments pour stocker ou manipuler des données temporaires on les met tous sur le segment de données principal pour simplifier
MOV FS, AX 
MOV GS, AX

MOV EBP, 0x90000
; EBP = base de la pile en 32 bits
; La pile commence ici (au sommet de l’espace libre)
; Utilisé pour les appels de fonctions et variables locales
; SP/ESP pointera sur le dessus de la pile, EBP reste fixe

MOV ESP, EBP                            ; Set stack pointer at base of stack, comme on a fait au début pour le 16 bit

; Au lieu de CALL ADDR_KERNEL_OFFSET
MOV EAX, ADDR_KERNEL_OFFSET  ; Charge l'adresse du kernel dans EAX
CALL EAX                     ; Appelle le kernel via le registre (32 bits sécurisé)
; OU
JMP ADDR_KERNEL_OFFSET       ; Simple saut vers le kernel (pas d'adresse de retour)


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
