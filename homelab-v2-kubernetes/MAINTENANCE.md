# Manuten√ß√£o do cluster

Este guia re√∫ne as rotinas operacionais do homelab. Para construir ou reconstruir o servidor, use [INSTALLATION.md](INSTALLATION.md). Para recupera√ß√£o de dados, use [BACKUP.md](BACKUP.md).

## Verifica√ß√£o di√°ria

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get certificates -A
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

Todos os n√≥s devem estar `Ready`, os servi√ßos permanentes devem estar `Running` e os PVCs devem estar `Bound`. Jobs conclu√≠dos aparecem como `Succeeded` ou `Completed` e n√£o representam falha.

Para acompanhar temperatura e armazenamento no servidor:

```bash
sensors
df -h
sudo du -sh /var/lib/rancher/k3s/storage
```

## Diagn√≥stico

```bash
kubectl describe pod POD -n NAMESPACE
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --tail=200
kubectl logs -n NAMESPACE deploy/DEPLOYMENT --previous --tail=200
kubectl get events -A --sort-by=.lastTimestamp
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Teste um servi√ßo pelo Ingress mesmo quando o DNS externo n√£o estiver dispon√≠vel:

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

Depois de validar, fa√ßa commit e promova a altera√ß√£o para `main`. Imagens com tag `latest` s√≥ s√£o baixadas novamente quando o pod √© recriado; reinicie um servi√ßo deliberadamente com:

```bash
kubectl rollout restart deployment/DEPLOYMENT -n NAMESPACE
kubectl rollout status deployment/DEPLOYMENT -n NAMESPACE --timeout=300s
```

Antes de atualizar bancos ou aplica√ß√µes que armazenam dados, execute um backup. Actual Budget 26.8.0 e Memos usam SQLite e estrat√©gia `Recreate`; n√£o altere para `RollingUpdate`, pois dois pods n√£o devem acessar o mesmo arquivo simultaneamente. Consulte as notas da vers√£o do Actual Budget antes de atualizar e mantenha a imagem fixada por tag e digest.

### Atualizar o RomM

O RomM est√° fixado na vers√£o 5.2.0 e executa as migra√ß√µes do MariaDB ao
iniciar. Antes de trocar a imagem, execute o backup descrito em [BACKUP.md](BACKUP.md).
Depois que o Argo CD sincronizar a altera√ß√£o, valide o rollout, a vers√£o e os
logs de migra√ß√£o:

```bash
kubectl rollout status deployment/romm -n homelab --timeout=600s
kubectl get deployment/romm -n homelab \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl logs -n homelab deployment/romm --since=15m
curl -fsS -o /dev/null https://jogos.feanor.com.br/
```

Se a aplica√ß√£o n√£o ficar pronta, preserve o banco e os PVCs, consulte os logs
e reverta o commit no Git. Se a migra√ß√£o tiver alterado o banco de forma
incompat√≠vel, restaure em conjunto o dump do MariaDB e os volumes auxiliares do
backup criado antes da atualiza√ß√£o; n√£o restaure apenas um deles.

## Backup

Execute semanalmente e antes de atualiza√ß√µes relevantes:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

O procedimento para testar e restaurar c√≥pias est√° em [BACKUP.md](BACKUP.md).

## Letras no Navidrome

O plugin comunit√°rio `nd-lyrics` v7.2.0 fica em `/data/plugins/nd-lyrics.ndp`
no PVC `navidrome-data`. O SHA-256 esperado √©
`a9196e5b4e2c2eb2aaccb9f35c9faf6f488fe9081ff5685b1556901686c7540f`.
Ele usa LRCLIB e lyrics.ovh, procura a melhor sincroniza√ß√£o e grava letras ao
lado das m√∫sicas sem sobrescrever arquivos existentes.

```bash
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin validate nd-lyrics
kubectl exec -n homelab deploy/navidrome -- /app/navidrome plugin list -f json
```

O volume `/music` √© grav√°vel. O plugin s√≥ busca uma letra quando um cliente a
solicita. A WebUI n√£o consulta diretamente o provedor: use um cliente
OpenSubsonic compat√≠vel para a primeira solicita√ß√£o; depois o arquivo lateral
ser√° indexado e ficar√° dispon√≠vel como letra local.

## Secrets

Os valores reais n√£o devem entrar no Git. Os arquivos versionados cont√™m apenas recursos `SealedSecret`.

Para rotacionar as credenciais gerenciadas pelo script:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/secrets
./rotate-secrets.sh
```

As credenciais de provedores externos do RomM, como ScreenScraper, RetroAchievements e SteamGridDB, n√£o s√£o alteradas pelo script. Para rotacion√°-las, gere uma nova credencial no provedor, sele novamente o `Secret` correspondente com `kubeseal` e versione somente o `SealedSecret` criptografado. Para o SteamGridDB, use a chave `STEAMGRIDDB_API_KEY` no `Secret` `romm-steamgriddb-secrets`; nunca grave a chave em texto puro nos manifests ou na documentaÁ„o.

O script cria temporariamente `~/.local/state/homelab/credentials.env` com permiss√£o `0600`. Importe os valores em um gerenciador de senhas e remova essa c√≥pia quando n√£o for mais necess√°ria.

Fa√ßa backup criptografado da chave do controller Sealed Secrets fora do Git:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-master.key
chmod 600 sealed-secrets-master.key
```

Em uma restaura√ß√£o, aplique essa chave antes de instalar ou iniciar o controller.

## Certificados

O cert-manager usa DNS-01 no Cloudflare e grava o certificado wildcard em `feanor-wildcard-tls`.

```bash
kubectl get clusterissuer
kubectl get certificates -A
kubectl get challenges -A
kubectl describe certificate feanor-wildcard -n homelab
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

Os certificados Let's Encrypt duram 90 dias e s√£o renovados automaticamente. Se a renova√ß√£o falhar, confirme o token do Cloudflare no namespace `cert-manager`, a delega√ß√£o DNS e os eventos do `Challenge`. Nunca grave o token no reposit√≥rio.

## Monitoramento

Prometheus, Grafana e Alertmanager s√£o instalados pelo chart `kube-prometheus-stack` usando `monitoring-values.yaml`.

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

N√£o salve a senha real do Grafana no arquivo versionado. Use uma c√≥pia local ignorada ou um Secret existente no cluster.

### Alertas de pods

As regras de pods ficam em monitoring-alerts.yaml e devem ser reaplicadas ap√≥s reinstalar o kube-prometheus-stack:

```bash
kubectl apply -f homelab-v2-kubernetes/monitoring-alerts.yaml
kubectl get prometheusrule -n homelab homelab-pod-alerts
kubectl apply -f homelab-v2-kubernetes/alertmanager-n8n.yaml
```

O alerta aparece no Prometheus e no Alertmanager. Para receber e-mail, Telegram ou outro canal, configure um receiver e uma rota no Alertmanager; o manifesto n√£o inclui credenciais.

## Argo CD
O Argo CD √© opcional e usa `argocd-values.yaml`:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f homelab-v2-kubernetes/argocd-values.yaml
kubectl get pods -n argocd
```

Para reposit√≥rio hospedado no Gitea do pr√≥prio cluster, prefira o endere√ßo interno, evitando NAT loopback:

```text
http://gitea-http.homelab.svc.cluster.local:3000/USUARIO/REPOSITORIO.git
```

Use `dev` para valida√ß√£o e `main` para produ√ß√£o. Com `prune` e `selfHeal`, remo√ß√µes ou mudan√ßas no Git s√£o propagadas automaticamente ao cluster.

## Radarr e Bazarr

- Radarr: `https://radarr.feanor.com.br`; use `/media/filmes` como raiz, mantenha renomea√ß√£o desativada e n√£o configure cliente de download se o objetivo for apenas catalogar a biblioteca.
- Bazarr: `https://legendas.feanor.com.br`; conecte ao host interno `radarr`, porta `7878`, sem SSL, usando a API key do Radarr.
- Ambos montam `/media`, portanto n√£o precisam de path mapping.
- Configure Portuguese (Brazil), UTF-8 e armazenamento de legendas junto ao arquivo de v√≠deo.
- Credenciais do OpenSubtitles e API keys devem permanecer nos PVCs, nunca no Git.

## Comandos de emerg√™ncia

```bash
sudo systemctl status k3s
sudo journalctl -u k3s --since "30 minutes ago"
sudo systemctl restart k3s
```

Reiniciar o k3s interrompe todos os servi√ßos do n√≥. Use somente depois de verificar pods, eventos e logs.


## IntegraÁ„o de alertas com Telegram via n8n

O Alertmanager envia os alertas de pods para o webhook de produÁ„o do n8n:

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

5. Copie o valor de message.chat.id. Neste ambiente, o chat configurado È 145197342.

### Configurar o workflow no n8n

1. Crie um workflow com um nÛ Webhook.
2. Configure HTTP Method POST, Path alertmanager, Authentication conforme a proteÁ„o desejada e Respond Immediately.
3. Ative o workflow e use a URL de produÁ„o, com /webhook/alertmanager. A URL /webhook-test/alertmanager sÛ funciona durante testes.
4. Conecte a saÌda do Webhook ‡ entrada do nÛ Telegram.
5. No nÛ Telegram configure Resource Message, Operation Send Message, Chat ID 145197342, a credencial do BotFather e Additional Fields > Parse Mode Markdown.
6. Use este texto:

~~~text
5£`Ä©±ï…—ÑÅëºÅç±’Õ—ï»®((©9ΩµîË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπ±Öâï±ÃπÖ±ï…—πÖµîÅıÙ(©M—Ö—’ÃË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπÕ—Ö—’ÃÅıÙ(©9ÖµïÕ¡ÖçîË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπ±Öâï±ÃππÖµïÕ¡ÖçîÅıÙ(©AΩêË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπ±Öâï±Ãπ¡ΩêÅıÙ(©IïÕ’µºË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπÖππΩ—Ö—•ΩπÃπÕ’µµÖ…‰ÅıÙ(©ïÕç…ßüçºË®ÅÌÏÄë©ÕΩ∏πâΩë‰πÖ±ï…—Õl¡tπÖππΩ—Ö—•ΩπÃπëïÕç…•¡—•Ω∏ÅıÙ)˘˘¯()MîÅºÅ]ïâ°ΩΩ¨Åïπ—…ïùÖ»ÅÖ±ï…—ÃÅë•…ï—Öµïπ—îÅπÑÅ…Ö•Ë∞Å…ïµΩŸÑÄπâΩë‰ÅëÖÃÅï·¡…ïÕœ’ïÃ∏((åååÅQïÕ—Ö»()Ω¥ÅºÅ›Ω…≠ô±Ω‹ÅÖ—•Ÿº∞ÅïπŸ•îÅ’¥Å¡ÖÂ±ΩÖêÅëîÅ—ïÕ—îË()˘˘˘âÖÕ†)ç’…∞Äµ`ÅA=MPÅ°——¡ÃËºΩÖ’—ΩµÖçÖºπôïÖπΩ»πçΩ¥πâ»Ω›ïâ°ΩΩ¨ΩÖ±ï…—µÖπÖùï»ÄÄÄµ ÄâΩπ—ïπ–µQÂ¡îËÅÖ¡¡±•çÖ—•Ω∏Ω©ÕΩ∏àÄÄÄµêÄùÏâÕ—Ö—’ÃàËâô•…•πúà∞âÖ±ï…—ÃàÈmÏâÕ—Ö—’ÃàËâô•…•πúà∞â±Öâï±ÃàÈÏâÖ±ï…—πÖµîàËâQïÕ—ïQï±ïù…Ö¥à∞âπÖµïÕ¡ÖçîàËâ°Ωµï±Öàà∞â¡ΩêàËâ¡Ωêµ—ïÕ—îâÙ∞âÖππΩ—Ö—•ΩπÃàÈÏâÕ’µµÖ…‰àËâ±ï…—ÑÅëîÅ—ïÕ—îà∞âëïÕç…•¡—•Ω∏àËâ5ïπÕÖùï¥ÅëîÅ—ïÕ—îÅëºÅ±ï…—µÖπÖùï»Å¡Ö…ÑÅºÅQï±ïù…Ö¥∏âııuÙú)˘˘¯()Åï·ïç◊üçºÅëïŸîÅµΩÕ—…Ö»ÅΩÃÅªÕÃÅ]ïâ°ΩΩ¨ÅîÅQï±ïù…Ö¥ÅçΩµºÅçΩπç±◊µëΩÃ∞ÅîÅÑÅµïπÕÖùï¥ÅëïŸîÅç°ïùÖ»ÅπºÅç°Ö–ÅçΩπô•ù’…Öëº∏(
## Integra√ß√£o de alertas com Telegram via n8n

O Alertmanager envia os alertas de pods para o webhook de produ√ß√£o do n8n:

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

5. Copie o valor de message.chat.id. Neste ambiente, o chat configurado √© 145197342.

### Configurar o workflow no n8n

1. Crie um workflow com um n√≥ Webhook.
2. Configure HTTP Method POST, Path alertmanager, Authentication conforme a prote√ß√£o desejada e Respond Immediately.
3. Ative o workflow e use a URL de produ√ß√£o, com /webhook/alertmanager. A URL /webhook-test/alertmanager s√≥ funciona durante testes.
4. Conecte a sa√≠da do Webhook √† entrada do n√≥ Telegram.
5. No n√≥ Telegram configure Resource Message, Operation Send Message, Chat ID 145197342, a credencial do BotFather e Additional Fields > Parse Mode Markdown.
6. Use este texto:

~~~text
üö® *Alerta do cluster*

*Nome:* {{ $json.body.alerts[0].labels.alertname }}
*Status:* {{ $json.body.alerts[0].status }}
*Namespace:* {{ $json.body.alerts[0].labels.namespace }}
*Pod:* {{ $json.body.alerts[0].labels.pod }}
*Resumo:* {{ $json.body.alerts[0].annotations.summary }}
*Descri√ß√£o:* {{ $json.body.alerts[0].annotations.description }}
~~~

Se o Webhook entregar alerts diretamente na raiz, remova .body das express√µes.

### Testar

Com o workflow ativo, envie um payload de teste:

~~~bash
curl -X POST https://automacao.feanor.com.br/webhook/alertmanager \
  -H "Content-Type: application/json" \
  -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TesteTelegram","namespace":"homelab","pod":"pod-teste"},"annotations":{"summary":"Alerta de teste","description":"Mensagem de teste do Alertmanager para o Telegram."}}]}'
~~~

A execu√ß√£o deve mostrar os n√≥s Webhook e Telegram como conclu√≠dos, e a mensagem deve chegar no chat configurado.
