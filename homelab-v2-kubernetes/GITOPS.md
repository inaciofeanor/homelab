# GitOps com Argo CD

O Argo CD é instalado pelo chart Helm `argo/argo-cd`, fixado na versão `10.4.0`
(Argo CD `v3.5.1`). Os workloads declarados neste diretório são controlados
pela `Application` `homelab`, que acompanha a branch `dev`.

## Bootstrap do Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f homelab-v2-kubernetes/argocd-values.yaml
```

O repositório do GitHub é privado. Cadastre uma deploy key somente leitura no
repositório e crie um Secret do tipo `repository` no namespace `argocd`. A
chave privada nunca deve ser adicionada ao Git.

Depois de configurar o acesso ao repositório, aplique o bootstrap:

```bash
kubectl apply -f homelab-v2-kubernetes/210-argocd-certificate.yaml
kubectl apply -f homelab-v2-kubernetes/900-argocd-application.yaml
```

## Fluxo de alterações

1. Altere e valide os manifests localmente.
2. Crie um commit e envie para `dev`.
3. O Argo CD sincroniza automaticamente, remove recursos apagados do Git e
   corrige alterações manuais no cluster.
4. Promova para `main` somente depois da validação. Para usar `main`, altere
   `spec.source.targetRevision` em `900-argocd-application.yaml`.

Validações antes do push:

```bash
kubectl kustomize homelab-v2-kubernetes >/dev/null
kubectl apply --dry-run=server -k homelab-v2-kubernetes
```

## Atualizações de imagens com Renovate

O workflow `.github/workflows/renovate.yml`, executado a partir de `main`,
consulta diariamente os registries e abre pull requests contra `dev`. Ele
analisa os manifests Kubernetes deste diretório, arquivos Docker Compose e as
próprias GitHub Actions. O Renovate altera somente o Git; o Argo CD continua
sendo o único responsável por aplicar os manifests no cluster.

Cada PR de imagem identifica no título o repositório da imagem e a versão
anterior e nova. A tabela do corpo também mostra o arquivo alterado, o tipo da
atualização e os digests. Quando o registry publica uma nova construção para a
mesma tag, o título informa que se trata de uma troca de digest e mantém a tag
visível. Assim, uma atualização de conteúdo imutável não é confundida com uma
mudança de versão.

Acompanhe as versões detectadas na issue **Atualizações disponíveis**. Antes de
integrar um PR:

1. leia as notas da versão e procure mudanças incompatíveis ou migrações;
2. execute backup quando a aplicação ou o banco mantiver dados persistentes;
3. confirme tag e digest da imagem e valide os manifests;
4. integre em `dev` e acompanhe o rollout e a saúde no Argo CD;
5. promova para `main` somente após testar a aplicação.

Não integre em lote o PR inicial de pinagem sem revisar cada imagem. Atualizações
major exigem aprovação no Dependency Dashboard e nenhum PR usa automerge.

O workflow utiliza o `GITHUB_TOKEN` efêmero com permissões para Contents,
Issues, Pull requests e Commit statuses. No GitHub, mantenha habilitada a opção
**Allow GitHub Actions to create and approve pull requests**. Uma execução
manual pode ser iniciada em **Actions > Renovate > Run workflow**.

Para diagnosticar:

```bash
gh run list --workflow renovate.yml --limit 5
gh run view ID_DA_EXECUCAO --log
```

## Operação

```bash
kubectl get applications,appprojects -n argocd
kubectl get application homelab -n argocd \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl get pods -n argocd
```

A interface usa `https://argocd.feanor.com.br`. A senha inicial pode ser lida
uma única vez com:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Troque a senha no primeiro acesso e apague o Secret inicial:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## Recuperação

O Argo CD pode ser reinstalado pelo comando Helm de bootstrap. Depois, restaure
o Secret de acesso ao repositório e aplique `900-argocd-application.yaml`. Os
PVCs dos aplicativos não são recriados durante a adoção do GitOps.
