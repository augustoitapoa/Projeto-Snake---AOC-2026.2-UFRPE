# Projeto Snake — AOC 2026.2 UFRPE

Jogo **Snake** implementado em **Assembly MIPS**, desenvolvido para a disciplina de
**Arquitetura e Organização de Computadores (AOC) – 2026.2** da
**Universidade Federal Rural de Pernambuco (UFRPE)**.

Professora: Millena de Andrade Almeida Gomes Cavalcanti
Alunos: Augusto Itapoã, Renato Neves, Vitor Cardoso

O jogo segue as especificações disponíveis em:
https://view.genially.com/622931ea1b54ab00188cdf57

---

## Arquivos

- `snake_versao_1.asm` — código-fonte completo (MIPS, para o simulador MARS).
- `snake_versao_1.2.asm` — versão alternativa 1.2, implementada a partir do código original antes das correções acima. Contém correções para a colisão com a cauda, limite do vetor, condição de vitória, controle por setas (sequências de escape do MMIO), pausa, velocidade progressiva e preservação de registradores temporários nas rotinas de desenho. Use as mesmas instruções de configuração do MARS descritas abaixo.

## Como executar no MARS

1. **Tools → Bitmap Display** (exibição de bitmap):
   - Endereço base para exibição: `0x10010000 (static data)`
   - Largura/altura da exibição: `512` x `512` pixels
   - Largura/altura da unidade: `1` (em versões antigas, Pixel Pitch = 1)
   - Clique em **Connect to MIPS** (conectar ao MIPS) e mantenha a janela aberta.
2. **Tools → Keyboard and Display MMIO Simulator** (simulador de teclado):
   - Clique em **Connect to MIPS** e mantenha a janela aberta.
   - As teclas devem ser digitadas na caixa de texto de **baixo** (KEYBOARD).
3. **Settings → Memory Configuration** (configuração de memória): manter o valor `Default` (padrão).
4. Monte o código (`F3`) e execute (`F5`). As mensagens (início, pausa, pontuação e recorde) aparecem na aba **Run I/O**.

### Controles

| Tecla | Ação |
|-------|------|
| Qualquer tecla | Começar a partida |
| W / w | Cima |
| A / a | Esquerda |
| S / s | Baixo |
| D / d | Direita |
| P / p ou Espaço | Pausar / continuar |
| R / r | Jogar de novo (após o fim de jogo) |

### Elementos visuais

- Fundo em xadrez (preto / azul-cinza escuro)
- Cabeça da cobra em verde escuro
- Corpo da cobra em verde claro
- Comida em vermelho

### Regras do jogo

- Tabuleiro de 32x32 células (cada célula tem 16x16 pixels).
- A cobra começa com tamanho 1 na célula (0,0) e anda uma célula a cada 0,5 s, mantendo a última direção escolhida.
- A comida aparece em posição aleatória, nunca sobre o corpo da cobra.
- Ao comer, a cobra cresce 1 célula e a comida muda de lugar.
- Pontuação: +1 ponto a cada 0,5 s e +5 pontos a cada comida.
- Fim de jogo: a cabeça bater numa parede ou no próprio corpo. A pontuação é exibida no final.
- Vitória: a cobra ocupar as 1024 células do tabuleiro.

### Observação sobre memória

O Bitmap Display ocupa 1 MB a partir de `0x10010000`. Para não sobrescrever as
variáveis do jogo, a seção `.data` é montada em `0x10000000` (abaixo da exibição).

---

## Funções implementadas (e o que cada uma faz)

| Função | Descrição |
|--------|-----------|
| `main` | Coordena o ciclo de vida do jogo: inicializa, mostra a tela inicial e, em loop, espera 500 ms (`syscall 32`), lê o teclado, atualiza a lógica, verifica `game_over` e desenha o quadro. |
| `inicializar_jogo` | Limpa a exibição, posiciona a cobra na célula (0,0), define tamanho = 1 e direção = direita, zera a pontuação, `game_over` e `vitoria`, gera a primeira comida e desenha o quadro inicial. O recorde não é zerado. |
| `tela_inicial` | Mostra as instruções no console e espera o jogador apertar qualquer tecla para começar. |
| `esperar_tecla` | Espera até uma tecla ser apertada (checando o MMIO a cada 20 ms) e retorna o caractere em `$v0`. |
| `limpar_teclado` | Descarta uma tecla que tenha ficado pendente no MMIO. |
| `ler_teclado` | Lê o MMIO do teclado (`0xffff0000`/`0xffff0004`), reconhece W/A/S/D (maiúsculas e minúsculas), bloqueia reversões de 180° quando `tamanho > 1` e trata a pausa (P/p/Espaço). Durante a pausa o jogo fica parado e a pontuação não aumenta. |
| `atualizar_logica` | Calcula a nova posição da cabeça e detecta colisão com as bordas e com o próprio corpo (a cauda só conta quando a cobra come). Soma +1 ponto por passo e +5 ao comer, desloca o vetor `snake_addrs`, apaga a cauda antiga na exibição, toca um som ao comer (`syscall 31`) e verifica a condição de vitória. |
| `desenhar_frame` | Desenha a comida e percorre `snake_addrs` desenhando a cabeça com cor diferente do corpo. |
| `gerar_comida` | Usa a `syscall 42` (gerador de id 0) para sortear linha/coluna (0–31), calcula o endereço da célula e sorteia de novo se a comida cair sobre a cobra. Guarda seus valores em `$s0`–`$s2`, salvos na pilha. |
| `desenhar_celula` | Pinta um quadrado de 16x16 pixels a partir do endereço base em `$a0`, com a cor em `$a1`. |
| `desenhar_celula_completa` | Percorre as 32x32 células do tabuleiro e chama `desenhar_fundo_celula` para montar o fundo em xadrez. |
| `desenhar_fundo_celula` | Descobre `row`/`col` a partir do endereço e escolhe a cor do xadrez: par → preto, ímpar → azul-cinza escuro. |
| `calcular_endereco_celula` | Converte a linha (`$a0`) e a coluna (`$a1`) em endereço de memória: `base + row*32768 + col*64`, retornando em `$v0`. |
| `fim_de_jogo` | Toca um som de derrota ou de vitória (`syscall 33`), exibe a mensagem e a pontuação, atualiza e mostra o recorde da sessão e pergunta se o jogador quer jogar de novo (R) ou sair (`syscall 10`). |

---

## Correções feitas nesta versão

1. **Colisão com a própria cauda:** antes, a verificação de colisão incluía a célula da
   cauda mesmo quando a cobra não comia. Como a cauda sai do lugar nesse mesmo passo,
   o jogo terminava sem motivo. Agora a cauda só é considerada quando a cobra come
   (porque, nesse caso, ela não sai do lugar).
2. **Limite do vetor e tabuleiro cheio:** com a condição de vitória, o tamanho da cobra
   nunca passa de 1024 e a geração de comida não entra mais em loop infinito.
3. **`gerar_comida` e `calcular_endereco_celula`:** `calcular_endereco_celula` agora recebe
   linha e coluna em `$a0` e `$a1`, e `gerar_comida` não altera mais `cabeca_row`/`cabeca_col`.
4. **Instruções do MARS:** a configuração antiga mandava marcar "Enable MMIO", opção que
   não existe no MARS. O teclado funciona pelo **Keyboard and Display MMIO Simulator**.
5. **Gerador aleatório:** a `syscall 42` agora usa sempre o gerador de id 0 (`$a0 = 0`).

## Funcionalidades adicionadas nesta versão

- Tela inicial (o jogo começa ao apertar qualquer tecla).
- Pausa com P ou Espaço.
- Reinício com R após o fim de jogo.
- Recorde da sessão.
- Condição de vitória.
- Efeitos sonoros ao comer, ao perder e ao vencer.

## Observações e limitações

- **Velocidade fixa de 0,5 s:** mantida de propósito, porque é o que a especificação pede.
- **Pontuação:** +1 a cada passo e +5 a cada comida, como pede a especificação.
- **Registradores `$t` nas rotinas de desenho:** `desenhar_celula` e `desenhar_fundo_celula`
  alteram `$t0`–`$t5`. Pela convenção MIPS, os registradores `$t` são temporários: quem chama
  a função não deve contar com eles depois de um `jal`. O código segue essa convenção.
- **Setas do teclado:** não suportadas. O simulador de teclado do MARS recebe caracteres
  digitados, e as setas não geram caractere.
- **Recorde:** fica guardado só enquanto o programa está rodando. Não é salvo em arquivo.

