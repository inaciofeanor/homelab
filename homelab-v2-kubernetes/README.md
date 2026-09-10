# Homelab Kubernetes

Stack de nó único baseada em k3s e Traefik. Os manifests em `homelab-v2-kubernetes` são a fonte de verdade das aplicações do cluster.

## Documentação

- [Instalação](INSTALLATION.md): preparação de uma máquina nova, k3s, controllers, secrets, certificados, DNS e implantação da stack.
- [Manutenção](MAINTENANCE.md): verificações diárias, atualização, diagnóstico, monitoramento, certificados, rotação de secrets e Argo CD.
- [GitOps com Argo CD](GITOPS.md): bootstrap, sincronização automática, PRs de atualização do Renovate e recuperação.
- [Backup e restauração](BACKUP.md): cópia fria dos PVCs, bibliotecas em `hostPath` e recuperação em outra máquina.

O Home Assistant é executado como Container, com dados persistentes em PVC e acesso em `https://casa.feanor.com.br`.
O Pinchflat gerencia downloads do YouTube em `https://youtube.feanor.com.br`;
os arquivos são publicados na biblioteca `YouTube` do Jellyfin.

## Aplicar alterações

Trabalhe na branch `dev`, valide e aplique a stack a partir desta pasta:

```bash
kubectl apply --dry-run=client -k .
kubectl apply -k .
kubectl get pods -A
```

As imagens e Actions são verificadas diariamente pelo Renovate. As propostas
aparecem como pull requests contra `dev`, sem automerge; atualizações major
precisam ser liberadas na issue **Atualizações disponíveis**. O Renovate não
propõe versões Docker antes do período de três dias; digests sem timestamp do
registry não ficam bloqueados indefinidamente. O Renovate não altera o
cluster diretamente: depois do merge, o Argo CD aplica a mudança e o
serviço deve ser validado antes da promoção para `main`. Consulte
[GitOps com Argo CD](GITOPS.md#atualizações-de-imagens-com-renovate).

## Numeração dos manifests

Os arquivos usam três dígitos e intervalos de 10 para permitir inserções sem
renumerar toda a sequência:

- `000–099`: recursos base;
- `100–199`: secrets;
- `200–299`: certificados;
- `300–899`: serviços, aplicações e tarefas operacionais;
- `900–999`: bootstrap e recursos GitOps.

Ao adicionar um manifesto entre dois existentes, use um número livre no
intervalo (por exemplo, `305` entre `300` e `310`) e inclua-o em
`kustomization.yaml`.

Os arquivos em `homelab-v1-docker-compose` pertencem à primeira versão do ambiente e não fazem parte da instalação atual.
