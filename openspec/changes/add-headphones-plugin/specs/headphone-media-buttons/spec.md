# Spec Delta

## Purpose

Faz os toques e botões do fone Bluetooth (play/pause, próxima, anterior) controlarem os players de mídia do desktop, com uma alternância no painel do fone.

## ADDED Requirements

### Requirement: Encaminhamento AVRCP para MPRIS
O painel SHALL ter uma alternância "Botões do fone controlam o player" que, ligada, faz os comandos AVRCP do fone (play, pause, próxima, anterior) chegarem ao player MPRIS ativo, e desligada, interrompe esse encaminhamento.

#### Scenario: Pausar pelo fone
- **WHEN** a alternância está ligada, há música tocando num player MPRIS e o usuário toca no fone para pausar
- **THEN** o player pausa

#### Scenario: Alternância desligada
- **WHEN** a alternância está desligada
- **THEN** o plugin não mantém nenhum encaminhamento AVRCP→MPRIS ativo

### Requirement: Persistência e estado real
A alternância SHALL refletir se o encaminhamento está realmente ativo, e a escolha SHALL persistir entre sessões sem o painel precisar estar aberto.

#### Scenario: Após reiniciar
- **WHEN** o usuário ligou a alternância e reiniciou a sessão
- **THEN** o encaminhamento volta a funcionar ao entrar na sessão e a alternância aparece ligada

#### Scenario: Componente ausente
- **WHEN** o programa de encaminhamento não está instalado
- **THEN** a alternância aparece desabilitada com uma explicação, sem gerar erro
