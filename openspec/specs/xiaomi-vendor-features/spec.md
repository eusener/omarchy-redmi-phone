# xiaomi-vendor-features Specification

## Purpose

Expõe no painel do fone os recursos proprietários dos fones Xiaomi/Redmi que só existiam no app de celular: bateria de cada fone e do estojo, modo de baixa latência, preset de EQ e mapeamento de gestos de toque.

## Requirements

### Requirement: Recursos por modelo
A seção "Recursos Xiaomi" SHALL mostrar apenas os recursos que o catálogo de dispositivos associa ao modelo identificado (por VID/PID ou nome) e que o fone de fato respondeu numa leitura. Um recurso que falhar na leitura SHALL ficar oculto, sem esconder os demais.

#### Scenario: Recurso não suportado
- **WHEN** o fone responde à leitura de bateria e EQ, mas não à de gestos
- **THEN** a seção mostra bateria e EQ e não mostra gestos

### Requirement: Bateria por fone e estojo
O painel SHALL mostrar a bateria do fone esquerdo, do direito e do estojo, cada uma como porcentagem com indicação de "carregando" quando aplicável. Um componente informado como indisponível SHALL ser omitido.

#### Scenario: Fones fora do estojo
- **WHEN** o fone informa esquerdo 60%, direito 58% e estojo indisponível
- **THEN** o painel mostra "E 60%" e "D 58%" e não mostra o estojo

#### Scenario: Carregando
- **WHEN** o fone informa o esquerdo com o bit de carga ligado e 40%
- **THEN** o painel mostra 40% com o indicador de carregando no fone esquerdo

### Requirement: Modo de baixa latência
O painel SHALL ter uma alternância de baixa latência que reflete o valor lido do fone e, ao ser acionada, grava o novo valor e confirma por releitura antes de mostrar o novo estado.

#### Scenario: Ligar baixa latência
- **WHEN** a baixa latência está desligada e o usuário liga a alternância
- **THEN** o plugin grava o valor, relê, e a alternância só aparece ligada se a releitura confirmar

#### Scenario: Gravação não confirmada
- **WHEN** a releitura retorna o valor anterior
- **THEN** a alternância volta ao estado anterior e o painel mostra uma mensagem de falha

### Requirement: Preset de EQ
O painel SHALL listar os presets de EQ que o catálogo oferece para o modelo, exceto o preset personalizado, marcar o preset ativo lido do fone e, ao escolher outro, gravar e confirmar por releitura.

#### Scenario: Trocar preset
- **WHEN** o preset ativo é Vocal e o usuário escolhe Padrão
- **THEN** o plugin grava, a releitura retorna Padrão e o painel marca Padrão

#### Scenario: Preset fora do catálogo
- **WHEN** o helper recebe um ID de preset que o catálogo não lista para o modelo
- **THEN** recusa sem enviar nada ao fone

### Requirement: Mapeamento de gestos
Para cada gesto que o modelo suporta (por exemplo toque duplo, toque triplo, toque longo) e cada lado (esquerdo/direito), o painel SHALL mostrar a ação atual e permitir escolher outra entre as ações permitidas para aquele gesto, gravando e confirmando por releitura.

#### Scenario: Remapear toque triplo
- **WHEN** o toque triplo do fone direito está em "Próxima faixa" e o usuário escolhe "Assistente de voz"
- **THEN** a releitura retorna "Assistente de voz" para o toque triplo direito e o painel mostra a nova ação

#### Scenario: Ação inválida para o gesto
- **WHEN** o helper recebe uma ação que não está na lista permitida para aquele gesto
- **THEN** recusa sem enviar nada ao fone

### Requirement: Atualização sob demanda
Os valores da seção Xiaomi SHALL ser lidos ao abrir o painel e após cada gravação, e SHALL poder ser relidos por uma ação "atualizar", sem leituras periódicas com o painel fechado.

#### Scenario: Painel fechado
- **WHEN** o painel está fechado
- **THEN** o plugin não abre conexões RFCOMM com o fone
