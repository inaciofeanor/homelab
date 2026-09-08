# Manutenção do cluster

Este guia reúne as rotinas operacionais do homelab. Para construir ou reconstruir o servidor, use [INSTALLATION.md](INSTALLATION.md). Para recuperação de dados, use [BACKUP.md](BACKUP.md).

## Canary

O Canary é administrado pela aplicação `canary` no Argo CD. Verifique os
quatro componentes e o consumo real:

```bash
kubectl get application canary -n argocd
kubectl get pods,pvc,svc -n homelab | grep canary
kubectl top pod -n homelab | grep canary
kubectl logs -n homelab deploy/canary --tail=200
kubectl logs -n homelab deploy/canary-myaac --tail=100
```

Antes de atualizar Canary, MariaDB, datapack ou mapa, faça backup dos dois PVCs.
O MariaDB está restrito à série 11.4 no manifesto; qualquer mudança major exige
revisão de compatibilidade e teste de restauração. Ao reconstruir o MyAAC,
atualize também o digest em `470-canary.yaml`.

O primeiro carregamento baixa aproximadamente 176 MiB de mapa e pode levar
alguns minutos. Depois de pronto, a mensagem `server online!` aparece no log.
Avisos sobre geração da documentação Lua ou execução como root não impediram o
servidor oficial de iniciar, mas devem ser revistos ao criar uma imagem própria.

O MyAAC usa `https://canary.feanor.com.br`; o registro A aponta para
`192.168.0.23`. As portas 7171–7175 e os NodePorts 30086/30088 continuam
acessíveis na LAN. Não faça redirecionamento no roteador sem antes adicionar
proteção contra abuso, firewall e uma política de atualização.

## Verificação diária

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get certificates -A
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

Todos os nós devem estar `Ready`, os serviços permanentes devem estar `Running` e os PVCs devem estar `Bound`. Jobs concluídos aparecem como `Succeeded` ou `Completed` e não representam falha.

Para acompanhar temperatura e armazenamento no servidor:

```bash
sensors
df -h
sudo du -sh /var/lib/rancher/k3s/storage
```

## Diagnóstico

```bash
kubectl describe pod POD -n NAMESPACE
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --tail=200
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --previous --tail=200
kubectl get events -A --sort-by=.lastTimestamp
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Teste um serviço pelo Ingress mesmo quando o DNS externo não estiver disponível:

```bash
curl -k --resolve HOST:443:IP_DO_SERVIDOR https://HOST/
```

Exemplos de health checks:

```bash
curl -fsS https://financas.feanor.com.br/health
curl -fsS https://tarefas.feanor.com.br/api/v1/info
curl -fsS -o /dev/null https://diario.feanor.com.br/
```

## Alterar e atualizar a stack

Nunca edite recursos apenas no cluster quando o Argo CD estiver com `selfHeal` ativo. Altere primeiro os manifests na branch `dev`:

```bash
git switch dev
git pull --ff-only
kubectl apply --dry-run=client -k homelab-v2-kubernetes
kubectl diff -k homelab-v2-kubernetes
kubectl apply -k homelab-v2-kubernetes
kubectl get pods -A -w
```

Depois de validar, faça commit e promova a alteração para `main`. Imagens com tag `latest` só são baixadas novamente quando o pod é recriado; reinicie um serviço deliberadamente com:

```bash
kubectl rollout restart deployment/DEPLOYMENT -n NAMESPACE
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Antes de atualizar bancos ou aplicações que armazenam dados, execute um backup. Actual Budget 26.8.0 e Memos usam SQLite e estratégia `Recreate`; não altere para `RollingUpdate`, pois dois pods não devem acessar o mesmo arquivo simultaneamente. Consulte as notas da versão do Actual Budget antes de atualizar e mantenha a imagem fixada por tag e digest.

### Upgrades major do PostgreSQL

As imagens PostgreSQL persistentes do Immich, Vikunja e n8n ficam em
`ignoreDeps` no Renovate. Atualizações dessas imagens devem ser propostas
manualmente, depois de revisar a compatibilidade e preparar a migração. A troca
da tag não migra o diretório de dados: faça dump lógico, restaure em um PVC vazio
com a nova major e valide a aplicação antes de descartar o PVC anterior. Os
deployments dos bancos usam `Recreate` para impedir acesso simultâneo ao PVC.

No PostgreSQL 18, revise também o novo layout de `PGDATA`: o volume passa a ser
montado em `/var/lib/postgresql`, com os dados em um subdiretório específico da
major. Nunca aponte diretamente a imagem 18 para o PVC 17 atual.

### Atualizar o RomM

O RomM está fixado na versão 5.2.0 e executa as migrações do MariaDB ao
iniciar. Antes de trocar a imagem, execute o backup descrito em [BACKUP.md](BACKUP.md).
Depois que o Argo CD sincronizar a alteração, valide o rollout, a versão e os
logs de migração:

```bash
kubectl rollout status deployment/romm -n homelab --timeout=600s
kubectl get deployment/romm -n homelab \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl logs -n homelab deployment/romm --since=15m
curl -fsS -o /dev/null https://jogos.feanor.com.br/
```

Se a aplicação não ficar pronta, preserve o banco e os PVCs, consulte os logs
e reverta o commit no Git. Se a migração tiver alterado o banco de forma
incompatível, restaure em conjunto o dump do MariaDB e os volumes auxiliares do
backup criado antes da atualização; não restaure apenas um deles.

### Manutenção do Home Assistant

```bash
kubectl get deployment/home-assistant service/home-assistant ingress/home-assistant pvc/home-assistant-data -n homelab
kubectl logs -n homelab deployment/home-assistant --tail=200
kubectl exec -n homelab deploy/home-assistant -- python -m homeassistant --script check_config --config /config
kubectl top pod -n homelab -l app=home-assistant
```

A imagem é fixada por versão e digest em `460-home-assistant.yaml`. Faça backup do PVC antes de atualizar. O `ConfigMap` só inicia a configuração; alterações posteriores em `/config/configuration.yaml` permanecem no PVC. Esta instalação não possui Supervisor: mantenha dependências como MQTT em serviços separados.

## Atualizações automáticas de imagens

O workflow `.github/workflows/renovate.yml` executa o Renovate diariamente às
07:17 no horário de Brasília e também aceita execução manual. Ele consulta os
registries, atualiza tags e digests nos manifests e abre pull requests contra
`dev`; não altera o cluster diretamente e nunca faz merge automático.

A autenticação usa o `GITHUB_TOKEN` efêmero do próprio job, limitado a Contents,
Issues, Pull requests e Commit statuses. A opção **Allow GitHub Actions to create and approve pull
requests** precisa permanecer habilitada no repositório. Não substitua esse
token por uma credencial pessoal gravada nos manifests.

As regras ficam em `renovate.json5`. Atualizações major aparecem primeiro na
issue **Atualizações disponíveis** e só geram PR depois de aprovadas nessa
issue. As demais respeitam uma espera mínima de três dias após a publicação.
Para updates Docker de `digest` e `pinDigest`, a espera é aplicada quando o
registry fornece um timestamp confiável; sem timestamp, a proposta é liberada
para não ficar bloqueada indefinidamente em **Pending Status Checks**.
Nos PRs de imagens, o título informa a imagem e a mudança da versão anterior
para a nova. O corpo apresenta imagem, manifesto, tipo da atualização, versões
e digests em colunas separadas. Se apenas o digest de uma tag for alterado, o
título identifica explicitamente a tag e os digests anterior e novo, sem
apresentar a reconstrução da imagem como uma nova versão.
Depois do merge em `dev`, valide o serviço e promova a mudança para `main` pelo
fluxo normal do repositório.

Use nomes canônicos de registry nos manifests. A imagem do n8n deve usar
`docker.io/n8nio/n8n`: o alias `docker.n8n.io` delega a autenticação ao Docker
Hub e pode impedir que o Renovate determine o novo digest. A troca de registry
deve manter a tag e usar um digest previamente validado.

O diretório `homelab-v1-docker-compose` é legado e fica em `ignorePaths`;
somente a stack Kubernetes atual participa das propostas de atualização.

Como workflows agendados só são executados a partir da branch padrão, esses
arquivos precisam existir em `main`, embora os PRs de dependências tenham
`dev` como branch base.

Atualmente o workflow fixa `renovatebot/github-action` v46.2.5 por SHA e o
Renovate CLI em 44.65.5. Ao atualizar qualquer um, execute manualmente e confira
as anotações do job antes de considerar a manutenção concluída.

## Backup

Execute semanalmente e antes de atualizações relevantes:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

O procedimento para testar e restaurar cópias está em [BACKUP.md](BACKUP.md).

## Letras no Navidrome

O plugin comunitário `nd-lyrics` v7.2.0 fica em `/data/plugins/nd-lyrics.ndp`
no PVC `navidrome-data`. O SHA-256 esperado é
`a9196e5b4e2c2eb2aaccb9f35c9faf6f488fe9081ff5685b1556901686c7540f`.
Ele usa LRCLIB e lyrics.ovh, procura a melhor sincronização e grava letras ao
lado das músicas sem sobrescrever arquivos existentes.

```bash
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin validate nd-lyrics
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin list -f json
```

O volume `/music` é gravável. O plugin só busca uma letra quando um cliente a
solicita. A WebUI não consulta diretamente o provedor: use um cliente
OpenSubsonic compatível para a primeira solicitação; depois o arquivo lateral
será indexado e ficará disponível como letra local.

## Agenda e tarefas no Nextcloud

O Nextcloud usa os aplicativos oficiais `calendar` e `tasks` para agenda,
compromissos, tarefas e lembretes. Os aplicativos são persistidos no PVC
`nextcloud-data`. Verifique o estado e as versões com:

```bash
kubectl exec -n homelab deploy/nextcloud -- \
  su -s /bin/sh www-data -c \
  'php /var/www/html/occ app:list --enabled'
```

Para procurar e instalar atualizações compatíveis com a versão atual do
Nextcloud, faça primeiro o backup e execute:

```bash
kubectl exec -n homelab deploy/nextcloud -- \
  su -s /bin/sh www-data -c \
  'php /var/www/html/occ app:update --showonly calendar && php /var/www/html/occ app:update --showonly tasks'

kubectl exec -n homelab deploy/nextcloud -- \
  su -s /bin/sh www-data -c \
  'php /var/www/html/occ app:update calendar && php /var/www/html/occ app:update tasks'
```

Depois, confirme que os dois aplicativos continuam habilitados, abra Calendar
e Tasks na interface web e crie um evento e uma tarefa de teste. O endpoint
CalDAV usado pelos celulares é
`https://nextcloud.feanor.com.br/remote.php/dav`; credenciais devem ficar apenas
no dispositivo ou no gerenciador de senhas.

## Secrets

Os valores reais não devem entrar no Git. Os arquivos versionados contêm apenas recursos `SealedSecret`.

Para rotacionar as credenciais gerenciadas pelo script:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/secrets
./rotate-secrets.sh
```

As credenciais de provedores externos do RomM, como ScreenScraper, RetroAchievements e SteamGridDB, não são alteradas pelo script. Para rotacioná-las, gere uma nova credencial no provedor, sele novamente o `Secret` correspondente com `kubeseal` e versione somente o `SealedSecret` criptografado. Para o SteamGridDB, use a chave `STEAMGRIDDB_API_KEY` no `Secret` `romm-steamgriddb-secrets`; nunca grave a chave em texto puro nos manifests ou na documentação.

O script cria temporariamente `~/.local/state/homelab/credentials.env` com permissão `0600`. Importe os valores em um gerenciador de senhas e remova essa cópia quando não for mais necessária.

Faça backup criptografado da chave do controller Sealed Secrets fora do Git:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-master.key
chmod 600 sealed-secrets-master.key
```

Em uma restauração, aplique essa chave antes de instalar ou iniciar o controller.

## Certificados

O cert-manager usa DNS-01 no Cloudflare e grava o certificado wildcard em `feanor-wildcard-tls`.

```bash
kubectl get clusterissuer
kubectl get certificates -A
kubectl get challenges -A
kubectl describe certificate feanor-wildcard -n homelab
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

Os certificados Let's Encrypt duram 90 dias e são renovados automaticamente. Se a renovação falhar, confirme o token do Cloudflare no namespace `cert-manager`, a delegação DNS e os eventos do `Challenge`. Nunca grave o token no repositório.

## Monitoramento

Prometheus, Grafana e Alertmanager são instalados pelo chart `kube-prometheus-stack` usando `monitoring-values.yaml`.

```bash
helm repo update
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 88.3.0 \
  -f homelab-v2-kubernetes/monitoring-values.yaml

helm status kube-prometheus-stack -n monitoring
kubectl get pods -n monitoring
```

Interfaces:

- Grafana: `https://grafana.feanor.com.br`
- Prometheus: `https://prometheus.feanor.com.br`
- Alertmanager: `https://alertmanager.feanor.com.br`

Não salve a senha real do Grafana no arquivo versionado. Use uma cópia local ignorada ou um Secret existente no cluster.

### Alertas de pods

As regras de pods ficam em monitoring-alerts.yaml e devem ser reaplicadas após reinstalar o kube-prometheus-stack:

```bash
kubectl apply -f homelab-v2-kubernetes/monitoring-alerts.yaml
kubectl get prometheusrule -n homelab homelab-pod-alerts
kubectl apply -f homelab-v2-kubernetes/alertmanager-n8n.yaml
```

O alerta aparece no Prometheus e no Alertmanager. Para receber e-mail, Telegram ou outro canal, configure um receiver e uma rota no Alertmanager; o manifesto não inclui credenciais.

## Argo CD
O Argo CD é opcional e usa `argocd-values.yaml`:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f homelab-v2-kubernetes/argocd-values.yaml
kubectl get pods -n argocd
```

Para repositório hospedado no Gitea do próprio cluster, prefira o endereço interno, evitando NAT loopback:

```text
http://gitea-http.homelab.svc.cluster.local:3000/USUARIO/REPOSITORIO.git
```

Use `dev` para validação e `main` para produção. Com `prune` e `selfHeal`, remoções ou mudanças no Git são propagadas automaticamente ao cluster.

## Radarr e Bazarr

- Radarr: `https://radarr.feanor.com.br`; use `/media/filmes` como raiz, mantenha renomeação desativada e não configure cliente de download se o objetivo for apenas catalogar a biblioteca.
- Bazarr: `https://legendas.feanor.com.br`; conecte ao host interno `radarr`, porta `7878`, sem SSL, usando a API key do Radarr.
- Ambos montam `/media`, portanto não precisam de path mapping.
- Configure Portuguese (Brazil), UTF-8 e armazenamento de legendas junto ao arquivo de vídeo.
- Credenciais do OpenSubtitles e API keys devem permanecer nos PVCs, nunca no Git.

## Comandos de emergência

```bash
sudo systemctl status k3s
sudo journalctl -u k3s --since "30 minutes ago"
sudo systemctl restart k3s
```

Reiniciar o k3s interrompe todos os serviços do nó. Use somente depois de verificar pods, eventos e logs.

## Integração de alertas com Telegram via n8n

O Alertmanager envia os alertas de pods para o webhook de produção do n8n:

~~~text
https://automacao.feanor.com.br/webhook/alertmanager
~~~

### Criar o bot e obter o chat_id

1. No Telegram, abra o @BotFather e envie /newbot.
2. Guarde o token do bot somente nas credenciais do n8n; nunca o comite no Git.
3. Envie uma mensagem para o bot.
4. Consulte:

~~~text
https://api.telegram.org/botTOKEN/getUpdates
~~~

5. Copie o valor de message.chat.id. Neste ambiente, o chat configurado é 145197342.

### Configurar o workflow no n8n

1. Crie um workflow com um nó Webhook.
2. Configure HTTP Method POST, Path alertmanager, Authentication conforme a proteção desejada e Respond Immediately.
3. Ative o workflow e use a URL de produção, com /webhook/alertmanager. A URL /webhook-test/alertmanager só funciona durante testes.
4. Conecte a saída do Webhook à entrada do nó Telegram.
5. No nó Telegram configure Resource Message, Operation Send Message, Chat ID 145197342, a credencial do BotFather e Additional Fields > Parse Mode Markdown.
6. Use este texto:

~~~text
🚨 *Alerta do cluster*

*Nome:* {{ $json.body.alerts[0].labels.alertname }}
*Status:* {{ $json.body.alerts[0].status }}
*Namespace:* {{ $json.body.alerts[0].labels.namespace }}
*Pod:* {{ $json.body.alerts[0].labels.pod }}
*Resumo:* {{ $json.body.alerts[0].annotations.summary }}
*Descrição:* {{ $json.body.alerts[0].annotations.description }}
~~~

Se o Webhook entregar alerts diretamente na raiz, remova .body das expressões.

### Testar

Com o workflow ativo, envie um payload de teste:

~~~bash
curl -X POST https://automacao.feanor.com.br/webhook/alertmanager \
  -H "Content-Type: application/json" \
  -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TesteTelegram","namespace":"homelab","pod":"pod-teste"},"annotations":{"summary":"Alerta de teste","description":"Mensagem de teste do Alertmanager para o Telegram."}}]}'
~~~

A execução deve mostrar os nós Webhook e Telegram como concluídos, e a mensagem deve chegar no chat configurado.
