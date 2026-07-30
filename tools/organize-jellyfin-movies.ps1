param([string]$Root = 'D:\Google Drive\Videos\Filmes')
$ErrorActionPreference = 'Stop'
$videoExt = @('.mkv','.mp4','.avi','.rmvb','.m4v','.mov','.wmv')
$log = [System.Collections.Generic.List[string]]::new()

function Move-Movie([string]$Source, [string]$Title, [int]$Year, [string]$Edition = '') {
    $src = Join-Path $Root $Source
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
    $canonical = "$Title ($Year)"
    $destDir = Join-Path $Root $canonical
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $ext = [IO.Path]::GetExtension($src)
    $suffix = if ($Edition) { " - $Edition" } else { '' }
    $dest = Join-Path $destDir "$canonical$suffix$ext"
    if (Test-Path -LiteralPath $dest) {
        $n = 2
        do { $dest = Join-Path $destDir "$canonical$suffix - version $n$ext"; $n++ } while (Test-Path -LiteralPath $dest)
    }
    Move-Item -LiteralPath $src -Destination $dest
    $log.Add("MOVE - $Source -> $($dest.Substring($Root.Length + 1))")

    $parent = Split-Path -Parent $src
    $remainingVideos = @(Get-ChildItem -LiteralPath $parent -File -ErrorAction SilentlyContinue | Where-Object Extension -in $videoExt)
    if ($remainingVideos.Count -eq 0) {
        $sidecars = @(Get-ChildItem -LiteralPath $parent -File -ErrorAction SilentlyContinue | Where-Object Extension -in '.srt','.ass','.ssa','.sub','.idx')
        $i = 0
        foreach ($sidecar in $sidecars) {
            $i++
            $tag = if ($sidecars.Count -eq 1) { '' } else { ".subtitle$i" }
            $sideDest = Join-Path $destDir "$canonical$suffix$tag$($sidecar.Extension.ToLowerInvariant())"
            if (-not (Test-Path -LiteralPath $sideDest)) { Move-Item -LiteralPath $sidecar.FullName -Destination $sideDest }
        }
    }
}

$movies = @(
@('Dragonheart.[1996].DVDRip.XviD-BLiTZKRiEG.avi','Dragonheart',1996,''),
@('The Battle at Lake Changjin.comunaflix.mkv','The Battle at Lake Changjin',2021,''),
@('Constantine (2005) - [1080p] 5.1 S4 FILMES\Constantine.2005.1080p.5.1.BluRay.x264.S4FILMES.mp4','Constantine',2005,''),
@('Constantine City Of Demons (2018) [1080p] [BluRay] [5.1] [YTS.MX]\Constantine.City.Of.Demons.2018.1080p.BluRay.x264.AAC5.1-[YTS.MX].mp4','Constantine - City of Demons',2018,''),
@('Justice League Dark (2017) [1080p] [YTS.AG]\Justice.League.Dark.2017.1080p.BluRay.x264-[YTS.AG].mp4','Justice League Dark',2017,''),
@('Logan.2017.1080p.BluRay.x264-BLOW[rarbg]\blow-logan.2017 (1).1080p.bluray.x264.mkv','Logan',2017,''),
@('Song.of.the.Sea.2014.LIMITED.1080p.BluRay.X264-AMIABLE[rarbg]\song.of.the.sea.2014.limited (1).1080p.bluray.x264-amiable.mkv','Song of the Sea',2014,''),
@('Spirited Away [Anime][DvDRip][www.zonatorrent.com]\Spirited Away [Anime][DvDRip][www.zonatorrent.com].avi','Spirited Away',2001,'DVDRip'),
@('Split.2016.1080p.BluRay.H264.AAC-RARBG\Split.2016.1080p.BluRay.H264.AAC-RARBG.mp4','Split',2016,''),
@('The.Foreigner.2017.1080p.BluRay.x264-DRONES[rarbg]\The.Foreigner.2017.1080p.BluRay.x264-DRONES.mkv','The Foreigner',2017,''),
@('The.Kingdom.of.Dreams.and.Madness.2013.720p.BluRay.x264-WiKi\The.Kingdom.of.Dreams.and.Madness.2013.720p.BluRay.x264-WiKi.mkv','The Kingdom of Dreams and Madness',2013,''),
@('When.Marnie.Was.There.2014.720p.BluRay.x264-RedBlade[rarbg]\when.marnie.was.there.2014 (1).720p.bluray.x264-redblade.mkv','When Marnie Was There',2014,'720p'),
@('When.Marnie.Was.There.2014.720p.BluRay.x264-RedBlade[rarbg]\when.marnie.was.there.2014.720p.bluray.x264-redblade.mkv','When Marnie Was There',2014,'720p duplicate'),
@('Grave.of.the.fireflies.DVDRip.XviD-flourIsh\Grave.of.the.fireflies.DVDRip.XviD-flourIsh.avi','Grave of the Fireflies',1988,'DVDRip'),
@('Tales of Eartsea\Meikai-Animes_Gedo_Senki-Tales_from_Earthsea.mp4','Tales from Earthsea',2006,''),
@('Hellboy.Animated[Sword.Of.Storms][Blood.&.Iron]DvDrip-aXXo\Hellboy.Animated-Sword.Of.Storms[2006]DvDrip-aXXo.avi','Hellboy Animated - Sword of Storms',2006,''),
@('Hellboy.Animated[Sword.Of.Storms][Blood.&.Iron]DvDrip-aXXo\Hellboy.Animated-Blood.&.Iron[2007]DvDrip-aXXo.avi','Hellboy Animated - Blood and Iron',2007,'')
)
foreach ($m in $movies) { Move-Movie @m }

$ghibli = @{
'A Viagem de Chihiro (2001).mp4'=@('Spirited Away',2001); 'As Memórias de Marnie (2016).mp4'=@('When Marnie Was There',2014)
'Da Colina Kokuriko (2011).mp4'=@('From Up on Poppy Hill',2011); 'Eu Posso Ouvir o Oceano (1993).mp4'=@('Ocean Waves',1993)
'Grave Of The Fireflies.mp4'=@('Grave of the Fireflies',1988); 'Laputa O Castelo no Céu (1986).mp4'=@('Castle in the Sky',1986)
'Lupin III - E O Segredo de Mamo (1978).mkv'=@('Lupin the Third - The Mystery of Mamo',1978); 'Lupin III - O Castelo De Cagliostro (1979).mkv'=@('Lupin the Third - The Castle of Cagliostro',1979)
'Lupin III O Ouro da Babilônia - Dublado (1985).mkv'=@('Lupin the Third - Legend of the Gold of Babylon',1985); 'Mary e a Flor da Feiticeira (2017).mkv'=@('Mary and the Witch''s Flower',2017)
'Meu Amigo Totoro (1988).avi'=@('My Neighbor Totoro',1988); 'Nausicaa - A Princesa do Vale dos Ventos.mp4'=@('Nausicaä of the Valley of the Wind',1984)
'O Castelo Animado (2004).avi'=@('Howl''s Moving Castle',2004); 'O Conto da Princesa Kaguya (2015).mkv'=@('The Tale of the Princess Kaguya',2013)
'o mundo dos pequeninos (2010).mkv'=@('The Secret World of Arrietty',2010); 'O Reino dos Gatos (2002).mkv'=@('The Cat Returns',2002)
'O Serviço de Entregas da Kiki (1989).mp4'=@('Kiki''s Delivery Service',1989); 'Pom Poko - A Grande Batalha dos Guaxinins (1996).mkv'=@('Pom Poko',1994)
'ponyo-dublado.avi'=@('Ponyo',2008); 'Porco Rosso - O Porquinho Aviador (1992) Dublado.avi'=@('Porco Rosso',1992)
'Princesa Mononoke [1997].mkv'=@('Princess Mononoke',1997); 'Sussurros do Coração (1995).mkv'=@('Whisper of the Heart',1995)
'Tales from Earthsea (2006).mp4'=@('Tales from Earthsea',2006); 'Vidas ao Vento (2013).mp4'=@('The Wind Rises',2013)
}
foreach ($name in $ghibli.Keys) { $v=$ghibli[$name]; Move-Movie "Ghibli\$name" $v[0] $v[1] }

$dcRoot = Join-Path $Root 'DC.Comics.Animated.Original.Movies.Collection.720p.BluRay.Dual.Audio'
if (Test-Path -LiteralPath $dcRoot) {
    Get-ChildItem -LiteralPath $dcRoot -Directory -Recurse | ForEach-Object {
        if ($_.Name -match '^\d+\. \[(\d{4})\] (.+)$') {
            $year=[int]$Matches[1]; $title=($Matches[2] -replace '  +',' ').Trim()
            $vid=@(Get-ChildItem -LiteralPath $_.FullName -File | Where-Object Extension -in $videoExt)
            if ($vid.Count -eq 1) { Move-Movie $vid[0].FullName.Substring($Root.Length+1) $title $year }
        }
    }
}

$series = @(
@('O Senhor dos Anéis\2001.The.Lord.Of.The.Rings-.The.Fellowship.Of.The.Ring.[Extended.Cut].1920x800.BDRip.x264.DTS-HD.MA.mkv','The Lord of the Rings - The Fellowship of the Ring',2001,'Extended Edition'),
@('O Senhor dos Anéis\2002.The.Lord.Of.The.Rings-.The.Two.Towers.[Extended.Cut].1920x804.BDRip.x264.DTS-HD.MA (1).mkv','The Lord of the Rings - The Two Towers',2002,'Extended Edition'),
@('O Senhor dos Anéis\2003.The.Lord.Of.The.Rings-.The.Return.Of.The.King.[Extended.Cut].1920x796.BDRip.x264.DTS-HD.MA.mkv','The Lord of the Rings - The Return of the King',2003,'Extended Edition'),
@('The Hobbit\2012.The.Hobbit-.An.Unexpected.Journey.[Extended.Cut].1920x800.BDRip.x264.DTS-HD.MA.mkv','The Hobbit - An Unexpected Journey',2012,'Extended Edition'),
@('The Hobbit\2013.The.Hobbit-.The.Desolation.Of.Smaug.[Extended.Cut].1920x800.BDRip.x264.DTS-HD.MA.mkv','The Hobbit - The Desolation of Smaug',2013,'Extended Edition'),
@('The Hobbit\2014.The.Hobbit-.The.Battle.Of.The.Five.Armies.[Extended.Cut].1920x800.BDRip.x264.DTS-HD.MA.mkv','The Hobbit - The Battle of the Five Armies',2014,'Extended Edition')
)
foreach($m in $series){ Move-Movie @m }

$logPath = Join-Path $Root '_jellyfin_organization_log.txt'
$log | Set-Content -LiteralPath $logPath -Encoding UTF8
"Organized $($log.Count) video files. Log - $logPath"
