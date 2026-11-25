# UNIVERSIDADE FEDERAL RURAL DE PERNAMBUCO
# ARQUITETURA E ORGANIZACÃO DE COMPUTADORES (AOC) - 2026.2
#PROJETO SNAKE  - ASSEMBLY MIPS  -  VERSAO 1.6.speed
#Professora: MILLENA DE ANDRADE ALMEIDA GOMES CAVALCANTI
#Alunos: Augusto Itapoã
#				Renato Neves
#				Vitor Cardoso
#
# DESCRIÇÃO: O jogo segue as especificacoes em https://view.genially.com/622931ea1b54ab00188cdf57
#
# CONFIGURAÇÃO NO MARS:
# 1. Tools -> Bitmap Display:
#    - Base address for display: 0x10010000 (static data)
#    - Display width in pixels:  512
#    - Display height in pixels: 512
#    - Unit width in pixels:     1
#    - Unit height in pixels:    1  (em versões antigas: Pixel Pitch = 1)
#    - Clique em "Connect to MIPS"
#    - Manter a janela ABERTA
# 2. Tools -> Keyboard and Display MMIO Simulator:
#    - Clique em "Connect to MIPS"
#    - Manter a janela ABERTA
#    - As teclas devem ser digitadas na caixa de texto de BAIXO (KEYBOARD)
# 3. Settings -> Memory Configuration: mantenha "Default".
# 4. Assemble e Run. As mensagens aparecem na aba "Run I/O" do MARS.
#
# CONTROLES:
#   W = cima | A = esquerda | S = baixo | D = direita
#   P ou Espaço = pausar / continuar
#   R = jogar de novo (depois do fim de jogo)
#
# No funcionamento do jogo temos:
#   - Fundo em xadrez (preto / azul-cinza escuro)
#   - Cabeça da cobra em verde escuro
#   - Corpo da cobra em verde claro
#   - Comida em vermelho
#   - Pontuação: +1 a cada passo (0,5 s) e +5 extra a cada comida
#   - Fim de jogo: bater na parede ou no próprio corpo
#   - Vitória: a cobra ocupar o tabuleiro inteiro (1024 células)
#   - Sons ao comer, ao perder e ao vencer (syscalls 31 e 33 do MARS)
#   - Recorde da sessão (maior pontuação desde que o programa foi iniciado)
#
# CONVENÇÃO DE REGISTRADORES (padrão MIPS, seguida no código):
#   $a0-$a3 : argumentos das funções e das syscalls
#   $v0     : valor de retorno das funções / número da syscall
#   $t0-$t9 : temporários. Qualquer função pode alterá-los; quem chama
#             não deve contar com o valor deles depois de um "jal".
#   $s0-$s7 : salvos. Uma função que os usa guarda o valor antigo na
#             pilha e o devolve antes de retornar.
#   $sp     : topo da pilha | $ra : endereço de retorno
#
# MUDANÇAS DA VERSÃO 1.6 (anti-travamento do MARS 4.5):
# O MARS 4.5 tem um deadlock interno: o syscall de espera (sleep, 32) e o syscall
# de som síncrono (33) rodam com o "lock" do simulador seguro. Se uma tecla for
# apertada durante essa espera, a thread da janela fica presa esperando o lock
# (segurando o lock do teclado), e quando o programa volta a ler o teclado (MMIO)
# as duas threads ficam esperando uma pela outra e o MARS congela sem erro.
#   - Todas as esperas agora usam esperar_ms (laço com o relógio, syscall 30),
#     que solta o lock a cada instrução. Nenhum sleep (32) nem syscall 33 restou.
#   - Os sons de derrota/vitória usam o syscall 31 (assíncrono) + esperar_ms.
#   - O teclado é lido só uma vez por passo do jogo (e a cada 50 ms nas telas de
#     espera), para reduzir ao mínimo os acessos ao MMIO.
#   - [BUG] comida_desenhada agora é zerada em inicializar_jogo; antes, depois de
#     apertar R, a comida podia não ser desenhada se caísse no mesmo lugar.
#   Obs.: o laço de espera usa 100% de um núcleo da CPU enquanto aguarda.
#
# OBSERVAÇÃO SOBRE MEMÓRIA:
# O Bitmap Display usa 1 MB a partir de 0x10010000. Para não sobrescrever as
# variáveis do jogo, a seção .data é montada em 0x10000000 (abaixo do display).
# =============================================================================

.data 0x10000000
.align 2

# --- Endereços e Constantes ---
BASE_DISPLAY:   .word 0x10010000
TECLADO_MMIO:   .word 0xffff0000
TAMANHO_GRADE:  .word 32
TAM_CELULA:     .word 16
LARGURA_DISP:   .word 512
ALTURA_DISP:    .word 512
MAX_CELULAS:    .word 1024          # 32 x 32 = tabuleiro inteiro

# --- Curva de velocidade (herdada da antiga v1.6) ---
DELAY_INICIAL:  .word 500
DELAY_MINIMO:   .word 100
PASSO_DELAY:    .word 40
COMIDAS_POR_PASSO:.word 3

# --- Cores (Formato 0x00RRGGBB) ---
COR_FUNDO:      .word 0x00000000    # Preto (casa par do tabuleiro)
COR_FUNDO2:     .word 0x00101820    # Azul-cinza escuro (casa ímpar)
COR_COBRA_CORPO: .word 0x0000FF00   # Verde
COR_COBRA_CABECA: .word 0x0000AA00  # Verde Escuro
COR_COMIDA:     .word 0x00FF0000    # Vermelho

# --- Estruturas de Dados ---
# Vetor de endereços base para as células da cobra (máximo 1024 células)
snake_addrs:    .space 4096         # 1024 * 4 bytes
snake_tamanho:  .word 1
snake_direcao:  .word 0             # 0: Cima, 1: Direita, 2: Baixo, 3: Esquerda
comida_addr:    .word 0             # TAG: endereco da fruta ATIVA (logica do jogo)
comida_desenhada:.word 0xFFFFFFFF   # TAG: endereco PINTADO no ultimo frame (0xFFFFFFFF = nenhum)
pontuacao:      .word 0
comidas_comidas:.word 0             # contador de comidas (curva de velocidade)
game_over:      .word 0
vitoria:        .word 0             # 1 se a cobra encheu o tabuleiro
recorde:        .word 0             # maior pontuação da sessão (não é zerado ao reiniciar)

# Posição atual da cabeça (linha e coluna na grade 32x32)
cabeca_row:     .word 0
cabeca_col:     .word 0

# --- Mensagens (sem acentos para aparecerem certas no console do MARS) ---
MSG_INICIO:     .asciiz "\n========== SNAKE ==========\nControles: W A S D | P ou Espaco = pausa\nClique na caixa de texto de baixo do Keyboard and Display MMIO Simulator\ne aperte qualquer tecla para comecar.\n"
MSG_PAUSA:      .asciiz "\n[PAUSADO] Aperte P ou Espaco para continuar.\n"
MSG_CONTINUA:   .asciiz "[CONTINUANDO]\n"
MSG_GAME_OVER:  .asciiz "\nGAME OVER! Pontuacao final: "
MSG_VITORIA:    .asciiz "\nVOCE VENCEU! A cobra encheu o tabuleiro! Pontuacao final: "
MSG_NOVO_REC:   .asciiz "\nNOVO RECORDE!"
MSG_RECORDE:    .asciiz "\nRecorde da sessao: "
MSG_REINICIAR:  .asciiz "\n\nAperte R para jogar de novo ou qualquer outra tecla para sair.\n"
MSG_TCHAU:      .asciiz "\nFim do programa. Ate a proxima!\n"

.text

# =============================================================================
# FUNÇÃO: main
# Coordena o ciclo de vida do jogo.
# =============================================================================
main:
    jal inicializar_jogo
    jal tela_inicial        # espera o jogador apertar uma tecla para começar

loop_principal:
    # 1. Calcular e aplicar o intervalo (curva de velocidade + esperar_ms)
    jal calcular_velocidade
    move $a0, $v0
    jal esperar_ms

    # 2. Ler teclado (Input) - também trata a pausa
    jal ler_teclado

    # 3. Atualizar lógica (Update)
    jal atualizar_logica

    # 4. Verificar Game Over (derrota ou vitória)
    lw $t0, game_over
    bne $t0, $zero, fim_de_jogo

    # 5. Desenhar Frame (Render)
    jal desenhar_frame

    j loop_principal

# =============================================================================
# [HERDADO DA v1.6] FUNÇÃO: calcular_velocidade
# delay = max(100, 500 - (comidas / 3) * 40). Usa esperar_ms da v1.6.1.
# =============================================================================
calcular_velocidade:
    lw $t0, DELAY_INICIAL
    lw $t1, DELAY_MINIMO
    lw $t2, PASSO_DELAY
    lw $t3, COMIDAS_POR_PASSO
    lw $t4, comidas_comidas
    div $t4, $t3
    mflo $t4
    mult $t4, $t2
    mflo $t4
    sub $v0, $t0, $t4
    blt $v0, $t1, velocidade_no_piso
    jr $ra
velocidade_no_piso:
    move $v0, $t1
    jr $ra

# =============================================================================
# FUNÇÃO: inicializar_jogo
# Prepara o ambiente, limpa o display e posiciona a cobra.
# Também é chamada ao reiniciar a partida.
# =============================================================================
inicializar_jogo:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Limpar display (pintar fundo)
    li $a0, 0x10010000  # Endereço inicial
    lw $a1, COR_FUNDO
    jal desenhar_celula_completa

    # Configurar cobra inicial na (0,0)
    li $t0, 0           # row = 0
    li $t1, 0           # col = 0
    sw $t0, cabeca_row
    sw $t1, cabeca_col

    # Calcular endereço base da célula (0,0) e salvar no vetor
    li $a0, 0           # argumento: linha
    li $a1, 0           # argumento: coluna
    jal calcular_endereco_celula
    sw $v0, snake_addrs    # snake_addrs[0] = addr

    # Resetar estado (o recorde NÃO é zerado, ele vale para a sessão toda)
    li $t0, 1
    sw $t0, snake_tamanho
    li $t0, 1            # Direção inicial = 1 (Direita), para não sair do tabuleiro
    sw $t0, snake_direcao
    li $t0, 0
    sw $t0, pontuacao
    sw $t0, game_over
    sw $t0, vitoria
    sw $t0, comidas_comidas      # reinicia a curva de velocidade

    # O tabuleiro acabou de ser limpo, entao nenhuma fruta esta pintada:
    # volta a tag pintada para o sentinela 0xFFFFFFFF. [BUG corrigido na 1.6]
    # Sem isso, depois de apertar R a fruta nova podia cair no mesmo lugar da
    # fruta do jogo anterior e nunca ser desenhada.
    li $t0, -1
    sw $t0, comida_desenhada

    # Gerar primeira comida
    jal gerar_comida

    # Observacao: com a tag pintada = sentinela, o primeiro desenhar_frame nao
    # apaga nada e so pinta a fruta nova.

    # Desenhar o primeiro frame imediatamente (antes do primeiro movimento)
    jal desenhar_frame

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: tela_inicial  [NOVO]
# Mostra as instruções no console e espera qualquer tecla para começar.
# =============================================================================
tela_inicial:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $a0, MSG_INICIO
    li $v0, 4            # syscall print string
    syscall

    jal limpar_teclado   # descarta alguma tecla que tenha ficado "sobrando"
    jal esperar_tecla    # trava aqui até o jogador apertar algo

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: esperar_tecla  [NOVO / REESCRITA NA 1.6]
# Fica esperando até uma tecla ser apertada. Retorna o caractere em $v0.
# Entre uma checagem e outra espera 50 ms com esperar_ms (e NÃO com o syscall
# sleep, que causa deadlock no MARS 4.5 se uma tecla chegar durante a espera).
# =============================================================================
esperar_tecla:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
esperar_tecla_loop:
    lw $t0, TECLADO_MMIO
    lw $t1, 0($t0)       # registrador de controle do teclado
    andi $t1, $t1, 1     # bit 0 = "tem tecla pronta"
    bne $t1, $zero, esperar_tecla_leu
    li $a0, 50
    jal esperar_ms       # (altera $t0, por isso $t0 é recarregado no topo)
    j esperar_tecla_loop
esperar_tecla_leu:
    lw $v0, 4($t0)       # lê o caractere (isso também desliga o bit "pronto")
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: limpar_teclado  [NOVO]
# Se houver uma tecla pendente, lê e descarta.
# =============================================================================
limpar_teclado:
    lw $t0, TECLADO_MMIO
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beq $t1, $zero, limpar_teclado_fim
    lw $t1, 4($t0)       # lê e joga fora
limpar_teclado_fim:
    jr $ra

# =============================================================================
# FUNÇÃO: ler_teclado
# Lê entrada via MMIO e atualiza a direção da cobra.
# MMIO do teclado no MARS: 0xffff0000 = controle, 0xffff0004 = caractere.
# Agora também trata a PAUSA (teclas P, p ou Espaço).
# Como agora chama outras funções (jal), precisa salvar $ra na pilha.
# =============================================================================
ler_teclado:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, TECLADO_MMIO

    # Só lê o caractere se o bit de "pronto" estiver ligado
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beq $t1, $zero, fim_ler_teclado

    lw $a0, 4($t0)      # Lê o caractere do teclado

    # Se não houver tecla (caractere 0 ou NUL), sai
    beq $a0, $zero, fim_ler_teclado

    # Pausa: P, p ou Espaço
    li $t1, 0x50         # 'P'
    beq $a0, $t1, pausar
    li $t1, 0x70         # 'p'
    beq $a0, $t1, pausar
    li $t1, 0x20         # ' ' (Espaço)
    beq $a0, $t1, pausar

    # Verificar teclas W, A, S, D (maiúsculas e minúsculas)
    # W/w (Cima), A/a (Esq), S/s (Baixo), D/d (Dir)
    li $t1, 0x57         # 'W'
    beq $a0, $t1, set_cima
    li $t1, 0x77         # 'w'
    beq $a0, $t1, set_cima
    li $t1, 0x41         # 'A'
    beq $a0, $t1, set_esq
    li $t1, 0x61         # 'a'
    beq $a0, $t1, set_esq
    li $t1, 0x53         # 'S'
    beq $a0, $t1, set_baixo
    li $t1, 0x73         # 's'
    beq $a0, $t1, set_baixo
    li $t1, 0x44         # 'D'
    beq $a0, $t1, set_dir
    li $t1, 0x64         # 'd'
    beq $a0, $t1, set_dir

    j fim_ler_teclado

set_cima:
    li $t1, 0            # Direção 0
    j validar_direcao
set_esq:
    li $t1, 3            # Direção 3
    j validar_direcao
set_baixo:
    li $t1, 2            # Direção 2
    j validar_direcao
set_dir:
    li $t1, 1            # Direção 1
    j validar_direcao

validar_direcao:
    # Evitar reversão de 180 graus se tamanho > 1
    lw $t2, snake_tamanho
    ble $t2, 1, aplicar_dir

    lw $t3, snake_direcao
    # Se dir atual é 0 (Cima), não pode ir para 2 (Baixo)
    beq $t3, $zero, check_reverso_baixo
    # Se dir atual é 1 (Dir), não pode ir para 3 (Esq)
    beq $t3, 1, check_reverso_esq
    # Se dir atual é 2 (Baixo), não pode ir para 0 (Cima)
    beq $t3, 2, check_reverso_cima
    # Se dir atual é 3 (Esq), não pode ir para 1 (Dir)
    beq $t3, 3, check_reverso_dir
    j aplicar_dir

check_reverso_baixo:
    beq $t1, 2, fim_ler_teclado
    j aplicar_dir
check_reverso_esq:
    beq $t1, 3, fim_ler_teclado
    j aplicar_dir
check_reverso_cima:
    beq $t1, 0, fim_ler_teclado
    j aplicar_dir
check_reverso_dir:
    beq $t1, 1, fim_ler_teclado
    j aplicar_dir

aplicar_dir:
    sw $t1, snake_direcao
    j fim_ler_teclado

# --- PAUSA [NOVO] ---
# O jogo fica parado aqui dentro até P/p/Espaço ser apertado de novo.
# Como o loop principal não avança, a pontuação também não aumenta.
pausar:
    la $a0, MSG_PAUSA
    li $v0, 4
    syscall
pausa_loop:
    jal esperar_tecla    # $v0 = tecla apertada
    li $t1, 0x50         # 'P'
    beq $v0, $t1, sair_pausa
    li $t1, 0x70         # 'p'
    beq $v0, $t1, sair_pausa
    li $t1, 0x20         # Espaço
    beq $v0, $t1, sair_pausa
    j pausa_loop         # qualquer outra tecla é ignorada durante a pausa
sair_pausa:
    la $a0, MSG_CONTINUA
    li $v0, 4
    syscall

fim_ler_teclado:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: atualizar_logica
# Processa movimento, colisões e crescimento.
# Preserva $ra e os registradores $s0-$s7.
# =============================================================================
atualizar_logica:
    addi $sp, $sp, -40
    sw $ra, 36($sp)
    sw $s0, 32($sp)
    sw $s1, 28($sp)
    sw $s2, 24($sp)
    sw $s3, 20($sp)
    sw $s4, 16($sp)
    sw $s5, 12($sp)
    sw $s6, 8($sp)
    sw $s7, 4($sp)

    # 1. Obter posição atual da cabeça
    lw $t0, cabeca_row
    lw $t1, cabeca_col
    lw $t2, snake_direcao

    # 2. Calcular nova posição baseada na direção
    # Direções: 0: Cima (row-1), 1: Dir (col+1), 2: Baixo (row+1), 3: Esq (col-1)
    beq $t2, 0, move_cima
    beq $t2, 1, move_dir
    beq $t2, 2, move_baixo
    j move_esq

move_cima:
    addi $t0, $t0, -1
    j calc_nova_pos
move_dir:
    addi $t1, $t1, 1
    j calc_nova_pos
move_baixo:
    addi $t0, $t0, 1
    j calc_nova_pos
move_esq:
    addi $t1, $t1, -1

calc_nova_pos:
    # 3. Verificar colisão com bordas
    blt $t0, $zero, colidiu
    li $t4, 32
    bge $t0, $t4, colidiu
    blt $t1, $zero, colidiu
    bge $t1, $t4, colidiu

    # 4. Calcular endereço da nova cabeça para verificar colisão com corpo e comida
    sw $t0, cabeca_row
    sw $t1, cabeca_col
    move $a0, $t0        # argumento: linha
    move $a1, $t1        # argumento: coluna
    jal calcular_endereco_celula
    move $s0, $v0        # $s0 = nova_cabeca_addr

    # 5. Verificar colisão com corpo  [CORRIGIDO - bug 1]
    # Antes, o laço comparava a nova cabeça com TODAS as células, inclusive a
    # cauda. Mas, se a cobra NÃO comer neste passo, a cauda vai sair do lugar
    # no mesmo movimento, então entrar na célula da cauda não é batida.
    # Solução: se não vai comer, o laço ignora a última célula (a cauda).
    # Se vai comer, a cauda fica parada (a cobra cresce), então ela conta.
    lw $s6, comida_addr
    lw $s1, snake_tamanho        # limite do laço = tamanho
    beq $s0, $s6, verificar_corpo  # vai comer: verifica todas as células
    addi $s1, $s1, -1            # não vai comer: ignora a cauda (tamanho - 1)
verificar_corpo:
    li $s2, 0            # i = 0
loop_corpo:
    beq $s2, $s1, check_comida
    sll $s3, $s2, 2      # offset = i * 4
    la $s4, snake_addrs
    add $s4, $s4, $s3
    lw $s5, 0($s4)       # addr_corpo = snake_addrs[i]
    beq $s5, $s0, colidiu
    addi $s2, $s2, 1
    j loop_corpo

check_comida:
    # Pontuação base: +1 a cada passo de 0,5 s (vale também no passo em que come)
    lw $s7, pontuacao
    addi $s7, $s7, 1
    sw $s7, pontuacao

    lw $s6, comida_addr
    beq $s0, $s6, comeu_comida

# CASO: MOVIMENTO NORMAL (não comeu)
    # Apagar a cauda antiga no display antes de removê-la do vetor
    lw $s1, snake_tamanho
    addi $t0, $s1, -1    # índice da cauda = tamanho - 1
    sll $t0, $t0, 2
    la $t1, snake_addrs
    add $t1, $t1, $t0
    lw $a0, 0($t1)
    jal desenhar_fundo_celula

    # Mover cobra (deslocar elementos no vetor)
    # O novo endereço da cabeça entra em snake_addrs[0]
    # Os antigos snake_addrs[0...N-2] passam para [1...N-1]
    lw $s1, snake_tamanho
    addi $s2, $s1, -1    # i = size - 1
loop_shift_body:
    ble $s2, $zero, fim_shift_body
    sll $s3, $s2, 2
    la $s4, snake_addrs
    add $s4, $s4, $s3
    # snake_addrs[i] = snake_addrs[i-1]
    addi $s5, $s2, -1
    sll $s5, $s5, 2
    la $s6, snake_addrs
    add $s6, $s6, $s5
    lw $s7, 0($s6)
    sw $s7, 0($s4)
    addi $s2, $s2, -1
    j loop_shift_body

fim_shift_body:
    # Adiciona nova cabeça
    sw $s0, snake_addrs    # snake_addrs[0] = nova_cabeca
    j fim_atualizar

# CASO: COMEU COMIDA
comeu_comida:
    # Aumentar tamanho (+1)
    lw $s1, snake_tamanho
    addi $s1, $s1, 1
    sw $s1, snake_tamanho

    # Bônus da comida (+5)
    lw $s7, pontuacao
    addi $s7, $s7, 5
    sw $s7, pontuacao

    # Conta esta comida para a curva de velocidade
    lw $t0, comidas_comidas
    addi $t0, $t0, 1
    sw $t0, comidas_comidas

    # Deslocar todos (mesma lógica, mas o novo elemento não remove o último)
    lw $s1, snake_tamanho    # agora é o novo tamanho
    addi $s2, $s1, -1        # i = novo_tamanho - 1
loop_shift_eat_body:
    ble $s2, $zero, fim_shift_eat
    sll $s3, $s2, 2
    la $s4, snake_addrs
    add $s4, $s4, $s3
    # snake_addrs[i] = snake_addrs[i-1]
    addi $s5, $s2, -1
    sll $s5, $s5, 2
    la $s6, snake_addrs
    add $s6, $s6, $s5
    lw $s7, 0($s6)
    sw $s7, 0($s4)
    addi $s2, $s2, -1
    j loop_shift_eat_body

fim_shift_eat:
    sw $s0, snake_addrs    # snake_addrs[0] = nova_cabeca

    # Condição de vitória  [NOVO - resolve os bugs 2 e 7]
    # Se a cobra ocupa as 1024 células, não existe lugar para a comida
    # (gerar_comida ficaria em loop infinito) e o vetor está cheio.
    lw $t0, MAX_CELULAS
    blt $s1, $t0, nao_venceu
    li $t0, 1
    sw $t0, vitoria
    sw $t0, game_over
    j fim_atualizar

nao_venceu:
    # Som de comer [NOVO] - syscall 31 toca uma nota sem pausar o jogo
    li $a0, 76           # nota (altura do som, 0 a 127)
    li $a1, 120          # duração em ms
    li $a2, 9            # instrumento (9 = glockenspiel)
    li $a3, 100          # volume (0 a 127)
    li $v0, 31
    syscall

    jal gerar_comida
    j fim_atualizar

colidiu:
    li $t0, 1
    sw $t0, game_over

fim_atualizar:
    lw $s7, 4($sp)
    lw $s6, 8($sp)
    lw $s5, 12($sp)
    lw $s4, 16($sp)
    lw $s3, 20($sp)
    lw $s2, 24($sp)
    lw $s1, 28($sp)
    lw $s0, 32($sp)
    lw $ra, 36($sp)
    addi $sp, $sp, 40
    jr $ra

# =============================================================================
# FUNÇÃO: desenhar_frame
# Renderiza a comida e a cobra.
# =============================================================================
desenhar_frame:
    addi $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)

    # 1. Reconciliar a fruta usando as TAGS:
    #    Se a tag pintada no frame anterior (comida_desenhada) for diferente
    #    da tag ativa (comida_addr), apagamos a antiga e pintamos a nova.
    #    Assim sempre existe no maximo UMA fruta vermelha na tela,
    #    independente de quantas vezes a cobra tenha comido.
    # Usamos $s0/$s1 (preservados por desenhar_frame) para as tags,
    # pois desenhar_celula/desenhar_fundo_celula clobberam os $t.
    lw $s0, comida_addr        # $s0 = tag ativa
    lw $s1, comida_desenhada   # $s1 = tag pintada no frame anterior
    beq $s0, $s1, fruta_ja_desenada   # tag nao mudou: nada a fazer

    # Se a tag pintada eh o sentinela (nenhuma fruta ainda), nao apaga nada
    li $s2, 0xFFFFFFFF
    beq $s1, $s2, pintar_fruta_tag

    # Apagar o endereco da tag antiga (repinta com a cor do xadrez)
    move $a0, $s1
    jal desenhar_fundo_celula

pintar_fruta_tag:

    # Pintar o endereco da tag nova de vermelho
    move $a0, $s0
    lw $a1, COR_COMIDA
    jal desenhar_celula

    # Atualizar a tag pintada para a tag atual
    sw $s0, comida_desenhada

fruta_ja_desenada:

    # 2. Desenhar Cobra
    lw $s0, snake_tamanho
    li $s1, 0            # i = 0
    la $s2, snake_addrs
loop_draw_snake:
    beq $s1, $s0, fim_draw
    sll $t2, $s1, 2
    add $t3, $s2, $t2
    lw $a0, 0($t3)       # addr

    # Diferenciar cabeça do corpo
    beq $s1, $zero, draw_head
    lw $a1, COR_COBRA_CORPO
    j exec_draw
draw_head:
    lw $a1, COR_COBRA_CABECA
exec_draw:
    jal desenhar_celula

    addi $s1, $s1, 1
    j loop_draw_snake

fim_draw:
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addi $sp, $sp, 20
    jr $ra

# =============================================================================
# FUNÇÃO: gerar_comida  [REESCRITA - bug 4]
# Gera uma posição aleatória para a comida, fora do corpo da cobra.
# Usa syscall 42 (RandIntRange): $a0 = id do gerador, $a1 = limite superior,
# resultado em $a0.
# Antes, a função escrevia em cabeca_row/cabeca_col para reaproveitar
# calcular_endereco_celula. Agora a linha e a coluna são passadas como
# argumentos ($a0, $a1), e a posição da cabeça não é mais tocada.
# Usa $s0-$s2 para guardar valores entre chamadas, então salva-os na pilha.
# =============================================================================
gerar_comida:
    addi $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

gerar_comida_loop:
    # row = número aleatório de 0 a 31
    li $a0, 0            # sempre o mesmo gerador (id 0)
    li $a1, 32
    li $v0, 42
    syscall
    move $s0, $a0

    # col = número aleatório de 0 a 31
    li $a0, 0
    li $a1, 32
    li $v0, 42
    syscall
    move $s1, $a0

    # Calcular endereço da célula sorteada
    move $a0, $s0        # argumento: linha
    move $a1, $s1        # argumento: coluna
    jal calcular_endereco_celula
    move $s2, $v0        # $s2 = addr_comida_nova

    # Verificar se a comida não está sobre a cobra
    lw $t3, snake_tamanho
    li $t4, 0            # i = 0
loop_check_comida:
    beq $t4, $t3, comida_ok
    sll $t5, $t4, 2
    la $t6, snake_addrs
    add $t6, $t6, $t5
    lw $t7, 0($t6)
    beq $t7, $s2, gerar_comida_loop   # Se colidir, tenta de novo
    addi $t4, $t4, 1
    j loop_check_comida

comida_ok:
    sw $s2, comida_addr
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addi $sp, $sp, 16
    jr $ra

# =============================================================================
# FUNÇÃO: desenhar_celula
# Desenha um quadrado 16x16 pixels no display.
# $a0 = endereço base da célula, $a1 = cor.
# Usa $t0-$t5 livremente (são temporários pela convenção MIPS).
# =============================================================================
desenhar_celula:
    li $t0, 0            # y = 0
    li $t5, 16
loop_y:
    li $t1, 0            # x = 0
loop_x:
    # pixel_addr = base_addr + y * 2048 + x * 4
    sll $t2, $t0, 11     # y * 2048 (512 * 4)
    sll $t3, $t1, 2      # x * 4
    add $t4, $t2, $t3
    add $t4, $t4, $a0    # addr_pixel
    sw $a1, 0($t4)

    addi $t1, $t1, 1
    blt $t1, $t5, loop_x

    addi $t0, $t0, 1
    blt $t0, $t5, loop_y
    jr $ra

# =============================================================================
# FUNÇÃO AUXILIAR: desenhar_celula_completa
# Desenha o fundo do tabuleiro inteiro (32x32 células = 512x512 pixels).
# O fundo é um xadrez discreto para dar visibilidade ao display.
# $a0 = endereço base do display.
# =============================================================================
desenhar_celula_completa:
    addi $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    move $s2, $a0        # $s2 = base do display
    li $s0, 0            # row = 0
loop_fundo_row:
    li $s1, 0            # col = 0
loop_fundo_col:
    # addr = base + row*32768 + col*64
    sll $t0, $s0, 15
    sll $t1, $s1, 6
    add $a0, $s2, $t0
    add $a0, $a0, $t1
    jal desenhar_fundo_celula

    addi $s1, $s1, 1
    li $t2, 32
    blt $s1, $t2, loop_fundo_col

    addi $s0, $s0, 1
    li $t2, 32
    blt $s0, $t2, loop_fundo_row

    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addi $sp, $sp, 16
    jr $ra

# =============================================================================
# FUNÇÃO AUXILIAR: desenhar_fundo_celula
# Desenha uma célula com a cor de fundo correspondente à sua posição no xadrez.
# $a0 = endereço base da célula.
# =============================================================================
desenhar_fundo_celula:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Descobre row e col a partir do endereço da célula
    lw $t0, BASE_DISPLAY
    sub $t1, $a0, $t0
    srl $t2, $t1, 15     # row = offset / 32768
    srl $t3, $t1, 6
    andi $t3, $t3, 31    # col = (offset / 64) % 32

    # Xadrez: (row + col) par -> COR_FUNDO, ímpar -> COR_FUNDO2
    add $t4, $t2, $t3
    andi $t4, $t4, 1
    beq $t4, $zero, fundo_cor_par
    lw $a1, COR_FUNDO2
    j fundo_desenhar
fundo_cor_par:
    lw $a1, COR_FUNDO
fundo_desenhar:
    jal desenhar_celula

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: calcular_endereco_celula  [ALTERADA - bug 4]
# Calcula o endereço base de uma célula (row, col) de 16x16.
# Entrada: $a0 = linha (row), $a1 = coluna (col).
# Retorna em $v0.
# =============================================================================
calcular_endereco_celula:
    lw $t2, BASE_DISPLAY

    # offset = (row * 16 * 512 + col * 16) * 4
    # offset = row * 32768 + col * 64
    sll $t3, $a0, 15     # row * 32768
    sll $t4, $a1, 6      # col * 64
    add $t5, $t3, $t4
    add $v0, $t2, $t5
    jr $ra

# =============================================================================
# FUNÇÃO: esperar_ms  [NOVO NA 1.6]
# Espera $a0 milissegundos SEM usar o syscall sleep (32).
# O sleep do MARS dorme com o lock do simulador seguro; se o jogador apertar uma
# tecla nesse tempo, o MARS 4.5 entra em deadlock. Aqui o relógio (syscall 30,
# milissegundos em $a0) é consultado em laço, e o lock é solto a cada instrução.
# Altera: $v0, $a0, $a1, $t0, $t8, $t9.
# =============================================================================
esperar_ms:
    move $t8, $a0        # duração desejada
    li $v0, 30
    syscall              # $a0 = tempo atual (32 bits baixos, em ms)
    move $t9, $a0        # instante inicial
esperar_ms_loop:
    li $v0, 30
    syscall
    subu $t0, $a0, $t9   # decorrido (subu funciona mesmo se o contador der a volta)
    bltu $t0, $t8, esperar_ms_loop
    jr $ra

# =============================================================================
# FUNÇÃO: tocar_nota  [NOVO NA 1.6]
# Toca uma nota e espera ela terminar, no lugar do syscall 33 (síncrono), que
# também segura o lock do simulador durante a nota.
# Argumentos (iguais aos do syscall 31): $a0 = nota, $a1 = duração em ms,
# $a2 = instrumento, $a3 = volume.
# =============================================================================
tocar_nota:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $a1, 0($sp)       # guarda a duração (esperar_ms/syscall alteram $a1)
    li $v0, 31           # syscall 31: toca a nota e volta na hora (assíncrono)
    syscall
    lw $a0, 0($sp)
    jal esperar_ms       # espera a duração da nota
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

# =============================================================================
# FUNÇÃO: fim_de_jogo  [AMPLIADA]
# Toca um som, exibe o resultado (derrota ou vitória), a pontuação e o
# recorde, e pergunta se o jogador quer jogar de novo (tecla R).
# =============================================================================
fim_de_jogo:
    lw $t0, vitoria
    bne $t0, $zero, fim_vitoria

    # --- Derrota: três notas descendo (tocar_nota espera cada nota terminar) ---
    li $a0, 67
    li $a1, 180
    li $a2, 0            # instrumento 0 = piano
    li $a3, 100
    jal tocar_nota
    li $a0, 62
    li $a1, 180
    li $a2, 0
    li $a3, 100
    jal tocar_nota
    li $a0, 55
    li $a1, 400
    li $a2, 0
    li $a3, 100
    jal tocar_nota

    la $a0, MSG_GAME_OVER
    j mostrar_resultado

fim_vitoria:
    jal desenhar_frame   # mostra a cobra ocupando o tabuleiro todo
    # --- Vitória: três notas subindo ---
    li $a0, 60
    li $a1, 150
    li $a2, 0
    li $a3, 100
    jal tocar_nota
    li $a0, 64
    li $a1, 150
    li $a2, 0
    li $a3, 100
    jal tocar_nota
    li $a0, 67
    li $a1, 400
    li $a2, 0
    li $a3, 100
    jal tocar_nota

    la $a0, MSG_VITORIA

mostrar_resultado:
    li $v0, 4            # imprime a mensagem escolhida acima ($a0)
    syscall

    lw $a0, pontuacao
    li $v0, 1            # syscall print int
    syscall

    # --- Recorde da sessão ---
    lw $t0, pontuacao
    lw $t1, recorde
    ble $t0, $t1, mostrar_recorde   # não bateu o recorde
    sw $t0, recorde                 # bateu: guarda a nova maior pontuação
    la $a0, MSG_NOVO_REC
    li $v0, 4
    syscall
mostrar_recorde:
    la $a0, MSG_RECORDE
    li $v0, 4
    syscall
    lw $a0, recorde
    li $v0, 1
    syscall

    # --- Jogar de novo? ---
    la $a0, MSG_REINICIAR
    li $v0, 4
    syscall

    jal limpar_teclado   # descarta tecla apertada durante a batida
    jal esperar_tecla    # $v0 = tecla
    li $t1, 0x52         # 'R'
    beq $v0, $t1, reiniciar
    li $t1, 0x72         # 'r'
    beq $v0, $t1, reiniciar

    la $a0, MSG_TCHAU
    li $v0, 4
    syscall
    li $v0, 10           # syscall exit
    syscall

reiniciar:
    j main               # recomeça: redesenha o tabuleiro e espera uma tecla
