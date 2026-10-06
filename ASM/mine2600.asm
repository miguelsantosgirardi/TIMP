; ============================================================================
;  MINE 2600  --  Initial Test Build 2  ("ITB2 / BLOCO PRETO NO CENTRO")
; ----------------------------------------------------------------------------
;  Herda do ITB1 : o céu $9E, o quadro NTSC de 262 linhas e o cartucho de 2 KB
;  Adiciona      : um bloco preto -- cor $00 -- no centro exato da tela
;  Não tem       : jogador, mundo, colisão, HUD, áudio. O bloco é estático e
;                  ainda não é um objeto do jogo: é a primeira prova de que o
;                  renderizador escreve no TIA na hora certa.
;
;  Plataforma    : Atari 2600 (VCS), CPU MOS 6507, vídeo NTSC a 60 quadros/s
;  Cartucho      : 2 KB (2048 bytes) em $F800-$FFFF; vetores em $FFFC-$FFFF
;  Alvo          : Stella / Javatari
;  Montador      : DASM (arquivo autossuficiente: não precisa de vcs.h)
;  Montar        : dasm mine2600.asm -f3 -oMine2600_itb2.a2600
; ============================================================================

        processor 6502

; ----------------------------------------------------------------------------
;  Registradores do TIA (mesmos endereços do vcs.h oficial)
;
;  Atenção: os registradores do TIA em $00-$2C são só de ESCRITA. Ler esses
;  mesmos endereços devolve outra coisa (colisões, entradas). Por exemplo,
;  ler $01 NÃO diz se o VBLANK está ligado.
; ----------------------------------------------------------------------------
VSYNC           = $00       ; W  bit 1 = 1 liga o sincronismo vertical
VBLANK          = $01       ; W  bit 1 = 1 apaga a imagem
WSYNC           = $02       ; W  para a CPU até o começo da próxima linha
COLUPF          = $08       ; W  cor do playfield (aqui: a cor do bloco)
COLUBK          = $09       ; W  cor do fundo
CTRLPF          = $0A       ; W  controle do playfield (bit 0 = espelhar)
PF0             = $0D       ; W  playfield, pixels 0-3   (só usa os 4 bits altos)
PF1             = $0E       ; W  playfield, pixels 4-11
PF2             = $0F       ; W  playfield, pixels 12-19

; ----------------------------------------------------------------------------
;  Configuração
; ----------------------------------------------------------------------------
SKY_COLOR       = $9E       ; matiz 9 (azul), luminância E (a mais clara)
BLOCK_COLOR     = $00       ; preto

VBLANK_LINES    = 37
VISIBLE_LINES   = 192
OVERSCAN_LINES  = 30

CTRLPF_REFLECT  = %00000001 ; metade direita do playfield = espelho da esquerda

; ----------------------------------------------------------------------------
;  Geometria do bloco
;
;  A tela tem 160 pixels de largura. O playfield a cobre com 40 "pixels de
;  playfield" de 4 pixels cada: 20 na metade esquerda (PF0 = 4, PF1 = 8,
;  PF2 = 8) e 20 na direita. Com CTRLPF_REFLECT a direita é o espelho da
;  esquerda; então o PF2, que é o último da metade esquerda, fica encostado
;  no centro, e o seu bit 7 é o que encosta mais.
;
;      x =   68    72    76   | 80    84    88    92
;      PF2:  bit5  bit6  bit7 | bit7  bit6  bit5  ...
;                             ^ centro da tela (x = 80)
;
;  BLOCK_PF2 = %11100000 liga os bits 7, 6 e 5 -> 3 x 4 = 12 pixels de cada
;  lado do centro -> bloco de 24 pixels, x = 68..91, centrado.
;
;  Na vertical, o bloco ocupa BLOCK_HEIGHT linhas, centralizado entre as 192
;  linhas visíveis. O pixel do TIA é cerca de 1,7x mais largo do que uma linha
;  é alta; 24 pixels x 40 linhas dá um bloco de aparência quase quadrada.
;
;  Para mudar o tamanho: BLOCK_PF2 (largura, sempre simétrica) e
;  BLOCK_HEIGHT (altura, par, de 2 a 190). O resto é calculado.
; ----------------------------------------------------------------------------
BLOCK_PF2       = %11100000
BLOCK_HEIGHT    = 40

BLOCK_TOP       = (VISIBLE_LINES - BLOCK_HEIGHT) / 2        ; linhas de céu acima
BLOCK_BELOW     = VISIBLE_LINES - BLOCK_TOP - BLOCK_HEIGHT  ; linhas de céu abaixo

        IF BLOCK_HEIGHT < 2 || BLOCK_HEIGHT > 190 || (BLOCK_HEIGHT & 1)
            ECHO "ERRO: BLOCK_HEIGHT deve ser par, de 2 a 190"
            ERR
        ENDIF

; ----------------------------------------------------------------------------
;  Estrutura do quadro NTSC: 262 linhas de varredura (76 ciclos de CPU cada).
;  Todo trecho é contado em WSYNCs: 1 WSYNC = 1 linha, exatamente, em qualquer
;  emulador e no console de verdade.
;
;       3  VSYNC     a TV volta ao topo da imagem
;      37  VBLANK    imagem apagada
;     192  VISÍVEL   imagem
;      30  OVERSCAN  imagem apagada
;     ---
;     262
; ----------------------------------------------------------------------------

        org $F800

Reset:
        sei                 ; sem interrupções
        cld                 ; sem modo decimal
        ldx #0              ; zera TIA ($00-$7F) e RAM ($80-$FF) e deixa SP = $FF.
        txa                 ; Cada PHA grava A = 0 no espelho da pilha: o 6507 só
.clear  dex                 ; tem 13 bits de endereço, então $0100-$01FF cai em
        txs                 ; cima de $00-$FF.
        pha
        bne .clear

Frame:
        ; ---- VSYNC: 3 linhas -------------------------------------------------
        lda #2
        sta VSYNC           ; VSYNC ligado
        sta WSYNC           ; linha 1
        sta WSYNC           ; linha 2
        sta WSYNC           ; linha 3
        lda #0
        sta VSYNC           ; VSYNC desligado

        ; ---- VBLANK: 37 linhas -----------------------------------------------
        lda #SKY_COLOR      ; paleta e playfield escritos aqui, longe da área visível
        sta COLUBK
        lda #BLOCK_COLOR
        sta COLUPF
        lda #CTRLPF_REFLECT
        sta CTRLPF
        lda #0
        sta PF0             ; só o PF2 é usado
        sta PF1
        sta PF2             ; todo quadro começa sem bloco
        ; (futuro: a lógica do jogo entra aqui. Quando ela precisar de tempo,
        ;  troque o laço abaixo pelo timer do RIOT, armado no começo do
        ;  trecho: TIM64T = 44, laço de espera em INTIM e um WSYNC no fim.
        ;  Medido no Stella: o INTIM chega a 0 em (N-1) x 64 + 1 ciclos, e
        ;  não em N x 64.)
        ldx #VBLANK_LINES
.vblank sta WSYNC
        dex
        bne .vblank

        lda #0
        sta VBLANK          ; imagem ligada: esta linha já é a primeira visível

        ; ---- Área visível: 192 linhas ---------------------------------------
        ; Cada fase começa logo depois de um WSYNC, ainda no HBLANK da primeira
        ; linha dela: a escrita no PF2 vale já nessa linha, sem listra.

        ldx #BLOCK_TOP      ; céu acima do bloco
.above  sta WSYNC
        dex
        bne .above

        lda #BLOCK_PF2      ; bloco: liga o PF2 na primeira linha do bloco
        sta PF2
        ldx #BLOCK_HEIGHT
.block  sta WSYNC
        dex
        bne .block

        lda #0              ; céu abaixo do bloco: desliga o PF2
        sta PF2
        ldx #BLOCK_BELOW
.below  sta WSYNC
        dex
        bne .below

        ; ---- OVERSCAN: 30 linhas ---------------------------------------------
        lda #2
        sta VBLANK          ; imagem apagada
        ; (futuro: a lógica pós-quadro -- colisões, pontuação -- entra aqui.
        ;  Com o timer, armado no começo do trecho: TIM64T = 36, também
        ;  seguido de um WSYNC.)
        ldx #OVERSCAN_LINES
.over   sta WSYNC
        dex
        bne .over
        jmp Frame

; ----------------------------------------------------------------------------
;  Vetores do 6507 (espelhados em $1FFC no mapa de 13 bits)
;  IRQ/BRK também aponta para Reset: se a CPU cair no preenchimento zerado
;  (opcode $00 = BRK), o programa simplesmente reinicia.
; ----------------------------------------------------------------------------
        org $FFFC
        .word Reset         ; RESET
        .word Reset         ; IRQ / BRK
