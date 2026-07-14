# Gestão de secrets

Os manifests publicados contêm somente `SealedSecret`. Os valores reais ficam no
cluster e na cópia local de recuperação criada por `rotate-secrets.sh`; nenhum dos
dois locais deve ser versionado no Git.

## Rotação inicial

Execute `./rotate-secrets.sh` como o usuário que usa o `kubectl`. O script troca as
credenciais dos bancos e do administrador do Nextcloud de forma coordenada, aplica
os novos `Secret` no cluster e reinicia os serviços afetados. A cópia de recuperação
é criada em `~/.local/state/homelab/credentials.env` com permissão `0600`.

Importe os valores em um gerenciador de senhas e remova a cópia local quando não for
mais necessária. Nunca envie esse arquivo para Git, backup sem criptografia ou chat.

## Chave do controller

A chave privada do Sealed Secrets permite restaurar os manifests criptografados em
outro cluster. Faça backup dela fora do Git e em armazenamento criptografado:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master.key
chmod 600 sealed-secrets-master.key
```

Na restauração, aplique a chave **antes** de iniciar o controller Sealed Secrets.

