# Home Lab com Docker — Nextcloud + Gitea + Navidrome + Portainer

Stack pronta para subir 4 serviços de uma vez no seu Ubuntu Server.

## Pré-requisitos

```bash
sudo apt update
sudo apt install docker.io docker-compose-v2 -y
sudo usermod -aG docker $USER
```

Depois do `usermod`, **faça logout e login de novo** (ou reinicie) para o grupo `docker` ter efeito.

## Passo a passo

1. Copie os arquivos `docker-compose.yml` e `.env.example` para uma pasta no servidor, por exemplo:
   ```bash
   mkdir -p ~/homelab
   # copie os dois arquivos para dentro de ~/homelab
   ```

2. Renomeie o arquivo de variáveis e edite os valores:
   ```bash
   cd ~/homelab
   mv .env.example .env
   nano .env
   ```
   Troque todas as senhas `changeme_*`, ajuste `SERVER_IP` (veja com `ip a`) e `MUSIC_PATH` (pasta onde estão seus arquivos de música no notebook).

3. Suba tudo:
   ```bash
   docker compose up -d
   ```

4. Acompanhe os logs se quiser ver o progresso (principalmente do Nextcloud, que demora um pouco no primeiro start):
   ```bash
   docker compose logs -f
   ```

## Como acessar cada serviço

Substitua `SERVER_IP` pelo IP do seu notebook na rede local.

| Serviço | URL | Observação |
|---|---|---|
| Portainer | `http://SERVER_IP:9000` | Cria usuário admin no primeiro acesso |
| Nextcloud | `http://SERVER_IP:8080` | Login com o usuário/senha definidos no `.env` |
| Gitea | `http://SERVER_IP:3000` | Configuração inicial pela web na primeira vez |
| Navidrome | `http://SERVER_IP:4533` | Cria usuário admin no primeiro acesso |

Clone de repositórios Git via SSH: `git clone ssh://git@SERVER_IP:2222/usuario/repositorio.git`

## Liberar as portas no firewall (se o UFW estiver ativo)

```bash
sudo ufw allow 9000/tcp    # Portainer
sudo ufw allow 8080/tcp    # Nextcloud
sudo ufw allow 3000/tcp    # Gitea
sudo ufw allow 2222/tcp    # Gitea SSH
sudo ufw allow 4533/tcp    # Navidrome
sudo ufw reload
```

## Comandos úteis

```bash
docker compose ps                  # ver status dos containers
docker compose logs -f nextcloud   # ver logs de um serviço específico
docker compose stop                # parar tudo sem remover
docker compose down                # remover containers (os dados continuam nos volumes)
docker compose pull && docker compose up -d   # atualizar todas as imagens
```

## Backup

Os dados ficam em **volumes Docker nomeados** (não se perdem ao recriar containers). Para fazer backup de tudo:

```bash
docker run --rm -v nextcloud_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/nextcloud_backup.tar.gz -C /data .
```

Repita o mesmo comando trocando `nextcloud_data` pelos outros volumes (`gitea_data`, `navidrome_data`, `nextcloud_db_data`). O ideal é agendar isso com um `cron` e copiar os `.tar.gz` para um disco externo.

## Próximos passos sugeridos

- **Reverse proxy (Traefik ou Nginx Proxy Manager)**: para acessar tudo por nomes (`nextcloud.local`, `git.local`) em vez de portas, e adicionar HTTPS.
- **DNS local / mDNS**: para não depender de lembrar o IP do notebook.
- **Watchtower**: container que atualiza as imagens automaticamente.
- **Acesso externo**: Tailscale ou WireGuard para acessar o home lab fora de casa com segurança (evite expor portas direto na internet).
