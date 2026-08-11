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

O cron de root não precisa de `sudo`. Monitore o arquivo de log e o espaço livre;
este script deliberadamente não remove backups antigos automaticamente.

