# xiaomi-vendor-session Specification

## Purpose

Estabelece o canal de controle proprietário com fones Xiaomi/Redmi (RCSP sobre RFCOMM, UUID FD2D): descoberta do canal, conexão, autenticação, e degradação silenciosa quando o fone não suporta o protocolo.

## Requirements

### Requirement: Elegibilidade do fone
O plugin SHALL tentar o canal Xiaomi apenas quando o fone ativo anuncia o UUID `0000fd2d-0000-1000-8000-00805f9b34fb`. Para os demais fones, SHALL não abrir conexões RFCOMM e SHALL não exibir a seção "Recursos Xiaomi".

#### Scenario: Fone Xiaomi
- **WHEN** o fone ativo é o Redmi Buds 6 Play, que anuncia FD2D
- **THEN** o plugin tenta abrir o canal Xiaomi ao abrir o painel

#### Scenario: Fone de outra marca
- **WHEN** o fone ativo não anuncia FD2D
- **THEN** nenhuma conexão RFCOMM é aberta e a seção "Recursos Xiaomi" não aparece

### Requirement: Descoberta do canal RFCOMM
O plugin SHALL descobrir o canal do serviço FD2D pelo registro SDP quando houver ferramenta disponível. Na falta dela, SHALL tentar o canal 6 e depois varrer os canais 1 a 30, aceitando um canal só se ele responder a um pedido RCSP válido. O canal encontrado SHALL ficar em cache por endereço do fone.

#### Scenario: Sem sdptool
- **WHEN** `sdptool` não está instalado
- **THEN** o plugin encontra o canal por tentativa, guarda-o em cache e a próxima abertura usa o canal em cache

#### Scenario: Canal em cache inválido
- **WHEN** o canal em cache deixa de responder
- **THEN** o cache é descartado e a descoberta é refeita uma vez

### Requirement: Autenticação
Se o fone exigir o handshake de autenticação, o plugin SHALL concluí-lo antes de enviar qualquer comando de recurso. Se a autenticação falhar, SHALL encerrar a conexão sem enviar comandos de recurso.

#### Scenario: Autenticação exigida e bem-sucedida
- **WHEN** o fone responde ao pedido inicial exigindo autenticação
- **THEN** o plugin conclui o desafio/resposta e então executa o comando pedido

#### Scenario: Autenticação falha
- **WHEN** a resposta do fone ao desafio é inválida
- **THEN** a conexão é fechada, nenhum comando de recurso é enviado e o painel mostra "não foi possível autenticar com o fone"

### Requirement: Conexões curtas e limitadas
Cada operação SHALL abrir sua própria conexão, concluir em no máximo 10 segundos e fechar a conexão ao terminar, com sucesso ou erro, sem manter o canal aberto entre operações e sem afetar o áudio A2DP/HFP em andamento.

#### Scenario: Música tocando durante leitura
- **WHEN** há música tocando no fone e o painel lê os recursos Xiaomi
- **THEN** a reprodução continua sem interrupção e a conexão RFCOMM é fechada após a leitura

#### Scenario: Fone não responde
- **WHEN** o fone não responde em 10 segundos
- **THEN** a operação termina com erro de tempo esgotado e a conexão é fechada

### Requirement: Canal ocupado ou recusado
Quando a conexão ao canal Xiaomi for recusada (por exemplo, um celular com o app Xiaomi Earbuds conectado), o painel SHALL manter a camada 1 funcionando e exibir na seção "Recursos Xiaomi" uma mensagem explicando a recusa, com ação para tentar de novo.

#### Scenario: Celular segurando o canal
- **WHEN** a conexão RFCOMM é recusada
- **THEN** modo, codec e bateria do BlueZ continuam funcionando e a seção Xiaomi mostra a mensagem de recusa com "tentar de novo"

### Requirement: Entrada não confiável do fone
Respostas do fone SHALL ser tratadas como entrada não confiável: frames com tamanho incoerente, maiores que 4 KiB ou com valores fora do domínio de cada recurso SHALL ser descartados, sem travar o helper nem chegar à interface.

#### Scenario: Frame malformado
- **WHEN** o fone envia um frame cujo campo de tamanho excede os bytes recebidos
- **THEN** o frame é descartado e a operação termina com erro de protocolo, sem exceção não tratada
