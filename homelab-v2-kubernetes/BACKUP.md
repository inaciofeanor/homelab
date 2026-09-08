# Backup e restauração do homelab

Esta solução cria uma cópia **portátil**, destinada a reconstruir o ambiente em
outro computador. Ela não copia o banco interno, os certificados nem a identidade
do nó k3s antigo. Em vez disso, um cluster novo é criado a partir dos manifests e
recebe o conteúdo dos volumes persistentes.

## O que entra no backup

- todos os PVCs `local-path` de todos os namespaces, inclusive bancos, Nextcloud,
  Gitea, Memos, Actual Budget, Portainer e monitoramento;
- recursos e metadados Kubernetes para auditoria;
- uma cópia do repositório, sem o diretório `.git`;
- opcionalmente, as bibliotecas `hostPath`: ebooks, mídia, músicas, fotos e ROMs;
- checksums SHA-256 de todos os arquivos.

O plugin `nd-lyrics` e suas configurações ficam no PVC `navidrome-data` e entram
no backup normal de PVCs. As letras geradas ficam ao lado das músicas no
`hostPath`; elas só entram no backup geral quando `--include-hostpaths` é usado
ou quando a biblioteca musical é copiada por outro processo.

O PVC `home-assistant-data` contém `configuration.yaml`, `.storage`, o banco SQLite padrão e eventuais backups locais. O backup frio inclui todo o `/config` com o banco consistente, pois interrompe o k3s durante a cópia.

O backup contém senhas e outros dados privados. Guarde-o em disco criptografado e
mantenha pelo menos uma segunda cópia desconectada ou fora de casa. Um backup no
mesmo disco do servidor não protege contra falha física, roubo ou ransomware.

## Criar um backup

Escolha um destino montado, por exemplo um HD externo em `/mnt/backup-homelab`.
O processo para o k3s durante a cópia dos dados para manter os bancos consistentes;
os serviços ficam indisponíveis nesse intervalo e o script reinicia o k3s mesmo se
ocorrer um erro.

Backup dos PVCs e configurações:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
```

Backup completo, incluindo as bibliotecas grandes:

```bash
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

Se os caminhos de mídia mudarem, copie `backup.conf.example` para `backup.conf` e
ajuste `HOST_PATHS`. O arquivo local `backup.conf` não deve conter senhas.

Cada execução cria uma pasta como `homelab-20260714T220000Z`. Nunca sincronize uma
pasta terminada em `.partial`: ela representa uma execução incompleta.

## Política recomendada

- backup semanal completo dos PVCs;
- backup mensal incluindo `hostPath`, caso as mídias não tenham outra cópia;
- retenção de pelo menos 4 semanais e 3 mensais;
- teste de restauração em outra máquina ou VM a cada três meses;
- regra 3-2-1: três cópias, em dois tipos de mídia, uma delas fora do local.

O script cria cópias completas, não incrementais. Se as bibliotecas crescerem muito,
use uma ferramenta deduplicada como Kopia ou Restic para os `hostPath`, mantendo este
backup frio para PVCs e metadados.

## Restaurar em outro computador

1. Instale Linux e monte o disco de dados no mesmo caminho usado nos manifests
   (`/mnt/dados-homelab-novo`), ou ajuste todos os `hostPath` antes de continuar.
2. Instale um k3s novo. Não copie `/var/lib/rancher/k3s/server` da máquina antiga.
3. Extraia `repository/homelab.tar.gz` do backup ou clone este repositório.
4. Revise IPs, DNS, certificados, secrets e caminhos nos manifests.
5. Se quiser restaurar os volumes de monitoramento, instale o chart antes de rodar
   o restore, conforme a seção de monitoramento de `INSTALLATION.md`, para que os três PVCs já existam.
6. Execute inicialmente sem `--force`:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./restore.sh /mnt/backup-homelab/homelab-AAAAMMDDTHHMMSSZ
```

Se o script informar que os PVCs recém-criados não estão vazios, confira se é mesmo
um cluster novo e repita com `--force`:

```bash
sudo ./restore.sh --force /mnt/backup-homelab/homelab-AAAAMMDDTHHMMSSZ
```

Para restaurar também as bibliotecas de mídia:

```bash
sudo ./restore.sh --restore-hostpaths --force \
  /mnt/backup-homelab/homelab-AAAAMMDDTHHMMSSZ
```

`--force` apaga o conteúdo atual dos destinos antes de extrair o backup. Nunca o
use em uma máquina que contenha dados não copiados.

## Verificações pós-restauração

```bash
kubectl get pods -A
kubectl get pvc -A
kubectl logs -n homelab deploy/nextcloud --tail=100
kubectl logs -n homelab deploy/home-assistant --tail=100
curl -fsS -o /dev/null https://casa.feanor.com.br/
kubectl logs -n homelab deploy/gitea --tail=100
```

Depois, acesse Nextcloud, Gitea, Immich, RomM, Memos e os demais serviços, confirme os
arquivos e faça um novo backup. Só apague a cópia antiga depois dessa validação.

## Automação

Antes de agendar, execute manualmente e meça o tempo e o espaço usados. Exemplo de
cron semanal, domingo às 03:00:

```cron
0 3 * * 0 /home/SEU_USUARIO/git/homelab/homelab-v2-kubernetes/backup/backup.sh /mnt/backup-homelab >> /var/log/homelab-backup.log 2>&1
```

### Backup diário do RomM no WSL

O script `tools/backup-romm-to-google-drive.sh` cria um dump transacional do
MariaDB e arquiva `resources`, `assets` e `config`. A biblioteca de ROMs não é
incluída. Os arquivos são gravados em `Google Drive/Backups/RomM`, recebem
checksum SHA-256 e têm retenção de 14 dias.

No crontab do usuário do WSL, execute-o depois do backup de Memos/Actual:

```cron
CRON_TZ=America/Sao_Paulo
0 14 * * * /home/SEU_USUARIO/git/homelab/tools/backup-romm-to-google-drive.sh >> "/mnt/d/Google Drive/Backups/cron-romm.log" 2>&1
```

O WSL precisa estar ativo no horário; o cron comum não recupera execuções perdidas.

### Backups PostgreSQL do Immich e n8n no WSL

O script `tools/backup-postgres-to-google-drive.sh` cria dumps lógicos no
formato customizado do PostgreSQL, valida o catálogo, grava checksum SHA-256 e
mantém 14 dias. O dump do Immich cobre o banco; as fotografias continuam no
`hostPath` e precisam de uma estratégia de backup própria. O dump do n8n deve
ser preservado junto da chave `N8N_ENCRYPTION_KEY`, armazenada no Sealed Secret.

Os dumps são transferidos em partes de 32 MiB para evitar timeouts da conexão com
a API do Kubernetes:

```bash
./tools/backup-postgres-to-google-drive.sh immich
./tools/backup-postgres-to-google-drive.sh n8n
```

Agendamento sugerido, depois do Vikunja:

```cron
0 16 * * * /home/SEU_USUARIO/git/homelab/tools/backup-postgres-to-google-drive.sh immich >> "/mnt/d/Google Drive/Backups/cron-immich.log" 2>&1
0 17 * * * /home/SEU_USUARIO/git/homelab/tools/backup-postgres-to-google-drive.sh n8n >> "/mnt/d/Google Drive/Backups/cron-n8n.log" 2>&1
```

Em 8 de setembro de 2026, os dumps foram restaurados com sucesso em contêineres
temporários usando PostgreSQL 16 para o Immich e PostgreSQL 18 para o n8n. Repita
esse teste imediatamente antes de cada migração major.

### Backup diário do Vikunja no WSL

O script `tools/backup-vikunja-to-google-drive.sh` usa o comando nativo
`vikunja dump`, que exporta banco, configuração e anexos em um ZIP restaurável.
Os arquivos são gravados em `Google Drive/Backups/Vikunja`, recebem checksum
SHA-256 e têm retenção de 14 dias.

Agende depois dos backups de Memos/Actual e RomM:

```cron
CRON_TZ=America/Sao_Paulo
0 15 * * * /home/SEU_USUARIO/git/homelab/tools/backup-vikunja-to-google-drive.sh >> "/mnt/d/Google Drive/Backups/cron-vikunja.log" 2>&1
```

O ZIP contém dados sensíveis, inclusive a configuração de conexão com o banco.
O cron de root não precisa de `sudo`. Monitore o arquivo de log e o espaço livre;
este script deliberadamente não remove backups antigos automaticamente.

