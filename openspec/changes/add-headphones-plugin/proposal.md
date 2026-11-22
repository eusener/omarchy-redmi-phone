# Proposal

## Why

Configurar o fone Bluetooth (Redmi Buds 6 Play) no Omarchy hoje exige `pactl`, `wpctl` e `bluetoothctl` no terminal: trocar entre modo música (A2DP) e modo chamada com microfone (HFP), escolher o codec (SBC vs SBC-XQ), ver a bateria ou fazer os botões do fone controlarem o player. Os recursos próprios do fone (EQ, gestos de toque, modo de baixa latência, bateria de cada fone e do estojo) só existem no app Xiaomi Earbuds para celular. O painel `omarchy.bluetooth` só conecta e desconecta. Um plugin do shell resolve as duas coisas num lugar só.

## What Changes

- Novo plugin do Omarchy shell `eusener.headphones` (kind `bar-widget` com popup), versionado neste repositório e ligado em `~/.config/omarchy/plugins/eusener.headphones` por symlink, como os demais plugins `eusener.*`.
- **Licença:** o repositório passa a ser **GPL-3.0-only**, porque a camada 2 copia e adapta código do MiBudsClient (GPL-3.0, https://github.com/CesurPolat/MiBudsClient), com atribuição e registro das alterações.
- **Camada 1, recursos padrão de qualquer fone Bluetooth:**
  - Widget de barra com ícone de fone e porcentagem de bateria; fica esmaecido quando nenhum fone está conectado, e o clique abre o painel.
  - Painel com nome e bateria do fone, modo (Música / Chamada), codec, botão "usar como saída padrão", alternância de troca automática para o modo chamada, alternância dos botões de mídia (AVRCP → MPRIS) e ações conectar/desconectar.
  - Helper `bin/headphones-ctl` que encapsula `pactl`, `wpctl` e `systemctl --user`, com argumentos validados e sem interpolação em shell.
- **Camada 2, recursos proprietários Xiaomi pelo protocolo RCSP sobre RFCOMM (UUID FD2D):**
  - Módulos de protocolo do MiBudsClient copiados e adaptados em `vendor/mibuds/`.
  - Helper `bin/buds-vendor` (Python, só biblioteca padrão) que devolve JSON.
  - Seção "Recursos Xiaomi" no painel: bateria do fone esquerdo, do direito e do estojo, modo de baixa latência, preset de EQ e mapeamento de gestos. A seção só aparece quando o fone suporta o protocolo.
- Strings em `i18n/en.json` e `i18n/pt-BR.json`; lógica pura em `Model.js` com testes; testes Python portados do MiBudsClient para o código adaptado.

Fora de escopo:
- ANC/transparência (o 6 Play não tem).
- Atualização de firmware.
- Pareamento e descoberta (continuam no `omarchy.bluetooth`).
- Instalar pacotes automaticamente.
- Qualquer edição em `/usr/share/omarchy/`.
- Copiar código do Gadgetbridge (AGPL).

## Capabilities

### New Capabilities
- `headphone-status`: detecção do fone de áudio Bluetooth ativo, bateria e estado de conexão, e sua apresentação no widget de barra.
- `headphone-audio-routing`: modo de áudio (A2DP/HFP), codec, saída padrão e troca automática para o modo chamada.
- `headphone-media-buttons`: encaminhamento dos botões do fone (AVRCP) para players MPRIS.
- `xiaomi-vendor-session`: descoberta do canal de controle Xiaomi, conexão, autenticação e degradação quando o fone não suporta o protocolo.
- `xiaomi-vendor-features`: leitura e gravação dos recursos proprietários (bateria por fone e estojo, baixa latência, EQ, gestos).

### Modified Capabilities
<!-- nenhuma: o projeto ainda não tem specs -->

## Impact

- **Código novo neste repositório:** `manifest.json`, `Panel.qml`, `Model.js`, `bin/headphones-ctl`, `bin/buds-vendor`, `vendor/mibuds/`, `i18n/`, `tests/`, `README.md`, `LICENSE` (GPL-3.0).
- **Sistema do usuário:**
  - Symlink em `~/.config/omarchy/plugins/`.
  - Entrada do widget em `bar.layout`.
  - Possível ativação de `mpris-proxy.service` (usuário).
  - Alteração persistente via `wpctl settings --save`.
  - Conexões RFCOMM de saída ao fone.
- **Dependências já instaladas:** bluez 5.87, pipewire 1.6.9 / pipewire-pulse, wireplumber 0.5.18, `mpris-proxy` (bluez-utils), Python 3.14, módulos Quickshell `Quickshell.Bluetooth` e `Quickshell.Services.Pipewire`.
- **Dependência opcional:** `sdptool` (pacote `bluez-deprecated-tools`), que não está instalado; existe fallback.
