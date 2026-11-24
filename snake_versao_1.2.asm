# UNIVERSIDADE FEDERAL RURAL DE PERNAMBUCO
# ARQUITETURA E ORGANIZACÃO DE COMPUTADORES (AOC) - 2026.2
# PROJETO SNAKE  - ASSEMBLY MIPS  -  VERSAO 1.2
# Professora: MILLENA DE ANDRADE ALMEIDA GOMES CAVALCANTI
# Alunos: Augusto Itapoã
#			Renato Neves
#			Vitor Cardoso
#
# DESCRICAO: O jogo segue as especificacoes em https://view.genially.com/622931ea1b54ab00188cdf57
#
# VERSAO 1.2 - CORRECOES E MELHORIAS IMPLEMENTADAS:
#   1. Corrigida a colisao com a propria cauda (falso positivo): a cauda eh
#      ignorada na verificacao de colisao quando a cobra nao comeu.
#   2. Protecao contra estouro do vetor snake_addrs (limite de 1024 celulas).
#   3. Condicao de vitoria: o jogo termina quando o tabuleiro eh todo ocupado,
#      evitando o loop infinito em gerar_comida.
#   4. Controle por setas do teclado (sequencias de escape MMIO) alem de WASD.
#   5. Pausa do jogo com as teclas P/p ou ESPACO.
#   6. Velocidade progressiva: o intervalo entre movimentos diminui conforme
#      a pontuacao/crescimento da cobra.
#   7. gerar_comida usa parametros em registradores ($a0/$a1 = row/col) em vez
#      das variaveis globais cabeca_row/cabeca_col como temporarias. Foi criada
#      calcular_endereco_rowcol para calcular enderecos de posicoes arbitrayas.
#   8. Rotinas de desenho preservam os registradores temporarios que utilizam.
#
# CONFIGURACAO NO MARS:
# 1. Tools -> Bitmap Display:
#    - Base address for display: 0x10010000
#    - Display width in pixels:  512
#    - Display height in pixels: 512
#    - Unit width in pixels:     1
#    - Unit height in pixels:    1  (em versoes antigas: Pixel Pitch = 1)
#    - Clique em "Connect to MIPS"
#	 - Manter a Janela ABERTA
# 2. Settings -> Enable MMIO (marcar).
# 3. Settings -> Memory Configuration: mantenha "Default".
#		Manter a janela ABERTA
# 4. Assemble e Run
#
# No funcionamento do jogo temos:
#   - Fundo em xadrez (preto / azul-cinza escuro)
#   - Cabeça da cobra em verde escuro
#   - Corpo da cobra em verde claro
#   - Comida em vermelho
#
# OBSERVACAO SOBRE MEMORIA:
# O Bitmap Display usa 1 MB a partir de 0x10010000. Para nao sobrescrever as
# variaveis do jogo, a secao .data eh montada em 0x10000000 (abaixo do display).
# =============================================================================

.data 0x10000000
.align 2

# --- Enderecos e Constantes ---
BASE_DISPLAY:   .word 0x10010000
TECLADO_MMIO:   .word 0xffff0000
TAMANHO_GRADE:  .word 32
TAM_CELULA:     .word 16
LARGURA_DISP:   .word 512
ALTURA_DISP:    .word 512
TAM_MAX_COBRA:  .word 1024          # 32x32 celulas

# --- Cores (Formato 0x00RRGGBB) ---
COR_FUNDO:      .word 0x00000000    # Preto (casa par do tabuleiro)
COR_FUNDO2:     .word 0x00101820    # Azul-cinza escuro (casa impar)
COR_COBRA_CORPO: .word 0x0000FF00   # Verde
COR_COBRA_CABECA: .word 0x0000AA00  # Verde Escuro
COR_COMIDA:     .word 0x00FF0000    # Vermelho

# --- Estruturas de Dados ---
# Vetor de enderecos base para as celulas da cobra (maximo 1024 celulas)
snake_addrs:    .space 4096         # 1024 * 4 bytes
snake_tamanho:  .word 1
snake_direcao:  .word 0             # 0: Cima, 1: Direita, 2: Baixo, 3: Esquerda
comida_addr:    .word 0
pontuacao:      .word 0
game_over:      .word 0
venceu:         .word 0             # 1 se o tabuleiro foi todo preenchido

# Variaveis de posicao da cabeca (para facilitar calculos de movimento)
cabeca_row:     .word 0
cabeca_col:     .word 0

# Estado do teclado para sequencias de escape das setas
escape_estado:  .word 0             # 0 = normal, 1 = recebeu 0x1B, 2 = recebeu '['

# --- Mensagens ---
MSG_GAME_OVER:  .asciiz "\nGAME OVER! Pontuacao final: "
MSG_VITORIA:    .asciiz "\nVOCE GANHOU! Pontuacao final: "
MSG_PAUSA:      .asciiz "\n--- PAUSADO ---\n"

.text

# =============================================================================
# FUNCAO: main
# Coordena o ciclo de vida do jogo.
# =============================================================================
game_entry:
    jal inicializar_jogo

loop_principal:
    # 1. Calcular a velocidade conforme a pontuacao (tanto menor, quanto maior)
    jal calcular_delay

    # 2. Esperar o intervalo calculado (syscall sleep em ms)
    move $a0, $v0
    li $v0, 32
    syscall

    # 3. Ler teclado (Input)
    jal ler_teclado

    # 4. Atualizar logica (Update)
    jal atualizar_logica

    # 5. Verificar fim de jogo (derrota ou vitoria)
    lw $t0, game_over
    bne $t0, $zero, fim_de_jogo

    # 6. Desenhar Frame (Render)
    jal desenhar_frame

    j loop_principal

# =============================================================================
# FUNCAO: calcular_delay
# Retorna em $v0 o intervalo entre movimentos (ms), que diminui conforme a
# pontuacao. Comeca em 500 ms e vai ate no minimo 100 ms.
# =============================================================================
calcular_delay:
    lw $t0, pontuacao
    li $t1, 20
    div $t0, $t1                 # t0 = pontuacao / 20 (reduz de 20 em 20 pontos)
    mflo $t0
    li $t1, 500
    sub $v0, $t1, $t0            # delay = 500 - (pontuacao/20)
    blt $v0, $zero, delay_minimo
    li $t2, 100
    bge $v0, $t2, delay_ok
delay_minimo:
    li $v0, 100
delay_ok:
    jr $ra

# =============================================================================
# FUNCAO: inicializar_jogo
# Prepara o ambiente, limpa o display e posiciona a cobra.
# =============================================================================
inicializar_jogo:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Limpar display (pintar fundo)
    li $a0, 0x10010000  # Endereco inicial
    lw $a1, COR_FUNDO
    jal desenhar_celula_completa

    # Configurar cobra inicial na (0,0)
    li $t0, 0           # row = 0
    li $t1, 0           # col = 0
    sw $t0, cabeca_row
    sw $t1, cabeca_col

    # Calcular endereco base da celula (0,0) e salvar no vetor
    jal calcular_endereco_celula
    sw $v0, snake_addrs    # snake_addrs[0] = addr

    # Resetar estado
    li $t0, 1
    sw $t0, snake_tamanho
    li $t0, 1            # Direcao inicial = 1 (Direita), para nao sair do tabuleiro
    sw $t0, snake_direcao
    li $t0, 0
    sw $t0, pontuacao
    sw $t0, game_over
    sw $t0, venceu
    sw $t0, escape_estado

    # Gerar primeira comida (passando row=0, col=0 apenas como referencia;
    # a funcao ja evita as celulas ocupadas pela cobra)
    li $a0, 0
    li $a1, 0
    jal gerar_comida

    # Desenhar o primeiro frame imediatamente (antes do primeiro movimento)
    jal desenhar_frame

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNCAO: ler_teclado
# Le entrada via MMIO e atualiza a direcao da cobra.
# MMIO do teclado no MARS: 0xffff0000 = controle, 0xffff0004 = caractere.
# Reconhece WASD (maiusculas/minusculas), setas (via escape) e P/Espaco (pausa).
# =============================================================================
ler_teclado:
    addi $sp, $sp, -4
    sw $s0, 0($sp)

    lw $t0, TECLADO_MMIO

    # So le o caractere se o bit de "pronto" estiver ligado
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beq $t1, $zero, fim_ler_teclado

    lw $a0, 4($t0)      # Le o caractere do teclado

    # Se nao houver tecla (caractere 0 ou NUL), sai
    beq $a0, $zero, fim_ler_teclado

    # --- Tratamento de sequencias de escape para as setas ---
    lw $s0, escape_estado
    bne $s0, $zero, tratar_escape

    # Estado normal: verificar se eh o inicio de uma sequencia (ESC = 0x1B)
    li $t1, 0x1B
    beq $a0, $t1, esc_recebido

    # --- Pausa: teclas P/p (0x50/0x70) ou ESPACO (0x20) ---
    li $t1, 0x50         # 'P'
    beq $a0, $t1, alternar_pausa
    li $t1, 0x70         # 'p'
    beq $a0, $t1, alternar_pausa
    li $t1, 0x20         # ' ' (espaco)
    beq $a0, $t1, alternar_pausa

    # --- Verificar teclas W, A, S, D (maiusculas e minusculas) ---
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

esc_recebido:
    li $s0, 1
    sw $s0, escape_estado
    j fim_ler_teclado

tratar_escape:
    # Estado 1: esperando o '[' (0x5B) apos o ESC
    beq $s0, 1, esperando_bracket

    # Estado 2: apos ESC + '['; agora vem A/B/C/D
    li $t1, 0x41         # 'A' -> Cima
    beq $a0, $t1, seta_cima
    li $t1, 0x42         # 'B' -> Baixo
    beq $a0, $t1, seta_baixo
    li $t1, 0x43         # 'C' -> Direita
    beq $a0, $t1, seta_dir
    li $t1, 0x44         # 'D' -> Esquerda
    beq $a0, $t1, seta_esq
    j reset_escape

esperando_bracket:
    li $t1, 0x5B         # '['
    beq $a0, $t1, bracket_recebido
    j reset_escape

bracket_recebido:
    li $s0, 2
    sw $s0, escape_estado
    j fim_ler_teclado

seta_cima:
    j reset_escape_dir_cima
seta_baixo:
    j reset_escape_dir_baixo
seta_dir:
    j reset_escape_dir_dir
seta_esq:
    j reset_escape_dir_esq

reset_escape:
    li $s0, 0
    sw $s0, escape_estado
    j fim_ler_teclado

# Ao processar a ultima tecla da seta, reinicia o estado e vai para a validacao
reset_escape_dir_cima:
    li $t2, 0
    sw $zero, escape_estado
    move $t1, $zero         # direcao 0 (Cima)
    j validar_direcao
reset_escape_dir_baixo:
    sw $zero, escape_estado
    li $t1, 2               # direcao 2 (Baixo)
    j validar_direcao
reset_escape_dir_dir:
    sw $zero, escape_estado
    li $t1, 1               # direcao 1 (Direita)
    j validar_direcao
reset_escape_dir_esq:
    sw $zero, escape_estado
    li $t1, 3               # direcao 3 (Esquerda)
    j validar_direcao

alternar_pausa:
    jal fazer_pausa
    j fim_ler_teclado

set_cima:
    li $t1, 0            # Direcao 0
    j validar_direcao
set_esq:
    li $t1, 3            # Direcao 3
    j validar_direcao
set_baixo:
    li $t1, 2            # Direcao 2
    j validar_direcao
set_dir:
    li $t1, 1            # Direcao 1
    j validar_direcao

validar_direcao:
    # Evitar reversao de 180 graus se tamanho > 1
    lw $t2, snake_tamanho
    ble $t2, 1, aplicar_dir

    lw $t3, snake_direcao
    # Se dir atual eh 0 (Cima), nao pode ir para 2 (Baixo)
    beq $t3, $zero, check_reverso_baixo
    # Se dir atual eh 1 (Dir), nao pode ir para 3 (Esq)
    beq $t3, 1, check_reverso_esq
    # Se dir atual eh 2 (Baixo), nao pode ir para 0 (Cima)
    beq $t3, 2, check_reverso_cima
    # Se dir atual eh 3 (Esq), nao pode ir para 1 (Dir)
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
    lw $s0, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNCAO: fazer_pausa
# Exibe mensagem e aguarda outra tecla P/p/Espaco para retomar o jogo.
# =============================================================================
fazer_pausa:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $a0, MSG_PAUSA
    li $v0, 4
    syscall

pausa_loop:
    li $a0, 100
    li $v0, 32
    syscall

    lw $t0, TECLADO_MMIO
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beq $t1, $zero, pausa_loop

    lw $a0, 4($t0)
    li $t1, 0x50         # 'P'
    beq $a0, $t1, fim_pausa
    li $t1, 0x70         # 'p'
    beq $a0, $t1, fim_pausa
    li $t1, 0x20         # ' '
    beq $a0, $t1, fim_pausa
    j pausa_loop

fim_pausa:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNCAO: atualizar_logica
# Processa movimento, colisoes e crescimento.
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

    # 1. Obter posicao atual da cabeca
    lw $t0, cabeca_row
    lw $t1, cabeca_col
    lw $t2, snake_direcao

    # 2. Calcular nova posicao baseada na direcao
    # Direcoes: 0: Cima (row-1), 1: Dir (col+1), 2: Baixo (row+1), 3: Esq (col-1)
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
    # 3. Verificar colisao com bordas
    blt $t0, $zero, colidiu
    li $t4, 32
    bge $t0, $t4, colidiu
    blt $t1, $zero, colidiu
    bge $t1, $t4, colidiu

    # 4. Calcular endereco da nova cabeca para verificar colisao com corpo e comida
    sw $t0, cabeca_row
    sw $t1, cabeca_col
    jal calcular_endereco_celula
    move $s0, $v0        # $s0 = nova_cabeca_addr

    # 5. Verificar se vai comer (usado para decidir se a cauda deve ser ignorada)
    lw $s6, comida_addr
    beq $s0, $s6, comeu_comida

    # --- MOVIMENTO NORMAL (nao comeu) ---
    # A cauda atual (ultimo elemento) sera removida, entao deve ser ignorada
    # na verificacao de colisao. Caso contrario, ha falso positivo de colisao.
    lw $s1, snake_tamanho
    addi $s2, $zero, 0    # i = 0
    addi $s3, $s1, -1     # indice da cauda = tamanho - 1
loop_corpo:
    beq $s2, $s3, check_comida    # ignora a cauda
    sll $t3, $s2, 2
    la $t4, snake_addrs
    add $t4, $t4, $t3
    lw $t5, 0($t4)       # addr_corpo = snake_addrs[i]
    beq $t5, $s0, colidiu
    addi $s2, $s2, 1
    j loop_corpo

check_comida:
    # Aumentar pontuacao base (+1)
    lw $s7, pontuacao
    addi $s7, $s7, 1
    sw $s7, pontuacao

    # Apagar a cauda antiga no display antes de removela do vetor
    lw $s1, snake_tamanho
    addi $t0, $s1, -1    # indice da cauda = tamanho - 1
    sll $t0, $t0, 2
    la $t1, snake_addrs
    add $t1, $t1, $t0
    lw $a0, 0($t1)
    jal desenhar_fundo_celula

    # Mover cobra (deslocar elementos no vetor)
    lw $s1, snake_tamanho
    addi $s2, $s1, -1    # i = size - 1
loop_shift_body:
    ble $s2, $zero, fim_shift_body
    sll $s3, $s2, 2
    la $s4, snake_addrs
    add $s4, $s4, $s3
    addi $s5, $s2, -1
    sll $s5, $s5, 2
    la $s6, snake_addrs
    add $s6, $s6, $s5
    lw $s7, 0($s6)
    sw $s7, 0($s4)
    addi $s2, $s2, -1
    j loop_shift_body

fim_shift_body:
    sw $s0, snake_addrs    # snake_addrs[0] = nova_cabeca
    j fim_atualizar

# --- CASO: COMEU COMIDA ---
comeu_comida:
    # Protecao contra estouro do vetor: se ja atingiu 1024, nao cresce mais.
    # Nesse caso, o tabuleiro esta completo e o jogo termina com vitoria.
    lw $s1, snake_tamanho
    lw $t0, TAM_MAX_COBRA
    bge $s1, $t0, vitoria

    # Aumentar tamanho (+1)
    addi $s1, $s1, 1
    sw $s1, snake_tamanho

    # Aumentar pontuacao (+5)
    lw $s7, pontuacao
    addi $s7, $s7, 5
    sw $s7, pontuacao

    # Deslocar todos (o novo elemento nao remove o ultimo)
    lw $s1, snake_tamanho    # agora eh o novo tamanho
    addi $s2, $s1, -1        # i = novo_tamanho - 1
loop_shift_eat_body:
    ble $s2, $zero, fim_shift_eat
    sll $s3, $s2, 2
    la $s4, snake_addrs
    add $s4, $s4, $s3
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

    # Se apos crescer o tabuleiro ficou completo, venceu
    lw $s1, snake_tamanho
    lw $t0, TAM_MAX_COBRA
    bge $s1, $t0, vitoria

    # Gerar nova comida com parametros em registradores (sem variantas globais)
    # Extrai row/col da nova cabeca a partir de seu endereco
    move $a0, $s0
    jal extrair_row_col
    move $a0, $v0          # row da cabeca
    move $a1, $v1          # col da cabeca
    jal gerar_comida

    j fim_atualizar

vitoria:
    li $t0, 1
    sw $t0, game_over
    sw $t0, venceu
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
# FUNCAO: extrair_row_col
# Dado um endereco de celula em $a0, retorna row em $v0 e col em $v1.
# =============================================================================
extrair_row_col:
    lw $t0, BASE_DISPLAY
    sub $t1, $a0, $t0
    srl $v0, $t1, 15     # row = offset / 32768
    srl $v1, $t1, 6
    andi $v1, $v1, 31    # col = (offset / 64) % 32
    jr $ra

# =============================================================================
# FUNCAO: desenhar_frame
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

    # Diferenciar cabeca do corpo
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
# FUNCAO: gerar_comida
# Gera uma posicao aleatoria para a comida.
# $a0 = row de referencia, $a1 = col de referencia (nao usam variaveis globais).
# Usa syscall 42 (RandIntRange): $a1 = limite superior, resultado em $a0.
# =============================================================================
gerar_comida:
    addi $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)      # row da cabeca (referencia)
    sw $s1, 12($sp)      # col da cabeca (referencia)
    sw $s2, 8($sp)       # addr da nova comida
    sw $s3, 4($sp)       # tamanho da cobra
    sw $s4, 0($sp)       # contador i

    move $s0, $a0
    move $s1, $a1

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

    # Calcular endereco da comida com rotina por parametros
    move $a0, $t0
    move $a1, $t1
    jal calcular_endereco_rowcol
    move $s2, $v0        # addr_comida_nova

    # Verificar se a comida nao esta sobre a cobra
    lw $s3, snake_tamanho
    li $s4, 0            # i = 0
loop_check_comida:
    beq $s4, $s3, comida_ok
    sll $t5, $s4, 2
    la $t6, snake_addrs
    add $t6, $t6, $t5
    lw $t7, 0($t6)
    beq $t7, $s2, gerar_comida_loop   # Se colidir, tenta de novo
    addi $s4, $s4, 1
    j loop_check_comida

comida_ok:
    sw $s2, comida_addr
    lw $s4, 0($sp)
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addi $sp, $sp, 24
    jr $ra

# =============================================================================
# FUNCAO: calcular_endereco_rowcol
# Calcula o endereco base da celula (row, col) passada em $a0/$a1.
# Retorna em $v0. Nao le as variaveis globais cabeca_row/cabeca_col.
# =============================================================================
calcular_endereco_rowcol:
    lw $t2, BASE_DISPLAY
    sll $t3, $a0, 15     # row * 32768
    sll $t4, $a1, 6      # col * 64
    add $t5, $t3, $t4
    add $v0, $t2, $t5
    jr $ra

# =============================================================================
# FUNCAO: desenhar_celula
# Desenha um quadrado 16x16 pixels no display.
# $a0 = endereco base da celula, $a1 = cor.
# Preserva os registradores temporarios $t0-$t5 que utiliza.
# =============================================================================
desenhar_celula:
    addi $sp, $sp, -24
    sw $t0, 20($sp)
    sw $t1, 16($sp)
    sw $t2, 12($sp)
    sw $t3, 8($sp)
    sw $t4, 4($sp)
    sw $t5, 0($sp)

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

    lw $t5, 0($sp)
    lw $t4, 4($sp)
    lw $t3, 8($sp)
    lw $t2, 12($sp)
    lw $t1, 16($sp)
    lw $t0, 20($sp)
    addi $sp, $sp, 24
    jr $ra

# =============================================================================
# FUNCAO AUXILIAR: desenhar_celula_completa
# Desenha o fundo do tabuleiro inteiro (32x32 celulas = 512x512 pixels).
# O fundo eh um xadrez discreto para dar visibilidade ao display.
# $a0 = endereco base do display.
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
# FUNCAO AUXILIAR: desenhar_fundo_celula
# Desenha uma celula com a cor de fundo correspondente a sua posicao no xadrez.
# $a0 = endereco base da celula.
# Preserva os registradores temporarios $t0-$t4 que utiliza.
# =============================================================================
desenhar_fundo_celula:
    addi $sp, $sp, -24
    sw $ra, 20($sp)
    sw $t0, 16($sp)
    sw $t1, 12($sp)
    sw $t2, 8($sp)
    sw $t3, 4($sp)
    sw $t4, 0($sp)

    # Descobre row e col a partir do endereco da celula
    lw $t0, BASE_DISPLAY
    sub $t1, $a0, $t0
    srl $t2, $t1, 15     # row = offset / 32768
    srl $t3, $t1, 6
    andi $t3, $t3, 31    # col = (offset / 64) % 32

    # Xadrez: (row + col) par -> COR_FUNDO, impar -> COR_FUNDO2
    add $t4, $t2, $t3
    andi $t4, $t4, 1
    beq $t4, $zero, fundo_cor_par
    lw $a1, COR_FUNDO2
    j fundo_desenhar
fundo_cor_par:
    lw $a1, COR_FUNDO
fundo_desenhar:
    jal desenhar_celula

    lw $t4, 0($sp)
    lw $t3, 4($sp)
    lw $t2, 8($sp)
    lw $t1, 12($sp)
    lw $t0, 16($sp)
    lw $ra, 20($sp)
    addi $sp, $sp, 24
    jr $ra

# =============================================================================
# FUNCAO: calcular_endereco_celula
# Calcula o endereco base de uma celula (row, col) de 16x16.
# Usa cabeca_row/cabeca_col. Retorna em $v0.
# =============================================================================
calcular_endereco_celula:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    lw $a0, cabeca_row
    lw $a1, cabeca_col
    jal calcular_endereco_rowcol
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# =============================================================================
# FUNCAO: fim_de_jogo
# Exibe a pontuacao e encerra (ou exibe mensagem de vitoria).
# =============================================================================
fim_de_jogo:
    lw $t0, venceu
    bne $t0, $zero, fim_vitoria

    la $a0, MSG_GAME_OVER
    li $v0, 4
    syscall
    j imprimir_pontuacao

fim_vitoria:
    la $a0, MSG_VITORIA
    li $v0, 4
    syscall

imprimir_pontuacao:
    lw $a0, pontuacao
    li $v0, 1
    syscall

    li $v0, 10           # syscall exit
    syscall
