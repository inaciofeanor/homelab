# Stack de Monitoramento — Prometheus + Grafana + Alertmanager

Usa o Helm chart oficial **kube-prometheus-stack**, que empacota:
- Prometheus Operator + Prometheus (coleta e armazena métricas)
- Alertmanager (dispara alertas)
- Grafana (dashboards visuais)
- node-exporter (métricas de CPU/RAM/disco do notebook)
- kube-state-metrics (métricas dos objetos do Kubernetes: pods, deployments, etc)

Tudo já com dashboards prontos no Grafana — não precisa configurar do zero.

## 1. Instalar o Helm (se ainda não tiver)

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

## 2. Adicionar o repositório do chart

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

## 3. Ajustar o `monitoring-values.yaml`

Antes de instalar, edite o arquivo e troque:
- `grafana.adminPassword` — senha do usuário admin do Grafana
- `prometheus.prometheusSpec.storageSpec` (`storage: 10Gi`) — ajuste conforme o espaço livre no disco do notebook

## 4. Instalar

```bash
kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring-values.yaml
```

Acompanhar o status:

```bash
kubectl get pods -n monitoring -w
```

Pode levar 1-2 minutos para todos os pods ficarem `Running` (Prometheus Operator precisa instalar os CRDs primeiro, depois os outros componentes sobem).

## 5. Apontar os domínios para o IP do notebook

Adicione ao `/etc/hosts` dos clientes (mesma lista dos outros serviços):

```
192.168.1.100 grafana.homelab.local
192.168.1.100 prometheus.homelab.local
192.168.1.100 alertmanager.homelab.local
```

## 6. Acessar

| Serviço | URL | Login |
|---|---|---|
| Grafana | `http://grafana.homelab.local` | usuário `admin`, senha definida no `values.yaml` |
| Prometheus | `http://prometheus.homelab.local` | sem login |
| Alertmanager | `http://alertmanager.homelab.local` | sem login |

No Grafana, vá em **Dashboards** no menu lateral — já vêm prontos vários painéis úteis, por exemplo:
- **Kubernetes / Compute Resources / Cluster** — visão geral de CPU/RAM de tudo
- **Node Exporter / Nodes** — saúde do notebook (CPU, RAM, disco, rede)
- **Kubernetes / Compute Resources / Namespace (Pods)** — uso por namespace (dá pra ver `homelab`, `portainer`, etc separadamente)

## Comandos úteis

```bash
helm status kube-prometheus-stack -n monitoring     # status da instalação
kubectl get pods -n monitoring                      # ver todos os pods

# Atualizar configuração depois de editar o values.yaml
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring-values.yaml

# Remover tudo
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring
```

## Próximos passos sugeridos

- **Alertas no Telegram/Discord/e-mail**: configurar `alertmanager.config.receivers` no `values.yaml` para ser avisado quando algo cair (ex: disco do notebook ficando cheio, pod reiniciando em loop).
- **Dashboard customizado**: criar um painel no Grafana só com os serviços do seu homelab (Nextcloud, Gitea, Navidrome, Kavita) lado a lado.
- **Uptime Kuma**: complementar com um monitor simples de "está no ar ou não" para cada URL (`nextcloud.homelab.local`, etc), mais leve e visual que o Alertmanager para esse tipo de checagem.
