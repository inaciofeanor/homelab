# Homelab Kubernetes

Stack de nó único baseada em k3s e Traefik. Os manifests em `homelab-v2-kubernetes` são a fonte de verdade das aplicações do cluster.

## Documentação

- [Instalação](INSTALLATION.md): preparação de uma máquina nova, k3s, controllers, secrets, certificados, DNS e implantação da stack.
- [Manutenção](MAINTENANCE.md): verificações diárias, atualização, diagnóstico, monitoramento, certificados, rotação de secrets e Argo CD.
- [GitOps com Argo CD](GITOPS.md): bootstrap, acesso ao repositorio, sincronizacao automatica e recuperacao.
- [Backup e restauração](BACKUP.md): cópia fria dos PVCs, bibliotecas em `hostPath` e recuperação em outra máquina.

## Aplicar alterações

Trabalhe na branch `dev`, valide e aplique a stack a partir desta pasta:

```bash
kubectl apply --dry-run=client -k .
kubectl apply -k .
kubectl get pods -A
```

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
