# ManutenÃ§Ã£o do cluster

Este guia reÃºne as rotinas operacionais do homelab. Para construir ou reconstruir o servidor, use [INSTALLATION.md](INSTALLATION.md). Para recuperaÃ§Ã£o de dados, use [BACKUP.md](BACKUP.md).

## VerificaÃ§Ã£o diÃ¡ria

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get certificates -A
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

Todos os nÃ³s devem estar `Ready`, os serviÃ§os permanentes devem estar `Running` e os PVCs devem estar `Bound`. Jobs concluÃ­dos aparecem como `Succeeded` ou `Completed` e nÃ£o representam falha.

Para acompanhar temperatura e armazenamento no servidor:

```bash
sensors
df -h
sudo du -sh /var/lib/rancher/k3s/storage
```

## DiagnÃ³stico

```bash
kubectl describe pod POD -n NAMESPACE
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --tail=200
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --previous --tail=200
kubectl get events -A --sort-by=.lastTimestamp
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Teste um serviÃ§o pelo Ingress mesmo quando o DNS externo nÃ£o estiver disponÃ­vel:

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

Depois de validar, faÃ§a commit e promova a alteraÃ§Ã£o para `main`. Imagens com tag `latest` sÃ³ sÃ£o baixadas novamente quando o pod Ã© recriado; reinicie um serviÃ§o deliberadamente com:

```bash
kubectl rollout restart deployment/DEPLOYMENT -n NAMESPACE
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Antes de atualizar bancos ou aplicaÃ§Ãµes que armazenam dados, execute um backup. Actual Budget 26.8.0 e Memos usam SQLite e estratÃ©gia `Recreate`; nÃ£o altere para `RollingUpdate`, pois dois pods nÃ£o devem acessar o mesmo arquivo simultaneamente. Consulte as notas da versÃ£o do Actual Budget antes de atualizar e mantenha a imagem fixada por tag e digest.

### Atualizar o RomM

O RomM estÃ¡ fixado na versÃ£o 5.2.0 e executa as migraÃ§Ãµes do MariaDB ao
iniciar. Antes de trocar a imagem, execute o backup descrito em [BACKUP.md](BACKUP.md).
Depois que o Argo CD sincronizar a alteraÃ§Ã£o, valide o rollout, a versÃ£o e os
logs de migraÃ§Ã£o:

```bash
kubectl rollout status deployment/romm -n homelab --timeout=600s
kubectl get deployment/romm -n homelab \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl logs -n homelab deployment/romm --since=15m
curl -fsS -o /dev/null https://jogos.feanor.com.br/
```

Se a aplicaÃ§Ã£o nÃ£o ficar pronta, preserve o banco e os PVCs, consulte os logs
e reverta o commit no Git. Se a migraÃ§Ã£o tiver alterado o banco de forma
incompatÃ­vel, restaure em conjunto o dump do MariaDB e os volumes auxiliares do
backup criado antes da atualizaÃ§Ã£o; nÃ£o restaure apenas um deles.

## AtualizaÃ§Ãµes automÃ¡ticas de imagens

O workflow `.github/workflows/renovate.yml` executa o Renovate diariamente Ã s
07:17 no horÃ¡rio de BrasÃ­lia e tambÃ©m aceita execuÃ§Ã£o manual. Ele consulta os
registries, atualiza tags e digests nos manifests e abre pull requests contra
`dev`; nÃ£o altera o cluster diretamente e nunca faz merge automÃ¡tico.

A autenticaÃ§Ã£o usa o `GITHUB_TOKEN` efÃªmero do prÃ³prio job, limitado a Contents,
Issues, Pull requests e Commit statuses. A opÃ§Ã£o **Allow GitHub Actions to create and approve pull
requests** precisa permanecer habilitada no repositÃ³rio. NÃ£o substitua esse
token por uma credencial pessoal gravada nos manifests.

As regras ficam em `renovate.json5`. AtualizaÃ§Ãµes major aparecem primeiro na
issue **AtualizaÃ§Ãµes disponÃ­veis** e sÃ³ geram PR depois de aprovadas nessa
issue. As demais respeitam uma espera mÃ­nima de trÃªs dias apÃ³s a publicaÃ§Ã£o.
Depois do merge em `dev`, valide o serviÃ§o e promova a mudanÃ§a para `main` pelo
fluxo normal do repositÃ³rio.

Como workflows agendados sÃ³ sÃ£o executados a partir da branch padrÃ£o, esses
arquivos precisam existir em `main`, embora os PRs de dependÃªncias tenham
`dev` como branch base.

## Backup

Execute semanalmente e antes de atualizaÃ§Ãµes relevantes:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

O procedimento para testar e restaurar cÃ³pias estÃ¡ em [BACKUP.md](BACKUP.md).

## Letras no Navidrome

O plugin comunitÃ¡rio `nd-lyrics` v7.2.0 fica em `/data/plugins/nd-lyrics.ndp`
no PVC `navidrome-data`. O SHA-256 esperado Ã©
`a9196e5b4e2c2eb2aaccb9f35c9faf6f488fe9081ff5685b1556901686c7540f`.
Ele usa LRCLIB e lyrics.ovh, procura a melhor sincronizaÃ§Ã£o e grava letras ao
lado das mÃºsicas sem sobrescrever arquivos existentes.

```bash
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin validate nd-lyrics
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin list -f json
```

O volume `/music` Ã© gravÃ¡vel. O plugin sÃ³ busca uma letra quando um cliente a
solicita. A WebUI nÃ£o consulta diretamente o provedor: use um cliente
OpenSubsonic compatÃ­vel para a primeira solicitaÃ§Ã£o; depois o arquivo lateral
serÃ¡ indexado e ficarÃ¡ disponÃ­vel como letra local.

## Secrets

Os valores reais nÃ£o devem entrar no Git. Os arquivos versionados contÃªm apenas recursos `SealedSecret`.

Para rotacionar as credenciais gerenciadas pelo script:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/secrets
./rotate-secrets.sh
```

As credenciais de provedores externos do RomM, como ScreenScraper, RetroAchievements e SteamGridDB, nÃ£o sÃ£o alteradas pelo script. Para rotacionÃ¡-las, gere uma nova credencial no provedor, sele novamente o `Secret` correspondente com `kubeseal` e versione somente o `SealedSecret` criptografado. Para o SteamGridDB, use a chave `STEAMGRIDDB_API_KEY` no `Secret` `romm-steamgriddb-secrets`; nunca grave a chave em texto puro nos manifests ou na documentação.

O script cria temporariamente `~/.local/state/homelab/credentials.env` com permissÃ£o `0600`. Importe os valores em um gerenciador de senhas e remova essa cÃ³pia quando nÃ£o for mais necessÃ¡ria.

FaÃ§a backup criptografado da chave do controller Sealed Secrets fora do Git:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-master.key
chmod 600 sealed-secrets-master.key
```

Em uma restauraÃ§Ã£o, aplique essa chave antes de instalar ou iniciar o controller.

## Certificados

O cert-manager usa DNS-01 no Cloudflare e grava o certificado wildcard em `feanor-wildcard-tls`.

```bash
kubectl get clusterissuer
kubectl get certificates -A
kubectl get challenges -A
kubectl describe certificate feanor-wildcard -n homelab
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

Os certificados Let's Encrypt duram 90 dias e sÃ£o renovados automaticamente. Se a renovaÃ§Ã£o falhar, confirme o token do Cloudflare no namespace `cert-manager`, a delegaÃ§Ã£o DNS e os eventos do `Challenge`. Nunca grave o token no repositÃ³rio.

## Monitoramento

Prometheus, Grafana e Alertmanager sÃ£o instalados pelo chart `kube-prometheus-stack` usando `monitoring-values.yaml`.

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

NÃ£o salve a senha real do Grafana no arquivo versionado. Use uma cÃ³pia local ignorada ou um Secret existente no cluster.

### Alertas de pods

As regras de pods ficam em monitoring-alerts.yaml e devem ser reaplicadas apÃ³s reinstalar o kube-prometheus-stack:

```bash
kubectl apply -f homelab-v2-kubernetes/monitoring-alerts.yaml
kubectl get prometheusrule -n homelab homelab-pod-alerts
kubectl apply -f homelab-v2-kubernetes/alertmanager-n8n.yaml
```

O alerta aparece no Prometheus e no Alertmanager. Para receber e-mail, Telegram ou outro canal, configure um receiver e uma rota no Alertmanager; o manifesto nÃ£o inclui credenciais.

## Argo CD
O Argo CD Ã© opcional e usa `argocd-values.yaml`:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f homelab-v2-kubernetes/argocd-values.yaml
kubectl get pods -n argocd
```

Para repositÃ³rio hospedado no Gitea do prÃ³prio cluster, prefira o endereÃ§o interno, evitando NAT loopback:

```text
http://gitea-http.homelab.svc.cluster.local:3000/USUARIO/REPOSITORIO.git
```

Use `dev` para validaÃ§Ã£o e `main` para produÃ§Ã£o. Com `prune` e `selfHeal`, remoÃ§Ãµes ou mudanÃ§as no Git sÃ£o propagadas automaticamente ao cluster.

## Radarr e Bazarr

- Radarr: `https://radarr.feanor.com.br`; use `/media/filmes` como raiz, mantenha renomeaÃ§Ã£o desativada e nÃ£o configure cliente de download se o objetivo for apenas catalogar a biblioteca.
- Bazarr: `https://legendas.feanor.com.br`; conecte ao host interno `radarr`, porta `7878`, sem SSL, usando a API key do Radarr.
- Ambos montam `/media`, portanto nÃ£o precisam de path mapping.
- Configure Portuguese (Brazil), UTF-8 e armazenamento de legendas junto ao arquivo de vÃ­deo.
- Credenciais do OpenSubtitles e API keys devem permanecer nos PVCs, nunca no Git.

## Comandos de emergÃªncia

```bash
sudo systemctl status k3s
sudo journalctl -u k3s --since "30 minutes ago"
sudo systemctl restart k3s
```

Reiniciar o k3s interrompe todos os serviÃ§os do nÃ³. Use somente depois de verificar pods, eventos e logs.


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
5£`©±ÉÑ¼±ÕÍÑÈ¨((©9½µè¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹±±Ì¹±ÉÑ¹µõô(©MÑÑÕÌè¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹ÍÑÑÕÌõô(©9µÍÁè¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹±±Ì¹¹µÍÁõô(©A½è¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹±±Ì¹Á½õô(©IÍÕµ¼è¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹¹¹½ÑÑ¥½¹Ì¹ÍÕµµÉäõô(©ÍÉ§¼è¨íì©Í½¸¹½ä¹±ÉÑÍlÁt¹¹¹½ÑÑ¥½¹Ì¹ÍÉ¥ÁÑ¥½¸õô)ùùø()M¼]¡½½¬¹ÑÉÈ±ÉÑÌ¥ÉÑµ¹Ñ¹É¥è°Éµ½Ù¹½äÌáÁÉÍÏÕÌ¸((QÍÑÈ()
½´¼Ý½É­±½ÜÑ¥Ù¼°¹Ù¥Õ´Áå±½ÑÍÑè()ùùùÍ )ÕÉ°µ`A=MP¡ÑÑÁÌè¼½ÕÑ½µ¼¹¹½È¹½´¹È½Ý¡½½¬½±ÉÑµ¹Èµ 
½¹Ñ¹ÐµQåÁèÁÁ±¥Ñ¥½¸½©Í½¸µìÍÑÑÕÌè¥É¥¹°±ÉÑÌémìÍÑÑÕÌè¥É¥¹°±±Ìéì±ÉÑ¹µèQÍÑQ±É´°¹µÍÁè¡½µ±°Á½èÁ½µÑÍÑô°¹¹½ÑÑ¥½¹ÌéìÍÕµµÉäè±ÉÑÑÍÑ°ÍÉ¥ÁÑ¥½¸è5¹Í´ÑÍÑ¼±ÉÑµ¹ÈÁÉ¼Q±É´¸õõuô)ùùø()á×¼Ùµ½ÍÑÉÈ½Ì»ÍÌ]¡½½¬Q±É´½µ¼½¹±×µ½Ì°µ¹Í´Ù¡È¹¼¡Ð½¹¥ÕÉ¼¸(
## IntegraÃ§Ã£o de alertas com Telegram via n8n

O Alertmanager envia os alertas de pods para o webhook de produÃ§Ã£o do n8n:

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

5. Copie o valor de message.chat.id. Neste ambiente, o chat configurado Ã© 145197342.

### Configurar o workflow no n8n

1. Crie um workflow com um nÃ³ Webhook.
2. Configure HTTP Method POST, Path alertmanager, Authentication conforme a proteÃ§Ã£o desejada e Respond Immediately.
3. Ative o workflow e use a URL de produÃ§Ã£o, com /webhook/alertmanager. A URL /webhook-test/alertmanager sÃ³ funciona durante testes.
4. Conecte a saÃ­da do Webhook Ã  entrada do nÃ³ Telegram.
5. No nÃ³ Telegram configure Resource Message, Operation Send Message, Chat ID 145197342, a credencial do BotFather e Additional Fields > Parse Mode Markdown.
6. Use este texto:

~~~text
ð¨ *Alerta do cluster*

*Nome:* {{ $json.body.alerts[0].labels.alertname }}
*Status:* {{ $json.body.alerts[0].status }}
*Namespace:* {{ $json.body.alerts[0].labels.namespace }}
*Pod:* {{ $json.body.alerts[0].labels.pod }}
*Resumo:* {{ $json.body.alerts[0].annotations.summary }}
*DescriÃ§Ã£o:* {{ $json.body.alerts[0].annotations.description }}
~~~

Se o Webhook entregar alerts diretamente na raiz, remova .body das expressÃµes.

### Testar

Com o workflow ativo, envie um payload de teste:

~~~bash
curl -X POST https://automacao.feanor.com.br/webhook/alertmanager \
  -H "Content-Type: application/json" \
  -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TesteTelegram","namespace":"homelab","pod":"pod-teste"},"annotations":{"summary":"Alerta de teste","description":"Mensagem de teste do Alertmanager para o Telegram."}}]}'
~~~

A execuÃ§Ã£o deve mostrar os nÃ³s Webhook e Telegram como concluÃ­dos, e a mensagem deve chegar no chat configurado.
