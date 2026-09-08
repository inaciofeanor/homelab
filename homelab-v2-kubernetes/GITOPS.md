# GitOps com Argo CD

O Argo CD é instalado pelo chart Helm `argo/argo-cd`, fixado na versão `10.4.0`
(Argo CD `v3.5.1`). O manifesto `901-argocd-applications.yaml` cria uma
`Application` para cada serviço e acompanha a branch `dev`.

O ApplicationSet apresenta cada serviço separadamente no Argo CD. O Canary
aparece como a aplicação `canary` e reúne somente
`160-canary-sealed-secret.yaml` e `470-canary.yaml`; alterações nesses
arquivos não ficam misturadas com as demais aplicações.

A `Application` `homelab-apps` controla somente o `AppProject` e o
`ApplicationSet`. Na tela inicial, Nextcloud, Immich, Home Assistant e os
demais serviços aparecem separadamente. Recursos compartilhados também aparecem
como aplicações independentes: `homelab-platform`, `homelab-secrets`,
`homelab-ingresses` e `homelab-maintenance`.

O `ApplicationSet` usa uma lista explícita de arquivos, evitando que duas
aplicações gerenciem o mesmo recurso. Todas apontam exclusivamente para o
cluster local `https://kubernetes.default.svc`.

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
kubectl apply -f homelab-v2-kubernetes/901-argocd-applications.yaml
```

## Fluxo de alterações

1. Altere e valide os manifests localmente.
2. Crie um commit e envie para `dev`.
3. O Argo CD sincroniza automaticamente, remove recursos apagados do Git e
   corrige alterações manuais no cluster.
4. Promova para `main` somente depois da validação. Para usar `main`, altere
   os dois campos `targetRevision` em `901-argocd-applications.yaml`.

Validações antes do push:

```bash
kubectl kustomize homelab-v2-kubernetes >/dev/null
kubectl apply --dry-run=server -k homelab-v2-kubernetes
```

## Atualizações de imagens com Renovate

O workflow agendado `.github/workflows/renovate.yml` é carregado da branch
padrão `main`, consulta diariamente os registries e usa `dev` como branch base
das atualizações. Execuções manuais também podem ser iniciadas em `dev`. Ele
analisa os manifests Kubernetes deste diretório, arquivos Docker Compose e as
próprias GitHub Actions. O Renovate altera somente o Git; o Argo CD continua
sendo o único responsável por aplicar os manifests no cluster.

Cada PR de imagem identifica no título o repositório da imagem e a versão
anterior e nova. A tabela do corpo mostra separadamente a tag ou versão atual, a
nova tag ou versão, o digest atual, o novo digest, o arquivo e o tipo da
atualização. Quando a referência não declara uma tag, as colunas de versão
mostram `latest (implícita)`, que é o valor efetivamente usado pelo runtime.
Quando o registry publica uma nova construção para a mesma tag, o título informa
que se trata de uma troca de digest e mantém a tag visível. Assim, uma
atualização de conteúdo imutável não é confundida com uma mudança de versão.

Acompanhe as versões detectadas na issue **Atualizações disponíveis**. Antes de
integrar um PR:

1. leia as notas da versão e procure mudanças incompatíveis ou migrações;
2. execute backup quando a aplicação ou o banco mantiver dados persistentes;
3. confirme tag e digest da imagem e valide os manifests;
4. integre em `dev` e acompanhe o rollout e a saúde no Argo CD;
5. promova para `main` somente após testar a aplicação.


O MariaDB do Nextcloud fica restrito à série `11.8.x`, suportada pelo
Nextcloud 34. O Renovate pode propor patches dessa série, mas não deve abrir
atualizações para MariaDB 12 enquanto ele estiver fora da matriz suportada.

Não integre em lote o PR inicial de pinagem sem revisar cada imagem. Atualizações
major exigem aprovação no Dependency Dashboard e nenhum PR usa automerge.
As demais atualizações de versão aguardam três dias após a publicação. Trocas
de digest e pinagens iniciais também respeitam esse período quando o registry
informa a data; quando não há timestamp, o Renovate pode prosseguir para evitar
que a atualização permaneça indefinidamente em **Pending Status Checks**.

A action é fixada por SHA e a versão do Renovate CLI também é explícita no
workflow. Atualize ambas de forma controlada e confirme a versão usada nas
anotações da execução.

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
kubectl get applications,applicationsets,appprojects -n argocd
kubectl get applications -n argocd \
  -l app.kubernetes.io/part-of=homelab \
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
o Secret de acesso ao repositório e aplique `901-argocd-applications.yaml`.
O `ApplicationSet` recria automaticamente todas as aplicações. Os PVCs dos
aplicativos não são recriados durante a adoção do GitOps.
