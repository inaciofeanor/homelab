# Guia de instalação — Homelab Kubernetes

Este guia instala a stack atual deste repositório em um servidor Linux de nó único com k3s. A pasta `homelab-v1-docker-compose` é legada e não faz parte deste procedimento.

## O que será instalado

No namespace `homelab`: Nextcloud (MariaDB e Redis), Gitea, Navidrome, Kavita, Jellyfin, Radarr, Bazarr, Homepage, Immich (Postgres, Valkey e machine learning), Memos (SQLite), RomM (MariaDB), Vikunja (PostgreSQL), n8n (PostgreSQL), Actual Budget (SQLite), Home Assistant e rAthena (MariaDB e FluxCP). O Portainer é instalado no namespace `portainer`.

Opcionalmente, o procedimento também cobre cert-manager/Let's Encrypt, monitoramento (Prometheus, Grafana e Alertmanager) e Argo CD.

## Pré-requisitos

- Servidor Linux x86-64, preferencialmente Ubuntu ou Debian, com acesso à Internet.
- Um único nó com pelo menos 4 vCPU, 8 GiB de RAM e armazenamento rápido para os PVCs. O Immich machine-learning solicita 1 vCPU e pode usar até 3 GiB de RAM.
- Um disco de dados montado de forma persistente em `/mnt/dados-homelab-novo`.
- DNS dos domínios `*.feanor.com.br` apontando para o servidor caso HTTPS público seja usado. Para certificados DNS-01, a zona precisa estar no Cloudflare.
- Acesso administrativo (`sudo`) e Git.

### Aceleração por GPU

O manifesto expõe `/dev/dri` ao Jellyfin para transcodificação VA-API/QSV. No
servidor atual, a Intel HD Graphics 5500 usa o driver `i915`. Confirme no nó antes
da instalação:

```bash
test -d /dev/dri && ls -la /dev/dri
lspci -nnk | grep -EA3 'VGA|Display|3D'
```

Essa configuração usa `hostPath` e, portanto, pressupõe um cluster de nó único ou
que os pods sejam fixados em um nó com GPU. Em um cluster com vários nós, use um
device plugin e afinidade de nó. A Radeon HD 8550M/R5 M230 deste servidor não é
compatível com versões atuais do ROCm.

A imagem OpenVINO do Immich v3.0.3 foi testada neste host, mas retornou somente o
dispositivo `CPU`: a Intel Broadwell Gen8 não é suportada pelo runtime atual. Por
isso, o `immich-machine-learning` permanece na imagem CPU. Não monte `/dev/dri`
nesse pod até que o servidor receba uma GPU suportada pelo OpenVINO, CUDA ou ROCm.

Depois do rollout, confirme o acesso do Jellyfin:

```bash
kubectl exec -n homelab deploy/jellyfin -- ls -la /dev/dri
```

O Immich v3 requer CPU `x86-64-v2` quando o nó é `amd64`. Verifique antes de instalar:

```bash
grep -m1 '^flags' /proc/cpuinfo | grep -Eo 'cx16|popcnt|sse4_2|ssse3' | sort -u
```

Devem aparecer os quatro recursos.

## 1. Clonar e revisar a configuração

```bash
sudo apt update
sudo apt install -y git curl ca-certificates
git clone git@github.com:inaciofeanor/homelab.git ~/git/homelab
cd ~/git/homelab/homelab-v2-kubernetes
git switch dev
```

Antes de aplicar qualquer recurso, revise nomes de domínio, e-mail do ACME, tamanho dos PVCs e os `hostPath` dos manifestos. Os caminhos abaixo devem existir; crie-os e ajuste o dono conforme o serviço que irá escrever neles:

```bash
sudo mkdir -p /mnt/dados-homelab-novo/{ebooks,music,photos,roms}
sudo mkdir -p /mnt/dados-jellyfin
```

O disco dedicado de mídia deve ser persistido no `/etc/fstab`. Para o disco identificado pelo label `jellyfin-filmes`:

```fstab
LABEL=jellyfin-filmes /mnt/dados-jellyfin ext4 defaults,nofail 0 2
```

Depois de executar `sudo mount -a`, crie `/mnt/dados-jellyfin/media` com UID e GID `1000`.

| Serviço | Manifesto | Caminho de mídia |
| --- | --- | --- |
| Navidrome | `330-navidrome.yaml` | `/mnt/dados-homelab-novo/music` |
| Kavita | `350-kavita.yaml` | `/mnt/dados-homelab-novo/ebooks` |
| Jellyfin | `360-jellyfin.yaml` | `/mnt/dados-jellyfin/media` |
| Radarr e Bazarr | `370-radarr-bazarr.yaml` | `/mnt/dados-jellyfin/media` |
| Immich | `400-immich.yaml` | `/mnt/dados-homelab-novo/photos` |
| RomM | `420-romm.yaml` | caminho configurado no `hostPath` do manifesto |

`hostPath` prende o pod ao nó local. Não use essa configuração em um cluster com vários nós sem substituir o armazenamento por volumes compartilhados.

O Navidrome grava arquivos laterais de letras em `music`; por isso esse caminho
precisa permitir escrita pelo usuário do contêiner. Kavita, Jellyfin, Radarr e
Bazarr continuam usando seus mounts conforme indicado nos próprios manifestos.

## 2. Instalar k3s e configurar kubectl

```bash
curl -sfL https://get.k3s.io | sh -

mkdir -p ~/.kube
sudo k3s kubectl config view --raw > ~/.kube/config
sudo chown "$USER":"$USER" ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config

kubectl get nodes
kubectl get pods -n kube-system
```

k3s instala o Traefik por padrão. Confirme que ele está `Running` antes de continuar.

## 3. Instalar Helm e os controllers necessários

```bash
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 /tmp/get_helm.sh
/tmp/get_helm.sh

helm repo add jetstack https://charts.jetstack.io
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --version v1.21.1 \
  --set crds.enabled=true
```

Espere o cert-manager ficar pronto:

```bash
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=180s
```

## 4. Restaurar ou criar os segredos

O arquivo `100-sealed-secrets.yaml` contém somente valores criptografados. Ele não pode ser decifrado por um controller novo sem a chave-mestre original.

### Reinstalação com a chave-mestre original

Copie a chave de recuperação, que nunca deve estar no Git, para o servidor com permissão `0600`. Aplique-a antes de instalar o controller:

```bash
kubectl apply -f /caminho/seguro/sealed-secrets-master.key
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system
kubectl rollout status deployment/sealed-secrets -n kube-system --timeout=180s
```

### Instalação nova, sem a chave antiga

Instale o controller e gere novos segredos; não aplique o `100-sealed-secrets.yaml` antigo esperando que ele funcione.

```bash
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system
```

Instale `kubeseal`, crie os `Secret` necessários com valores novos e sele cada recurso para substituir o manifesto correspondente. As chaves obrigatórias são:

| Secret | Chaves |
| --- | --- |
| `nextcloud-db-secrets` | `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` |
| `nextcloud-app-secrets` | `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD` |
| `immich-db-secrets` | `DB_PASSWORD` |
| `romm-secrets` | `DB_PASSWD`, `MARIADB_ROOT_PASSWORD`, `ROMM_AUTH_SECRET_KEY` |
| `romm-screenscraper-secrets` | `SCREENSCRAPER_USER`, `SCREENSCRAPER_PASSWORD` (opcional) |
| `romm-retroachievements-secrets` | `RETROACHIEVEMENTS_API_KEY` (opcional) |
| `romm-steamgriddb-secrets` | `STEAMGRIDDB_API_KEY` (opcional) |
| `vikunja-secrets` | `DB_PASSWORD` |
| `n8n-secrets` | `DB_PASSWORD`, `ENCRYPTION_KEY` |

Exemplo seguro para um secret; repita para os demais usando a lista acima. Não salve o YAML puro nem as senhas no repositório:

```bash
read -rsp 'Senha: ' PASSWORD; echo
kubectl -n homelab create secret generic immich-db-secrets \
  --from-literal=DB_PASSWORD="$PASSWORD" --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system --format yaml \
  > /tmp/immich-db-sealed.yaml
unset PASSWORD
```

Atualize `100-sealed-secrets.yaml` somente com o resultado criptografado. Faça backup criptografado da chave do controller:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > ~/sealed-secrets-master.key
chmod 600 ~/sealed-secrets-master.key
```

## 5. Configurar HTTPS e DNS

Para HTTPS público, crie o token DNS-01 do Cloudflare limitado à zona e salve-o somente no cluster:

```bash
kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager --from-literal=api-token='COLE_O_TOKEN_AQUI'
```

Revise o endereço de e-mail e os domínios em `200-certificates.yaml`. O certificado wildcard é criado nos namespaces `homelab`, `portainer` e `monitoring`.

Se ainda não houver DNS interno ou público, adicione temporariamente no cliente:

```text
IP_DO_SERVIDOR nextcloud.feanor.com.br git.feanor.com.br musica.feanor.com.br
IP_DO_SERVIDOR portainer.feanor.com.br ebooks.feanor.com.br filmes.feanor.com.br
IP_DO_SERVIDOR radarr.feanor.com.br legendas.feanor.com.br
IP_DO_SERVIDOR fotos.feanor.com.br jogos.feanor.com.br home.feanor.com.br
IP_DO_SERVIDOR tarefas.feanor.com.br automacao.feanor.com.br financas.feanor.com.br diario.feanor.com.br
IP_DO_SERVIDOR grafana.feanor.com.br prometheus.feanor.com.br alertmanager.feanor.com.br
IP_DO_SERVIDOR argocd.feanor.com.br ragnarok.feanor.com.br
```

## 6. Aplicar a stack

Valide e aplique os recursos na ordem definida por `kustomization.yaml`:

```bash
kubectl apply --dry-run=client -k .
kubectl apply -k .

kubectl get pods -n homelab -w
kubectl get pods -n portainer -w
kubectl get sealedsecrets -n homelab
kubectl get certificates -A
```

Em uma instalação inicial, aguarde bancos e PVCs ficarem prontos antes de abrir os serviços. Diagnóstico básico:

```bash
kubectl get all -n homelab
kubectl get pvc -A
kubectl logs -n homelab deploy/nextcloud --tail=100
kubectl logs -n homelab deploy/immich-server --tail=100
kubectl logs -n homelab deploy/actual-budget --tail=100
kubectl logs -n homelab deploy/memos --tail=100
curl -fsS https://financas.feanor.com.br/health
curl -fsS -o /dev/null https://diario.feanor.com.br/
```

### Plugin de letras do Navidrome

O plugin comunitário `nd-lyrics` v7.2.0 deve existir em
`/data/plugins/nd-lyrics.ndp`, dentro do PVC `navidrome-data`. Confira o pacote
antes de habilitá-lo:

```bash
echo 'a9196e5b4e2c2eb2aaccb9f35c9faf6f488fe9081ff5685b1556901686c7540f  nd-lyrics.ndp' | sha256sum -c -
kubectl cp nd-lyrics.ndp homelab/$(kubectl get pod -n homelab -l app=navidrome -o jsonpath='{.items[0].metadata.name}'):/data/plugins/nd-lyrics.ndp
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin rescan
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin validate nd-lyrics
```

Habilite o plugin para todos os usuários e bibliotecas, conceda acesso de
escrita e mantenha `overwriteLyrics=false`. O manifesto configura a prioridade
de letras e monta `/music` para escrita.
### rAthena e FluxCP

O manifesto `470-rathena.yaml` instala rAthena em modo Renewal, MariaDB 11.4
e FluxCP. O painel usa HTTPS, mas as portas do jogo ficam acessíveis apenas na
LAN ou VPN:

| Componente | Endereço |
| --- | --- |
| FluxCP | `https://ragnarok.feanor.com.br` |
| Login do cliente | `192.168.0.23:6900` |
| Character server | `192.168.0.23:6121` |
| Map server | `192.168.0.23:5121` |

A imagem está compilada com `PACKETVER=20211103`; use um executável kRO
compatível com essa data e configure o `clientinfo.xml` com o host
`192.168.0.23` e a porta `6900`. O servidor não cria contas pelo sufixo
`_M/_F`; registre a conta no FluxCP.

No primeiro acesso, abra o FluxCP e conclua o instalador. A senha do instalador
fica somente em
`~/.local/state/homelab/rathena-credentials.env` e no Sealed Secret. Depois,
registre uma conta; para torná-la administradora, altere o `group_id` no banco
de forma deliberada e remova o acesso ao instalador.

O MariaDB persiste no PVC `rathena-db-data`. O código e as configurações são
reproduzíveis a partir de `containers/rathena`, `containers/fluxcp` e do
workflow `.github/workflows/rathena-images.yml`. Alterações do jogo devem ser
versionadas e incorporadas à imagem, nunca feitas diretamente no pod.

Valide a implantação com:

```bash
kubectl rollout status deployment/rathena-db -n homelab --timeout=360s
kubectl rollout status deployment/rathena -n homelab --timeout=900s
kubectl rollout status deployment/fluxcp -n homelab --timeout=360s
curl -fsS -o /dev/null https://ragnarok.feanor.com.br/
nc -vz 192.168.0.23 6900
```


### Agenda e tarefas no Nextcloud

Depois que o Nextcloud estiver instalado e saudável, instale os aplicativos
oficiais Calendar e Tasks. Eles ficam em `/var/www/html/custom_apps`, dentro do
PVC `nextcloud-data`, e persistem durante recriações do pod:

```bash
kubectl exec -n homelab deploy/nextcloud -- \
  su -s /bin/sh www-data -c \
  'php /var/www/html/occ app:install calendar && php /var/www/html/occ app:install tasks'
```

O comando `app:install` também habilita os aplicativos. Caso já estejam
instalados, habilite-os explicitamente e confirme as versões:

```bash
kubectl exec -n homelab deploy/nextcloud -- \
  su -s /bin/sh www-data -c \
  'php /var/www/html/occ app:enable calendar tasks && php /var/www/html/occ app:list --enabled'
```

O Calendar gerencia compromissos e eventos recorrentes; o Tasks gerencia
tarefas, vencimentos, prioridades e lembretes. A sincronização móvel usa
CalDAV. No Android, use um adaptador CalDAV, como DAVx5, com um calendário e um
cliente de tarefas compatíveis. No iOS, adicione uma conta CalDAV apontando para
`https://nextcloud.feanor.com.br/remote.php/dav`.

## 7. URLs e primeiro acesso

| Serviço | URL |
| --- | --- |
| Homepage | `https://home.feanor.com.br` |
| Nextcloud | `https://nextcloud.feanor.com.br` |
| Gitea | `https://git.feanor.com.br` |
| Navidrome | `https://musica.feanor.com.br` |
| Portainer | `https://portainer.feanor.com.br` |
| Kavita | `https://ebooks.feanor.com.br` |
| Jellyfin | `https://filmes.feanor.com.br` |
| Radarr | `https://radarr.feanor.com.br` |
| Bazarr | `https://legendas.feanor.com.br` |
| Immich | `https://fotos.feanor.com.br` |
| RomM | `https://jogos.feanor.com.br` |
| Vikunja | `https://tarefas.feanor.com.br` |
| n8n | `https://automacao.feanor.com.br` |
| Actual Budget | `https://financas.feanor.com.br` |
| Memos | `https://diario.feanor.com.br` |
| Home Assistant | `https://casa.feanor.com.br` |
| rAthena/FluxCP | `https://ragnarok.feanor.com.br` |

O SSH do Gitea usa NodePort:

```bash
git clone ssh://git@IP_DO_SERVIDOR:30022/USUARIO/REPOSITORIO.git
```

A configuração operacional do Radarr e do Bazarr está resumida em [Manutenção](MAINTENANCE.md#radarr-e-bazarr).

### Actual Budget

O Actual Budget 26.8.0 usa o manifesto `450-actual-budget.yaml`, persiste seus dados no PVC `actual-budget-data` e não requer um banco externo. A imagem está fixada pelo digest `sha256:ef66469837852d04dd67e70cb069dca71a95e6ab135a905f6568730bf3f71480` para `linux/amd64`. O Deployment usa a estratégia `Recreate` para impedir que dois pods acessem simultaneamente o mesmo banco SQLite durante atualizações. Consulte as [notas da versão 26.8.0](https://actualbudget.org/blog/release-26.8.0) antes de futuras atualizações.

No primeiro acesso a `https://financas.feanor.com.br`:

1. defina uma senha forte para o servidor;
2. crie um orçamento e configure a moeda e a localização;
3. cadastre as contas manualmente ou importe extratos OFX, QIF, QFX, CAMT ou CSV;
4. opcionalmente, habilite criptografia de ponta a ponta nas configurações do orçamento.

Para verificar o serviço:

```bash
kubectl rollout status deployment/actual-budget -n homelab --timeout=360s
kubectl get pvc actual-budget-data -n homelab
curl -fsS https://financas.feanor.com.br/health
```

Uma resposta `{"status":"UP"}` confirma que o servidor está saudável. O script de backup geral inclui esse PVC automaticamente.

### Memos

O Memos usa o manifesto `410-memos.yaml`, SQLite e o PVC `memos-data`. O Deployment mantém uma única réplica com estratégia `Recreate`, evitando que dois processos acessem o mesmo banco durante atualizações. A instância não publica uma URL pública no backend, mantendo desativadas as superfícies públicas de exploração e RSS.

No primeiro acesso a `https://diario.feanor.com.br`, crie a conta administrativa. Em seguida, abra as configurações da instância e desative o cadastro de novos usuários. Não habilite acesso público caso o serviço seja usado como diário pessoal.

Para verificar o serviço:

```bash
kubectl rollout status deployment/memos -n homelab --timeout=180s
kubectl get pvc memos-data -n homelab
curl -fsS -o /dev/null https://diario.feanor.com.br/
```


### Home Assistant

O Home Assistant 2026.8.3 usa o manifesto `460-home-assistant.yaml` na modalidade Container, sem Supervisor nem loja de aplicativos. O PVC `home-assistant-data` reserva 10 GiB para `/config`. A rede do host permite descoberta por mDNS/SSDP e a estratégia `Recreate` protege o banco SQLite padrão.

O pod reserva `100m` de CPU e `512Mi` de memória, com limites de `1` CPU e `2Gi`. No primeiro acesso a `https://casa.feanor.com.br`, conclua o assistente e crie a conta proprietária. O `ConfigMap` de bootstrap cria `configuration.yaml` somente se ele não existir e restringe a confiança no proxy reverso às redes internas do cluster.

```bash
kubectl rollout status deployment/home-assistant -n homelab --timeout=600s
kubectl get pvc home-assistant-data -n homelab
kubectl exec -n homelab deploy/home-assistant -- python -m homeassistant --script check_config --config /config
curl -fsS -o /dev/null https://casa.feanor.com.br/
```

O contêiner não recebe acesso privilegiado nem dispositivos USB/Bluetooth. Para Zigbee, Z-Wave ou Bluetooth, mapeie somente o dispositivo necessário e reavalie o contexto de segurança.
O script de backup geral inclui o banco SQLite e os anexos armazenados nesse PVC automaticamente.

## 8. Monitoramento (opcional)

Use o arquivo atual `homelab-v2-kubernetes/monitoring-values.yaml`. Não grave a senha real do Grafana no Git: crie uma cópia local ignorada, por exemplo `monitoring-values.local.yaml`, e altere nela `grafana.adminPassword`.

```bash
cp monitoring-values.yaml monitoring-values.local.yaml
chmod 600 monitoring-values.local.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --version 88.3.0 \
  -f monitoring-values.local.yaml
kubectl get pods -n monitoring -w
kubectl apply -f monitoring-alerts.yaml
kubectl get prometheusrule -n homelab homelab-pod-alerts
```

## 9. Argo CD (opcional)

Instale somente depois que a stack manual estiver validada. O arquivo `argocd-values.yaml` expõe `argocd.feanor.com.br` pelo Traefik.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd
helm upgrade --install argocd argo/argo-cd \
  --version 10.4.0 \
  --namespace argocd \
  -f homelab-v2-kubernetes/argocd-values.yaml
kubectl get pods -n argocd -w
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Configure o recurso `Application` do Argo CD para a branch desejada. Para este repositório, use `dev` para testes e `main` somente para versões aprovadas. Com `selfHeal` ativo, mudanças feitas manualmente no cluster serão revertidas pelo Argo CD.

### Renovate no GitHub Actions

O Renovate não instala componentes no cluster. O agendamento do workflow
`.github/workflows/renovate.yml` é carregado da branch padrão `main`, enquanto
as atualizações usam `dev` como branch base. Execuções manuais podem usar
`dev`. Em **Settings > Actions > General > Workflow permissions**, mantenha a
permissão padrão como leitura e habilite **Allow GitHub Actions to create and
approve pull requests**. As permissões adicionais ficam limitadas ao job no
próprio workflow.

Execute **Actions > Renovate > Run workflow** uma vez após configurar ou
restaurar o repositório. Confirme que a execução cria ou atualiza a issue
**Atualizações disponíveis** e que os PRs usam `dev` como base. O agendamento
diário só funciona quando o workflow existe em `main`.

O workflow mantém a action fixada por SHA e o Renovate CLI por versão. Após
atualizá-los, execute o workflow manualmente e confirme nos checks a versão
efetivamente utilizada.

## 10. Backup e recuperação

O backup frio inclui PVCs, metadados e, opcionalmente, as bibliotecas em `hostPath`. Ele para o k3s durante a cópia para manter bancos consistentes.

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

Para restaurar em um computador novo, monte primeiro o disco em `/mnt/dados-homelab-novo`, instale k3s, restaure a chave do Sealed Secrets, ajuste os manifests e use:

```bash
sudo ./restore.sh /mnt/backup-homelab/homelab-AAAAMMDDTHHMMSSZ
```

Use `--force` apenas em um destino descartável ou após confirmar que os dados atuais podem ser apagados. Veja [Backup e restauração](BACKUP.md) para o procedimento completo e [Manutenção](MAINTENANCE.md) para as rotinas operacionais.

## Operação diária

```bash
kubectl get pods -A
kubectl get pvc -A
kubectl rollout restart deployment/immich-server -n homelab
kubectl logs -n homelab deploy/NOME_DO_SERVICO -f
kubectl apply -k .
```

Faça alterações e commits na branch `dev`. Promova para `main` somente após validar no cluster e revisar os manifests. O workflow de GitHub executa Gitleaks em push para `main` e em pull requests.
O Renovate verifica imagens e Actions diariamente, mas nunca integra ou implanta atualizações automaticamente.
