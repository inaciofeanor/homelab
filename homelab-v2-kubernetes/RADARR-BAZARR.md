# Radarr e Bazarr

O manifesto `75-radarr-bazarr.yaml` instala o Radarr como catálogo da biblioteca existente e o Bazarr para obter legendas. Os dois serviços recebem `/media` com escrita porque o Radarr exige uma pasta raiz gravável mesmo ao importar uma biblioteca existente. Para evitar alterações indesejadas, não configure cliente de download e mantenha a renomeação desativada no Radarr.

## Primeiro acesso

1. Abra `https://radarr.feanor.com.br`, configure autenticação e adicione `/media/filmes` como pasta raiz.
2. Use **Library Import** para importar os filmes existentes como monitorados. Em `Settings > Media Management`, mantenha a renomeação desativada.
3. Copie a API key em `Radarr > Settings > General > Security`.
4. Abra `https://legendas.feanor.com.br` e configure autenticação em `Settings > General`.
5. Em `Bazarr > Settings > Radarr`, use host `radarr`, porta `7878`, sem SSL, e informe a API key. Como os dois serviços usam `/media`, não configure path mapping.
6. Em `Settings > Languages`, adicione **Portuguese (Brazil)** e crie um perfil com esse idioma como cutoff. Aplique-o aos filmes existentes com **Mass Edit**.
7. Em `Settings > Providers`, adicione OpenSubtitles.com e informe a conta diretamente na interface.
8. Em `Settings > Subtitles`, use **Alongside Media File**, mantenha UTF-8 habilitado e ative sincronização automática somente se o consumo adicional de CPU for aceitável.

## Integração opcional com Jellyfin

Gere uma API key no Jellyfin em `Dashboard > API Keys`. Em `Bazarr > Settings > Jellyfin`, use `http://jellyfin:8096`, informe a chave, selecione a biblioteca de filmes e habilite atualização imediata depois dos downloads.

O Bazarr depende do Radarr para catalogar filmes. A integração com Jellyfin apenas solicita a atualização da biblioteca depois que uma legenda é criada. Credenciais do OpenSubtitles e API keys devem permanecer nos PVCs de configuração e nunca devem ser gravadas no Git.
