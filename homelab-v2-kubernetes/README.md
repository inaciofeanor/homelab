# Home Lab em Kubernetes (k3s) com Traefik

Migração da stack Docker Compose para Kubernetes, usando **k3s** (distribuição leve de
Kubernetes, ideal para notebook/single-node) com **Traefik** — que já vem **embutido por
padrão no k3s** como Ingress Controller.

## 1. Instalar o k3s

```bash
curl -sfL https://get.k3s.io | sh -
```

Verificar se está rodando:

```bash
sudo systemctl status k3s
```

Configurar o `kubectl` para o seu usuário (sem precisar de `sudo` toda vez):

```bash
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

Confirmar que o cluster está de pé e que o Traefik já está rodando (vem com o k3s por padrão):

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep traefik
```

## 2. Ajustar os manifests antes de aplicar

1. **Senhas** — edite `01-secrets.yaml` e troque todos os valores `changeme_*`.
2. **Pasta de música** — edite `40-navidrome.yaml` e ajuste o `hostPath.path` para o caminho real da sua pasta de música no notebook.
3. **Domínios locais** — os hosts usados são `nextcloud.feanor.com.br`, `git.feanor.com.br`, `musica.feanor.com.br` e `portainer.feanor.com.br` (arquivo `50-ingress.yaml`). Pode trocar por outros nomes se preferir.

## 3. Aplicar tudo de uma vez

```bash
kubectl apply -k .
```

Acompanhar o status:

```bash
kubectl get pods -n homelab -w
kubectl get pods -n portainer -w
```

O Nextcloud demora um pouco mais no primeiro start (criação do banco). Use `kubectl logs -n homelab deploy/nextcloud -f` para acompanhar.

## 4. Apontar os domínios para o IP do notebook

Descubra o IP do servidor:

```bash
ip a
```

Em **cada dispositivo cliente** (não no servidor), adicione ao arquivo de hosts:

- Linux/Mac: `/etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts`

```
192.168.1.100 nextcloud.feanor.com.br
192.168.1.100 git.feanor.com.br
192.168.1.100 musica.feanor.com.br
192.168.1.100 portainer.feanor.com.br
```

> Alternativa mais prática se tiver vários dispositivos: configurar essas entradas no seu roteador (DNS local) em vez de editar o hosts file em cada cliente.

## 5. Acessar os serviços

Todos passam pelo Traefik na porta 80 (HTTP):

| Serviço | URL |
|---|---|
| Nextcloud | `http://nextcloud.feanor.com.br` |
| Gitea | `http://git.feanor.com.br` |
| Navidrome | `http://musica.feanor.com.br` |
| Portainer | `http://portainer.feanor.com.br` |

Git via SSH (esse não passa pelo Traefik, vai direto por NodePort):

```bash
git clone ssh://git@SERVER_IP:30022/usuario/repositorio.git
```

## 6. Comandos úteis

```bash
kubectl get all -n homelab              # ver tudo no namespace
kubectl describe pod <nome> -n homelab  # debugar um pod com problema
kubectl logs -n homelab deploy/gitea -f # logs em tempo real
kubectl rollout restart deploy/nextcloud -n homelab  # reiniciar um serviço
kubectl delete -k .                     # remover tudo (os PVCs continuam, a não ser que delete eles também)
```

## 7. Sobre o Traefik

Como o k3s já traz o Traefik pronto, você pode acessar o dashboard dele (útil para ver rotas, certificados, etc):

```bash
kubectl port-forward -n kube-system deploy/traefik 9001:9000
```

Depois acesse `http://localhost:9001/dashboard/` no notebook.

## 8. Backup

Os dados agora vivem em PersistentVolumeClaims, com os arquivos reais em
`/var/lib/rancher/k3s/storage/` no notebook (provisionador `local-path`, padrão do k3s).

Para um home lab, duas opções:

- **Simples**: copiar periodicamente a pasta `/var/lib/rancher/k3s/storage/` inteira para um HD externo.
- **Mais robusto**: instalar o [Velero](https://velero.io/) para fazer snapshot/backup nativo dos volumes do cluster.

## Próximos passos sugeridos

- **HTTPS local**: usar [cert-manager](https://cert-manager.io/) com uma CA própria para gerar certificados confiáveis na rede interna (já que Let's Encrypt exige domínio público).
- **DNS interno**: rodar um Pi-hole ou dnsmasq para resolver `*.feanor.com.br` automaticamente, sem editar hosts file em cada dispositivo.
- **Monitoramento**: adicionar Prometheus + Grafana para acompanhar uso de CPU/memória/disco do cluster.
- **GitOps**: usar ArgoCD ou Flux para versionar essa configuração e aplicar mudanças automaticamente a partir do próprio Gitea que você acabou de criar.
