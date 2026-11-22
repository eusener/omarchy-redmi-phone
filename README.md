# Headphones — plugin do Omarchy para fones Bluetooth

Widget de barra e painel do Omarchy shell para o fone Bluetooth conectado.
Funciona com qualquer fone de áudio Bluetooth. Em fones **Xiaomi/Redmi** (testado
no Redmi Buds 6 Play), também mostra os recursos que antes só existiam no app
Xiaomi Earbuds do celular.

## Recursos

**Qualquer fone Bluetooth**

- Bateria do fone na barra; o ícone fica esmaecido sem fone conectado.
- Modo **Música** (A2DP, alta qualidade) ou **Chamada** (HFP, com microfone).
- Escolha do **codec**: SBC / SBC-XQ / AAC / LDAC… em Música, mSBC / CVSD em Chamada,
  conforme o que o fone e o PipeWire oferecem.
- **Usar como saída**: torna o fone a saída de áudio padrão.
- **Modo chamada automático**: troca para Chamada quando um app abre o microfone
  (configuração `bluetooth.autoswitch-to-headset-profile` do WirePlumber).
- **Botões do fone controlam o player**: toques no fone tocam, pausam e pulam
  faixas (serviço `mpris-proxy` do BlueZ).
- Conectar o último fone usado e desconectar.

**Fones Xiaomi/Redmi**, que anunciam o serviço de controle `0000fd2d-…`

- Bateria do fone **esquerdo**, do **direito** e do **estojo**, com indicador de carga.
- **Baixa latência** (modo jogo).
- **Equalizador**: os presets que o catálogo da Xiaomi lista para o modelo.
- **Controles de toque**: a ação de cada gesto, por lado.

A seção Xiaomi só aparece se o fone responder. Um recurso que não responder fica
oculto, e o resto do painel continua funcionando.

## Instalação

```bash
git clone <este repositório> ~/Projects/omarchy-redmi-phone
ln -s ~/Projects/omarchy-redmi-phone ~/.config/omarchy/plugins/eusener.headphones
omarchy bar put eusener.headphones --section right
```

Para abrir o painel por atalho: `omarchy-shell eusener.headphones toggle`.

**Dependências:** já vêm no Omarchy (`bluez`, `bluez-utils`, `pipewire-pulse`,
`wireplumber`, `jq`, `python3`).

Opcional: `bluez-deprecated-tools`, que traz o `sdptool`. Sem ele, o plugin
encontra o canal de controle Xiaomi pelo canal conhecido do modelo ou varrendo
os canais 1 a 30, e guarda o resultado em cache.

## Efeitos colaterais

- **Modo chamada automático** grava a configuração persistente do WirePlumber
  (`~/.local/state/wireplumber/sm-settings`). Com ela ligada, o WirePlumber pode
  voltar para Música quando o microfone fecha, mesmo que você tenha escolhido
  Chamada à mão.
- **Botões do fone** habilita o serviço de usuário `mpris-proxy`. Ele encaminha
  os botões de **qualquer** dispositivo Bluetooth (por exemplo, o rádio do carro)
  para o player ativo.
- **Recursos Xiaomi** abrem uma conexão RFCOMM curta (cerca de 1 s) só enquanto o
  painel está aberto. O canal descoberto fica em
  `~/.local/state/eusener-headphones/channels.json`. Equalizador, gestos e baixa
  latência ficam gravados **no fone**.
- Se um celular com o app Xiaomi Earbuds estiver conectado ao mesmo fone, a
  conexão de controle pode ser recusada. O painel avisa e oferece "Tentar de novo".

## Remover

```bash
# 1. tire "eusener.headphones" de bar.layout em ~/.config/omarchy/shell.json
rm ~/.config/omarchy/plugins/eusener.headphones
# 2. se quiser, desfaça as configurações
wpctl settings --save bluetooth.autoswitch-to-headset-profile true   # padrão
systemctl --user disable --now mpris-proxy
rm -r ~/.local/state/eusener-headphones
```

O que foi gravado no fone (EQ, gestos, latência) pode ser revertido pelo próprio
painel ou pelo app Xiaomi Earbuds.

## Desenvolvimento

| Arquivo | Papel |
|---|---|
| `Panel.qml` | widget de barra + painel (base `qs.Ui/Panel`) |
| `Model.js` | lógica pura: fone ativo, perfis/codecs, bateria, ordem dos gestos |
| `bin/headphones-ctl` | única porta de alteração do áudio/BlueZ (bash, argumentos validados) |
| `bin/buds-vendor` | recursos Xiaomi via RFCOMM; uma sessão por chamada, JSON em stdout |
| `vendor/mibuds/` | protocolo Xiaomi adaptado do MiBudsClient (veja o README de lá) |
| `i18n/` | `en.json` e `pt-BR.json` |
| `docs/hardware-log.md` | resultados dos testes no fone real |

Testes:

```bash
node tests/test_model.js
bash tests/test_ctl.sh
python3 -I tests/test_buds_vendor.py
python3 -I -m unittest discover -s tests/vendor -t tests/vendor
```

O watcher de plugins do shell (`inotifywait -r`) não segue o symlink. Depois de
editar arquivos aqui, recarregue com `omarchy restart shell`.

## Licença

**GPL-3.0-only** (veja `LICENSE`). O diretório `vendor/mibuds/` é uma cópia
modificada de partes do [MiBudsClient](https://github.com/CesurPolat/MiBudsClient),
de Cesur Polat e colaboradores, também sob GPL v3. A origem, o commit e as
alterações estão em [`vendor/mibuds/README.md`](vendor/mibuds/README.md).
