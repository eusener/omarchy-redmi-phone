# Design

## Context

O que já existe na máquina e define a abordagem (motivação em proposal.md):

- **Plugins do shell.** O Omarchy shell (Quickshell) carrega plugins de `~/.config/omarchy/plugins/<id>/` a partir de um `manifest.json`, com hot-reload ao salvar. Os outros plugins do usuário (`eusener.yubikey`, `eusener.power`, `eusener.dock`) servem de padrão. O yubikey usa `kinds: ["panel", "bar-widget"]`. O widget abre o painel com `bar.run("omarchy-shell shell toggle <id> '{}'")`, e o painel expõe `open(payloadJson)`. Os do launcher são symlinks para um repositório em `~/Projects`.
- **Restrição observada no yubikey.** O widget de barra recebe `bar`, não o manifest, então não sabe com certeza o caminho dos arquivos irmãos. Usa `Qt.resolvedUrl(...)` para os catálogos.
- **Dados de Bluetooth.** O `omarchy.bluetooth` lê tudo de `Quickshell.Bluetooth` (`Bluetooth.devices`, `device.connected`, `device.batteryAvailable`, `device.battery` em fração 0–1) e de `Quickshell.Services.Pipewire`. Conectar e desconectar passa por `omarchy-bluetooth-device`.
- **Fone real.**
  - Cartão: `bluez_card.AA_BB_CC_DD_EE_FF`.
  - Perfis: `a2dp-sink` (SBC, prioridade 132), `a2dp-sink-sbc_xq` (131), `headset-head-unit` (mSBC, 5), `headset-head-unit-cvsd` (4), `off`.
  - Bateria via BlueZ: 60%.
- **WirePlumber 0.5.18.** Expõe as configurações `bluetooth.autoswitch-to-headset-profile` e `bluetooth.profile-preference` via `wpctl settings`. Já existe `~/.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf` do usuário.
- **mpris-proxy.** O `bluez-utils` traz `/usr/lib/systemd/user/mpris-proxy.service`, que hoje está inativo.
- **Camada 2.**
  - O fone anuncia o UUID Xiaomi FD2D.
  - O MiBudsClient (GPL-3.0, commit `52eb3f94`) tem a pilha de protocolo em `controllers/bluetooth/`: só biblioteca padrão, mais dois imports de `utils/` (`utils.i18n.message`, `utils.error_reports.redact`).
  - Registro de hardware dele no 6 Play: SDP resolveu FD2D no canal 6 e autenticou (2026-10-31). Num teste anterior pelo canal 6 (2026-10-27), o EQ foi lido e gravado com releitura.
  - Bateria, latência e gestos pelo caminho autenticado continuam sem validação no hardware.
  - O `sdptool` não está instalado aqui. Detalhes em `research-vendor-protocol.md`.

## Goals / Non-Goals

**Goals:**
- Funcionar com qualquer fone de áudio Bluetooth. O Redmi Buds 6 Play é o caso de teste, mas a camada 1 não tem nada específico da Xiaomi.
- Estado sempre derivado do sistema (BlueZ, PipeWire, systemd). O plugin não guarda cópia própria que possa divergir.
- Lógica pura testável fora do shell, com `node` para `Model.js` e `bash`/`bats` ou shell puro para o helper.
- Camada 2 reaproveitando o código de protocolo já validado do MiBudsClient, sem reescrever o que funciona. A licença do repositório (GPL-3.0-only) é a mesma dele.

**Non-Goals:**
- ANC, áudio espacial, OTA e qualquer recurso que o catálogo do 6 Play não liste.
- Interface Flet, bandeja, notificações, monitor de jogos e caminhos Windows do MiBudsClient.
- Conexão RFCOMM permanente ou stream de notificações em segundo plano.
- Gerenciar pareamento ou descoberta. Isso continua no `omarchy.bluetooth`.
- Instalar pacotes ou editar `/usr/share/omarchy/`.

## Decisions

### D1. Estrutura e entrega: repositório próprio + symlink
O código fica na raiz deste repositório (`manifest.json`, `Panel.qml`, `Model.js`, `bin/headphones-ctl`, `bin/buds-vendor`, `vendor/mibuds/`, `i18n/`, `tests/`, `LICENSE` GPL-3.0-only). A instalação é `ln -s ~/Projects/omarchy-redmi-phone ~/.config/omarchy/plugins/eusener.headphones`.
- *Alternativa:* código numa subpasta `plugins/eusener.headphones/`, como no omarchy-launcher. Foi descartada porque o repositório tem um plugin só, e a raiz como plugin segue o modelo do `omarchy-yubikey`.
- *Alternativa:* `omarchy plugin clone omarchy.bluetooth`. Foi descartada porque substituiria o painel oficial na barra, e o objetivo é um widget adicional.

### D2. Id `eusener.headphones`, um único bar-widget baseado em `qs.Ui/Panel`
O id é genérico porque a camada 1 vale para qualquer fone. A estrutura segue o padrão do `omarchy.bluetooth` e do `eusener.power`: um único `Panel.qml` (kind `bar-widget`) que estende `qs.Ui/Panel`. Ele traz um `BarIconButton` na barra e um `KeyboardPanel` como popup. O IPC `omarchy-shell eusener.headphones toggle` (via `ipcTarget`) permite abrir o painel por atalho. Animação, troca entre painéis da barra e espelhamento RTL vêm do kit `qs.Ui`, e `Qt.resolvedUrl` localiza `bin/` e `i18n/` a partir da entrada do widget.
- *Alternativa:* widget + painel separado (`kind: panel`, janela própria, como no yubikey). Foi descartada durante a implementação: mais código de janela e sem a troca entre painéis da barra.

### D3. Leitura de estado: Quickshell, não polling de CLI
- Fone ativo, conexão e bateria vêm de `Quickshell.Bluetooth`, que é reativo via D-Bus e atende o requisito de até 5 s sem timer.
- Saída padrão vem de `Pipewire.defaultAudioSink`.
- Perfil ativo e perfis disponíveis do cartão: os nodes PipeWire do Quickshell não expõem a lista de perfis do *device*. Por isso o helper roda `pactl --format=json list cards` e filtra pelo cartão `bluez_card.<MAC_com_underscores>`. Isso acontece ao abrir o painel, depois de cada troca e por um `Timer` de 3 s só enquanto o painel está aberto.
- *Alternativa:* `pw-dump` com parsing do objeto Device. Funciona, mas é mais verboso. O `pactl` JSON já entrega `profiles`, `active_profile` e prioridades.

### D4. Seleção do fone ativo em `Model.js`
Função pura `pickActiveHeadphone(devices, defaultSinkName)`:
1. Filtra os dispositivos conectados cujo `icon` é `audio-headset`/`audio-headphones` ou cujos UUIDs incluem `0000110b` (Audio Sink) ou `0000111e` (Handsfree).
2. Prefere aquele cujo `bluez_output.<MAC>` é o sink padrão.
3. Se nenhum for o sink padrão, fica com o primeiro da lista, na ordem de `Bluetooth.devices`.

"Mais recentemente conectado" é aproximado pela ordem em que o shell recebeu a conexão, guardada num mapa em memória.

### D5. Modelo de modos e codecs
`Model.js` agrupa os perfis do cartão:
- **Música:** perfis `a2dp-sink*`. O codec sai do sufixo (`sbc_xq` → SBC-XQ, `aac`, `ldac`…) ou do texto "codec X" na descrição. Sem sufixo, vale o codec da descrição (SBC).
- **Chamada:** perfis `headset-head-unit*`. O codec vem da descrição (mSBC, CVSD, LC3-SWB).

Escolher só o modo ativa o perfil de maior `priority` do grupo. Isso deixa o modelo genérico para AAC e LDAC em outros fones.

### D6. Helper `bin/headphones-ctl` (bash)
Subcomandos:

| Subcomando | O que faz |
|---|---|
| `status <MAC>` | imprime JSON com perfis, perfil ativo, se é saída padrão, autoswitch e mpris-proxy |
| `set-profile <MAC> <profile>` | troca o perfil do cartão |
| `set-default <MAC>` | torna o fone a saída padrão |
| `autoswitch on\|off` | `wpctl settings --save bluetooth.autoswitch-to-headset-profile true\|false` |
| `media-buttons on\|off` | `systemctl --user enable\|disable --now mpris-proxy.service` |
| `connect\|disconnect <MAC>` | delega para `omarchy-bluetooth-device` |

Validação: MAC com `^([0-9A-F]{2}:){5}[0-9A-F]{2}$`, e o perfil precisa estar na lista que o próprio `pactl` retornou para aquele cartão. A QML chama o helper com `Process { command: [helperPath, "set-profile", mac, profile] }`, sem `sh -c`.

O painel acha o helper por `Qt.resolvedUrl("bin/headphones-ctl")`. O widget não precisa do helper, porque só lê Quickshell.
- *Alternativa:* chamar `pactl` direto da QML. Foi descartada porque espalharia validação e montagem de comando por vários arquivos e não seria testável fora do shell.

### D7. Troca automática para chamada via `wpctl settings --save`
A troca usa a configuração oficial do WirePlumber, persistida no state dele, em vez de escrever um `.conf` novo. O estado lido é `wpctl settings bluetooth.autoswitch-to-headset-profile`.
- *Alternativa:* um arquivo em `wireplumber.conf.d/`. Exigiria reiniciar o WirePlumber, o que derruba o áudio, e duplicaria a configuração.

### D8. Botões de mídia via `mpris-proxy.service` do sistema
A alternância é exatamente `systemctl --user is-enabled/is-active mpris-proxy`. A persistência fica a cargo do systemd. Se a unit não existir (`systemctl --user cat` falha), a alternância fica desabilitada.

### D9. Idioma
Os textos ficam em `Commons.Translations { directory: Qt.resolvedUrl("i18n") }` com `en.json` e `pt-BR.json`, conforme o guia de plugins. Todo `Text` usa `textFormat: Text.PlainText`, através de um componente local `PlainText.qml`.

### D10. Camada 2: copiar e adaptar o MiBudsClient em `vendor/mibuds/`
São copiados os módulos de protocolo de `controllers/bluetooth/`:

| Função | Módulos |
|---|---|
| Frames | `rcsp`, `protocol`, `constants` |
| Autenticação | `safer_plus`, `auth_codec`, `auth_session`, `raw_auth` |
| Transporte | `sdp`, `connection`, `config_transport` |
| Recursos | `battery_stream`, `latency_transport`, `eq_transport`, `equalizer`, `gesture_transport`, `gestures` |
| Catálogo | `device_catalog`, `capabilities`, `catalog_options`, e a parte necessária de `assets/device_catalog.json` |

Ficam de fora a interface Flet, a bandeja, `noise*`, `windows_discovery`, `controller.py` (o orquestrador da UI) e `utils/` além de dois stubs: `vendor/mibuds/_compat.py` provê `message()` (mensagens em inglês fixas) e `redact()`.

Cada arquivo copiado mantém o aviso de copyright original e ganha `SPDX-License-Identifier: GPL-3.0-only` e uma linha "Adaptado de MiBudsClient@52eb3f94: <arquivo original>; alterações: …". `vendor/mibuds/README.md` lista a origem, o commit, os arquivos e um resumo das mudanças, como pede a seção 5a da GPL-3.0.

As adaptações:
- imports relativos ajustados;
- remoção do Windows;
- descoberta de canal conforme D12;
- limite de 4 KiB por frame, se não existir;
- nenhuma mudança nos bytes do protocolo.

- *Alternativa:* reimplementação clean-room. Foi descartada por decisão do usuário, porque é mais lenta e joga fora código com validação no hardware.
- *Alternativa:* chamar o MiBudsClient como processo externo. Foi descartada porque ele não tem CLI e depende do Flet.
- *Alternativa:* trazer o MiBudsClient como submódulo git. Foi descartada porque prenderia o projeto à árvore da UI dele e ainda exigiria patches.

### D11. Helper `bin/buds-vendor` (Python)
Executado como `python3 -I bin/buds-vendor <subcomando> <MAC> [args]`, com `sys.path` apontando só para `vendor/`. Subcomandos:

| Subcomando | O que faz |
|---|---|
| `probe` | modelo, recursos disponíveis, se autenticou |
| `battery` | bateria por fone e do estojo |
| `latency get` / `latency set on\|off` | lê ou grava a baixa latência |
| `eq get` / `eq set <id>` | lê ou grava o preset de EQ |
| `gestures get` / `gestures set <gesture> <side> <action>` | lê ou grava o mapeamento de gestos |

Cada chamada:
- abre uma conexão, autentica se preciso, executa e fecha;
- tem prazo total de 10 s;
- imprime um único objeto JSON em stdout (`{"ok": true, ...}` ou `{"ok": false, "error": "<código>"}`);
- sai com código ≠ 0 em erro.

O MAC é validado por regex. IDs de preset, gesto e ação são validados contra o catálogo do modelo antes de qualquer envio. A QML chama o helper com `Process` e argumentos em array, e nunca abre o socket.
- *Alternativa:* um daemon com conexão permanente e stream de bateria. Foi descartada por ora: mais estado e mais chance de disputar o canal com o celular. Pode vir depois.

### D12. Descoberta do canal sem `sdptool`
Ordem de tentativa:
1. canal em cache, em `$XDG_STATE_HOME/eusener-headphones/channels.json`, por MAC;
2. `sdptool browse --xml`, se existir no PATH (o caminho já implementado em `sdp.py`);
3. canal 6, que é o padrão conhecido do 6 Play;
4. varredura dos canais 1–30.

Um canal só é aceito se responder a um pedido RCSP (`GET_DEVICE_INFO`) com frame válido. `bluez-deprecated-tools` não é instalado automaticamente; o README o cita como opcional.
- *Alternativa:* `org.bluez.ProfileManager1.RegisterProfile`. Exigiria `python-dbus` ou `dbus-next`, que não estão garantidos, e um loop D-Bus no helper. Fica como melhoria futura.

### D13. Seção "Recursos Xiaomi" no painel
O painel roda `buds-vendor probe` quando o fone ativo anuncia FD2D e o painel abre. Com sucesso, ele monta só os recursos que o `probe` reportou. Gravações usam o mesmo padrão de estado pendente da camada 1, e a confirmação vem da releitura feita pelo próprio helper. Erros (`refused`, `auth_failed`, `timeout`, `protocol`) viram mensagens traduzidas com "tentar de novo". O widget de barra continua usando só a bateria do BlueZ e não abre RFCOMM.

### D14. Escolha do microfone: fone ou notebook
Com a troca automática ligada, o WirePlumber cria uma fonte virtual `bluez_input.<MAC>` (com dois-pontos), mesmo em A2DP, e a torna a entrada padrão. É por isso que qualquer app que grava derruba o fone para HFP: o Bluetooth Clássico não tem perfil com áudio de alta qualidade nos dois sentidos, e o fone não oferece LE Audio nem codecs A2DP duplex.

`headphones-ctl mic <MAC> internal|headset` combina três ajustes já existentes:
- **internal:** desliga a troca automática (com a espera de persistência do D7), define como padrão a fonte ALSA de captura do computador (nunca um `.monitor`, preferindo nomes com "mic") e, se o fone estiver em HFP, volta ao perfil A2DP de maior prioridade.
- **headset:** religa a troca automática, espera a fonte virtual aparecer (até 3 s) e a define como padrão.

O estado lido (`status.mic.source`) vem sempre da entrada padrão real: `headset`, `internal` ou `other`.
- *Alternativa:* só trocar a entrada padrão, sem mexer na troca automática. Foi descartada porque, com a troca ligada, o WirePlumber recria a fonte virtual e ela volta a ganhar prioridade.

## Risks / Trade-offs

- **Trocar para HFP derruba a qualidade e pode cortar o áudio por ~1 s.** → O rótulo do modo "Chamada" explica a troca, e o painel nunca troca sozinho.
- **O autoswitch do WirePlumber pode brigar com uma escolha manual de modo.** → O painel mostra sempre o perfil real (D3). A documentação explica que, com autoswitch ligado, o WirePlumber volta para Música quando o microfone fecha.
- **O formato JSON do `pactl` pode mudar entre versões.** → O parsing fica isolado em `Model.js`, com testes sobre um fixture capturado do fone real.
- **A bateria do BlueZ é uma média dos dois fones, sem o estojo.** → O widget usa o valor do BlueZ. A bateria por fone e do estojo aparece no painel pela camada 2.
- **Bateria, latência e gestos nunca foram validados no 6 Play real.** → O grupo de experimentos (tasks §7) vem antes da interface da camada 2. Recurso que não responder fica oculto (spec `xiaomi-vendor-features`).
- **Gravar um valor inválido pode deixar o fone num estado estranho.** → Só valores do catálogo são aceitos, toda gravação é confirmada por releitura, e o experimento sempre registra o valor original para restaurar.
- **Uma atualização de firmware pode mudar opcodes ou exigir outra autenticação.** → Erros de protocolo escondem a seção sem afetar a camada 1, e `probe` registra a versão do firmware.
- **O código adaptado diverge do upstream.** → O commit fica preso em `vendor/mibuds/README.md`, com as diferenças listadas. Sincronizar com o upstream é manual.
- **A GPL-3.0-only obriga quem redistribuir o plugin a fornecer o código-fonte.** → O repositório já é público e completo, e `LICENSE` + SPDX deixam isso explícito.
- **A varredura de canais pode demorar até ~30 conexões.** → O canal fica em cache e o canal 6 é tentado antes. A varredura só ocorre na primeira vez ou depois de uma falha no cache.
- **Ligar o `mpris-proxy` também encaminha comandos de outros dispositivos Bluetooth** (por exemplo, o carro). → É o comportamento esperado do proxy, e a documentação avisa.
- **Symlink para um repositório de desenvolvimento.** Um arquivo quebrado durante a edição recarrega quebrado no shell. → É o mesmo fluxo dos outros plugins `eusener.*`, e `omarchy-shell shell rescanPlugins` recupera.

## Migration Plan

1. Criar o symlink e adicionar o widget com `omarchy bar put eusener.headphones --section right`.
2. Nenhuma configuração existente é alterada na instalação. `autoswitch` e `mpris-proxy` só mudam quando o usuário aciona a alternância.
3. **Rollback:** remover o widget da barra (editando `bar.layout` em `~/.config/omarchy/shell.json`) e o symlink. Para reverter as configurações: `wpctl settings --save bluetooth.autoswitch-to-headset-profile true` (valor padrão) e `systemctl --user disable --now mpris-proxy`. Para a camada 2: apagar `$XDG_STATE_HOME/eusener-headphones/`. Valores gravados no fone (EQ, gestos, latência) ficam no fone e podem ser revertidos pelo próprio painel ou pelo app Xiaomi Earbuds.

## Open Questions

- O widget também deve aparecer quando nenhum fone *pareado* existe? A decisão atual é que sim, esmaecido. Isso pode ser revisto depois sem mudar a estrutura.
