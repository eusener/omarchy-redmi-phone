# Tasks

## 1. Estrutura do plugin

- [x] 1.1 Criar `manifest.json` (id `eusener.headphones`, kind `bar-widget`, entryPoint `Panel.qml`, `defaultSection: "right"`), `LICENSE` com o texto integral da GPL-3.0, `.gitignore` e `PlainText.qml`, com cabeçalho `SPDX-License-Identifier: GPL-3.0-only` em cada arquivo de código; verificar com `python3 -m json.tool manifest.json` e `grep -L SPDX-License-Identifier *.qml *.js bin/*` vazio
- [x] 1.2 Criar o symlink `~/.config/omarchy/plugins/eusener.headphones -> ~/Projects/omarchy-redmi-phone` e verificar que `omarchy-shell shell rescanPlugins` não registra erro no log do shell

## 2. Modelo puro (`Model.js`)

- [x] 2.1 Capturar `pactl --format=json list cards` do Redmi Buds 6 Play em `tests/fixtures/redmi-buds-6-play.json` (e um fixture sintético com AAC/LDAC/LC3) e verificar que os arquivos são JSON válido
- [x] 2.2 Implementar `pickActiveHeadphone(devices, defaultSinkName)` (D4) com testes em `tests/test_model.js` cobrindo: um fone, só teclado, dois fones com sink padrão; verificar com `node tests/test_model.js`
- [x] 2.3 Implementar `groupProfiles(card)` → modos Música/Chamada com codecs, prioridade e perfil ativo (D5), e `batteryLabel(fraction, available)`; testes para SBC/SBC-XQ/mSBC/CVSD, fone só-A2DP e bateria indisponível; verificar com `node tests/test_model.js`
- [x] 2.4 Implementar `isMac()`, `cardNameFor(mac)` e `hasXiaomiControl(device)` (UUID FD2D) com testes para entradas inválidas e com markup; verificar com `node tests/test_model.js`

## 3. Helper `bin/headphones-ctl`

- [x] 3.1 Implementar `status <MAC>` emitindo JSON (cartão, perfis, perfil ativo, é-saída-padrão, autoswitch, mpris-proxy disponível/ativo) e verificar com `bin/headphones-ctl status AA:BB:CC:DD:EE:FF | python3 -m json.tool`
- [x] 3.2 Implementar `set-profile`, `set-default`, `autoswitch on|off`, `media-buttons on|off`, `connect|disconnect` com validação de MAC e de perfil contra a lista do cartão (D6); verificar trocando `a2dp-sink` → `a2dp-sink-sbc_xq` → `a2dp-sink` no fone real e conferindo `Active Profile` em `pactl list cards`
- [x] 3.3 Escrever `tests/test_ctl.sh` com stubs de `pactl`/`wpctl`/`systemctl` no `PATH` verificando: perfil inválido (`'a2dp-sink; rm -rf ~'`) é recusado com código ≠ 0 e nenhum stub é chamado; MAC inválido recusado; argumentos chegam separados; verificar com `bash tests/test_ctl.sh`

## 4. Widget de barra

- [x] 4.1 Implementar o botão de barra em `Panel.qml` (base `qs.Ui/Panel`) com `Quickshell.Bluetooth` + `Model.pickActiveHeadphone`: ícone, bateria, esmaecido sem fone, tooltip PlainText, clique abre/fecha o `KeyboardPanel`; verificar adicionando com `omarchy bar put eusener.headphones --section right` e observando o widget com o fone conectado e desconectado (≤ 5 s)
- [x] 4.2 Criar `i18n/en.json` e `i18n/pt-BR.json` com as strings do widget e verificar que trocar o idioma do Omarchy atualiza o tooltip sem reiniciar o shell

## 5. Painel — camada 1

- [x] 5.1 Implementar o conteúdo do `KeyboardPanel` em `Panel.qml` (cabeçalho com nome/bateria, estado "nenhum fone conectado", polling de `status` só com painel aberto) e verificar abrindo por clique e por `omarchy-shell eusener.headphones toggle`
- [x] 5.2 Adicionar seletor de modo Música/Chamada e de codec com estado pendente, timeout de 5 s e reversão + mensagem em falha; verificar no fone real que Chamada expõe o microfone (`pactl list sources short | grep bluez`) e que SBC-XQ fica marcado
- [x] 5.3 Adicionar "Usar como saída" e verificar alternando entre o alto-falante interno e o fone (`wpctl status` mostra o `*` no sink certo)
- [x] 5.4 Adicionar alternância de troca automática (D7) e verificar com `wpctl settings bluetooth.autoswitch-to-headset-profile` antes/depois e após `systemctl --user restart wireplumber`
- [ ] 5.5 Adicionar alternância "Botões do fone controlam o player" (D8), desabilitada quando a unit não existe; verificar com `systemctl --user is-active mpris-proxy` e pausando um player pelo toque no fone
- [x] 5.6 Adicionar conectar/desconectar com estados pendentes e falha; verificar desconectando e reconectando o fone pelo painel
- [x] 5.7 Completar `i18n/` com as strings da camada 1 e verificar que nenhuma string visível está hardcoded (`grep -n 'text: "' *.qml` vazio, exceto glifos)
- [x] 5.8 Verificar segurança de texto: `bluetoothctl set-alias '<img src="https://example.invalid/x">'`, confirmar que painel e tooltip mostram o texto literal, e restaurar o alias original

## 6. Código adaptado do MiBudsClient (`vendor/mibuds/`)

- [x] 6.1 Clonar `https://github.com/CesurPolat/MiBudsClient` e fixar o commit `52eb3f94` (`git -C <clone> rev-parse HEAD` confere); copiar para `vendor/mibuds/` os módulos listados em D10 e o trecho de `assets/device_catalog.json` necessário; verificar que nenhum arquivo de UI/Flet/Windows/noise foi copiado (`grep -rl "flet\|winreg\|windows_discovery" vendor/` vazio)
- [x] 6.2 Adaptar: criar `vendor/mibuds/_compat.py` (`message`, `redact`), ajustar imports, remover caminhos Windows, garantir limite de 4 KiB por frame; verificar com `python3 -I -c "import sys; sys.path.insert(0,'vendor'); import mibuds.connection, mibuds.battery_stream, mibuds.equalizer, mibuds.gestures"` sem erro
- [x] 6.3 Adicionar a cada arquivo copiado o aviso de origem e `SPDX-License-Identifier: GPL-3.0-only` + linha "Adaptado de MiBudsClient@52eb3f94: <arquivo>; alterações: …", e escrever `vendor/mibuds/README.md` (origem, commit, lista de arquivos, resumo das alterações); verificar com `grep -L "Adaptado de MiBudsClient" vendor/mibuds/*.py` vazio
- [x] 6.4 Portar os testes `test_command_auth`, `test_rfcomm_services`, `test_linux_sdp`, `test_battery_stream`, `test_equalizer`, `test_gestures`, `test_latency_controller` (só as partes de protocolo) para `tests/vendor/`, mais um teste de frame malformado (tamanho excede os bytes recebidos) e de frame > 4 KiB; verificar com `python3 -I -m unittest discover -s tests/vendor` passando

## 7. Experimentos de protocolo no fone real

- [x] 7.1 Iniciar `btmon -w ~/Projects/omarchy-redmi-phone/captures/redmi-$(date +%F).btsnoop` (diretório no `.gitignore`) e, com um script descartável usando `vendor/mibuds`, descobrir o canal FD2D sem `sdptool` (canal 6, depois 1–30); registrar o canal em `docs/hardware-log.md`
- [x] 7.2 Enviar `GET_DEVICE_INFO` sem autenticar e, se recusado, com o handshake `50`/`51`; registrar em `docs/hardware-log.md` se a autenticação é exigida e a versão de firmware
- [x] 7.3 Ler bateria por fone/estojo e comparar com o valor do BlueZ; ler e gravar baixa latência (ligar → reler → restaurar); ler EQ e trocar para outro preset e de volta; ler gestos e remapear um gesto e restaurar; registrar cada resultado (ok/sem resposta/erro) em `docs/hardware-log.md`. Recursos sem resposta ficam marcados como não suportados para as specs `xiaomi-vendor-features`

## 8. Helper `bin/buds-vendor`

- [x] 8.1 Implementar a CLI (D11) com `probe`, `battery`, `latency get|set`, `eq get|set`, `gestures get|set`, saída JSON única, prazo de 10 s e fechamento garantido da conexão; verificar com `bin/buds-vendor probe AA:BB:CC:DD:EE:FF | python3 -m json.tool` no fone real
- [x] 8.2 Implementar a descoberta de canal com cache em `$XDG_STATE_HOME/eusener-headphones/channels.json` (D12) e invalidação; verificar apagando o cache (1ª chamada descobre e grava), repetindo (usa o cache) e editando o cache para um canal errado (rediscovery uma vez)
- [x] 8.3 Validar MAC e IDs de preset/gesto/ação contra o catálogo do modelo; escrever `tests/test_buds_vendor.py` com socket falso verificando: ID fora do catálogo recusado sem envio, MAC inválido recusado, timeout fecha o socket, `refused`/`auth_failed`/`protocol` mapeados para os códigos de erro; verificar com `python3 -I tests/test_buds_vendor.py`
- [ ] 8.4 Verificar no fone real que uma leitura durante reprodução de música não interrompe o áudio e que, com um celular com o app Xiaomi Earbuds conectado, o helper retorna `refused` (ou registrar em `docs/hardware-log.md` se o canal aceitar conexões simultâneas)

## 9. Painel — seção "Recursos Xiaomi"

- [x] 9.1 Integrar `buds-vendor probe` ao abrir o painel quando `hasXiaomiControl`, montando só os recursos reportados (D13); verificar que a seção aparece com o Redmi Buds e não aparece com outro fone (ou com o FD2D simulado ausente via fixture)
- [ ] 9.2 Adicionar bateria E/D/estojo com indicador de carga; verificar comparando com o `battery` do helper e colocando um fone no estojo
- [ ] 9.3 Adicionar alternância de baixa latência, seletor de preset de EQ (sem o personalizado) e editor de gestos por lado, todos com estado pendente e confirmação por releitura; verificar cada um no fone real e restaurar os valores originais registrados em 7.3
- [ ] 9.4 Adicionar mensagens traduzidas para `refused`, `auth_failed`, `timeout`, `protocol` com "tentar de novo" e ação "atualizar"; verificar desligando o fone durante uma leitura e conferindo que a camada 1 continua funcionando
- [x] 9.5 Completar `i18n/en.json` e `i18n/pt-BR.json` com as strings da seção Xiaomi (nomes de presets, gestos e ações) e verificar a troca de idioma ao vivo

## 12. Escolha do microfone (fone / notebook)

- [x] 12.1 Implementar `headphones-ctl mic <MAC> internal|headset` e `status.mic` (D14), com testes em `tests/test_ctl.sh` para a fonte ALSA escolhida, a troca automática gravada com `--save`, o A2DP preservado e valores inválidos recusados; verificar com `bash tests/test_ctl.sh`
- [x] 12.2 Verificar no fone real: partindo de HFP, `mic internal` volta o fone para `a2dp-sink`; uma gravação com `parecord` mantém `a2dp-sink`; `mic headset` volta a trocar para HFP durante a gravação e de volta para A2DP depois
- [x] 12.3 Adicionar ao painel o seletor "Microfone: Fone / Notebook" (oculto sem microfone interno), com texto explicativo e strings en/pt-BR; verificar que ele reflete o modo ativo depois de uma troca feita pelo helper

## 10. Documentação

- [x] 10.1 Escrever `README.md` (instalação via symlink + `omarchy bar put`, recursos das duas camadas, `bluez-deprecated-tools` opcional, efeitos colaterais do autoswitch e do mpris-proxy, rollback, seção de licença GPL-3.0-only com crédito ao MiBudsClient e link para `vendor/mibuds/README.md`) e verificar seguindo a instalação do zero após remover o symlink

## 11. Integração

- [ ] 11.1 Percorrer todos os cenários das specs `headphone-status`, `headphone-audio-routing`, `headphone-media-buttons`, `xiaomi-vendor-session` e `xiaomi-vendor-features` com o fone real, registrar o resultado em `docs/hardware-log.md` e verificar que `node tests/test_model.js`, `bash tests/test_ctl.sh` e `python3 -I -m unittest discover -s tests` passam
- [x] 11.2 Rodar `openspec validate add-headphones-plugin --strict` e verificar que passa

## Workflow follow-up

- Arquivar esta change depois da revisão.
