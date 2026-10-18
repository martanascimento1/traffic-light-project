;atualizadooooo
;  SIMULACAO DOS SEMAFOROS DO CRUZAMENTO
;  Av. Alvaro Otacilio x R. Prof. Sandoval Arroxelas - Maceio/AL
;
;  Placa      : Arduino Uno (ATmega328P @ 16 MHz)
;  Montador   : AVRASM2 (Microchip Studio, projeto "AVR Assembler")
;  Arquivo    : semaforo.asm
;
;  RESUMO DO FUNCIONAMENTO
;  -----------------------
;  O cruzamento e modelado como uma maquina de 7 estados. Cada estado define
;  a cor de cada um dos 5 sinais (S1, S2, S3, S4 e P) e dura um numero fixo
;  de segundos. A tabela de estados fica gravada na memoria flash (ver
;  "tabela_estados" no final) e o codigo e totalmente generico: para mudar a
;  temporizacao ou as cores basta editar a tabela.
;
;  Sao usados dois timers, cada um com a sua interrupcao:
;
;  * Timer1 (16 bits), modo CTC, uma interrupcao por segundo. A ISR
;      1. decrementa o contador de segundos do estado atual;
;      2. separa o contador em dezena e unidade (para os displays);
;      3. quando o contador chega a zero, avanca para o proximo estado,
;         escreve as cores nos pinos dos LEDs e inicia o envio da mensagem
;         de status pela USART.
;
;  * Timer0 (8 bits), modo CTC, uma interrupcao a cada 5 ms. A ISR faz a
;    multiplexacao dos dois displays: num tique mostra a dezena no display
;    da esquerda, no tique seguinte a unidade no da direita. Cada display e
;    atualizado 100 vezes por segundo, rapido demais para o olho perceber.
;    Assim os dois displays usam um unico decodificador BCD.
;
;  A transmissao serial tambem e feita por interrupcao (UDRE): cada vez que
;  o registrador de transmissao esvazia, a ISR envia o proximo caractere da
;  string ate encontrar o terminador 0. O laco principal fica vazio: todo o
;  comportamento acontece nas interrupcoes, como pede o requisito de usar
;  interrupcao em vez de verificacao de flag.
;
;  HARDWARE (20 pinos do Uno, todos usados)
;  ----------------------------------------
;  Serial : D0/D1 (USART0) a 9600 bps, 8N1, via USB -> monitor serial.
;
;  Displays (2 x 7 segmentos de CATODO COMUM, 1 decodificador BCD):
;     A0..A3 (PC0..PC3) -> entradas A,B,C,D (S0..S3) do decodificador BCD
;     saidas a..g do decodificador -> resistores de 330 ohms -> segmentos
;     a..g dos DOIS displays em paralelo
;     A5 (PC5) -> 100 ohms -> base do transistor NPN do display das DEZENAS
;     A4 (PC4) -> 100 ohms -> base do transistor NPN do display das UNIDADES
;     (coletor de cada transistor no catodo comum do seu display, emissor
;      no GND; pino em 1 = display aceso)
;     No SimulIDE: "BCD to 7S" com Open Drain = No e OE no GND;
;     "7 Segment Display" em catodo comum. Na protoboard: CD4511.
;
;  LEDs (12 pinos, 14 LEDs), cada um com resistor de 220 ohms:
;     PORTD                         PORTB
;     D2 (PD2) S1 vermelho          D8  (PB0) S3 vermelho
;     D3 (PD3) S1 amarelo           D9  (PB1) S3 amarelo E S4 amarelo *
;     D4 (PD4) S1 verde             D10 (PB2) S3 verde
;     D5 (PD5) S2 vermelho          D11 (PB3) S4 vermelho
;     D6 (PD6) S2 amarelo           D12 (PB4) S4 verde
;     D7 (PD7) S2 verde             D13 (PB5) P: 1 = vermelho, 0 = verde **
;
;   * S3 e S4 so ficam amarelos ao mesmo tempo (estado q2), entao os dois
;     LEDs amarelos podem dividir um pino (um resistor para cada LED).
;  ** O pedestre e sempre vermelho OU verde, entao um pino basta:
;        D13 -> 220 ohms -> LED vermelho -> GND   (acende com D13 = 1)
;        5V  -> 220 ohms -> LED verde    -> D13   (acende com D13 = 0)
;     O LED da propria placa no pino 13 acompanha o vermelho do pedestre.
;
;  SIGNIFICADO DOS SINAIS (conforme o levantamento de campo)
;  --------------------------------------------------------
;  S1 = R. Prof. Sandoval Arroxelas entrando na avenida (sinal lateral)
;  S2 = avenida, sentido que sobe, faixa de conversao para a Sandoval
;       Arroxelas (sinal de baixo, a esquerda)
;  S3 = avenida, sentido que sobe, segue em frente (sinal de baixo, a direita)
;  S4 = avenida, sentido que desce, segue ou converte (sinal de cima)
;  P  = as duas faixas de pedestre sobre a avenida (abrem juntas quando S3 e
;       S4 fecham; tratadas como um unico sinal de duas cores)
;==============================================================================

.include "m328Pdef.inc"

;------------------------------------------------------------------------------
; CONSTANTES
;------------------------------------------------------------------------------
.equ F_CPU        = 16000000          ; clock do Uno

; Chave de simulacao:
;   1 = depuracao no simulador do Microchip Studio (tempos encurtados, senao
;       cada "segundo" da maquina leva minutos de relogio para simular)
;   0 = versao final, para o SimulIDE e para a protoboard
; LEMBRE DE DEIXAR EM 0 ANTES DE GERAR O .HEX FINAL.
.equ SIMULACAO    = 0

.if SIMULACAO
.equ UBRR_VAL     = 0                 ; 62500 bps: strings saem em poucos ciclos
.equ OCR1A_VAL    = 624               ; interrupcao a cada 10 ms em vez de 1 s
.else
.equ BAUD         = 9600              ; velocidade da serial
.equ UBRR_VAL     = (F_CPU/16/BAUD)-1 ; = 103 para 9600 bps (ver datasheet)
; Timer1 em CTC com prescaler 256:
;   16.000.000 / 256 = 62.500 contagens por segundo
;   OCR1A = 62.500 - 1 = 62.499  ->  uma interrupcao por segundo
.equ OCR1A_VAL    = 62499
.endif

; Timer0 em CTC com prescaler 1024 (varredura dos displays):
;   16.000.000 / 1024 = 15.625 contagens por segundo
;   OCR0A = 78 - 1 = 77  ->  uma interrupcao a cada 78/15625 = 5 ms
.equ OCR0A_VAL    = 77

.equ NUM_ESTADOS  = 7                 ; quantidade de linhas da tabela
.equ TAM_ESTADO   = 4                 ; bytes por linha (dur, byteD, byteB, 0)

; ---- Bits dos LEDs em PORTD (D2..D7) ----
.equ S1_VM = (1<<2)
.equ S1_AM = (1<<3)
.equ S1_VD = (1<<4)
.equ S2_VM = (1<<5)
.equ S2_AM = (1<<6)
.equ S2_VD = (1<<7)
.equ MASK_D = 0b11111100              ; bits de PORTD usados pelos LEDs

; ---- Bits dos LEDs em PORTB (D8..D13) ----
.equ S3_VM = (1<<0)
.equ S3_AM = (1<<1)
.equ S4_AM = (1<<1)                   ; mesmo pino do S3_AM (ver cabecalho)
.equ S3_VD = (1<<2)
.equ S4_VM = (1<<3)
.equ S4_VD = (1<<4)
.equ P_VM  = (1<<5)                   ; D13 = 1 -> LED vermelho do pedestre
.equ P_VD  = 0                        ; D13 = 0 -> LED verde do pedestre
.equ MASK_B = 0b00111111              ; bits de PORTB usados pelos LEDs

; ---- Pinos de selecao dos displays em PORTC ----
.equ SEL_DEZ = (1<<PC5)               ; A5: liga o display das dezenas
.equ SEL_UNI = (1<<PC4)               ; A4: liga o display das unidades

;------------------------------------------------------------------------------
; REGISTRADORES COM NOME
;------------------------------------------------------------------------------
.def tmp    = r16   ; temporario de uso geral
.def tmp2   = r17   ; segundo temporario
.def estado = r18   ; indice do estado atual (0..NUM_ESTADOS-1)
.def seg    = r19   ; segundos restantes no estado atual
.def ledsD  = r20   ; bits dos LEDs para PORTD
.def ledsB  = r21   ; bits dos LEDs para PORTB
.def zero   = r22   ; registrador sempre com valor 0 (usado em adc)
.def dez    = r23   ; digito das dezenas (0..9) para o display
.def uni    = r24   ; digito das unidades (0..9) para o display
.def mux    = r25   ; qual display esta aceso: 0 = dezenas, 1 = unidades

;------------------------------------------------------------------------------
; VARIAVEIS NA SRAM
;------------------------------------------------------------------------------
.dseg
tx_ptr: .byte 2     ; ponteiro (endereco em flash) do proximo caractere a enviar

;------------------------------------------------------------------------------
; VETORES DE INTERRUPCAO
;------------------------------------------------------------------------------
.cseg
.org 0x0000
    rjmp reset                  ; vetor de reset

.org OC1Aaddr
    rjmp isr_timer1             ; Timer1 Compare Match A -> a cada 1 s

.org OC0Aaddr
    rjmp isr_timer0             ; Timer0 Compare Match A -> a cada 5 ms

.org UDREaddr
    rjmp isr_udre               ; USART Data Register Empty -> proximo char

.org INT_VECTORS_SIZE           ; o codigo comeca depois da tabela de vetores

;==============================================================================
; RESET / INICIALIZACAO
;==============================================================================
reset:
    ; ---- pilha ----------------------------------------------------------
    ldi  tmp, high(RAMEND)
    out  SPH, tmp
    ldi  tmp, low(RAMEND)
    out  SPL, tmp

    clr  zero                   ; registrador zero = 0
    clr  mux                    ; comeca mostrando as dezenas

    ; ---- portas ---------------------------------------------------------
    ldi  tmp, MASK_D            ; PD2..PD7 -> LEDs (PD0/PD1 ficam com a USART)
    out  DDRD, tmp
    ldi  tmp, MASK_B            ; PB0..PB5 -> LEDs
    out  DDRB, tmp
    ldi  tmp, 0x3F              ; PC0..PC3 -> BCD, PC4/PC5 -> selecao display
    out  DDRC, tmp
    out  PORTC, zero            ; displays comecam apagados

    ; ---- USART0 (9600 bps, 8 bits, sem paridade, 1 stop) ----------------
    ldi  tmp, high(UBRR_VAL)
    sts  UBRR0H, tmp
    ldi  tmp, low(UBRR_VAL)
    sts  UBRR0L, tmp
    ldi  tmp, (1<<TXEN0)        ; habilita apenas o transmissor
    sts  UCSR0B, tmp
    ldi  tmp, (1<<UCSZ01)|(1<<UCSZ00)   ; 8 bits de dados
    sts  UCSR0C, tmp

    ; ---- mensagem de abertura (enviada por polling, antes das interrupcoes)
    ldi  ZL, low(str_banner*2)
    ldi  ZH, high(str_banner*2)
    rcall envia_string_polling

    ; ---- estado inicial -------------------------------------------------
    clr  estado                 ; comeca no estado q1 (indice 0)
    rcall carrega_estado        ; le a tabela, acende LEDs, agenda serial
    rcall separa_digitos        ; prepara dezena/unidade do primeiro estado

    ; ---- Timer0: CTC, prescaler 1024, interrupcao a cada 5 ms -----------
    ; (varredura dos displays)
    ldi  tmp, (1<<WGM01)        ; modo CTC (TOP = OCR0A)
    out  TCCR0A, tmp
    ldi  tmp, OCR0A_VAL
    out  OCR0A, tmp
    ldi  tmp, (1<<CS02)|(1<<CS00)       ; prescaler 1024, liga o timer
    out  TCCR0B, tmp
    ldi  tmp, (1<<OCIE0A)       ; habilita a interrupcao de compare A
    sts  TIMSK0, tmp

    ; ---- Timer1: CTC, prescaler 256, interrupcao a cada 1 s -------------
    ; (relogio da maquina de estados)
    sts  TCCR1A, zero           ; modo normal de saida (sem PWM)
    ; Escrita de 16 bits: sempre o byte alto primeiro
    ldi  tmp, high(OCR1A_VAL)
    sts  OCR1AH, tmp
    ldi  tmp, low(OCR1A_VAL)
    sts  OCR1AL, tmp
    ldi  tmp, (1<<WGM12)|(1<<CS12)      ; WGM12 = CTC; CS12 = prescaler 256
    sts  TCCR1B, tmp
    ldi  tmp, (1<<OCIE1A)       ; habilita a interrupcao de compare A
    sts  TIMSK1, tmp

    sei                         ; habilita interrupcoes globais

;------------------------------------------------------------------------------
; LACO PRINCIPAL
; Nao ha nada para fazer aqui: timers, LEDs, displays e serial sao todos
; tratados nas rotinas de interrupcao.
;------------------------------------------------------------------------------
loop:
    rjmp loop

;==============================================================================
; ISR DO TIMER1 - executada uma vez por segundo
;==============================================================================
isr_timer1:
    ; salva os registradores que a rotina usa (e o SREG)
    push tmp
    in   tmp, SREG
    push tmp
    push tmp2
    push ZL
    push ZH

    dec  seg                    ; passou 1 segundo
    brne t1_atualiza            ; ainda ha tempo: so atualiza os digitos

    ; ---- contador chegou a zero: proximo estado -------------------------
    inc  estado
    cpi  estado, NUM_ESTADOS
    brlo t1_carrega             ; estado < NUM_ESTADOS -> ok
    clr  estado                 ; passou do ultimo -> volta ao q1
t1_carrega:
    rcall carrega_estado        ; carrega seg/LEDs e dispara a serial

t1_atualiza:
    rcall separa_digitos        ; dez/uni = segundos restantes

    ; restaura os registradores
    pop  ZH
    pop  ZL
    pop  tmp2
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

;==============================================================================
; ISR DO TIMER0 - executada a cada 5 ms (varredura dos displays)
; Alterna entre os dois displays. Em cada tique escreve em PORTC, numa unica
; operacao, o digito (bits 0..3, que vao ao decodificador BCD) junto com o
; bit de selecao do display correspondente (bit 4 ou 5). Como a escrita e
; de um byte so, nunca ha um instante em que o digito novo aparece no
; display errado.
;==============================================================================
isr_timer0:
    push tmp
    in   tmp, SREG
    push tmp

    tst  mux
    brne t0_unidades

    ; ---- tique par: dezenas ---------------------------------------------
    mov  tmp, dez
    ori  tmp, SEL_DEZ           ; digito + liga transistor das dezenas
    out  PORTC, tmp
    ldi  mux, 1                 ; proximo tique: unidades
    rjmp t0_sai

t0_unidades:
    ; ---- tique impar: unidades ------------------------------------------
    mov  tmp, uni
    ori  tmp, SEL_UNI           ; digito + liga transistor das unidades
    out  PORTC, tmp
    clr  mux                    ; proximo tique: dezenas

t0_sai:
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

;==============================================================================
; ISR DA USART (UDRE) - registrador de transmissao vazio
; Envia o proximo caractere apontado por tx_ptr. Quando encontra o 0 final,
; desabilita a propria interrupcao e para.
;==============================================================================
isr_udre:
    push tmp
    in   tmp, SREG
    push tmp
    push ZL
    push ZH

    lds  ZL, tx_ptr             ; recupera o ponteiro da string
    lds  ZH, tx_ptr+1
    lpm  tmp, Z+                ; le o caractere e avanca o ponteiro
    tst  tmp
    breq udre_fim               ; 0 = fim da string

    sts  UDR0, tmp              ; envia o caractere
    sts  tx_ptr, ZL             ; guarda o ponteiro avancado
    sts  tx_ptr+1, ZH
    rjmp udre_sai

udre_fim:
    lds  tmp, UCSR0B
    cbr  tmp, (1<<UDRIE0)       ; desliga a interrupcao UDRE
    sts  UCSR0B, tmp

udre_sai:
    pop  ZH
    pop  ZL
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

;==============================================================================
; carrega_estado
; Le a linha da tabela correspondente a "estado", carrega os segundos,
; escreve as cores nos pinos dos LEDs e inicia o envio da mensagem de status.
; Usa: tmp, tmp2, Z. Altera: seg, ledsD, ledsB.
;==============================================================================
carrega_estado:
    ; Z = endereco(tabela_estados) + estado * TAM_ESTADO
    ldi  ZL, low(tabela_estados*2)      ; *2: endereco em bytes para o lpm
    ldi  ZH, high(tabela_estados*2)
    mov  tmp, estado
    lsl  tmp                    ; x2
    lsl  tmp                    ; x4  (TAM_ESTADO = 4)
    add  ZL, tmp
    adc  ZH, zero               ; propaga o carry para o byte alto

    lpm  seg,   Z+              ; duracao do estado em segundos
    lpm  ledsD, Z+              ; bits dos LEDs de PORTD (S1, S2)
    lpm  ledsB, Z+              ; bits dos LEDs de PORTB (S3, S4, P)

    rcall atualiza_leds         ; acende os LEDs do novo estado

    ; ---- agenda a mensagem de status --------------------------------------
    ; Z = tab_strings + estado*2 -> contem o endereco da string do estado
    ldi  ZL, low(tab_strings*2)
    ldi  ZH, high(tab_strings*2)
    mov  tmp, estado
    lsl  tmp                    ; x2 (cada ponteiro tem 2 bytes)
    add  ZL, tmp
    adc  ZH, zero
    lpm  tmp,  Z+               ; byte baixo do endereco da string
    lpm  tmp2, Z                ; byte alto
    sts  tx_ptr,   tmp
    sts  tx_ptr+1, tmp2

    ; Habilita a interrupcao UDRE: como o registrador ja esta vazio, a ISR
    ; dispara imediatamente e comeca a transmitir.
    ; Obs.: o menor estado dura 4 s e a maior mensagem leva ~0,1 s a 9600 bps,
    ; entao nunca ha uma transmissao em andamento neste ponto.
    lds  tmp, UCSR0B
    sbr  tmp, (1<<UDRIE0)
    sts  UCSR0B, tmp
    ret

;==============================================================================
; atualiza_leds
; Escreve ledsD em PD2..PD7 e ledsB em PB0..PB5, preservando os demais bits
; de cada porta (PD0/PD1 sao a USART; PB6/PB7 sao o cristal).
; Usa: tmp.
;==============================================================================
atualiza_leds:
    in   tmp, PORTD
    andi tmp, 0x03              ; zera PD2..PD7, preserva PD0/PD1 (USART)
    or   tmp, ledsD
    out  PORTD, tmp

    in   tmp, PORTB
    andi tmp, 0xC0              ; zera PB0..PB5, preserva PB6/PB7 (cristal)
    or   tmp, ledsB
    out  PORTB, tmp
    ret

;==============================================================================
; separa_digitos
; Converte "seg" (0..99) em dezena e unidade, guardadas em dez/uni para a
; ISR do Timer0 mostrar nos displays.
; Usa: tmp. Altera: dez, uni.
;==============================================================================
separa_digitos:
    mov  tmp, seg               ; tmp = valor a mostrar
    clr  dez
sd_loop:
    cpi  tmp, 10
    brlo sd_pronto              ; tmp < 10 -> terminou a divisao
    subi tmp, 10                ; tmp = tmp - 10
    inc  dez                    ; dezenas++
    rjmp sd_loop
sd_pronto:
    mov  uni, tmp               ; o que sobrou e a unidade
    ret

;==============================================================================
; envia_string_polling
; Envia a string em flash apontada por Z esperando o UDRE0 por polling.
; Usada so para a mensagem de abertura, antes de habilitar as interrupcoes.
; Usa: tmp, tmp2, Z.
;==============================================================================
envia_string_polling:
esp_loop:
    lpm  tmp, Z+
    tst  tmp
    breq esp_fim                ; 0 = fim
esp_espera:
    lds  tmp2, UCSR0A
    sbrs tmp2, UDRE0            ; espera o registrador esvaziar
    rjmp esp_espera
    sts  UDR0, tmp
    rjmp esp_loop
esp_fim:
    ret

;==============================================================================
; TABELA DE ESTADOS (na flash)
; Uma linha por estado: duracao (s), bits de PORTD, bits de PORTB, 0.
; O byte final so existe para cada linha ter 4 bytes (indexacao com estado*4).
;
; Para alterar a temporizacao ou as cores, edite APENAS esta tabela e as
; strings de status abaixo. O codigo nao precisa mudar.
;
;  Estado (codigo) | S1 | S2 | S3 | S4 | P  | Duracao | Quem passa
;  ----------------+----+----+----+----+----+---------+----------------------
;    q1   (000)    | Vm | Vm | Vd | Vd | Vm |  53 s   | avenida nos 2 sentidos
;    q2   (001)    | Vm | Vm | Am | Am | Vm |   4 s   | avenida fechando
;    q3   (010)    | Vd | Vm | Vm | Vm | Vd |  39 s   | rua lateral + pedestre
;    q4   (011)    | Am | Vm | Vm | Vm | Vd |   4 s   | lateral fechando
;    q5   (100)    | Vm | Vm | Vm | Vm | Vd |  15 s   | vermelho geral: so pedestre
;    q6   (101)    | Vm | Vd | Vd | Vm | Vm |  23 s   | sobe: reto + conversao
;    q7   (110)    | Vm | Am | Vd | Vm | Vm |   4 s   | conversao fechando
;  Ciclo total: 142 s. Depois de q7 volta a q1.
;
;  Pedestre (P): fica verde de q3 a q5, enquanto S2, S3 e S4 estao vermelhos.
;  q5 e o "vermelho geral": todos os veiculos parados e so o pedestre
;  atravessa. Se no levantamento o pedestre ja estiver vermelho em q5, troque
;  P_VD por P_VM na linha de q5.
;==============================================================================
tabela_estados:
    ;   dur  PORTD (S1, S2)     PORTB (S3, S4, P)          reservado
    .db 53,  S1_VM|S2_VM,       S3_VD|S4_VD|P_VM,          0   ; q1
    .db  4,  S1_VM|S2_VM,       S3_AM|S4_AM|P_VM,          0   ; q2
    .db 39,  S1_VD|S2_VM,       S3_VM|S4_VM|P_VD,          0   ; q3
    .db  4,  S1_AM|S2_VM,       S3_VM|S4_VM|P_VD,          0   ; q4
    .db 15,  S1_VM|S2_VM,       S3_VM|S4_VM|P_VD,          0   ; q5
    .db 23,  S1_VM|S2_VD,       S3_VD|S4_VM|P_VM,          0   ; q6
    .db  4,  S1_VM|S2_AM,       S3_VD|S4_VM|P_VM,          0   ; q7

;------------------------------------------------------------------------------
; Tabela de ponteiros para as strings de status (enderecos em bytes).
; A ordem deve ser a mesma da tabela de estados.
;------------------------------------------------------------------------------
tab_strings:
    .dw str_e1*2, str_e2*2, str_e3*2, str_e4*2
    .dw str_e5*2, str_e6*2, str_e7*2

;------------------------------------------------------------------------------
; Strings (sem acentos, para o terminal serial nao mostrar lixo).
; 13,10 = CR LF (quebra de linha); 0 = terminador.
; O montador pode avisar que preencheu um byte a mais quando o tamanho
; e impar: nao tem problema, o byte extra fica depois do terminador.
;------------------------------------------------------------------------------
str_banner:
    .db "Semaforos - Av. Alvaro Otacilio x R. Prof. Sandoval Arroxelas - Maceio/AL", 13, 10, 0

str_e1: .db "q1 (53s): S1 - Vermelho; S2 - Vermelho; S3 - Verde; S4 - Verde; P - Vermelho", 13, 10, 0
str_e2: .db "q2 (4s): S1 - Vermelho; S2 - Vermelho; S3 - Amarelo; S4 - Amarelo; P - Vermelho", 13, 10, 0
str_e3: .db "q3 (39s): S1 - Verde; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e4: .db "q4 (4s): S1 - Amarelo; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e5: .db "q5 (15s): S1 - Vermelho; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e6: .db "q6 (23s): S1 - Vermelho; S2 - Verde; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0
str_e7: .db "q7 (4s): S1 - Vermelho; S2 - Amarelo; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0