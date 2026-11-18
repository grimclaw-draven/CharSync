# CharSync

[English](../README.md) · [Deutsch](de.md) · [Français](fr.md) · [Español](es.md) · [Português](pt-BR.md) · [Italiano](it.md) · [Русский](ru.md) · [한국어](ko.md) · [简体中文](zh-CN.md) · [繁體中文](zh-TW.md)

Configure um personagem do jeito que você gosta – e dê as mesmas configurações a todos os outros. O CharSync mostra, configuração por configuração, o que vai mudar (antes → depois) e o que cada mudança faz, para você deixar de fora o que não quiser.

Para **WoW Forever**. No idioma do seu cliente do jogo: inglês, alemão, francês, espanhol, português, italiano, russo, coreano e chinês (simplificado e tradicional).

## Como funciona

1. Entre com o personagem cujas configurações devem valer para todos, abra `/charsync` e clique em **“Salvar como modelo geral”**.
2. Para macros e barras de ação, salve um **modelo de classe** uma vez por classe – eles só vão para personagens da mesma classe.
3. Quando outro personagem entra no jogo, o CharSync abre uma janela de revisão: cada diferença com antes → depois e uma explicação. Desmarque o que não quiser e clique em **“Aplicar marcados”**.

Um addon não consegue gravar arquivos de outros personagens, por isso o modelo fica salvo para a conta toda e é aplicado quando cada personagem entra no jogo.

## O que pode ser sincronizado

- Opções de interface que o WoW salva por personagem (barras de ação extras, exibição de recursos pessoais, nível da missão, opções dos quadros de raide, mapa-múndi, minimapa)
- Janelas de bate-papo (nome, tamanho da fonte, fundo, tipos de mensagem, canais) e cores do bate-papo
- O layout ativo do Modo de Edição
- Atalhos de teclado
- Quais addons estão ativados
- Perfis de addons que salvam as configurações com a biblioteca Ace3
- Macros do personagem e barras de ação – só da mesma classe
- Posições das janelas (janelas movidas, do WoW e de addons) e posições dos botões do minimapa

Gráficos, som, a maioria das opções de interface e quase todas as configurações de addons já valem para a conta toda no WoW.

## Opções

- Ative ou desative seções inteiras.
- Desmarque uma configuração específica para nunca mais sincronizá-la (vale para todos os personagens).
- Salve um modelo automaticamente (desligado por padrão): uma vez por minuto e ao sair do jogo, só quando algo mudou.
- Aplique novos modelos sem perguntar.
- Seção “Configurações da conta” (desligada por padrão): marcada, cada mudança em configurações que valem para todos os personagens (configurações de addons e opções do WoW da conta) aparece com o valor anterior – aceite ou redefina uma a uma.
- Redefina cada entrada separadamente. No personagem modelo, as mudanças desde o salvamento vão uma a uma para o modelo (**"Para o modelo"**). A última aplicação pode ser desfeita (**"Desfazer"**).
- Recolha seções; a caixa no cabeçalho marca tudo o que há nela.
- **"Configurações excluídas"** lista tudo o que você excluiu – marque para trazer de volta.

Comandos: `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`, `/charsync icon` (traz de volta o botão do minimapa)
