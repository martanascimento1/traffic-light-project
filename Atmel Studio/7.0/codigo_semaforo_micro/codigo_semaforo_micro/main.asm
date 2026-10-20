;  SIMULACAO DOS SEMAFOROS DO CRUZAMENTO - Av. Alvaro Otacilio x Av. Prof. Sandoval Arroxelas - Ponta Verde, Maceio/AL
;		Mapeamento dos sinais:
;     S1 = Av. Prof. Sandoval Arroxelas entrando na avenida (sinal lateral)
;     S2 = avenida, sentido que sobe, faixa de conversao para a Sandoval
;     S3 = avenida, sentido que sobe, segue em frente
;     S4 = avenida, sentido que desce
;     P  = as duas faixas de pedestre sobre a avenida (abrem e fecham juntas,
;          por isso aqui tratamos como um unico sinal)

.include "m328Pdef.inc"   

; Definicao de constantes e equacoes de tempo: 
.equ F_CPU        = 16000000  ; Frequencia do oscilador (16 MHz)

;  Chaves para o modo de simulacao:
; 1 = depuracao no simulador do Microchip Studio.  
; 0 = versao final,usada  para o SimulIDE e para quando trabalharmos no protoboard.
.equ SIMULACAO    = 0
.if SIMULACAO                ; so e compilado quando SIMULACAO = 1 
.equ UBRR_VAL     = 0        ; 62500 bps: as strings saem em poucos ciclos
.equ OCR1A_VAL    = 624      ; "segundo" encurtado para 10 ms
.else                        ; so e compilado quando SIMULACAO = 0
.equ BAUD         = 9600     ; velocidade da porta serial em bps
.equ UBRR_VAL     = (F_CPU/16/BAUD)-1   ; Calculo do registrador de baud rate (= 103)                            
;   Conta do Timer1, que gera o segundo:
;   prescaler 256  ->  16.000.000 / 256 = 62.500 contagens por segundo
;   em modo CTC o timer zera quando chega em OCR1A, ou seja, conta
;   OCR1A + 1 vezes; para 62.500 contagens, temos OCR1A = 62.499.
.equ OCR1A_VAL    = 62499 ; Comparador para o Timer1 (1 segundo)
.endif

;   Conta do Timer0, que varre os displays (5ms para a Multiplexacao):
;   prescaler 1024  ->  16.000.000 / 1024 = 15.625 contagens por segundo
;   queremos 5 ms = 1/200 s  ->  15.625 / 200 = 78 contagens
;   em CTC conta OCR0A + 1 vezes, logo temos OCR0A = 77.
.equ OCR0A_VAL    = 77 ; Comparador para o Timer0 (5 ms)

.equ NUM_ESTADOS  = 7         ; numero de  linhas da tabela de estados
.equ TAM_ESTADO   = 4         ; quantidade de bytes por linha (duracao, PORTD, PORTB, livre)

; Bits dos LEDs em PORTD (pinos D2..D7)
.equ S1_VM = (1<<2)           ; bit 2 = pino D2 = S1 vermelho
.equ S1_AM = (1<<3)           ; bit 3 = pino D3 = S1 amarelo
.equ S1_VD = (1<<4)           ; bit 4 = pino D4 = S1 verde
.equ S2_VM = (1<<5)           ; bit 5 = pino D5 = S2 vermelho
.equ S2_AM = (1<<6)           ; bit 6 = pino D6 = S2 amarelo
.equ S2_VD = (1<<7)           ; bit 7 = pino D7 = S2 verde
.equ MASK_D = 0b11111100      ; os 6 bits de PORTD usados por LEDs  (bits 0 e 1 ficam com a USART: RX e TX)

; Bits dos LEDs em PORTB (pinos D8..D13)
.equ S3_VM = (1<<0)           ; bit 0 = pino D8  = S3 vermelho
.equ S3_AM = (1<<1)           ; bit 1 = pino D9  = S3 amarelo
.equ S4_AM = (1<<1)           ; MESMO bit do S3_AM: os dois amarelos dividem o mesmo
                              ; o pino D9 (olhando a tabela de estados, percebemos que S3 e S4 ficam amarelos exatamente no mesmo estado (q2) e em nenhum outro. 
;     Logo um  pino pode acender os dois, cada um com seu proprio resistor.)
.equ S3_VD = (1<<2)           ; bit 2 = pino D10 = S3 verde
.equ S4_VM = (1<<3)           ; bit 3 = pino D11 = S4 vermelho
.equ S4_VD = (1<<4)           ; bit 4 = pino D12 = S4 verde
.equ P_VM  = (1<<5)           ; bit 5 em 1  -> pino D13 alto  -> P vermelho
.equ P_VD  = 0                ; bit 5 em 0  -> pino D13 baixo -> P verde
                              ; (vale 0 de proposito: somar 0 na tabela nao
                              ;  liga bit nenhum, e o pino fica em nivel baixo)
.equ MASK_B = 0b00111111      ; os 6 bits de PORTB usados por LEDs
                              ; (bits 6 e 7 sao os pinos do cristal)

;  Pinos que selecionam qual display esta aceso
.equ SEL_DEZ = (1<<PC5)       ; A5 em nivel alto -> liga o display das dezenas
.equ SEL_UNI = (1<<PC4)       ; A4 em nivel alto -> liga o das unidades

; REGISTRADORES 
.def tmp    = r16   ; temporario de uso geral 
.def tmp2   = r17   ; segundo temporario, quando somente um nao for suficiente
.def estado = r18   ; indice do estado atual na tabela (onde 0 = q1 e 6 = q7)
.def seg    = r19   ; segundos que faltam para o estado atual terminar
.def ledsD  = r20   ; copia dos bits de LED que vao para PORTD
.def ledsB  = r21   ; copia dos bits de LED que vao para PORTB
.def zero   = r22   ; registrador mantido sempre em 0 (o AVR nao tem um fixo)
.def dez    = r23   ; digito das dezenas do contador (0..9)
.def uni    = r24   ; digito das unidades do contador (0..9)
.def mux    = r25   ; indica qual display foi aceso por ultimo: 0 = dezenas, 1 = unid.


; VARIAVEIS NA MEMORIA RAM
.dseg                        
tx_ptr:  .byte 2              ; endereco (na memoria flash) do proximo caractere a enviar pela serial.  2 bytes = ponteiro de 16 bits
tx_next: .byte 2              ; endereco da proxima string da fila; 0 = fila vazia.

; TABELA DE VETORES DE INTERRUPCAO
; Quando uma interrupcao ocorre, o processador salta automaticamente para um
; endereco fixo da flash, diferente para cada fonte. Colocamos em cada um
; desses enderecos um salto para a nossa rotina.

.cseg                         

.org 0x0000                   ; endereco 0: para onde o chip vai ao ligar
    rjmp reset                ; desvia para a inicializacao

.org OC1Aaddr                 ; Interrupcao do Timer1 (Compare Match A)
    rjmp isr_timer1           ; -> nossa rotina do tique de 1 segundo

.org OC0Aaddr                 ; Interrupcao do Timer0 (Compare Match A)
    rjmp isr_timer0           ; -> nossa rotina da varredura dos displays

.org UDREaddr                 ; Interrupcao da USART (Registrador de dados vazio)
    rjmp isr_udre             ; -> nossa rotina que envia o proximo caractere

.org INT_VECTORS_SIZE         ; pula o resto da tabela de vetores; 

reset:
    ; A pilha guarda o endereco de retorno dos "rcall" no topo da RAM e o que as ISRs empilham. 
    ldi  tmp, high(RAMEND)    ; byte alto do ultimo endereco da RAM para a parte alta do ponteiro de pilha
    out  SPH, tmp             
    ldi  tmp, low(RAMEND)     ; byte baixo para a parte baixa
    out  SPL, tmp             

    clr  zero                 ; zera o registrador que servira de constante 0
    clr  mux                  ; comeca a varredura pelas dezenas

    ; direcao dos pinos (DDR = 1 significa saida)
    ldi  tmp, MASK_D          ; 0b11111100
    out  DDRD, tmp            ; pinos PD2..PD7 viram saidas (LEDs); PD0/PD1 ficam como estao, para a USART usar
    ldi  tmp, MASK_B          ; 0b00111111
    out  DDRB, tmp            ; pinos PB0..PB5 viram saidas (LEDs)
    ldi  tmp, 0x3F            ; 0b00111111
    out  DDRC, tmp            ; pinos PC0..PC3 viram saidas (BCD) e PC4/PC5 saidas  (selecao dos displays)
                              
    out  PORTC, zero          ; comeca com os dois displays apagados e o BCD em 0

    ;  Inicializa o hardware da USART gravando o valor UBRR_VAL nos registradores UBRR0H/L e habilitando a transmissao (TXEN0) no formato 8N1. 
    ldi  tmp, high(UBRR_VAL)  ; byte alto do divisor de velocidade
    sts  UBRR0H, tmp          ; (UBRR0H/L ficam fora do alcance de "out",
    ldi  tmp, low(UBRR_VAL)   ;  por isso "sts", que aceita endereco de 16 bits)
    sts  UBRR0L, tmp          ; grava o byte baixo do divisor
    ldi  tmp, (1<<TXEN0)      ; TXEN0 = habilita o transmissor
    sts  UCSR0B, tmp          
    ldi  tmp, (1<<UCSZ01)|(1<<UCSZ00)  ; UCSZ01:UCSZ00 = 11 -> 8 bits por quadro
    sts  UCSR0C, tmp          ; grava o formato do quadro


    sts  tx_next,   zero		   ; fila comeca vazia (byte baixo)
    sts  tx_next+1, zero		   ; byte alto
    ldi  tmp,  low(str_banner*2)   ; endereco do banner na flash.  O "*2" e porque rotulos da flash sao contados em palavras de 16 bits, e "lpm" le bytes
    ldi  tmp2, high(str_banner*2)  
    rcall agenda_string       ; entrega a string a serial

    ; estado inicial
    clr  estado               ; indice 0 = estado q1
    rcall carrega_estado      ; le a linha q1: tempo, LEDs e mensagem
    rcall separa_digitos      ; converte os segundos em dezena e unidade

    ; Timer0: varredura dos displays, 1 interrupcao a cada 5 ms
    ldi  tmp, (1<<WGM01)      ; WGM01 = modo CTC: o timer conta ate OCR0A e volta a zero sozinho
    out  TCCR0A, tmp          
    ldi  tmp, OCR0A_VAL       
    out  OCR0A, tmp           ; valor de comparacao (o topo da contagem)
    ldi  tmp, (1<<CS02)|(1<<CS00)   ; CS02:CS00 = 101 -> prescaler 1024.
    out  TCCR0B, tmp          ; escrever os bits CS liga o timer OCIE0A = gera interrupcao quando TCNT0 = OCR0A
    ldi  tmp, (1<<OCIE0A)     ; a partir daqui o Timer0 interrompe a cada 5 ms
    sts  TIMSK0, tmp          

    ; Timer1: relogio da maquina, 1 interrupcao por segundo
    sts  TCCR1A, zero         ; nenhuma saida PWM nos pinos; modo normal
    ; OCR1A tem 16 bits e e escrito em dois acessos.  O hardware exige o byte
    ; ALTO primeiro: ele fica num registrador temporario e so e gravado junto com o baixo, para o timer nunca ver meio valor.
    ldi  tmp, high(OCR1A_VAL) ; carrega o byte alto de 62499
    sts  OCR1AH, tmp          ; byte alto primeiro
    ldi  tmp, low(OCR1A_VAL)  ; carrega o byte baixo
    sts  OCR1AL, tmp          ; byte baixo depois: agora os 16 bits valem
    ldi  tmp, (1<<WGM12)|(1<<CS12)  ; WGM12 = CTC com topo em OCR1A;
    sts  TCCR1B, tmp          ; CS12 = 100 -> prescaler 256 e liga o timer
    ldi  tmp, (1<<OCIE1A)     ; habilita a interrupcao de comparacao A
    sts  TIMSK1, tmp          ; a partir daqui o Timer1 interrompe a cada 1 s

    sei                       ;liga o bit I do registrador de status e libera as interrupcoes globais, a partir daqui o programa passa a ser movido so por elas

loop:
    rjmp loop                 ; fica girando aqui ate uma interrupcao ocorrer, e um salto para si mesmo, nao fica lendo bit e voltando atras pra checar de novo

; Rotina isr_timer1 - INTERRUPCAO DO TIMER1, uma vez por segundo
isr_timer1:
    ; A cada segundo, reduz a contagem regressiva. Ao alcancar 0, avanca para o proximo estado da FSM,
	; atualiza os registradores de saida dos LEDs e agenda a nova mensagem serial. 
    push tmp                  ; salva contexto
    in   tmp, SREG            ; le o registrador de status (guarda as flags Z, C, N...)
    push tmp                  
    push tmp2                 ; salva tmp2
    push ZL                   ; salva o ponteiro Z (usado por carrega_estado) nas suas duas metades
    push ZH                   
    dec  seg                  ; Decrementa o tempo restante do estado
    brne t1_atualiza          ; Se ainda nao eh zero, apenas atualiza o display
    inc  estado               ; Se zerou, passa para o proximo estado
    cpi  estado, NUM_ESTADOS  ; passou do ultimo estado (q7)? --> nao: segue com o indice novo e sim: o ciclo reinicia em q1
    brlo t1_carrega           
    clr  estado				  ;  fecha o ciclo, fazendo o q7 voltar para o q1        
t1_carrega:
    rcall carrega_estado      ; Le novos valores da Flash
t1_atualiza:
    rcall separa_digitos      ; Converte "seg" para BCD (dezena/unidade)

    pop  ZH                   ; devolve os registradores na ordem inversa da que foram empilhados
    pop  ZL                   
    pop  tmp2                
    pop  tmp                  
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  
    reti                      ; "return from interrupt": volta e reabilita
                              ; as interrupcoes

; isr_timer0 - INTERRUPCAO DO TIMER0, a cada 5 ms
;  A cada 5 ms, alterna qual display esta ligado.  
isr_timer0:
    push tmp                  ; salva tmp
    in   tmp, SREG            ; le os flags
    push tmp                  ; e salva tambem

    tst  mux                  ; Verifica se acendeu dezenas (0) ou unidades (1)
    brne t0_unidades          
    
    mov  tmp, dez             ; Pega o digito da dezena
    ori  tmp, SEL_DEZ         ; Ativa o bit de selecao do display 1 (PC5)
    out  PORTC, tmp           ; Envia BCD + Selecao de uma so vez
    ldi  mux, 1               
    rjmp t0_sai               ; pula o trecho das unidades

t0_unidades:
    mov  tmp, uni             ; Pega o digito da unidade
    ori  tmp, SEL_UNI         ; Ativa o bit de selecao do display 2 (PC4)
    out  PORTC, tmp           ; escrita unica: BCD + selecao
    clr  mux                  ; proximo tique volta a ser das dezenas

t0_sai:
    pop  tmp                  ; recupera o SREG salvo
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  ; restaura tmp
    reti                      ; volta

; isr_udre - INTERRUPCAO DA USART, "registrador de transmissao vazio"
; Sempre que o hardware envia um caractere e fica livre para o proximo, ele dispara a interrupcao UDRE
; A ISR pega o proximo caractere da string armazenada na Flash e o escreve no registrador UDR0
; sem travar o processador com lacos de espera.
isr_udre:
    push tmp                  ; salva tmp
    in   tmp, SREG            ; le os flags
    push tmp                  ; e salva o SREG tambem
    push ZL                   
    push ZH                   

    lds  ZL, tx_ptr           ; Z = endereco do proximo caractere
    lds  ZH, tx_ptr+1         ; ...byte alto do ponteiro
    lpm  tmp, Z+              ; le o caractere da flash e ja avanca Z
    tst  tmp                  ; o caractere e 0? 0 marca o fim da string
    breq udre_fim             

    sts  UDR0, tmp            ; escreve no registrador de dados: o hardware transmite esse byte bit a bit
    sts  tx_ptr,   ZL         ; guarda o ponteiro ja avancado para a proxima
    sts  tx_ptr+1, ZH         ; chamada desta ISR
    rjmp udre_sai             

udre_fim:
    
    lds  ZL, tx_next          ; le o endereco guardado na fila
    lds  ZH, tx_next+1        ; ...byte alto
    mov  tmp, ZL              
    or   tmp, ZH              
    breq udre_vazio           ; zero = fila vazia, nada mais a enviar

    sts  tx_ptr,   ZL         
    sts  tx_ptr+1, ZH         
    sts  tx_next,   zero      
    sts  tx_next+1, zero     
    rjmp udre_sai             ; UDRIE0 continua ligada, entao a proxima interrupcao ja envia o 1o caractere dela

udre_vazio:
    lds  tmp, UCSR0B          ; nada mais a enviar:
    cbr  tmp, (1<<UDRIE0)     ; desliga a interrupcao UDRE, senao ela ficaria disparando sem parar (o registrador esta vazio o tempo todo)
    sts  UCSR0B, tmp          
                              

udre_sai:
    pop  ZH                   ; restaura tudo na ordem inversa
    pop  ZL                   ; ponteiro Z
    pop  tmp                  ; SREG salvo
    out  SREG, tmp            ; restaura os flags
    pop  tmp                  ; tmp original
    reti                      ; volta ao ponto interrompido



carrega_estado:
    ; calcula o endereco da linha: base + indice * 4 
    ldi  ZL, low(tabela_estados*2)   ; Z aponta para o inicio da tabela.
    ldi  ZH, high(tabela_estados*2)  ; "*2" converte palavras em bytes
                                     
    mov  tmp, estado          ; tmp = indice do estado
    lsl  tmp                  ; desloca 1 bit a esquerda = multiplica por 2
    lsl  tmp                  ; de novo = multiplica por 4 (TAM_ESTADO)
    add  ZL, tmp              ; soma o deslocamento ao byte baixo de Z
    adc  ZH, zero             ; e propaga o "vai um" para o byte alto (adc soma o carry; por isso zero existe)
                             

    lpm  seg,   Z+            ; byte 1: duracao do estado, em segundos
    lpm  ledsD, Z+            ; byte 2: bits dos LEDs de PORTD (S1 e S2)
    lpm  ledsB, Z+            ; byte 3: bits dos LEDs de PORTB (S3, S4 e P)
                              

    rcall atualiza_leds       
    ;escolhe a mensagem de status deste estado 
    ldi  ZL, low(tab_strings*2)    ; Z aponta para o inicio do vetor
    ldi  ZH, high(tab_strings*2)   
    mov  tmp, estado          ; indice do estado
    lsl  tmp                  ; x2, porque cada ponteiro ocupa 2 bytes
    add  ZL, tmp              ; soma ao endereco base
    adc  ZH, zero             ; propaga o carry
    lpm  tmp,  Z+             ; byte baixo do endereco da string
    lpm  tmp2, Z              ; byte alto
    rcall agenda_string       ; entrega essa string a serial
    ret                       ; volta para quem chamou (reset ou isr_timer1)


agenda_string:
    lds  ZL, UCSR0B           ; le a configuracao atual da USART
    sbrc ZL, UDRIE0           ; a interrupcao UDRE esta ligada? "sbrc" = pula a proxima instrucao se o bit = 0
                              ; bit = 1: ha transmissao em curso -> vai p/ fila
    rjmp ag_fila              

    sts  tx_ptr,   tmp        ; serial livre: esta string vira a atual
    sts  tx_ptr+1, tmp2       ; ...byte alto do ponteiro
    sbr  ZL, (1<<UDRIE0)      ; liga a interrupcao "registrador vazio"
    sts  UCSR0B, ZL           ; como ele ja esta vazio, a ISR dispara em seguida e comeca a enviar volta; o envio segue sozinho, por interrupcao
                              
    ret                       

ag_fila:
    sts  tx_next,   tmp       ; ocupada: a string espera a vez na fila
    sts  tx_next+1, tmp2      ; ...byte alto do ponteiro
    ret                       ; a ISR a pegara quando terminar a atual

atualiza_leds:
    in   tmp, PORTD           ; le o estado atual da porta D
    andi tmp, 0x03            ; zera PD2..PD7 (os LEDs) e mantem PD0/PD1, que pertencem a USART e nao podem ser mexido
    or   tmp, ledsD           ; acrescenta os bits das cores deste estado
    out  PORTD, tmp           ; escreve: os LEDs de S1 e S2 mudam juntos
    in   tmp, PORTB           
    andi tmp, 0xC0            ; zera PB0..PB5 e mantem PB6/PB7 (cristal)
    or   tmp, ledsB           ; acrescenta as cores de S3, S4 e P
    out  PORTB, tmp           
    ret                       ; o estado ja esta visivel nos 14 LEDs


separa_digitos:
    mov  tmp, seg             ; copia o valor, para nao destruir "seg"
    clr  dez                  ; comeca com zero dezenas
sd_loop:
    cpi  tmp, 10              ; ainda da para tirar 10? menor que 10: acabou, o que sobrou  a unidade tira 10
    brlo sd_pronto           
    subi tmp, 10              
    inc  dez                  
    rjmp sd_loop             
sd_pronto:
    mov  uni, tmp             ; conta maus uma dezena repete o resto (0..9) e o digito das unidades
    ret                       ; dez e uni sao lidos pela ISR do Timer0

; TABELA DE ESTADOS (gravada na memoria flash)
; Cada linha tem 4 bytes:
;   1) duracao do estado, em segundos
;   2) bits dos LEDs de PORTD  (S1 e S2)
;   3) bits dos LEDs de PORTB  (S3, S4 e P)
;   4) byte reservado, so para a linha ter 4 bytes e o calculo do endereco
;      ser um deslocamento de 2 bits ("lsl" duas vezes em carrega_estado)
;
;  Estado (codigo) | S1 | S2 | S3 | S4 | P  | Duracao | Quem passa
;    q1   (000)    | Vm | Vm | Vd | Vd | Vm |  53 s   | avenida nos 2 sentidos
;    q2   (001)    | Vm | Vm | Am | Am | Vm |   4 s   | avenida fechando
;    q3   (010)    | Vd | Vm | Vm | Vm | Vd |  39 s   | rua lateral + pedestre
;    q4   (011)    | Am | Vm | Vm | Vm | Vd |   4 s   | lateral fechando
;    q5   (100)    | Vm | Vm | Vm | Vm | Vd |  15 s   | vermelho geral: so pedestre
;    q6   (101)    | Vm | Vd | Vd | Vm | Vm |  23 s   | sobe: reto + conversao
;    q7   (110)    | Vm | Am | Vd | Vm | Vm |   4 s   | conversao fechando

;  Ciclo total: 142 s.  Depois de q7 o ciclo recomeca em q1.
; Tres regras que a tabela respeita, e que valem citar na apresentacao:
;   - nenhum sinal passa de verde direto para vermelho: sempre ha amarelo;
;   - o pedestre so fica verde quando S2, S3 e S4 estao vermelhos, porque as
;     duas faixas atravessam a avenida;
;   - todo amarelo dura 4 s, medidos no estudo de campo.

tabela_estados:
    ;   dur  PORTD (S1, S2)     PORTB (S3, S4, P)       reserva
    .db 53,  S1_VM|S2_VM,       S3_VD|S4_VD|P_VM,       0   ; q1
    .db  4,  S1_VM|S2_VM,       S3_AM|S4_AM|P_VM,       0   ; q2 (um bit so acende os dois amarelos
                                                            ;     
    .db 39,  S1_VD|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q3
    .db  4,  S1_AM|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q4
    .db 15,  S1_VM|S2_VM,       S3_VM|S4_VM|P_VD,       0   ; q5
    .db 23,  S1_VM|S2_VD,       S3_VD|S4_VM|P_VM,       0   ; q6
    .db  4,  S1_VM|S2_AM,       S3_VD|S4_VM|P_VM,       0   ; q7


; ".dw" grava palavras de 16 bits; cada uma e o endereco (em bytes) de uma
; string.  A ordem tem de ser a mesma da tabela de estados.
tab_strings:
    .dw str_e1*2, str_e2*2, str_e3*2, str_e4*2
    .dw str_e5*2, str_e6*2, str_e7*2


str_banner:
    .db "Semaforos - Av. Alvaro Otacilio x Av. Prof. Sandoval Arroxelas - Maceio/AL", 13, 10, 0

str_e1: .db "q1 (53s): S1 - Vermelho; S2 - Vermelho; S3 - Verde; S4 - Verde; P - Vermelho", 13, 10, 0
str_e2: .db "q2 (4s): S1 - Vermelho; S2 - Vermelho; S3 - Amarelo; S4 - Amarelo; P - Vermelho", 13, 10, 0
str_e3: .db "q3 (39s): S1 - Verde; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e4: .db "q4 (4s): S1 - Amarelo; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e5: .db "q5 (15s): S1 - Vermelho; S2 - Vermelho; S3 - Vermelho; S4 - Vermelho; P - Verde", 13, 10, 0
str_e6: .db "q6 (23s): S1 - Vermelho; S2 - Verde; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0
str_e7: .db "q7 (4s): S1 - Vermelho; S2 - Amarelo; S3 - Verde; S4 - Vermelho; P - Vermelho", 13, 10, 0