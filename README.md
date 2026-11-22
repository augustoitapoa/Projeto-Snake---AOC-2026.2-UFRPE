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

1. **Ferramentas → Bitmap Display** (exibição de bitmap):
   - Endereço base para exibição: `0x10010000`
   - Largura/altura da exibição: `512` x `512` pixels
   - Largura/altura da unidade: `1` (em versões antigas, Pixel Pitch = 1)
   - Clique em **Connect to MIPS** (conectar ao MIPS) e mantenha a janela aberta.
2. **Configurações → Enable MMIO** (habilitar MMIO — marcar a opção).
3. **Configurações → Memory Configuration** (configuração de memória): manter o valor `Default` (padrão).
4. Monte o código (`F3`) e execute (`F5`).

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
variáveis do jogo, a seção `.data` é montada em `0x10000000` (abaixo da exibição).

---

## Funções implementadas (e o que cada uma faz)

| Função | Situação | Descrição |
|--------|----------|-----------|
| `main` | Funcional | Coordena o ciclo de vida do jogo: espera 500 ms (`syscall 32`), lê o teclado, atualiza a lógica, verifica `game_over` e desenha o quadro em loop. |
| `inicializar_jogo` | Funcional | Limpa a exibição, posiciona a cobra na célula (0,0), inicializa tamanho = 1, direção = direita, zera a pontuação e `game_over`, gera a primeira comida e desenha o quadro inicial. |
| `ler_teclado` | Parcial | Lê o MMIO do teclado (`0xffff0000`/`0xffff0004`), reconhece W/A/S/D (maiúsculas e minúsculas) e bloqueia reversões de 180°. Não reconhece as setas do teclado. |
| `validar_direcao` (incorporada em `ler_teclado`) | Parcial | Impede inverter a direção quando `tamanho > 1`. A lógica está correta para os pares opostos. |
| `atualizar_logica` | Parcial | Calcula a nova posição da cabeça, detecta colisão com as bordas e com o próprio corpo, trata o caso de comer a comida (cresce +5 pontos), o movimento normal (+1 ponto), o deslocamento do vetor `snake_addrs` e a atualização da cauda na exibição. |
| `desenhar_frame` | Funcional | Desenha a comida e percorre `snake_addrs` desenhando a cabeça com cor diferente do corpo. |
| `gerar_comida` | Funcional | Usa `syscall 42` para sortear linha/coluna (0–31), calcula o endereço da célula e evita que a comida nasça sobre a cobra, sorteando novamente em caso de colisão. Observação: usa as variáveis `cabeca_row`/`cabeca_col` como temporárias, mas as restaura corretamente. |
| `desenhar_celula` | Funcional | Pinta um quadrado de 16x16 pixels a partir de um endereço base passado em `$a0` com a cor em `$a1`. |
| `desenhar_celula_completa` | Funcional | Percorre as 32x32 células do tabuleiro e chama `desenhar_fundo_celula` para montar o fundo em xadrez. |
| `desenhar_fundo_celula` | Funcional | Infere `row`/`col` a partir do endereço e escolhe a cor do xadrez: par → preto, ímpar → azul-cinza escuro. |
| `calcular_endereco_celula` | Funcional | Converte `(cabeca_row, cabeca_col)` em endereço de memória: `base + row*32768 + col*64`, retornando em `$v0`. |
| `fim_de_jogo` | Funcional | Exibe a mensagem `GAME OVER! Pontuacao final: ` por meio da `syscall 4`, imprime a pontuação com a `syscall 1` e encerra com a `syscall 10`. |

---

## Bugs conhecidos

1. **Colisão com a própria cauda conta como derrota indevidamente.**
   A verificação de colisão com o corpo ocorre antes da remoção da cauda antiga,
   fazendo o jogo encerrar quando a cobra se move para uma célula que a cauda
   está desocupando.

2. **O crescimento pode ultrapassar o limite do vetor.**
   O tamanho da cobra é incrementado sem verificar a capacidade máxima de
   1024 posições do vetor `snake_addrs`.

3. **Velocidade fixa e sem aceleração.**
   O intervalo de 500 ms entre os movimentos é constante, sem aumento de
   velocidade conforme a pontuação.

4. **`gerar_comida` usa variáveis globais como temporárias.**
   A função salva e restaura `cabeca_row` e `cabeca_col` para reaproveitar
   `calcular_endereco_celula`, criando acoplamento entre rotinas.

5. **Rotinas de desenho não preservam os registradores temporários.**
   `desenhar_celula` e `desenhar_fundo_celula` alteram os registradores
   `$t0`–`$t5` sem salvar seu conteúdo.

6. **`ler_teclado` não trata as teclas de seta.**
   Somente as teclas W/A/S/D são reconhecidas.

7. **`main` não possui condição de vitória.**
   Não há verificação de tabuleiro completo. Se todas as células forem ocupadas,
   a geração de comida entra em loop infinito e o programa trava.

8. **A pontuação aumenta a cada movimento, e não apenas ao comer.**
   O código soma +1 por passo e +5 ao comer, o que difere da maioria das
   implementações de Snake.

---

## Funcionalidades pendentes / não implementadas

- **Menu inicial / tela de início** (pressione qualquer tecla para começar).
- **Tela de reinício após o fim de jogo** (o programa apenas exibe a pontuação e encerra).
- **Controle por setas do teclado** (somente WASD foi implementado).
- **Aumento de velocidade progressivo** conforme a pontuação/o crescimento.
- **Condição de vitória** (tabuleiro completo / tamanho máximo).
- **Pausa do jogo** (por exemplo, tecla `P` ou `Espaço`).
- **Dificuldades / níveis** (não há seleção de velocidade inicial).
- **Efeitos sonoros** (seria necessário MMIO de áudio ou chamadas de sistema específicas).
- **Persistência de recorde** (salvar/carregar a maior pontuação em memória ou arquivo).
- **Tratamento correto da colisão com a cauda** (ver bug 1).
- **Documentação de registradores / convenções de chamada** além dos comentários no código.

---

> Este repositório contém o código original, **sem alterações**. A análise acima
> tem finalidade documental e de planejamento para versões futuras.
