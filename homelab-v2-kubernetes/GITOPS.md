# GitOps com Argo CD

O Argo CD e instalado pelo Helm chart `argo/argo-cd` fixado na versao `10.2.2`
(Argo CD `v3.4.6`). Os workloads declarados neste diretorio sao controlados
pela `Application` `homelab`, que acompanha a branch `dev`.

## Bootstrap do Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.2.2 \
  --namespace argocd --create-namespace \
  -f homelab-v2-kubernetes/argocd-values.yaml
```

O repositorio GitHub e privado. Cadastre uma deploy key somente leitura no
repositorio e crie um Secret do tipo `repository` no namespace `argocd`. A
chave privada nunca deve ser adicionada ao Git.

Depois de configurar o acesso ao repositorio, aplique o bootstrap:

```bash
kubectl apply -f homelab-v2-kubernetes/08-argocd-certificate.yaml
kubectl apply -f homelab-v2-kubernetes/99-argocd-application.yaml
```

## Fluxo de alteracoes

1. Altere e valide os manifests localmente.
2. Crie um commit e envie para `dev`.
3. O Argo CD sincroniza automaticamente, remove recursos apagados do Git e
   corrige alteracoes manuais no cluster.
4. Promova para `main` somente depois da validacao. Para usar `main`, altere
   `spec.source.targetRevision` em `99-argocd-application.yaml`.

Validacoes antes do push:

```bash
kubectl kustomize homelab-v2-kubernetes >/dev/null
kubectl apply --dry-run=server -k homelab-v2-kubernetes
```

## Operacao

```bash
kubectl get applications,appprojects -n argocd
kubectl get application homelab -n argocd \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl get pods -n argocd
```

A interface usa `https://argocd.feanor.com.br`. A senha inicial pode ser lida
uma unica vez com:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Troque a senha no primeiro acesso e apague o Secret inicial:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## Recuperacao

O Argo CD pode ser reinstalado pelo comando Helm de bootstrap. Depois, restaure
o Secret de acesso ao repositorio e aplique `99-argocd-application.yaml`. Os
PVCs dos aplicativos nao sao recriados durante a adocao GitOps.
