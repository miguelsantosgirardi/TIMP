; ============================================================================
;  MINE 2600  --  Initial Test Build 3  ("ITB3 / JOGADOR + GRAVIDADE")
; ----------------------------------------------------------------------------
;  Herda do ITB2 : céu $9E, bloco preto central, quadro NTSC de 262 linhas,
;                  cartucho de 2 KB
;  Muda          : bloco na metade do tamanho do ITB2
;                    largura: 8px   (ITB2 tinha 24px)
;                    altura : 20 linhas (ITB2 tinha 40)
;  Adiciona      : jogador  -- sprite GRP0 de 8x8 px (menor que o bloco 8x20)
;                    movimento esquerda/direita: ambos os controles (~15px/quadro)
;                    pulo: cima em qualquer controle
;                    gravidade constante de +1 linha/quadro
;                    velocidade de pulo  = -5 linhas/quadro
;                    terminal velocity   =  4 linhas/quadro
;                    colisão com o chão (topo do bloco) e bordas da tela
;  Não tem       : áudio, inimigos, HUD, mundo maior que uma tela
;
;  Plataforma    : Atari 2600 (VCS), CPU MOS 6507, vídeo NTSC a 60 quadros/s
;  Cartucho      : 2 KB em $F800-$FFFF; vetores em $FFFC-$FFFF
;  Alvo          : Stella / Javatari
;  Montador      : DASM >= 2.20  (sem includes extras)
;  Montar        : dasm mine2600.asm -f3 -oMine2600_itb3.a2600
;
;  Posicionamento horizontal do sprite (calibrado no Stella)
;  ----------------------------------------------------------
;  Após WSYNC, um laço de delay (beq .skip / dex / bne .dly) com N iterações
;  produz as seguintes posições de sprite (empiricamente):
;    N= 3 -> x= 3    N= 4 -> x=18    N= 5 -> x=33
;    N= 6 -> x=48    N= 7 -> x=63    N= 8 -> x=78    N= 9 -> x=93
;  Passo: 15px por iteração. Usamos N=3..9 -> x=3..93.
;  PL_X_NOPS guarda o N atual. Limite: 3 (esquerda) a 9 (direita).
; ============================================================================

        processor 6502

; ============================================================================
;  Registradores TIA e RIOT
; ============================================================================
VSYNC   = $00
VBLANK  = $01
WSYNC   = $02
NUSIZ0  = $04
COLUP0  = $06
COLUPF  = $08
COLUBK  = $09
CTRLPF  = $0A
REFP0   = $0B
PF0     = $0D
PF1     = $0E
PF2     = $0F
RESP0   = $10
GRP0    = $1B
ENAM0   = $1D
ENAM1   = $1E
ENABL   = $1F
HMP0    = $20
HMOVE   = $2A
HMCLR   = $2B

SWCHA   = $0280     ; joystick: P0=bits7-4, P1=bits3-0, ativo baixo

; ============================================================================
;  RAM ($80-$FF)
; ============================================================================
        SEG.U RAM
        ORG   $80

PL_Y            ds 1    ; $80  linha do topo do sprite na área visível
PL_X_NOPS       ds 1    ; $81  posição X em iterações de laço (3..9, ver tabela)
PL_YV           ds 1    ; $82  velocidade vertical s8 (+ = desce, - = sobe)
PL_GROUND       ds 1    ; $83  1 = no chão, 0 = no ar
PL_FACING       ds 1    ; $84  0 = direita, 1 = esquerda
JOYPREV         ds 1    ; $85  estado do joystick anterior (edge-detect do pulo)
KERN_LENA       ds 1    ; $86  linhas de céu acima do sprite
KERN_LENC       ds 1    ; $87  linhas entre o sprite e o bloco

        SEG
        ORG $F800

; ============================================================================
;  Constantes
; ============================================================================
SKY_COLOR       = $9E
BLOCK_COLOR     = $00
PLAYER_COLOR    = $1E       ; amarelo claro NTSC

VBLANK_LINES    = 37
VISIBLE_LINES   = 192
OVERSCAN_LINES  = 30

BLOCK_PF2       = %10000000 ; 1 bit/lado com reflect = 8px total
BLOCK_H         = 20
BLOCK_TOP       = (VISIBLE_LINES - BLOCK_H) / 2    ; = 86
BLOCK_BOT       = VISIBLE_LINES - BLOCK_TOP - BLOCK_H  ; = 86

PLAYER_H        = 8             ; linhas de sprite
; Posição inicial: em cima do bloco, centrado (~x=78, N=8)
PLAYER_NOPS_INIT = 8
PLAYER_Y_INIT   = BLOCK_TOP - PLAYER_H  ; = 78

; Física
GRAV            = 1
JUMP_VEL        = $FB           ; -5 em s8
TERM_VEL        = 4

; Limites X em NOPs
NOPS_MIN        = 3             ; x=3  (esquerda)
NOPS_MAX        = 9             ; x=93 (direita)

; ============================================================================
;  Sprite do jogador (tabela na ROM, índice 0 = linha base = fundo do sprite)
;  Kernel lê do topo para baixo mas indexa a tabela de 7 a 0.
; ============================================================================
PlayerSprite:
        .byte %01000010     ; linha 7 (base / pernas)
        .byte %01000010     ; linha 6 (pernas)
        .byte %01111110     ; linha 5 (cintura)
        .byte %01111110     ; linha 4 (corpo)
        .byte %01111110     ; linha 3 (corpo)
        .byte %00111100     ; linha 2 (ombros)
        .byte %01111110     ; linha 1 (cabeça)
        .byte %00111100     ; linha 0 (topo da cabeça)

; ============================================================================
;  RESET
; ============================================================================
Reset:
        sei
        cld
        ; zera toda a RAM e TIA em um único laço via espelho do 6507
        ldx #0
        txa
.cl     dex
        txs
        pha
        bne .cl

        ; paleta e playfield
        lda #SKY_COLOR
        sta COLUBK
        lda #BLOCK_COLOR
        sta COLUPF
        lda #PLAYER_COLOR
        sta COLUP0
        lda #%00000001
        sta CTRLPF
        lda #0
        sta NUSIZ0          ; sprite: 1 cópia, largura normal (8px)
        sta REFP0
        sta PF0
        sta PF1
        sta PF2
        sta GRP0
        sta ENAM0
        sta ENAM1
        sta ENABL

        ; estado inicial do jogador
        lda #PLAYER_Y_INIT
        sta PL_Y
        lda #PLAYER_NOPS_INIT
        sta PL_X_NOPS
        lda #0
        sta PL_YV
        lda #1
        sta PL_GROUND
        lda #0
        sta PL_FACING
        sta JOYPREV

; ============================================================================
;  Loop principal
; ============================================================================
Frame:
        ; ---- VSYNC: 3 linhas -----------------------------------------------
        lda #2
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC

        ; ================================================================
        ;  VBLANK: 37 linhas -- toda a lógica do jogo
        ; ================================================================

        lda SWCHA
        sta $88             ; salva SWCHA

        ; -- gravidade -------------------------------------------------------
        lda PL_GROUND
        bne .skip_grav
        lda PL_YV
        clc
        adc #GRAV
        cmp #TERM_VEL + 1
        bcc .no_clamp
        lda #TERM_VEL
.no_clamp
        sta PL_YV
        ; integra: PL_Y += PL_YV
        clc
        adc PL_Y
        sta PL_Y
.skip_grav

        ; -- colisão com teto ------------------------------------------------
        lda PL_Y
        bpl .no_ceil
        lda #0
        sta PL_Y
        sta PL_YV
.no_ceil

        ; -- colisão com chão (topo do bloco) --------------------------------
        lda PL_Y
        clc
        adc #PLAYER_H
        cmp #BLOCK_TOP + 1
        bcc .in_air
        lda #BLOCK_TOP - PLAYER_H   ; = 78
        sta PL_Y
        lda #0
        sta PL_YV
        lda #1
        sta PL_GROUND
        bne .done_vert
.in_air
        lda #0
        sta PL_GROUND
.done_vert

        ; -- movimento esquerda: P0 bit6=0 OU P1 bit2=0 ----------------------
        lda $88
        and #%01000100
        cmp #%01000100
        beq .chk_right

        lda PL_X_NOPS
        cmp #NOPS_MIN + 1
        bcc .at_left
        dec PL_X_NOPS
        lda #1
        sta PL_FACING
        lda #%00001000
        sta REFP0
        bne .done_horiz
.at_left
        lda #NOPS_MIN
        sta PL_X_NOPS
        lda #1
        sta PL_FACING
        lda #%00001000
        sta REFP0
        bne .done_horiz

.chk_right
        ; -- movimento direita: P0 bit7=0 OU P1 bit3=0 ----------------------
        lda $88
        and #%10001000
        cmp #%10001000
        beq .done_horiz

        lda PL_X_NOPS
        cmp #NOPS_MAX
        bcs .at_right
        inc PL_X_NOPS
        lda #0
        sta PL_FACING
        sta REFP0
        bne .done_horiz
.at_right
        lda #NOPS_MAX
        sta PL_X_NOPS
        lda #0
        sta PL_FACING
        sta REFP0

.done_horiz

        ; -- pulo: borda de subida em cima + no chão -------------------------
        lda $88
        and #%00010001
        sta $89                 ; cima agora (0 = pressionado)
        lda JOYPREV
        and #%00010001
        sta $8A                 ; cima anterior

        ; pulo se cima pressionado (algum bit = 0) e no chão
        lda $89
        cmp #%00010001
        beq .no_jump
        lda PL_GROUND
        beq .no_jump
        lda #JUMP_VEL
        sta PL_YV
        lda #0
        sta PL_GROUND
.no_jump
        lda $88
        sta JOYPREV

        ; -- pré-calcula limites do kernel -----------------------------------
        lda PL_Y
        sta KERN_LENA           ; céu acima do sprite = PL_Y linhas
        lda #BLOCK_TOP
        sec
        sbc PL_Y
        sbc #PLAYER_H           ; BLOCK_TOP - PL_Y - PLAYER_H
        bcs .lenC_ok
        lda #0
.lenC_ok
        sta KERN_LENC

        ; -- VBLANK: WSYNCs --------------------------------------------------
        ldx #VBLANK_LINES
.vbl    sta WSYNC
        dex
        bne .vbl
        lda #0
        sta VBLANK              ; imagem ligada: próxima linha é visível 0

        ; ================================================================
        ;  Kernel de renderização
        ; ================================================================

        ; -- Posiciona o sprite (HBLANK da linha 0) --------------------------
        ; Após "sta VBLANK", o TIA emite internamente um WSYNC e começa o
        ; HBLANK da linha 0. Usamos mais um WSYNC para ter um HBLANK limpo,
        ; depois rodamos o laço de delay e escrevemos RESP0.
        ;
        ; Laço calibrado (probe3 com setRAM):
        ;   N iterações (beq .skip / dex / bne .dly) -> x pixel inicial:
        ;   N=3:x=3   N=4:x=18   N=5:x=33   N=6:x=48
        ;   N=7:x=63  N=8:x=78   N=9:x=93
        ;
        ; Overhead antes do laço: ldx (3c) + beq (2c) = 5c.
        ; Após cada iteração: dex(2c) + bne(3c) = 5c/iter (2c final).
        ; Total antes de RESP0 para N iterações: 5 + (N-1)*5 + 2 + 3 = 5N+5c.
        sta WSYNC               ; HBLANK linha 0
        ldx PL_X_NOPS           ; 3c
        beq .pos_skip           ; 2c (N=0: salta direto pro RESP0; nunca acontece aqui)
.pos_dly
        dex                     ; 2c
        bne .pos_dly            ; 3c (tomado) / 2c (não tomado = última iter)
.pos_skip
        sta RESP0               ; posiciona P0 no ciclo atual
        lda #0
        sta HMP0
        sta HMOVE
        sta HMCLR

        ; -- Faixa A: céu acima do sprite ------------------------------------
        lda #0
        sta GRP0
        sta PF2
        ldx KERN_LENA
        beq .end_A
.loopA  sta WSYNC
        dex
        bne .loopA
.end_A

        ; -- Faixa B: sprite (PLAYER_H = 8 linhas) ---------------------------
        ; GRP0 é trocado a cada linha. A tabela está de baixo para cima,
        ; então indexamos de PLAYER_H-1 (=7) até 0.
        lda #0
        sta PF2
        ldx #PLAYER_H - 1
.loopB
        lda PlayerSprite,x
        sta GRP0
        sta WSYNC
        dex
        bpl .loopB
        lda #0
        sta GRP0

        ; -- Faixa C: céu entre sprite e bloco -------------------------------
        ldx KERN_LENC
        beq .end_C
.loopC  sta WSYNC
        dex
        bne .loopC
.end_C

        ; -- Faixa D: bloco (BLOCK_H = 20 linhas) ----------------------------
        lda #BLOCK_PF2
        sta PF2
        ldx #BLOCK_H
.loopD  sta WSYNC
        dex
        bne .loopD

        ; -- Faixa E: céu abaixo do bloco ------------------------------------
        lda #0
        sta PF2
        ldx #BLOCK_BOT
.loopE  sta WSYNC
        dex
        bne .loopE

        ; ================================================================
        ;  OVERSCAN
        ; ================================================================
        lda #2
        sta VBLANK
        ldx #OVERSCAN_LINES
.ovscan sta WSYNC
        dex
        bne .ovscan
        jmp Frame

; ============================================================================
;  Vetores
; ============================================================================
        org $FFFC
        .word Reset
        .word Reset
