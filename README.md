# traffic-light-project

Simulação dos semáforos do cruzamento Av. Álvaro Otacílio x R. Prof. Sandoval Arroxelas (Maceió/AL) em Assembly para Arduino Uno (ATmega328P), com circuito no SimulIDE.

## Estrutura

- `Atmel Studio/7.0/codigo_semaforo_micro/` — projeto do Atmel/Microchip Studio (AVR Assembler). O código-fonte é `codigo_semaforo_micro/main.asm` e o firmware compilado é `codigo_semaforo_micro/Debug/codigo_semaforo_micro.hex`.
- `simulide/` — circuitos do SimulIDE (`funcionando.sim1` e `teste2.sim1`) e arquivos de configuração do programa.

## Como rodar

1. Abra o SimulIDE e carregue `simulide/funcionando.sim1`.
2. **Ajuste o caminho do firmware.** Os arquivos `.sim1` apontam para o `.hex` por um caminho relativo da máquina onde foram criados (`../../../OneDrive/Documentos/Atmel Studio/...`). Clique com o botão direito no Arduino Uno do circuito, escolha *Load firmware* e selecione `Atmel Studio/7.0/codigo_semaforo_micro/codigo_semaforo_micro/Debug/codigo_semaforo_micro.hex`. Alternativamente, edite o atributo `Program=` dentro do `.sim1` para `../Atmel Studio/7.0/codigo_semaforo_micro/codigo_semaforo_micro/Debug/codigo_semaforo_micro.hex`.
3. Inicie a simulação.

Para alterar o código, abra `codigo_semaforo_micro.atsln` no Atmel/Microchip Studio, edite `main.asm` e recompile. O `.hex` é regenerado em `Debug/`.

Os arquivos `simulide/simulide.ini` e `simulide/compList.ini` são configurações pessoais do SimulIDE e contêm caminhos da máquina de origem. Não são necessários para rodar o projeto.
