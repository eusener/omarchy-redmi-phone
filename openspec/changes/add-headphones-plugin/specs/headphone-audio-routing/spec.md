# Spec Delta

## Purpose

Permite escolher como o fone Bluetooth ativo é usado pelo sistema de áudio: modo música ou chamada, codec, saída padrão e troca automática para o modo chamada.

## ADDED Requirements

### Requirement: Modos de áudio
O painel SHALL oferecer os modos "Música" (A2DP, só saída, alta qualidade) e "Chamada" (HFP/HSP, com microfone, qualidade menor), listando apenas os que o fone ativo suporta e marcando o modo atual.

#### Scenario: Mudar para modo chamada
- **WHEN** o fone ativo está em "Música" e o usuário escolhe "Chamada"
- **THEN** o perfil do cartão Bluetooth passa a ser um perfil HFP/HSP, um microfone do fone fica disponível e o painel marca "Chamada"

#### Scenario: Fone só com A2DP
- **WHEN** o fone ativo não expõe nenhum perfil HFP/HSP
- **THEN** a opção "Chamada" não é oferecida

### Requirement: Codec
Dentro de cada modo, o painel SHALL listar os codecs que o fone e o sistema oferecem (por exemplo SBC e SBC-XQ em Música; mSBC e CVSD em Chamada), marcar o atual e trocar ao ser escolhido. Escolher um modo sem codec SHALL usar o perfil de maior prioridade desse modo.

#### Scenario: Ativar SBC-XQ
- **WHEN** o fone está em Música com SBC e o usuário escolhe SBC-XQ
- **THEN** o perfil ativo do cartão passa a ser o A2DP com SBC-XQ e o painel marca SBC-XQ

#### Scenario: Mudar de modo sem escolher codec
- **WHEN** o usuário escolhe "Chamada"
- **THEN** é ativado o perfil HFP de maior prioridade (mSBC no Redmi Buds 6 Play)

### Requirement: Falha ao trocar perfil
Se a troca de modo ou codec falhar ou não se refletir em até 5 segundos, o painel SHALL voltar a mostrar o perfil realmente ativo e exibir uma mensagem de falha.

#### Scenario: Perfil rejeitado
- **WHEN** o sistema de áudio rejeita o perfil escolhido
- **THEN** o painel mostra o perfil anterior como selecionado e uma mensagem de falha

### Requirement: Saída padrão
O painel SHALL indicar se o fone ativo é a saída de áudio padrão e, quando não for, oferecer uma ação que o torna padrão.

#### Scenario: Tornar o fone padrão
- **WHEN** a saída padrão é o alto-falante interno e o usuário aciona "Usar como saída"
- **THEN** a saída de áudio padrão passa a ser o fone e o painel indica isso

### Requirement: Troca automática para chamada
O painel SHALL ter uma alternância que liga/desliga a troca automática para o modo chamada quando um aplicativo abre o microfone, refletindo a configuração real do sistema e persistindo entre reinícios.

#### Scenario: Desligar a troca automática
- **WHEN** o usuário desliga a alternância
- **THEN** abrir o microfone num aplicativo não muda o perfil do fone, e a configuração continua desligada após reiniciar a sessão

### Requirement: Comandos seguros
Toda alteração de sistema feita pelo plugin SHALL passar endereço e perfil como argumentos separados, aceitar só endereços MAC válidos e nomes de perfil existentes no cartão do fone, e nunca montar comandos de shell com texto vindo de dispositivos ou da saída de outros comandos.

#### Scenario: Perfil inválido
- **WHEN** o helper recebe o perfil `a2dp-sink; rm -rf ~`
- **THEN** recusa com erro, sem executar nada
