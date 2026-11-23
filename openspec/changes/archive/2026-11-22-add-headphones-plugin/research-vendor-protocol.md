# Pesquisa: camada 2 — protocolo proprietário Xiaomi (Redmi Buds 6 Play)

Status: **decidido em 2026-11-22.** A camada 2 entra nesta change (`add-headphones-plugin`) pela **opção A**: copiar e adaptar o MiBudsClient. O repositório passa a usar a licença **GPL-3.0-only**. Detalhes em design.md, decisões D10–D13.

Fatos levantados depois da pesquisa inicial:
- O `docs/equalizer.md` do MiBudsClient registra um teste num 6 Play real em 2026-10-27, pelo canal RFCOMM 6. O EQ `0007` foi lido (Vocal), trocado para Balanced com releitura e restaurado.
- O `sdptool` **não está instalado** nesta máquina. A descoberta de canal usa cache, o canal 6 e uma varredura de 1–30 (D12).
Fontes lidas em 2026-11-22: Gadgetbridge (commit `160beab417a0`) e MiBudsClient (commit `52eb3f94`, 2026-11-20).

## Resumo

- **Gadgetbridge não suporta o Buds 6 Play.** Suporta Redmi Buds 3 Pro, 4 Active, 5 Pro, 6, 6 Pro, 6 Active, 6 Lite e 8 Active. A lista está em https://gadgetbridge.org/gadgets/headphones/xiaomi/.
- **MiBudsClient** (https://github.com/CesurPolat/MiBudsClient, GPL-3.0) é um cliente Python feito para o Buds 6 Play. No catálogo dele o modelo aparece como `miwear.headphone.n79bg`, VID 2717, PID 509b. Ele implementa bateria, modo de baixa latência, gestos e EQ. No hardware real, só a autenticação foi registrada, numa sessão no Windows. Os comandos de recurso não foram exercitados nessa sessão.
- **Transporte:** RFCOMM clássico no UUID `0000fd2d-0000-1000-8000-00805f9b34fb`. Conferido em `RedmiBudsProtocol.java:83` do Gadgetbridge. Não é BLE GATT.
- **Os UUIDs batem com o fone:** o `bluetoothctl info` mostra FD2D e SPP. O UUID `df21fe2c-…927c` é provavelmente o Message Stream do Google Fast Pair, o que não foi verificado.

## Enquadramento (JieLi RCSP), segundo o código-fonte

Formato do frame:

```
FE DC BA | tipo | opcode | len(2, BE) | [status] seq | payload | EF
```

**Tipos de frame**

| Valor | Significado |
|---|---|
| `C4` | pedido do host |
| `04` | resposta (tem byte de status) |
| `C0` | pedido do fone |
| `C7` | notificação do fone |

**Opcodes**

| Opcode | Função |
|---|---|
| `02` | info do dispositivo (firmware) |
| `08` | ANC |
| `09` | run info |
| `0E` | relatório de status |
| `50` / `51` | desafio e confirmação de autenticação |
| `F2` / `F3` / `F4` | set / get / notify de configuração |

**IDs de configuração**

| ID | Recurso | Fonte |
|---|---|---|
| `02` | gestos | Gadgetbridge |
| `03` | atender automaticamente | Gadgetbridge |
| `06` | detecção de ouvido | Gadgetbridge |
| `07` | preset de EQ | Gadgetbridge |
| `0A` | gesto longo | Gadgetbridge |
| `37` | curva de EQ | Gadgetbridge |
| `2F` | baixa latência | MiBudsClient |

**Exemplo: baixa latência**
- ler: `fe dc ba c4 f3 00 03 <seq> 00 2f ef`
- gravar: `fe dc ba c4 f2 00 05 <seq> 03 00 2f <00|01> ef`

**Bateria:** um byte para cada fone e um para o estojo. O bit 7 indica carregando, os 7 bits baixos são a porcentagem, e `FF` significa indisponível. Com isso dá para mostrar bateria por fone e do estojo, coisa que o BlueZ não entrega.

**Autenticação no FD2D**
1. O host envia `C4 50` com `01 + 16 bytes aleatórios`.
2. O fone responde com SAFER+ sobre uma chave fixa e pública (`11 22 33 33 22 11 …`).
3. O fone desafia de volta, e a troca termina com o opcode `51`.

No Gadgetbridge, o código está em `encodeStartAuthentication` (~l.108) e `handleAuthentication` (~l.499). Não se sabe se o 6 Play exige essa autenticação. O fallback do MiBudsClient para o canal 6 manda comandos sem autenticar, mas isso não foi revalidado.

## Licenças: impacto na decisão (escolhida: opção A, GPL-3.0-only)

- Gadgetbridge é AGPL-3.0+, e MiBudsClient e o código SAFER+ que ele usa são GPL-3.0. Traduzir ou copiar esse código torna o plugin GPL/AGPL.
- **Opção A:** licenciar o helper da camada 2 como GPL-3.0 e reaproveitar o MiBudsClient. É o caminho mais rápido.
- **Opção B:** fazer uma reimplementação "clean-room" a partir de uma descrição escrita do protocolo, sem copiar código. Isso permite outra licença. Não é parecer jurídico.
- Uma opção intermediária é rodar o MiBudsClient como processo externo, sem embutir o código dele. Precisa confirmar se ele tem uma CLI usável.

## Arquitetura sugerida para a camada 2

- O helper `bin/buds-vendor` em Python usa só a biblioteca padrão: `socket.AF_BLUETOOTH`, `BTPROTO_RFCOMM`, sem PyBluez. Ele faz uma conexão curta por comando e devolve JSON, como o `headphones-ctl`. Assim o processo do shell nunca segura o canal.
- Para descobrir o canal, a ordem é:
  1. `sdptool browse --xml <MAC>` procurando FD2D. O `sdptool` está obsoleto e pode não estar instalado.
  2. `org.bluez.ProfileManager1.RegisterProfile` com o UUID FD2D e `Role=client`, recebendo o fd em `NewConnection`.
  3. Como fallback, o canal 6.
- **Conflitos:** a conexão é de saída e não disputa nada com o PipeWire, que só usa A2DP/HFP. Pode ser recusada se um celular com o app Xiaomi Earbuds estiver conectado ao mesmo fone (não verificado).
- O painel ganha uma seção "Recursos Xiaomi" (EQ, gestos, baixa latência, bateria L/R/estojo). Ela só aparece quando o fone tem o UUID FD2D e o handshake funciona, e degrada sem erro nos outros casos.

## Primeiros experimentos (para a change da camada 2)

1. `sdptool browse --xml AA:BB:CC:DD:EE:FF` → anotar o canal do FD2D.
2. Abrir o RFCOMM e enviar `GET_DEVICE_INFO` sem autenticar: `fe dc ba c4 02 00 05 <seq> ff ff ff ff ef`. Se não houver resposta, tentar o handshake `50`/`51`.
3. Ler a bateria (`F3`/`0E`) e comparar com os 60% do BlueZ.
4. Ler e gravar a baixa latência (`2F`), que é reversível e não destrutiva.
5. Capturar tudo com `btmon -w redmi.btsnoop` para registro.

## Engenharia reversa do que faltar

1. **Android:** em Opções do desenvolvedor, ativar o "Registro de rastreamento HCI Bluetooth" e reiniciar o Bluetooth. No app Xiaomi Earbuds, mudar uma configuração por vez, anotando o horário de cada uma.
2. **Extrair o log:** `adb bugreport`, arquivo `FS/data/misc/bluetooth/logs/btsnoop_hci.log`.
3. **Wireshark:** filtrar por `btrfcomm && data contains fe:dc:ba` e casar cada frame com os horários anotados.
4. **Opcional:** abrir o APK com jadx (`BluetoothAuth`, `libxm_bluetooth.so`) e usar Frida em `OutputStream.write`. O catálogo de IDs de configuração por modelo vem dentro do app.

## Incertezas em aberto

- Quais opcodes e IDs o 6 Play de fato aceita.
- Se o 6 Play tem detecção de ouvido.
- Se a autenticação é obrigatória.
- Se o FD2D aceita conexão com um celular conectado ao mesmo tempo.
