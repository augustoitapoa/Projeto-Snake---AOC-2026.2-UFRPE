# Projeto Snake — AOC 2026.2 UFRPE

Jogo **Snake** implementado em **Assembly MIPS**, desenvolvido para a disciplina de
**Arquitetura e Organização de Computadores (AOC) – 2026.2** da
**Universidade Federal Rural de Pernambuco (UFRPE)**.

Professora: Millena de Andrade Almeida Gomes Cavalcanti
Alunos: Augusto Itapoã, Renato Neves, Vitor Cardoso

O jogo segue as especificações disponíveis em:
https://view.genially.com/622931ea1b54ab00188cdf57

---

## Arquivo

- `snake_versao_1.asm` — código-fonte completo (MIPS, para o simulador MARS).

## Como executar no MARS

1. **Tools → Bitmap Display**:
   - Base address for display: `0x10010000`
   - Display width/height: `512` x `512` pixels
   - Unit width/height: `1` (em versões antigas, Pixel Pitch = 1)
   - Clique em **Connect to MIPS** e mantenha a janela aberta.
2. **Settings → Enable MMIO** (marcar).
3. **Settings → Memory Configuration**: manter `Default`.
4. Assemble (`F3`) e Run (`F5`).

### Controles

| Tecla | Ação        |
|-------|-------------|
| W / w | Cima        |
| A / a | Esquerda    |
| S / s | Baixo       |
| D / d | Direita     |

### Elementos visuais

- Fundo em xadrez (preto / azul-cinza escuro)
- Cabeça da cobra em verde escuro
- Corpo da cobra em verde claro
- Comida em vermelho

### Observação sobre memória

O Bitmap Display ocupa 1 MB a partir de `0x10010000`. Para não sobrescrever as
variáveis do jogo, a seção `.data` é montada em `0x10000000` (abaixo do display).

---

## Funções implementadas (e o que cada uma faz)

| Função | Status | Descrição |
|--------|--------|-----------|
| `main` | ✅ Funcional | Coordena o ciclo de vida: espera 500 ms (`syscall 32`), lê teclado, atualiza lógica, verifica `game_over` e desenha o frame em loop. |
| `inicializar_jogo` | ✅ Funcional | Limpa o display, posiciona a cobra na célula (0,0), inicializa tamanho = 1, direção = direita, zera pontuação e `game_over`, gera a primeira comida e desenha o frame inicial. |
| `ler_teclado` | ⚠️ Parcial | Lê o MMIO do teclado (`0xffff0000`/`0xffff0004`), reconhece W/A/S/D (maiúsculas e minúsculas) e bloqueia reversões de 180°. **Não reconhece as setas do teclado** (ver bugs). |
| `validar_direcao` (inline em `ler_teclado`) | ⚠️ Parcial | Impede inverter a direção quando `tamanho > 1`. A lógica está correta para os pares opostos, mas não cobre a lista de bugs abaixo. |
| `atualizar_logica` | ⚠️ Parcial | Calcula a nova posição da cabeça, detecta colisão com bordas e com o próprio corpo, tratamento de comed-comida (cresce +5 pontos), movimento normal (+1 ponto), deslocamento do vetor `snake_addrs` e atualização da cauda no display. |
| `desenhar_frame` | ✅ Funcional | Desenha a comida e percorre `snake_addrs` desenhando a cabeça com cor diferente do corpo. |
| `gerar_comida` | ✅ Funcional | Usa `syscall 42` para sortear linha/coluna (0–31), calcula o endereço da célula e **garante que a comida não nasce sobre a cobra**, sorteando novamente em caso de colisão. Observação: usa as variáveis `cabeca_row`/`cabeca_col` como temporárias, mas as restaura corretamente. |
| `desenhar_celula` | ✅ Funcional | Pinta um quadrado 16x16 pixels a partir de um endereço base passado em `$a0` com a cor em `$a1`. |
| `desenhar_celula_completa` | ✅ Funcional | Percorre as 32x32 células do tabuleiro e chama `desenhar_fundo_celula` para montar o fundo em xadrez. |
| `desenhar_fundo_celula` | ✅ Funcional | Infere `row`/`col` a partir do endereço e escolhe a cor do xadrez: par → preto, ímpar → azul-cinza escuro. |
| `calcular_endereco_celula` | ✅ Funcional | Converte `(cabeca_row, cabeca_col)` em endereço de memória: `base + row*32768 + col*64`, retornando em `$v0`. |
| `fim_de_jogo` | ✅ Funcional | Exibe a mensagem `GAME OVER! Pontuacao final: ` via `syscall 4`, imprime a pontuação via `syscall 1` e encerra com `syscall 10`. |

---

## Bugs conhecidos

1. **Colisão com a própria cauda sempre conta como derrota (falso positivo).
** Em `atualizar_logica`, a verificação de colisão com o corpo (`loop_corpo`) é feita
   **antes** de remover a cauda antiga. Assim, quando a cobra se move para a posição
   que a cauda está prestes a desocupar, o jogo encerra incorretamente. O correto
   seria ignorar a última célula (`snake_addrs[tamanho-1]`) quando a cobra não comeu.

2. **Crescimento pode ultrapassar o limite do vetor (estouro de buffer).**
   `snake_addrs` reserva 4096 bytes = 1024 posições, mas `comeu_comida` incrementa
   `snake_tamanho` sem verificar esse limite. O tabuleiro tem 1024 células (32x32),
   então teoricamente é possível alcançar o limite — porém se a lógica de colisão
   estiver com o bug 1, a cobra morre antes disso. Ainda assim, não há guarda
   explícita contra `tamanho >= 1024`.

3. **Velocidade fixa e sem aceleração.**
   O `sleep` de 500 ms em `main` é constante, não há aumento de velocidade conforme
   a pontuação, ao contrário do que jogos clássicos normalmente fazem. Isso é mais
   uma limitação de design do que um bug, mas afeta a jogabilidade.

4. **`gerar_comida` usa variáveis globais como temporárias (acoplamento frágil).**
   A função salva/restaura `cabeca_row` e `cabeca_col` para reaproveitar
   `calcular_endereco_celula`. Funciona no fluxo atual, mas é susceptível a
   problemas se a função for chamada de outro contexto (por exemplo, interrompida
   ou reentrante). Uma versão com parâmetros em registradores seria mais segura.

5. **`desenhar_celula` e `desenhar_fundo_celula` não preservam registradores `$t0`–`$t5`.**
   As funções usam registradores temporários sem documentar/salvar seu conteúdo.
   No MARS, `$t*` são caller-saved; as funções chamadoras (`atualizar_logica`,
   `desenhar_frame`, etc.) já salvam `$s*`, mas o reaproveitamento de `$t*` após
   certas chamadas pode gerar valores corrompidos se o código for estendido sem
   cuidado. No fluxo atual isso não se manifesta porque cada uso recarrega os
   valores necessários, mas é um ponto de atenção para manutenção.

6. **`ler_teclado` não trata teclas de seta.**
   O enunciado do jogo (Genially) pode esperar setas do teclado; a implementação
   reconhece apenas WASD. Para setas seria necessário ler os códigos de escape
   MMIO (`0x1B`, `[`, `A/B/C/D`).

7. **`main` não possui condição de vitória.**
   Não há verificação de "tabuleiro completo" (tamanho == 1024). Quando a cobra
   ocupa todas as células, o jogo continua tentando gerar comida forever (loop
   infinito em `gerar_comida_loop`), travando o programa. Na prática o bug 1
   impede que isso ocorra, mas é um caso limite não tratado.

8. **Pontuação incrementa a cada movimento, não apenas ao comer.**
   O código soma +1 por passo (`MOVIMENTO NORMAL`) e +5 ao comer. Isso difere da
   maioria das implementações de Snake, onde a pontuação só aumenta ao comer.
   Pode ser intencional, mas vale conferir com a especificação do professor.

---

## Funcionalidades pendentes / não implementadas

- ❌ **Menu inicial / tela de início** (pressione qualquer tecla para começar).
- ❌ **Tela de reinício após Game Over** (o programa apenas exibe a pontuação e encerra).
- ❌ **Controle por setas do teclado** (somente WASD foi implementado).
- ❌ **Aumento de velocidade progressivo** conforme a pontuação/crescimento.
- ❌ **Condição de vitória** (tabuleiro completo / tamanho máximo).
- ❌ **Pausa do jogo** (por exemplo, tecla `P` ou `Espaço`).
- ❌ **Dificuldades / níveis** (não há seleção de velocidade inicial).
- ❌ **Efeitos sonoros** (seria necessário MMIO de áudio ou syscalls específicas).
- ❌ **Persistência de recorde** (salvar/carregar maior pontuação em memória ou arquivo).
- ❌ **Tratamento de colisão com a cauda correto** (ver bug 1 — é o item mais grave).
- ❌ **Documentação de registradores / convenções de chamada** além dos comentários inline.

---

## Resumo

O projeto possui uma base sólida e **jogável**: o loop principal, inicialização,
renderização, geração de comida, controle WASD, pontuação e tela de fim de jogo
estão funcionando. Os pontos que mais merecem atenção para uma próxima versão são:

1. Corrigir a **colisão com a cauda** (bug 1);
2. Adicionar **setas do teclado** e **reinício**;
3. Implementar **velocidade progressiva** e **condição de vitória**;
4. Revisar a política de **pontuação** com base no enunciado oficial.

> Este repositório contém o código original, **sem alterações**. A análise acima
> tem finalidade documental e de planejamento para versões futuras.
