;==============================================================================
;  SIMULACAO DOS SEMAFOROS DO CRUZAMENTO
;  Av. Alvaro Otacilio x Av. Prof. Sandoval Arroxelas - Ponta Verde, Maceio/AL
;
;  Placa      : Arduino Uno (ATmega328P @ 16 MHz)
;  Montador   : AVRASM2 (Microchip Studio, projeto "AVR Assembler")
;  Arquivo    : semaforo.asm
;
;------------------------------------------------------------------------------
;  ONDE CADA REQUISITO DO ENUNCIADO E ATENDIDO
;  (procure no arquivo pela etiqueta entre colchetes)
;
;  [REQUISITO 1] "Deve-se utilizar os Timers do AVR para definir os tempos"
;       Timer1 (16 bits, modo CTC) gera 1 interrupcao por segundo: e o relogio
;       da maquina de estados.  Configuracao em "reset", uso em "isr_timer1".
;       Timer0 (8 bits, modo CTC) gera 1 interrupcao a cada 5 ms: e a varredura
;       dos displays.  Configuracao em "reset", uso em "isr_timer0".
;       Nenhum atraso e feito por laco de software (nada de "delay" contando
;       instrucoes): todo tempo vem de hardware.
;
;  [REQUISITO 2] "Deve-se utilizar interrupcao ao inves de verificacao de flag"
;       O programa tem 3 rotinas de interrupcao (Timer1, Timer0 e USART UDRE)
;       e o laco principal e literalmente "rjmp loop", sem nada dentro.
;       Nao existe no arquivo nenhum laco do tipo "le o flag e volta se ainda
;       nao mudou" (sbic/sbis/sbrs seguido de rjmp para tras).  Ate a saida da
;       mensagem inicial pela serial passa pela interrupcao UDRE, usando a
;       fila "tx_next".
;
;  [REQUISITO 3] "Apresentar o contador de um dos semaforos usando displays de
;                 7seg. Pode utilizar o CI BCD."
;       Um unico decodificador BCD (CD4511 na protoboard / "BCD to 7S" no
;       SimulIDE) recebe 4 bits em PC0..PC3 e aciona os dois displays, que sao
;       multiplexados por "isr_timer0".  O valor exibido e "seg", os segundos
;       que faltam para o estado atual terminar - o mesmo numero que um
;       semaforo com contador mostra na rua.
;
;  [REQUISITO 4] "Enviar pela serial informacoes de status"
;       A cada mudanca de estado, "carrega_estado" agenda uma string no
;       formato do enunciado e a ISR "isr_udre" a transmite.  Exemplo:
;       "q2 (4s): S1 - Vermelho; S2 - Vermelho; S3 - Amarelo; S4 - Amarelo;
;        P - Vermelho".  Strings no fim do arquivo.
;
;  [REQUISITO 5] "Controle feito por Arduino com codigo em Assembly"
;       Arquivo inteiro em assembly AVR, sem biblioteca nem codigo em C.
;
;  [REQUISITO 6] "Os semaforos devem ser implementados com tres leds"
;       4 semaforos de veiculos (S1..S4) com vermelho, amarelo e verde cada +
;       1 sinal de pedestre (P) com vermelho e verde = 14 LEDs.  Mapa de pinos
;       na secao HARDWARE abaixo.
;
;  [REQUISITO 7] "O valor do contador deve ser implementado com dois displays"
;       Dois displays de 7 segmentos (dezena e unidade), ver [REQUISITO 3].
;
;  [REQUISITO 8] "Codigo assembly muito bem comentado"
;       Este cabecalho + um comentario em cada linha do programa.
;------------------------------------------------------------------------------
;
;  COMO O PROGRAMA FUNCIONA, EM TRES PARAGRAFOS
;
;  1) O cruzamento inteiro e modelado como UMA maquina de 7 estados (q1..q7).
;     Um estado nao e "o semaforo S1 esta verde": e a combinacao das cores dos
;     cinco sinais ao mesmo tempo, mais a duracao em segundos.  Isso garante
;     por construcao que dois fluxos conflitantes nunca ficam verdes juntos,
;     porque simplesmente nao existe linha na tabela com essa combinacao.
;     A tabela esta no fim do arquivo, em "tabela_estados", gravada na memoria
;     flash.  Para mudar a temporizacao basta editar numeros nessa tabela; o
;     codigo nao muda.
;
;  2) A unica "entrada" da maquina e o tique de 1 segundo do Timer1.  A ISR
;     desse timer decrementa o contador de segundos; quando ele chega a zero,
;     avanca para o proximo estado (voltando a q1 depois de q7), le a nova
;     linha da tabela, acende os LEDs correspondentes e manda a mensagem de
;     status pela serial.
;
;  3) Os dois displays dividem um unico decodificador BCD.  Nao da para
;     mostrar dois numeros diferentes ao mesmo tempo com um decodificador so,
;     entao a ISR do Timer0 alterna entre eles a cada 5 ms: num tique acende
;     a dezena, no tique seguinte a unidade.  Cada display pisca 100 vezes por
;     segundo, rapido demais para o olho perceber, e os dois parecem acesos.
;
;------------------------------------------------------------------------------
;  HARDWARE (os 20 pinos de I/O do Uno, todos usados)
;
;  Serial : D0/D1 (USART0) a 9600 bps, 8N1, pelo USB -> monitor serial.
;
;  Displays (2 x 7 segmentos de CATODO COMUM, 1 decodificador BCD):
;     A0..A3 (PC0..PC3) -> entradas A,B,C,D do decodificador BCD
;     saidas a..g do decodificador -> resistores de 330 ohms -> segmentos
;        a..g dos DOIS displays, em paralelo
;     A5 (PC5) -> 1 kohm -> base do transistor NPN do display das DEZENAS
;     A4 (PC4) -> 1 kohm -> base do transistor NPN do display das UNIDADES
;        (coletor de cada transistor no catodo comum do seu display,
;         emissor no GND; pino em nivel alto = aquele display aceso)
;
;  LEDs (12 pinos para 14 LEDs), cada LED com resistor de 330 ohms:
;     PORTD                          PORTB
;     D2 (PD2) S1 vermelho           D8  (PB0) S3 vermelho
;     D3 (PD3) S1 amarelo            D9  (PB1) S3 amarelo E S4 amarelo  (*)
;     D4 (PD4) S1 verde              D10 (PB2) S3 verde
;     D5 (PD5) S2 vermelho           D11 (PB3) S4 vermelho
;     D6 (PD6) S2 amarelo            D12 (PB4) S4 verde
;     D7 (PD7) S2 verde              D13 (PB5) P: 1 = vermelho, 0 = verde (**)
;
;   (*) Dois LEDs num pino so: olhando a tabela de estados, S3 e S4 ficam
;       amarelos exatamente no mesmo estado (q2) e em nenhum outro.  Logo um
;       pino pode acender os dois, cada um com seu proprio resistor.
;
;  (**) Os dois LEDs do pedestre num pino so: P e sempre vermelho OU verde,
;       nunca os dois nem nenhum.  Entao:
;          pino 13 -> 330 ohms -> LED vermelho -> GND    (acende com pino = 1)
;          5 V     -> 330 ohms -> LED verde    -> pino 13 (acende com pino = 0)
;       O LED que ja existe na placa no pino 13 acompanha o vermelho.
;
;  SIGNIFICADO DOS SINAIS (levantamento de campo no cruzamento)
;     S1 = Av. Prof. Sandoval Arroxelas entrando na avenida (sinal lateral)
;     S2 = avenida, sentido que sobe, faixa de conversao para a Sandoval
;     S3 = avenida, sentido que sobe, segue em frente
;     S4 = avenida, sentido que desce
;     P  = as duas faixas de pedestre sobre a avenida (abrem e fecham juntas,
;          por isso sao tratadas como um unico sinal)
;==============================================================================

.include "m328Pdef.inc"     ; nomes dos registradores do ATmega328P (PORTB,
                            ; TCCR1B, OCIE1A...) e dos vetores de interrupcao

;==============================================================================
; CONSTANTES
;==============================================================================
.equ F_CPU        = 16000000  ; frequencia do cristal do Uno, em Hz

; ---- Chave de modo de simulacao ---------------------------------------------
; 1 = depuracao no simulador do Microchip Studio.  O simulador e centenas de
;     vezes mais lento que o chip real; com os tempos normais, cada "segundo"
;     da maquina levaria minutos de relogio para simular.
; 0 = versao final, para o SimulIDE e para a protoboard.
; DEIXAR EM 0 ANTES DE GERAR O .HEX FINAL.
.equ SIMULACAO    = 0

.if SIMULACAO                 ; ---- bloco compilado so quando SIMULACAO = 1 --
.equ UBRR_VAL     = 0         ; 62500 bps: as strings saem em poucos ciclos
.equ OCR1A_VAL    = 624       ; "segundo" encurtado para 10 ms
.else                         ; ---- bloco compilado so quando SIMULACAO = 0 --
.equ BAUD         = 9600      ; velocidade da serial, em bits por segundo
.equ UBRR_VAL     = (F_CPU/16/BAUD)-1   ; = 103.  Formula do datasheet do
                                        ; ATmega328P para o modo assincrono
                                        ; normal: UBRR = F_CPU/(16*BAUD) - 1
; [REQUISITO 1] Conta do Timer1, que gera o segundo:
;   prescaler 256  ->  16.000.000 / 256 = 62.500 contagens por segundo
;   em modo CTC o timer zera quando chega em OCR1A, ou seja, conta
;   OCR1A + 1 vezes; para 62.500 contagens, OCR1A = 62.499.
.equ OCR1A_VAL    = 62499
.endif

; [REQUISITO 1] Conta do Timer0, que varre os displays:
;   prescaler 1024  ->  16.000.000 / 1024 = 15.625 contagens por segundo
;   queremos 5 ms = 1/200 s  ->  15.625 / 200 = 78 contagens
;   em CTC conta OCR0A + 1 vezes, logo OCR0A = 77.
.equ OCR0A_VAL    = 77

.equ NUM_ESTADOS  = 7         ; quantas linhas tem a tabela de estados
.equ TAM_ESTADO   = 4         ; bytes por linha (duracao, PORTD, PORTB, livre)

; ---- Bits dos LEDs em PORTD (pinos D2..D7) ----------------------------------
; [REQUISITO 6] cada constante e a mascara de 1 bit do LED correspondente
.equ S1_VM = (1<<2)           ; bit 2 = pino D2 = S1 vermelho
.equ S1_AM = (1<<3)           ; bit 3 = pino D3 = S1 amarelo
.equ S1_VD = (1<<4)           ; bit 4 = pino D4 = S1 verde
.equ S2_VM = (1<<5)           ; bit 5 = pino D5 = S2 vermelho
.equ S2_AM = (1<<6)           ; bit 6 = pino D6 = S2 amarelo
.equ S2_VD = (1<<7)           ; bit 7 = pino D7 = S2 verde
.equ MASK_D = 0b11111100      ; os 6 bits de PORTD usados por LEDs
                              ; (bits 0 e 1 ficam com a USART: RX e TX)

; ---- Bits dos LEDs em PORTB (pinos D8..D13) ---------------------------------
.equ S3_VM = (1<<0)           ; bit 0 = pino D8  = S3 vermelho
.equ S3_AM = (1<<1)           ; bit 1 = pino D9  = S3 amarelo
.equ S4_AM = (1<<1)           ; MESMO bit do S3_AM: os dois amarelos dividem
                              ; o pino D9 (ver nota (*) no cabecalho)
.equ S3_VD = (1<<2)           ; bit 2 = pino D10 = S3 verde
.equ S4_VM = (1<<3)           ; bit 3 = pino D11 = S4 vermelho
.equ S4_VD = (1<<4)           ; bit 4 = pino D12 = S4 verde
.equ P_VM  = (1<<5)           ; bit 5 em 1  -> pino D13 alto  -> P vermelho
.equ P_VD  = 0                ; bit 5 em 0  -> pino D13 baixo -> P verde
                              ; (vale 0 de proposito: somar 0 na tabela nao
                              ;  liga bit nenhum, e o pino fica em nivel baixo)
.equ MASK_B = 0b00111111      ; os 6 bits de PORTB usados por LEDs
                              ; (bits 6 e 7 sao os pinos do cristal)

; ---- Pinos que escolhem qual display esta aceso -----------------------------
.equ SEL_DEZ = (1<<PC5)       ; A5 em nivel alto -> liga o display das dezenas
.equ SEL_UNI = (1<<PC4)       ; A4 em nivel alto -> liga o das unidades

;==============================================================================
; REGISTRADORES COM NOME
; O ".def" so da um apelido ao registrador; nao gera instrucao nenhuma.
;==============================================================================
.def tmp    = r16   ; temporario de uso geral (r16..r31 aceitam "ldi")
.def tmp2   = r17   ; segundo temporario, quando um nao basta
.def estado = r18   ; indice do estado atual na tabela (0 = q1 ... 6 = q7)
.def seg    = r19   ; segundos que faltam para o estado atual terminar
.def ledsD  = r20   ; copia dos bits de LED que vao para PORTD
.def ledsB  = r21   ; copia dos bits de LED que vao para PORTB
.def zero   = r22   ; registrador mantido sempre em 0 (o AVR nao tem um fixo)
.def dez    = r23   ; digito das dezenas do contador (0..9)
.def uni    = r24   ; digito das unidades do contador (0..9)
.def mux    = r25   ; qual display foi aceso por ultimo: 0 = dezenas, 1 = unid.

;==============================================================================
; VARIAVEIS NA MEMORIA RAM
;==============================================================================
.dseg                         ; a partir daqui, enderecos na SRAM
tx_ptr:  .byte 2              ; endereco (na flash) do proximo caractere a
                              ; enviar pela serial.  2 bytes = ponteiro de
                              ; 16 bits
tx_next: .byte 2              ; endereco da PROXIMA string da fila; 0 = fila
                              ; vazia.  Ver "agenda_string"

;==============================================================================
; TABELA DE VETORES DE INTERRUPCAO
; Quando uma interrupcao ocorre, o processador salta automaticamente para um
; endereco fixo da flash, diferente para cada fonte.  Colocamos em cada um
; desses enderecos um salto para a nossa rotina.
; [REQUISITO 2] e aqui que as interrupcoes sao amarradas as rotinas
;==============================================================================
.cseg                         ; a partir daqui, enderecos na flash (programa)

.org 0x0000                   ; endereco 0: para onde o chip vai ao ligar
    rjmp reset                ; desvia para a inicializacao

.org OC1Aaddr                 ; vetor "Timer1 Compare Match A"
    rjmp isr_timer1           ; -> nossa rotina do tique de 1 segundo

.org OC0Aaddr                 ; vetor "Timer0 Compare Match A"
    rjmp isr_timer0           ; -> nossa rotina da varredura dos displays

.org UDREaddr                 ; vetor "USART Data Register Empty"
    rjmp isr_udre             ; -> nossa rotina que envia o proximo caractere

.org INT_VECTORS_SIZE         ; pula o resto da tabela de vetores; o programa
                              ; propriamente dito comeca depois dela

;==============================================================================
; RESET - roda uma unica vez, ao ligar ou apertar reset
;==============================================================================
reset:
    ; ---- pilha ---------------------------------------------------------
    ; A pilha guarda o endereco de retorno dos "rcall" e o que as ISRs
    ; empilham.  Ela cresce de cima para baixo, entao comeca no fim da RAM.
    ldi  tmp, high(RAMEND)    ; byte alto do ultimo endereco da RAM
    out  SPH, tmp             ; ...para a parte alta do ponteiro de pilha
    ldi  tmp, low(RAMEND)     ; byte baixo
    out  SPL, tmp             ; ...para a parte baixa

    clr  zero                 ; zera o registrador que servira de constante 0
    clr  mux                  ; comeca a varredura pelas dezenas

    ; ---- direcao dos pinos (DDR = 1 significa saida) --------------------
    ldi  tmp, MASK_D          ; 0b11111100
    out  DDRD, tmp            ; PD2..PD7 viram saidas (LEDs); PD0/PD1 ficam
                              ; como estao, para a USART usar
    ldi  tmp, MASK_B          ; 0b00111111
    out  DDRB, tmp            ; PB0..PB5 viram saidas (LEDs)
    ldi  tmp, 0x3F            ; 0b00111111
    out  DDRC, tmp            ; PC0..PC3 saidas (BCD) e PC4/PC5 saidas
                              ; (selecao dos displays)
    out  PORTC, zero          ; comeca com os dois displays apagados e o BCD
                              ; em 0

    ; ---- USART0: 9600 bps, 8 bits de dados, sem paridade, 1 stop --------
    ; [REQUISITO 4] configuracao da serial que levara o status
    ldi  tmp, high(UBRR_VAL)  ; byte alto do divisor de velocidade
    sts  UBRR0H, tmp          ; (UBRR0H/L ficam fora do alcance de "out",
    ldi  tmp, low(UBRR_VAL)   ;  por isso "sts", que aceita endereco de 16 bits)
    sts  UBRR0L, tmp          ; grava o byte baixo do divisor
    ldi  tmp, (1<<TXEN0)      ; TXEN0 = habilita o transmissor
    sts  UCSR0B, tmp          ; (o receptor nao e usado: o projeto so envia)
    ldi  tmp, (1<<UCSZ01)|(1<<UCSZ00)  ; UCSZ01:UCSZ00 = 11 -> 8 bits por quadro
    sts  UCSR0C, tmp          ; grava o formato do quadro

    ; ---- mensagem de abertura -------------------------------------------
    ; [REQUISITO 2] Mesmo o banner inicial sai por interrupcao, nao por
    ; espera de flag.  Como as interrupcoes ainda estao desligadas aqui, ele
    ; so comeca a ser transmitido no "sei" la embaixo; a linha de q1,
    ; agendada logo em seguida, fica esperando a vez em "tx_next".
    sts  tx_next,   zero      ; fila comeca vazia (byte baixo)
    sts  tx_next+1, zero      ; ...e byte alto
    ldi  tmp,  low(str_banner*2)   ; endereco do banner na flash.  O "*2" e
    ldi  tmp2, high(str_banner*2)  ; porque rotulos da flash sao contados em
                                   ; palavras de 16 bits, e "lpm" le bytes
    rcall agenda_string       ; entrega a string a serial

    ; ---- estado inicial --------------------------------------------------
    clr  estado               ; indice 0 = estado q1
    rcall carrega_estado      ; le a linha q1: tempo, LEDs e mensagem
    rcall separa_digitos      ; converte os segundos em dezena e unidade

    ; ---- Timer0: varredura dos displays, 1 interrupcao a cada 5 ms -------
    ; [REQUISITO 1] [REQUISITO 3]
    ldi  tmp, (1<<WGM01)      ; WGM01 = modo CTC: o timer conta ate OCR0A e
    out  TCCR0A, tmp          ; volta a zero sozinho
    ldi  tmp, OCR0A_VAL       ; 77
    out  OCR0A, tmp           ; valor de comparacao (o "topo" da contagem)
    ldi  tmp, (1<<CS02)|(1<<CS00)   ; CS02:CS00 = 101 -> prescaler 1024.
    out  TCCR0B, tmp          ; escrever os bits CS liga o timer
    ldi  tmp, (1<<OCIE0A)     ; OCIE0A = gera interrupcao quando TCNT0 = OCR0A
    sts  TIMSK0, tmp          ; a partir daqui o Timer0 interrompe a cada 5 ms

    ; ---- Timer1: relogio da maquina, 1 interrupcao por segundo -----------
    ; [REQUISITO 1]
    sts  TCCR1A, zero         ; nenhuma saida PWM nos pinos; modo normal
    ; OCR1A tem 16 bits e e escrito em dois acessos.  O hardware exige o byte
    ; ALTO primeiro: ele fica num registrador temporario e so e gravado junto
    ; com o baixo, para o timer nunca ver meio valor.
    ldi  tmp, high(OCR1A_VAL) ; carrega o byte alto de 62499
    sts  OCR1AH, tmp          ; byte alto primeiro
    ldi  tmp, low(OCR1A_VAL)  ; carrega o byte baixo
    sts  OCR1AL, tmp          ; byte baixo depois: agora os 16 bits valem
    ldi  tmp, (1<<WGM12)|(1<<CS12)  ; WGM12 = CTC com topo em OCR1A;
    sts  TCCR1B, tmp          ; CS12 = 100 -> prescaler 256 e liga o timer
    ldi  tmp, (1<<OCIE1A)     ; habilita a interrupcao de comparacao A
    sts  TIMSK1, tmp          ; a partir daqui o Timer1 interrompe a cada 1 s

    sei                       ; [REQUISITO 2] libera as interrupcoes globais.
                              ; A partir daqui o programa passa a ser movido
                              ; so por elas

;------------------------------------------------------------------------------
; LACO PRINCIPAL
; [REQUISITO 2] Proposital e literalmente vazio: nao ha nada para verificar.
; Tudo (tempo, LEDs, displays, serial) acontece nas tres rotinas de
; interrupcao.  Esta e a prova mais direta de que nao se usa polling.
;------------------------------------------------------------------------------
loop:
    rjmp loop                 ; fica girando aqui ate uma interrupcao ocorrer

;==============================================================================
; isr_timer1 - INTERRUPCAO DO TIMER1, uma vez por segundo
; [REQUISITO 1] [REQUISITO 2]
; Faz o tempo passar: desconta um segundo, atualiza os digitos do contador e,
; quando o tempo do estado acaba, avanca a maquina de estados.
;==============================================================================
isr_timer1:
    ; Uma ISR pode interromper o programa em qualquer ponto, entao ela tem de
    ; devolver todos os registradores que usar exatamente como estavam.
    push tmp                  ; salva tmp
    in   tmp, SREG            ; le o registrador de status (flags Z, C, N...)
    push tmp                  ; salva o SREG tambem: um "dec" aqui dentro
                              ; mudaria o flag Z que o programa interrompido
                              ; talvez fosse testar
    push tmp2                 ; salva tmp2
    push ZL                   ; salva o ponteiro Z (usado por carrega_estado)
    push ZH                   ; ...nas suas duas metades

    dec  seg                  ; passou 1 segundo: um a menos no estado atual
    brne t1_atualiza          ; se nao chegou a zero, so atualiza o display

    ; ---- o tempo do estado acabou: proximo estado ------------------------
    inc  estado               ; avanca o indice
    cpi  estado, NUM_ESTADOS  ; passou do ultimo estado (q7)?
    brlo t1_carrega           ; nao: segue com o indice novo
    clr  estado               ; sim: o ciclo reinicia em q1
t1_carrega:
    rcall carrega_estado      ; le a nova linha: tempo, LEDs e mensagem serial

t1_atualiza:
    rcall separa_digitos      ; dez/uni passam a valer o novo "seg"

    pop  ZH                   ; devolve os registradores na ordem inversa
    pop  ZL                   ; da que foram empilhados
    pop  tmp2                 ; segundo temporario
    pop  tmp                  ; este e o SREG salvo la em cima
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  ; e finalmente o tmp original
    reti                      ; "return from interrupt": volta e reabilita
                              ; as interrupcoes

;==============================================================================
; isr_timer0 - INTERRUPCAO DO TIMER0, a cada 5 ms
; [REQUISITO 1] [REQUISITO 3] [REQUISITO 7]
; Multiplexacao: com um unico decodificador BCD para dois displays, so da para
; mostrar um digito de cada vez.  Esta rotina alterna entre eles tao depressa
; que os dois parecem acesos ao mesmo tempo (100 atualizacoes por segundo em
; cada um).
;
; Detalhe importante: o digito (bits 0..3) e o bit que liga o display (4 ou 5)
; sao escritos em PORTC numa UNICA instrucao "out".  Se fossem duas escritas,
; existiria um instante em que o digito novo estaria no display velho, e
; apareceria um numero fantasma.
;==============================================================================
isr_timer0:
    push tmp                  ; salva tmp
    in   tmp, SREG            ; le os flags
    push tmp                  ; e salva tambem

    tst  mux                  ; mux vale 0 ou 1?
    brne t0_unidades          ; se for 1, e a vez das unidades

    ; ---- vez das dezenas -------------------------------------------------
    mov  tmp, dez             ; tmp = digito das dezenas (0..9, cabe em 4 bits)
    ori  tmp, SEL_DEZ         ; acrescenta o bit que liga o display da dezena
    out  PORTC, tmp           ; escrita unica: BCD + selecao
                              ; (o display das unidades apaga, pois PC4 = 0)
    ldi  mux, 1               ; marca que o proximo tique e das unidades
    rjmp t0_sai               ; pula o trecho das unidades

t0_unidades:
    ; ---- vez das unidades ------------------------------------------------
    mov  tmp, uni             ; tmp = digito das unidades
    ori  tmp, SEL_UNI         ; acrescenta o bit que liga o display da unidade
    out  PORTC, tmp           ; escrita unica: BCD + selecao
    clr  mux                  ; proximo tique volta a ser das dezenas

t0_sai:
    pop  tmp                  ; recupera o SREG salvo
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  ; restaura tmp
    reti                      ; volta

;==============================================================================
; isr_udre - INTERRUPCAO DA USART, "registrador de transmissao vazio"
; [REQUISITO 2] [REQUISITO 4]
; O hardware chama esta rotina sempre que esta pronto para receber mais um
; caractere.  Ela envia o proximo byte da string e volta; assim a mensagem
; inteira sai sem que o programa principal espere por nada.
;==============================================================================
isr_udre:
    push tmp                  ; salva tmp
    in   tmp, SREG            ; le os flags
    push tmp                  ; e salva o SREG tambem
    push ZL                   ; salva o ponteiro Z, que esta rotina usa
    push ZH                   ; ...nas suas duas metades

    lds  ZL, tx_ptr           ; Z = endereco do proximo caractere
    lds  ZH, tx_ptr+1         ; ...byte alto do ponteiro
    lpm  tmp, Z+              ; le o caractere da flash e ja avanca Z
    tst  tmp                  ; o caractere e 0?
    breq udre_fim             ; 0 marca o fim da string

    sts  UDR0, tmp            ; escreve no registrador de dados: o hardware
                              ; transmite esse byte bit a bit
    sts  tx_ptr,   ZL         ; guarda o ponteiro ja avancado para a proxima
    sts  tx_ptr+1, ZH         ; chamada desta ISR
    rjmp udre_sai             ; termina por aqui

udre_fim:
    ; A string acabou.  Existe outra esperando na fila?
    lds  ZL, tx_next          ; le o endereco guardado na fila
    lds  ZH, tx_next+1        ; ...byte alto
    mov  tmp, ZL              ; para testar se os 16 bits sao zero,
    or   tmp, ZH              ; basta ver se o OU dos dois bytes e zero
    breq udre_vazio           ; zero = fila vazia, nada mais a enviar

    sts  tx_ptr,   ZL         ; ha outra: ela passa a ser a string atual
    sts  tx_ptr+1, ZH         ; ...byte alto
    sts  tx_next,   zero      ; e a fila fica vazia de novo
    sts  tx_next+1, zero      ; ...byte alto
    rjmp udre_sai             ; UDRIE0 continua ligada, entao a proxima
                              ; interrupcao ja envia o 1o caractere dela

udre_vazio:
    lds  tmp, UCSR0B          ; nada mais a enviar:
    cbr  tmp, (1<<UDRIE0)     ; desliga a interrupcao UDRE, senao ela ficaria
    sts  UCSR0B, tmp          ; disparando sem parar (o registrador esta vazio
                              ; o tempo todo)

udre_sai:
    pop  ZH                   ; restaura tudo na ordem inversa
    pop  ZL                   ; ponteiro Z
    pop  tmp                  ; SREG salvo
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  ; tmp original
    reti                      ; volta ao ponto interrompido

;==============================================================================
; carrega_estado
; Le da tabela a linha do estado atual e aplica tudo que ela define:
; o tempo, as cores dos LEDs e a mensagem de status.
; Entrada : "estado" = indice (0..6)
; Altera  : seg, ledsD, ledsB, tmp, tmp2, Z
;==============================================================================
carrega_estado:
    ; ---- calcula o endereco da linha: base + indice * 4 ------------------
    ldi  ZL, low(tabela_estados*2)   ; Z aponta para o inicio da tabela.
    ldi  ZH, high(tabela_estados*2)  ; "*2" converte palavras em bytes, que e
                                     ; como "lpm" enderaca a flash
    mov  tmp, estado          ; tmp = indice do estado
    lsl  tmp                  ; desloca 1 bit a esquerda = multiplica por 2
    lsl  tmp                  ; de novo = multiplica por 4 (TAM_ESTADO)
    add  ZL, tmp              ; soma o deslocamento ao byte baixo de Z
    adc  ZH, zero             ; e propaga o "vai um" para o byte alto
                              ; (adc soma o carry; por isso zero existe)

    ; ---- le os tres bytes uteis da linha ---------------------------------
    lpm  seg,   Z+            ; byte 1: duracao do estado, em segundos
    lpm  ledsD, Z+            ; byte 2: bits dos LEDs de PORTD (S1 e S2)
    lpm  ledsB, Z+            ; byte 3: bits dos LEDs de PORTB (S3, S4 e P)
                              ; (o byte 4 existe so para a linha ter 4 bytes)

    rcall atualiza_leds       ; [REQUISITO 6] acende as cores deste estado

    ; ---- escolhe a mensagem de status deste estado -----------------------
    ; [REQUISITO 4] "tab_strings" e um vetor de ponteiros: na posicao do
    ; estado esta o endereco da string correspondente.
    ldi  ZL, low(tab_strings*2)    ; Z aponta para o inicio do vetor
    ldi  ZH, high(tab_strings*2)   ; ...byte alto do endereco
    mov  tmp, estado          ; indice do estado
    lsl  tmp                  ; x2, porque cada ponteiro ocupa 2 bytes
    add  ZL, tmp              ; soma ao endereco base
    adc  ZH, zero             ; propaga o carry
    lpm  tmp,  Z+             ; byte baixo do endereco da string
    lpm  tmp2, Z              ; byte alto
    rcall agenda_string       ; entrega essa string a serial
    ret                       ; volta para quem chamou (reset ou isr_timer1)

;==============================================================================
; agenda_string
; [REQUISITO 2] [REQUISITO 4]
; Entrada: tmp:tmp2 = endereco (em bytes, na flash) de uma string terminada
;          em 0.
; Se a serial estiver parada, torna essa string a atual e liga a interrupcao
; UDRE, que entao envia tudo sozinha.  Se ainda houver uma transmissao em
; andamento, guarda o endereco em "tx_next" e a ISR pega quando terminar.
; Na pratica a fila so e usada na partida (banner + linha de q1); depois disso
; o estado mais curto dura 4 s e a maior mensagem leva cerca de 0,09 s a
; 9600 bps, entao nunca ha sobreposicao.
; Altera: ZL (usado como temporario), tmp, tmp2 preservados
;==============================================================================
agenda_string:
    lds  ZL, UCSR0B           ; le a configuracao atual da USART
    sbrc ZL, UDRIE0           ; a interrupcao UDRE esta ligada?
                              ; "sbrc" = pula a proxima instrucao se o bit = 0
    rjmp ag_fila              ; bit = 1: ha transmissao em curso -> vai p/ fila

    sts  tx_ptr,   tmp        ; serial livre: esta string vira a atual
    sts  tx_ptr+1, tmp2       ; ...byte alto do ponteiro
    sbr  ZL, (1<<UDRIE0)      ; liga a interrupcao "registrador vazio"
    sts  UCSR0B, ZL           ; como ele ja esta vazio, a ISR dispara em
                              ; seguida e comeca a enviar
    ret                       ; volta; o envio segue sozinho, por interrupcao

ag_fila:
    sts  tx_next,   tmp       ; ocupada: a string espera a vez na fila
    sts  tx_next+1, tmp2      ; ...byte alto do ponteiro
    ret                       ; a ISR a pegara quando terminar a atual

;==============================================================================
; atualiza_leds
; [REQUISITO 6]
; Escreve os bits de cor nos pinos, preservando os pinos que nao sao LEDs.
; Entrada: ledsD (bits para PORTD), ledsB (bits para PORTB)
; Altera : tmp
;==============================================================================
atualiza_leds:
    in   tmp, PORTD           ; le o estado atual da porta D
    andi tmp, 0x03            ; zera PD2..PD7 (os LEDs) e mantem PD0/PD1,
                              ; que pertencem a USART e nao podem ser mexidos
    or   tmp, ledsD           ; acrescenta os bits das cores deste estado
    out  PORTD, tmp           ; escreve: os LEDs de S1 e S2 mudam juntos

    in   tmp, PORTB           ; mesma ideia na porta B
    andi tmp, 0xC0            ; zera PB0..PB5 e mantem PB6/PB7 (cristal)
    or   tmp, ledsB           ; acrescenta as cores de S3, S4 e P
    out  PORTB, tmp           ; escreve
    ret                       ; o estado ja esta visivel nos 14 LEDs

;==============================================================================
; separa_digitos
; [REQUISITO 3] [REQUISITO 7]
; Converte "seg" (0..99) nos dois digitos decimais que os displays mostram.
; O AVR nao tem instrucao de divisao, entao a conta e feita por subtracoes
; sucessivas: quantas vezes da para tirar 10 e quanto sobra.
; Entrada: seg.  Saida: dez, uni.  Altera: tmp
;==============================================================================
separa_digitos:
    mov  tmp, seg             ; copia o valor, para nao destruir "seg"
    clr  dez                  ; comeca com zero dezenas
sd_loop:
    cpi  tmp, 10              ; ainda da para tirar 10?
    brlo sd_pronto            ; menor que 10: acabou, o que sobrou e a unidade
    subi tmp, 10              ; tira 10
    inc  dez                  ; e conta mais uma dezena
    rjmp sd_loop              ; repete
sd_pronto:
    mov  uni, tmp             ; o resto (0..9) e o digito das unidades
    ret                       ; dez e uni sao lidos pela ISR do Timer0

;==============================================================================
; TABELA DE ESTADOS (gravada na memoria flash)
;
; Esta tabela E a maquina de estados: o codigo acima e generico e nao sabe
; nada sobre semaforos.  Para mudar tempos ou cores, edita-se apenas esta
; tabela (e as strings logo abaixo).
;
; Cada linha tem 4 bytes:
;   1) duracao do estado, em segundos
;   2) bits dos LEDs de PORTD  (S1 e S2)
;   3) bits dos LEDs de PORTB  (S3, S4 e P)
;   4) byte reservado, so para a linha ter 4 bytes e o calculo do endereco
;      ser um deslocamento de 2 bits ("lsl" duas vezes em carrega_estado)
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
;  Ciclo total: 142 s.  Depois de q7 o ciclo recomeca em q1.
;
; Tres regras que a tabela respeita, e que valem citar na apresentacao:
;   - nenhum sinal passa de verde direto para vermelho: sempre ha amarelo;
;   - o pedestre so fica verde quando S2, S3 e S4 estao vermelhos, porque as
;     duas faixas atravessam a avenida;
;   - todo amarelo dura 4 s, medidos no estudo de campo.
;==============================================================================
tabela_estados:
    ;   dur  PORTD (S1, S2)     PORTB (S3, S4, P)       reserva
    .db 53,  S1_VM|S2_VM,       S3_VD|S4_VD|P_VM,       0   ; q1
    .db  4,  S1_VM|S2_VM,       S3_AM|S4_AM|P_VM,       0   ; q2 (um bit so
                                                            ;     acende os
                                                            ;     dois amarelos)
    .db 39,  S1_VD|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q3
    .db  4,  S1_AM|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q4
    .db 15,  S1_VM|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q5
    .db 23,  S1_VM|S2_VD,       S3_VD|S4_VM|P_VM,       0   ; q6
    .db  4,  S1_VM|S2_AM,       S3_VD|S4_VM|P_VM,       0   ; q7

;------------------------------------------------------------------------------
; Vetor de ponteiros para as mensagens de status.
; ".dw" grava palavras de 16 bits; cada uma e o endereco (em bytes) de uma
; string.  A ordem tem de ser a mesma da tabela de estados.
;------------------------------------------------------------------------------
tab_strings:
    .dw str_e1*2, str_e2*2, str_e3*2, str_e4*2
    .dw str_e5*2, str_e6*2, str_e7*2

;------------------------------------------------------------------------------
; MENSAGENS DE STATUS - [REQUISITO 4]
; Formato pedido no enunciado: "Semaforo 1 - Amarelo; Semaforo 2 - Verde; ..."
; Escritas sem acentos, porque o terminal serial nem sempre interpreta UTF-8.
; Os numeros 13 e 10 sao CR e LF (fim de linha); o 0 final marca o fim da
; string para a ISR da serial.
; O montador pode avisar que preencheu um byte a mais nas strings de tamanho
; impar; isso e normal e nao atrapalha, pois o byte extra fica depois do 0.
;------------------------------------------------------------------------------
str_banner:
    .db "Semaforos - Av. Alvaro Otacilio x Av. Prof. Sandoval Arroxelas - Maceio/AL", 13, 10, 0

str_e1: .db "q1 (53s): S1 - Vermelho; S2 - Vermelho; S3 - Verde; S4 - Verde; P - Vermelho", 13, 10, 0
str_e2: .db "q2 (4s): S1 - Vermelho; S2 - Vermelho; S3 - Amarelo; S4 - Amarelo; P - Vermelho", 13, 10, 0
str_e3: .db "q3 (39s): S1 - Verde; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e4: .db "q4 (4s): S1 - Amarelo; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e5: .db "q5 (15s): S1 - Vermelho; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e6: .db "q6 (23s): S1 - Vermelho; S2 - Verde; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0
str_e7: .db "q7 (4s): S1 - Vermelho; S2 - Amarelo; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0