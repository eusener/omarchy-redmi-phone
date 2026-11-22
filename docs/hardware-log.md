# Registro de hardware — Redmi Buds 6 Play

Aparelho: Redmi Buds 6 Play `AA:BB:CC:DD:EE:FF`, firmware **2.0.2.2**, identidade
RCSP `N79B`, VID `0x2717`, PID `0x509B` (`miwear.headphone.n79bg`).
Host: Omarchy, BlueZ 5.87, PipeWire 1.6.9, WirePlumber 0.5.18, Python 3.14.
Código: `vendor/mibuds` (MiBudsClient@52eb3f94 adaptado).

## 2026-11-22 — experimentos da camada 2 (tarefas 7.1–7.3)

### Canal e sessão (7.1, 7.2)

| Teste | Resultado |
|---|---|
| `sdptool` | ausente; as três consultas SDP falham com "requires BlueZ's sdptool" |
| Fallback do 6 Play | **canal RFCOMM 6**, política `direct`, sem autenticação, conectado em 0,4 s |
| Canal 6 anunciado como FD2D (cache) | política `command_auth`, **autenticação SAFER+ concluída**, 0,9 s |
| `GET_DEVICE_INFO` sem autenticar | responde: `Redmi Buds 6 Play [N79B]`, firmware 2.0.2.2 |
| `GET_DEVICE_INFO` autenticado | responde igual |

Conclusão: a autenticação **não é exigida**, mas funciona. O canal 6 aceita as duas
políticas.

A captura `btmon -w captures/…` ficou vazia (16 bytes): o `btmon` precisa rodar
como root (`CAP_NET_RAW`). Para capturar, rode `btmon -w captures/redmi-$(date +%F).btsnoop`
como root num terminal enquanto o helper executa.

### Recursos (7.3), todos pelo caminho `direct`, valores originais restaurados

| Recurso | Leitura | Gravação + releitura | Observação |
|---|---|---|---|
| Bateria (opcode 02) | ok: E=228, D=228, estojo=228 (bit 7 = carregando, 100%) | — | BlueZ informava 100% no mesmo momento |
| Baixa latência (`002F`) | ok: desligada | ligar → relido ligado → desligar → relido desligado | ok |
| EQ (`0007`) | ok: preset 0 (Padrão) | 0 → 1 (Vocal), relido 1 → 0, relido 0 | presets do catálogo: 0, 6, 5, 1, 7 |
| Gestos (`0002`) | ok: toque simples 8/8, duplo 1/1, triplo 3/3, longo 0/0 (E/D) | triplo D 3 → 2, relido 2 → 3, relido 3 | exige uma leitura na mesma sessão antes de gravar |
| Baixa latência autenticada | ok: desligada | — | caminho `command_auth` também responde |

Nenhum recurso ficou sem resposta: bateria, baixa latência, EQ e gestos são
marcados como suportados para o 6 Play.

## 2026-11-22 — helper `bin/buds-vendor` (tarefas 8.1–8.4)

| Teste | Resultado |
|---|---|
| `probe` sem cache | 1,0 s; descobre o canal 6 (`direct`) e grava o cache |
| `battery` com cache | 0,5 s |
| Cache adulterado (canal 3) | falha, descarta o cache, redescobre o canal 6 uma vez |
| `latency set on/off`, `eq set 5/0`, `gestures set 2 right 2/3` | confirmados por releitura e restaurados |
| `eq set` sem leitura prévia | o transporte exige uma leitura na mesma sessão; o helper agora lê antes de gravar (EQ e gestos) |
| `probe` com um fluxo A2DP ativo (silêncio via `pacat`) | o sink continua `RUNNING`, o perfil continua `a2dp-sink`, sem erros no journal |
| Celular com o app Xiaomi Earbuds conectado ao mesmo tempo | **não testado**: falta um celular pareado |
