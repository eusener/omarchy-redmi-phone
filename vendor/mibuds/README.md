# vendor/mibuds — protocolo Xiaomi/Redmi adaptado do MiBudsClient

Estes arquivos são uma **cópia modificada** de partes do
[MiBudsClient](https://github.com/CesurPolat/MiBudsClient), de Cesur Polat e
colaboradores, licenciado sob a **GNU GPL v3**. Por isso este plugin inteiro é
distribuído sob a **GPL-3.0-only** (veja `LICENSE` na raiz).

- **Origem:** https://github.com/CesurPolat/MiBudsClient
- **Commit:** `52eb3f94da84ae0236f3f6a2c879765bdeecc3d4` (2026-11-20)
- **Data da cópia e das modificações:** 2026-11-22

Cada arquivo `.py` leva no cabeçalho o aviso de origem, o identificador SPDX e
a lista das alterações feitas nele (GPL-3.0, seção 5a).

## O que foi copiado

Só a pilha de protocolo de `controllers/bluetooth/`, que usa apenas a biblioteca
padrão do Python. **Não** foram copiados: a interface Flet, a bandeja, as
notificações, os módulos de ANC (`noise*`), a descoberta do Windows
(`windows_discovery.py`), o orquestrador da UI (`controller.py`) nem `utils/`.

| Arquivo | Original | Alterações |
|---|---|---|
| `rcsp.py` | `controllers/bluetooth/rcsp.py` | frames maiores que 4 KiB (MAX_FRAME_BYTES) descartados |
| `protocol.py` | `controllers/bluetooth/protocol.py` | nenhuma |
| `constants.py` | `controllers/bluetooth/constants.py` | nenhuma |
| `safer_plus.py` | `controllers/bluetooth/safer_plus.py` | nenhuma |
| `auth_codec.py` | `controllers/bluetooth/auth_codec.py` | nenhuma |
| `auth_session.py` | `controllers/bluetooth/auth_session.py` | nenhuma |
| `raw_auth.py` | `controllers/bluetooth/raw_auth.py` | nenhuma |
| `sdp.py` | `controllers/bluetooth/sdp.py` | consulta SDP do Windows (PowerShell/Winsock) removida; só Linux |
| `connection.py` | `controllers/bluetooth/connection.py` | imports de utils.* trocados por ._compat; captura de ANC (noise_capture) removida; mensagens de diagnóstico enviadas para stderr |
| `config_transport.py` | `controllers/bluetooth/config_transport.py` | imports de utils.* trocados por ._compat |
| `battery_stream.py` | `controllers/bluetooth/battery_stream.py` | nenhuma |
| `latency_transport.py` | `controllers/bluetooth/latency_transport.py` | imports de utils.* trocados por ._compat |
| `eq_transport.py` | `controllers/bluetooth/eq_transport.py` | imports de utils.* trocados por ._compat |
| `equalizer.py` | `controllers/bluetooth/equalizer.py` | imports de utils.* trocados por ._compat |
| `gesture_transport.py` | `controllers/bluetooth/gesture_transport.py` | imports de utils.* trocados por ._compat |
| `gestures.py` | `controllers/bluetooth/gestures.py` | nenhuma |
| `device_catalog.py` | `controllers/bluetooth/device_catalog.py` | imports de utils.* trocados por ._compat; catálogo lido de vendor/mibuds/device_catalog.json (sem PyInstaller) |
| `capabilities.py` | `controllers/bluetooth/capabilities.py` | nenhuma |
| `catalog_options.py` | `controllers/bluetooth/catalog_options.py` | nenhuma |
| `_compat.py` | `utils/i18n.py`, `utils/error_reports.py`, `utils/mibuds_api.py` | só as funções usadas (`message`, `error_message`, `redact`, `validate_catalog`), apenas em inglês |
| `device_catalog.json` | `assets/device_catalog.json` | nenhuma (resposta original do app, usada para nomes, VID/PID e recursos por modelo) |

Os bytes do protocolo (frames RCSP, opcodes, IDs de configuração, SAFER+) não
foram alterados.

## Sincronizar com o upstream

A sincronização é manual: compare o commit acima com o atual do MiBudsClient,
reaplique as alterações listadas na tabela e atualize o commit e a data aqui e
nos cabeçalhos.
