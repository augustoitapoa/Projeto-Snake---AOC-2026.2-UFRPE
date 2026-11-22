# UNIVERSIDADE FEDERAL RURAL DE PERNAMBUCO
# ARQUITETURA E ORGANIZACÃO DE COMPUTADORES (AOC) - 2026.2
#PROJETO SNAKE  - ASSEMBLY MIPS
#Professora: MILLENA DE ANDRADE ALMEIDA GOMES CAVALCANTI
#Alunos: Augusto Itapoã
#				Renato Neves
#				Vitor Cardoso
#
# DESCRIÇÃO: O jogo segue as especificacoes em https://view.genially.com/622931ea1b54ab00188cdf57
# 
# 
# 
#
# CONFIGURAÇÃO NO MARS:
# 1. Tools -> Bitmap Display:
#    - Base address for display: 0x10010000
#    - Display width in pixels:  512
#    - Display height in pixels: 512
#    - Unit width in pixels:     1
#    - Unit height in pixels:    1  (em versões antigas: Pixel Pitch = 1)
#    - Clique em "Connect to MIPS"
#	 - Manter a Janela ABERTA
# 2. Settings -> Enable MMIO (marcar).
# 3. Settings -> Memory Configuration: mantenha "Default".
# 		Manter a janela ABERTA
# 4. Assemble e Run 
#
#
# No funcionamento do jogo temos: 
#   - Fundo em xadrez (preto / azul-cinza escuro)
#   - Cabeça da cobra em verde escuro
#   - Corpo da cobra em verde claro
#   - Comida em vermelho 
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
comida_addr:    .word 0
pontuacao:      .word 0
game_over:      .word 0

# Variáveis de posição da cabeça (para facilitar cálculos de movimento)
cabeca_row:     .word 0
cabeca_col:     .word 0

# --- Mensagens ---
MSG_GAME_OVER:  .asciiz "\nGAME OVER! Pontuacao final: "

.text

# =============================================================================
# FUNÇÃO: main
# Coordena o ciclo de vida do jogo.
# =============================================================================
main:
    jal inicializar_jogo

loop_principal:
    # 1. Esperar 500ms
    li $a0, 500
    li $v0, 32          # syscall sleep (ms)
    syscall

    # 2. Ler teclado (Input)
    jal ler_teclado

    # 3. Atualizar lógica (Update)
    jal atualizar_logica

    # 4. Verificar Game Over
    lw $t0, game_over
    bne $t0, $zero, fim_de_jogo

    # 5. Desenhar Frame (Render)
    jal desenhar_frame

    j loop_principal

# =============================================================================
# FUNÇÃO: inicializar_jogo
# Prepara o ambiente, limpa o display e posiciona a cobra.
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
    jal calcular_endereco_celula
    sw $v0, snake_addrs    # snake_addrs[0] = addr

    # Resetar estado
    li $t0, 1
    sw $t0, snake_tamanho
    li $t0, 1            # Direção inicial = 1 (Direita), para não sair do tabuleiro
    sw $t0, snake_direcao
    li $t0, 0
    sw $t0, pontuacao
    sw $t0, game_over

    # Gerar primeira comida
    jal gerar_comida

    # Desenhar o primeiro frame imediatamente (antes do primeiro movimento)
    jal desenhar_frame

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: ler_teclado
# Lê entrada via MMIO e atualiza a direção da cobra.
# MMIO do teclado no MARS: 0xffff0000 = controle, 0xffff0004 = caractere.
# =============================================================================
ler_teclado:
    lw $t0, TECLADO_MMIO

    # Só lê o caractere se o bit de "pronto" estiver ligado
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beq $t1, $zero, fim_ler_teclado

    lw $a0, 4($t0)      # Lê o caractere do teclado

    # Se não houver tecla (caractere 0 ou NUL), sai
    beq $a0, $zero, fim_ler_teclado

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

fim_ler_teclado:
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
    jal calcular_endereco_celula
    move $s0, $v0        # $s0 = nova_cabeca_addr

    # 5. Verificar colisão com corpo
    lw $s1, snake_tamanho
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
    lw $s6, comida_addr
    beq $s0, $s6, comeu_comida

# CASO: MOVIMENTO NORMAL (não comeu)
    # Aumentar pontuação base (+1)
    lw $s7, pontuacao
    addi $s7, $s7, 1
    sw $s7, pontuacao

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

    # Aumentar pontuação (+5)
    lw $s7, pontuacao
    addi $s7, $s7, 5
    sw $s7, pontuacao

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

    # 1. Desenhar Comida
    lw $a0, comida_addr
    lw $a1, COR_COMIDA
    jal desenhar_celula

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
# FUNÇÃO: gerar_comida
# Gera uma posição aleatória para a comida.
# Usa syscall 42 (RandIntRange): $a1 = limite superior, resultado em $a0.
# =============================================================================
gerar_comida:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

gerar_comida_loop:
    # row = random % 32
    li $a1, 32
    li $v0, 42
    syscall
    move $t0, $a0

    # col = random % 32
    li $a1, 32
    li $v0, 42
    syscall
    move $t1, $a0

    # Calcular endereço (preservando a posição real da cabeça)
    lw $t8, cabeca_row
    lw $t9, cabeca_col
    sw $t0, cabeca_row    # temporário para calcular
    sw $t1, cabeca_col
    jal calcular_endereco_celula
    move $t2, $v0        # addr_comida_nova
    sw $t8, cabeca_row
    sw $t9, cabeca_col

    # Verificar se a comida não está sobre a cobra
    lw $t3, snake_tamanho
    li $t4, 0            # i = 0
loop_check_comida:
    beq $t4, $t3, comida_ok
    sll $t5, $t4, 2
    la $t6, snake_addrs
    add $t6, $t6, $t5
    lw $t7, 0($t6)
    beq $t7, $t2, gerar_comida_loop   # Se colidir, tenta de novo
    addi $t4, $t4, 1
    j loop_check_comida

comida_ok:
    sw $t2, comida_addr
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNÇÃO: desenhar_celula
# Desenha um quadrado 16x16 pixels no display.
# $a0 = endereço base da célula, $a1 = cor.
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
# FUNÇÃO: calcular_endereco_celula
# Calcula o endereço base de uma célula (row, col) de 16x16.
# Retorna em $v0.
# =============================================================================
calcular_endereco_celula:
    # row em cabeca_row, col em cabeca_col
    lw $t0, cabeca_row
    lw $t1, cabeca_col
    lw $t2, BASE_DISPLAY

    # offset = (row * 16 * 512 + col * 16) * 4
    # offset = row * 32768 + col * 64
    sll $t3, $t0, 15     # row * 32768
    sll $t4, $t1, 6      # col * 64
    add $t5, $t3, $t4
    add $v0, $t2, $t5
    jr $ra

# =============================================================================
# FUNÇÃO: fim_de_jogo
# Exibe a pontuação e para.
# =============================================================================
fim_de_jogo:
    la $a0, MSG_GAME_OVER
    li $v0, 4
    syscall

    lw $a0, pontuacao
    li $v0, 1
    syscall

    li $v0, 10           # syscall exit
    syscall
