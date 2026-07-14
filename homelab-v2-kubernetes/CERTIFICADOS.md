# Certificados HTTPS — Let's Encrypt via cert-manager + Cloudflare

## Por que migrar o DNS pro Cloudflare

O UOL Host não tem integração (nativa ou de comunidade) com o cert-manager para
o desafio DNS-01. Os provedores com suporte direto são outros (Cloudflare, Route53,
Google CloudDNS, Hetzner, OVH, DigitalOcean, etc).

**O que muda:** só a parte de **DNS** do `feanor.com.br` passa a ser gerenciada pelo
Cloudflare (gratuito). O registro do domínio continua onde está — não é necessário
trocar de registrador, só de "onde fica o DNS".

> **Alternativa sem migrar o DNS**: existe um truque de delegação via `CNAME` que
> aponta só o registro `_acme-challenge.feanor.com.br` para uma zona no Cloudflare,
> sem migrar o resto do DNS. É mais complexo de configurar — me avisa se preferir
> esse caminho.

## 1. Migrar o DNS para o Cloudflare

1. Crie uma conta gratuita em [cloudflare.com](https://cloudflare.com)
2. **Add a Site** → digite `feanor.com.br` → escolha o plano **Free**
3. O Cloudflare vai importar os registros DNS existentes automaticamente — **confira
   se todos os registros (A, MX, CNAME, TXT) foram importados corretamente** antes
   de prosseguir, principalmente os de e-mail (MX/SPF/DKIM) se você usa e-mail
   `@feanor.com.br`
4. O Cloudflare vai te dar 2 nameservers (algo como `xxx.ns.cloudflare.com`)
5. No painel do UOL Host, troque os nameservers do domínio para os do Cloudflare
6. Aguarde a propagação (pode levar de minutos a algumas horas)

Confirme que propagou:
```bash
dig feanor.com.br NS +short
```
Deve mostrar os nameservers do Cloudflare.

## 2. Instalar o cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Verificar:
```bash
kubectl get pods -n cert-manager
```
(devem aparecer 3 pods: `cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook`, todos `Running`)

## 3. Criar um token de API no Cloudflare

1. No painel do Cloudflare: **Meu Perfil → API Tokens → Create Token**
2. Use o template **Edit zone DNS**
3. Em **Zone Resources**, restrinja para **Specific zone → feanor.com.br** (não dê acesso a todas as zonas)
4. Crie e copie o token (só aparece uma vez)

## 4. Criar o Secret com o token no cluster

```bash
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token=COLE_SEU_TOKEN_AQUI
```

## 5. Ajustar e aplicar o `05-certificates.yaml`

Edite o arquivo e troque `seu-email@exemplo.com` pelo seu e-mail real (usado pelo Let's Encrypt para avisos importantes, não para renovação — isso é automático).

```bash
kubectl apply -k .
```

## 6. Testar primeiro com o ambiente de staging (recomendado)

O Let's Encrypt tem limite de **5 certificados duplicados por semana** no ambiente de produção. Para não gastar essa cota testando configuração, teste primeiro com o `letsencrypt-staging`:

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: teste-staging
  namespace: homelab
spec:
  secretName: teste-staging-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - teste.feanor.com.br
EOF

kubectl describe certificate teste-staging -n homelab
```

Se aparecer `Ready: True` no final, está tudo certo — pode seguir com o `letsencrypt-prod` (que já está configurado em todos os Ingress). Depois, pode remover o certificado de teste:
```bash
kubectl delete certificate teste-staging -n homelab
kubectl delete secret teste-staging-tls -n homelab
```

## 7. Acompanhar a emissão dos certificados reais

```bash
kubectl get certificates -A
kubectl describe certificate feanor-wildcard -n homelab
```

O processo: cert-manager cria um registro TXT temporário no Cloudflare → aguarda propagação (1-3 min) → Let's Encrypt verifica → certificado é emitido e salvo no Secret `feanor-wildcard-tls`. Leva de 1 a 5 minutos por namespace.

## Comandos úteis de diagnóstico

```bash
kubectl get clusterissuer                          # status dos issuers
kubectl get challenges -A                           # desafios em andamento
kubectl describe challenge <nome> -n <namespace>    # detalhes de um desafio
kubectl logs -n cert-manager deploy/cert-manager -f # logs do controller
```

## Renovação

É automática — o cert-manager renova sozinho ~30 dias antes do vencimento (certificados do Let's Encrypt duram 90 dias). Não precisa fazer nada.

## Próximo passo opcional

Com a stack de monitoramento já no ar, dá pra criar um alerta no Alertmanager pra te avisar se algum certificado estiver perto de vencer sem renovar (caso de falha silenciosa na renovação) — me avisa se quiser que eu monte essa regra.
