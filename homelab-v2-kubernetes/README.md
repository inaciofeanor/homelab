# Homelab Kubernetes

Stack de nó único baseada em k3s e Traefik. Os manifests em `homelab-v2-kubernetes` são a fonte de verdade das aplicações do cluster.

## Documentação

- [Instalação](INSTALLATION.md): preparação de uma máquina nova, k3s, controllers, secrets, certificados, DNS e implantação da stack.
- [Manutenção](MAINTENANCE.md): verificações diárias, atualização, diagnóstico, monitoramento, certificados, rotação de secrets e Argo CD.
- [GitOps com Argo CD](GITOPS.md): bootstrap, sincronização automática, PRs de atualização do Renovate e recuperação.
- [Backup e restauração](BACKUP.md): cópia fria dos PVCs, bibliotecas em `hostPath` e recuperação em outra máquina.

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
altera o cluster diretamente: depois do merge, o Argo CD aplica a mudança e o
serviço deve ser validado antes da promoção para `main`. Consulte
[GitOps com Argo CD](GITOPS.md#atualizações-de-imagens-com-renovate).

Os arquivos em `homelab-v1-docker-compose` pertencem à primeira versão do ambiente e não fazem parte da instalação atual.
