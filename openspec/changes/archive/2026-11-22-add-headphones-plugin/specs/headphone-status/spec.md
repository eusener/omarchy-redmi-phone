# Spec Delta

## Purpose

Identifica qual fone de áudio Bluetooth está ativo, informa bateria e estado de conexão, e mostra isso na barra do Omarchy com acesso ao painel do fone.

## ADDED Requirements

### Requirement: Seleção do fone ativo
O plugin SHALL considerar como "fone ativo" um dispositivo Bluetooth pareado e conectado que exponha o serviço Audio Sink (A2DP) ou Handsfree. Havendo mais de um, SHALL preferir o que é a saída de áudio padrão atual; senão, o conectado mais recentemente.

#### Scenario: Um fone conectado
- **WHEN** o Redmi Buds 6 Play está conectado e nenhum outro dispositivo de áudio Bluetooth está conectado
- **THEN** o fone ativo é o Redmi Buds 6 Play

#### Scenario: Teclado Bluetooth conectado, sem fone
- **WHEN** apenas dispositivos sem serviço de áudio (teclado, mouse) estão conectados
- **THEN** não há fone ativo

#### Scenario: Dois fones conectados
- **WHEN** dois fones de áudio estão conectados e um deles é a saída padrão
- **THEN** o fone ativo é o que é a saída padrão

### Requirement: Indicador de bateria
Quando o sistema informa a bateria do fone ativo, o plugin SHALL exibi-la como porcentagem inteira, formatada conforme o idioma do Omarchy. Quando não há informação, SHALL omitir o número sem exibir 0%.

#### Scenario: Bateria informada
- **WHEN** o BlueZ informa bateria de 60% para o fone ativo
- **THEN** o widget e o painel mostram "60%"

#### Scenario: Bateria indisponível
- **WHEN** o fone ativo não informa bateria
- **THEN** o widget mostra apenas o ícone e o painel não mostra porcentagem

### Requirement: Widget de barra
O plugin SHALL oferecer um widget de barra que mostra um ícone de fone e a bateria do fone ativo, aparece esmaecido (não oculto) sem fone ativo, tem tooltip com o nome do fone ou "nenhum fone conectado", e abre/fecha o painel ao ser clicado.

#### Scenario: Clique com fone conectado
- **WHEN** o usuário clica no widget com o fone conectado
- **THEN** o painel do fone abre

#### Scenario: Sem fone
- **WHEN** nenhum fone está conectado
- **THEN** o widget continua visível, esmaecido, e o tooltip diz que não há fone conectado

### Requirement: Atualização ao vivo
O widget e o painel SHALL refletir conexão, desconexão e mudança de bateria sem reiniciar o shell e sem o usuário reabrir o painel, em no máximo 5 segundos.

#### Scenario: Fone desconecta com o painel aberto
- **WHEN** o fone é desligado com o painel aberto
- **THEN** em até 5 segundos o painel mostra o estado "nenhum fone conectado" e o widget fica esmaecido

### Requirement: Conectar e desconectar
O painel SHALL permitir desconectar o fone ativo e reconectar o último fone de áudio pareado quando nenhum está conectado, mostrando estado de "conectando…"/"desconectando…" até o BlueZ confirmar ou falhar.

#### Scenario: Reconectar
- **WHEN** nenhum fone está conectado e o usuário aciona "Conectar Redmi Buds 6 Play"
- **THEN** o painel mostra "conectando…" e, após a conexão, passa a mostrar o fone como ativo

#### Scenario: Falha ao conectar
- **WHEN** a conexão falha (fone no estojo fechado)
- **THEN** o painel sai do estado "conectando…" e mostra uma mensagem de falha

### Requirement: Texto não confiável
Nomes de dispositivo e qualquer texto vindo de BlueZ, PipeWire ou da saída de comandos SHALL ser exibidos como texto puro, nunca interpretados como rich text ou markup.

#### Scenario: Nome com markup
- **WHEN** um dispositivo pareado se chama `<img src="https://example.invalid/x">`
- **THEN** o painel e o tooltip exibem esse texto literalmente e nenhum recurso é carregado

### Requirement: Idiomas
Todo texto do plugin SHALL vir de catálogos de tradução do próprio plugin, com inglês e português do Brasil, acompanhando o idioma escolhido no Omarchy sem reiniciar o shell e caindo para inglês quando uma string faltar.

#### Scenario: Troca de idioma
- **WHEN** o usuário muda o idioma do Omarchy de inglês para português com o painel aberto
- **THEN** os textos do painel passam a aparecer em português
