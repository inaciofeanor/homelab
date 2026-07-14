# ArgoCD — GitOps para o deploy das aplicações

Ideia: em vez de rodar `kubectl apply -k .` manualmente toda vez que você edita
um manifest, você dá `git push` pro Gitea e o ArgoCD aplica (e mantém) o estado
do cluster igual ao que está no repositório — incluindo desfazer mudanças
manuais feitas por fora (drift).

## 1. Instalar o Helm repo do Argo

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

## 2. Criar o namespace e instalar

```bash
kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f argocd-values.yaml
```

Acompanhar:

```bash
kubectl get pods -n argocd -w
```

## 3. Pegar a senha inicial do admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Usuário: `admin`. Troque essa senha assim que logar (**User Info → Update
Password** na UI, ou via `argocd account update-password` pela CLI).

## 4. Apontar o domínio

Igual aos outros serviços — adicione ao `/etc/hosts` (ou DNS local/roteador):

```
192.168.1.100 argocd.feanor.com.br
```

Acesse `https://argocd.feanor.com.br`.

## 5. ⚠️ Sobre usar o Gitea como repositório do ArgoCD

Não aponte o ArgoCD para `https://git.feanor.com.br/...`. Como esse domínio
resolve pro seu IP público, o repo-server (rodando *dentro* do cluster)
provavelmente vai tentar sair pra internet e voltar pelo mesmo IP — muitos
roteadores domésticos não suportam esse "NAT loopback" e a conexão falha ou
trava, sem erro claro no ArgoCD (só timeout).

Use o Service interno do Gitea em vez do domínio público:

```
http://gitea-http.homelab.svc.cluster.local:3000/SEU_USUARIO/SEU_REPO.git
```

Isso também evita lidar com TLS/certificado entre o repo-server e o Gitea —
é tráfego só dentro do cluster.

Se o repositório for privado, adicione a credencial primeiro
(**Settings → Repositories → Connect Repo** na UI do ArgoCD, ou via CLI
`argocd repo add`).

## 6. Subir este projeto pro Gitea

Se esses manifests (`kustomization.yaml` e os `NN-*.yaml`) ainda só existem
localmente, crie um repo no Gitea (ex: `homelab-k8s`) e dê push neles antes
do próximo passo — o ArgoCD sincroniza a partir do que está no Git, não do
que está no seu disco.

## 7. Criar a Application (o "app-of-apps" mais simples: um Application só)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homelab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea-http.homelab.svc.cluster.local:3000/SEU_USUARIO/homelab-k8s.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true      # remove do cluster o que for removido do repo
      selfHeal: true    # desfaz mudanças manuais feitas fora do Git
    syncOptions:
      - CreateNamespace=false   # 00-namespace.yaml já cria os namespaces
```

Aplique com `kubectl apply -f essa-application.yaml` (não precisa entrar no
`kustomization.yaml` principal — é um recurso do próprio ArgoCD, no
namespace `argocd`).

A partir daqui, qualquer `git push` no repo dispara uma sincronização
(por padrão o ArgoCD faz polling a cada ~3 minutos; dá pra configurar um
webhook do Gitea pra ArgoCD depois, se quiser que seja instantâneo).

## O que fica de fora por enquanto

- **`05-certificates.yaml`** e o resto do `kustomization.yaml` continuam
  funcionando normalmente dentro desse mesmo Application — nada muda aí.
- **Monitoring** (`kube-prometheus-stack`) continua sendo instalado via
  Helm separado, fora do ArgoCD — dá pra trazer isso pro GitOps depois
  usando o suporte a Helm charts do próprio ArgoCD, mas não é necessário
  agora.
- **O próprio ArgoCD** não gerencia a si mesmo aqui (ficaria mais complexo
  sem necessidade real num homelab). Se quiser esse nível depois, é o
  padrão "app of apps" com um segundo Application apontando pra própria
  instalação do ArgoCD.

## Importante: isso aumenta a prioridade do Sealed Secrets/SOPS

Hoje o `01-secrets.yaml`, `90-immich.yaml` e `95-romm.yaml` têm senhas em
texto plano. Levar esse repositório pro Gitea (mesmo que privado) é o
momento certo pra resolver isso antes, e não depois — já que fica registrado
no histórico do Git de forma mais "permanente" que arquivos soltos no disco.
Isso já estava no seu radar como próximo passo; vale adiantar antes do
`git push` inicial.
