# Manutenção do cluster

Este guia reúne as rotinas operacionais do homelab. Para construir ou reconstruir o servidor, use [INSTALLATION.md](INSTALLATION.md). Para recuperação de dados, use [BACKUP.md](BACKUP.md).

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

Antes de atualizar bancos ou aplicações que armazenam dados, execute um backup. Actual Budget e Memos usam SQLite e estratégia `Recreate`; não altere para `RollingUpdate`, pois dois pods não devem acessar o mesmo arquivo simultaneamente.

## Backup

Execute semanalmente e antes de atualizações relevantes:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/backup
sudo ./backup.sh /mnt/backup-homelab
sudo ./backup.sh --include-hostpaths /mnt/backup-homelab
```

O procedimento para testar e restaurar cópias está em [BACKUP.md](BACKUP.md).

## Secrets

Os valores reais não devem entrar no Git. Os arquivos versionados contêm apenas recursos `SealedSecret`.

Para rotacionar as credenciais gerenciadas pelo script:

```bash
cd ~/git/homelab/homelab-v2-kubernetes/secrets
./rotate-secrets.sh
```

As credenciais de provedores externos do RomM, como ScreenScraper e RetroAchievements, não são alteradas pelo script. Para rotacioná-las, gere uma nova credencial no provedor, sele novamente o `Secret` correspondente com `kubeseal` e versione somente o `SealedSecret` criptografado.

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
  -f homelab-v2-kubernetes/monitoring-values.yaml

helm status kube-prometheus-stack -n monitoring
kubectl get pods -n monitoring
```

Interfaces:

- Grafana: `https://grafana.feanor.com.br`
- Prometheus: `https://prometheus.feanor.com.br`
- Alertmanager: `https://alertmanager.feanor.com.br`

Não salve a senha real do Grafana no arquivo versionado. Use uma cópia local ignorada ou um Secret existente no cluster.

## Argo CD

O Argo CD é opcional e usa `argocd-values.yaml`:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.2.2 \
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
