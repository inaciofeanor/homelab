param([string]$Root = 'D:\Google Drive\Videos\Filmes')
$ErrorActionPreference = 'Stop'
$moved = 0

function Move-Remaining([string]$RelativeSource, [string]$Title, [int]$Year, [string]$Edition = '') {
    $source = Join-Path $Root $RelativeSource
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
    $safeTitle = $Title -replace '[:\\/*?"<>|]', ' -'
    $canonical = "$safeTitle ($Year)"
    $folder = Join-Path $Root $canonical
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $suffix = if ($Edition) { " - $Edition" } else { '' }
    $destination = Join-Path $folder "$canonical$suffix$([IO.Path]::GetExtension($source))"
    if (Test-Path -LiteralPath $destination) {
        $n = 2
        do { $destination = Join-Path $folder "$canonical$suffix - version $n$([IO.Path]::GetExtension($source))"; $n++ } while (Test-Path -LiteralPath $destination)
    }
    Move-Item -LiteralPath $source -Destination $destination
    $script:moved++
}

$items = @(
@('Ghibli\As Memórias de Marnie (2016).mp4','When Marnie Was There',2014,'Portuguese title'),
@('Ghibli\Laputa O Castelo no Céu (1986).mp4','Castle in the Sky',1986,''),
@('Ghibli\Lupin III O Ouro da Babilônia - Dublado (1985).mkv','Lupin the Third - Legend of the Gold of Babylon',1985,'Dubbed'),
@('Ghibli\O Serviço de Entregas da Kiki (1989).mp4','Kiki''s Delivery Service',1989,''),
@('Ghibli\Sussurros do Coração (1995).mkv','Whisper of the Heart',1995,''),
@('O Senhor dos Anéis\The Lord of the Rings The Fellowship of the Ring - Special Extended Edition Scenes 2002.mkv','The Lord of the Rings - The Fellowship of the Ring',2001,'Extended Edition'),
@('O Senhor dos Anéis\The Lord of the Rings The Two Towers - Special Extended Edition Scenes 2003.mkv','The Lord of the Rings - The Two Towers',2002,'Extended Edition'),
@('O Senhor dos Anéis\he Lord of the Rings The Return of the King - Special Extended Edition Scenes 2004.mkv','The Lord of the Rings - The Return of the King',2003,'Extended Edition'),
@('Pokemon\Mewtwo Vs. Mew.rmvb','Pokémon - The First Movie',1998,'RMVB'),
@('Pokemon\Pokemon.The.First.Movie.1999.DVDRip.XviD-Pokemon.avi','Pokémon - The First Movie',1998,'DVDRip'),
@('Pokemon\O Filme 2000 - O Poder De Um.rmvb','Pokémon the Movie 2000 - The Power of One',1999,''),
@('Pokemon\O Feitiço dos Unown.rmvb','Pokémon 3 - The Movie',2000,''),
@('Pokemon\Viajantes do Tempo.rmvb','Pokémon 4Ever',2001,''),
@('Pokemon\Heróis Pokémon.rmvb','Pokémon Heroes',2002,''),
@('Pokemon\Jirachi - O Realizador de Desejos.rmvb','Pokémon - Jirachi, Wish Maker',2003,''),
@('Pokemon\Alma Gemea.rmvb','Pokémon - Destiny Deoxys',2004,''),
@('Pokemon\Lucario e o Misterio de Mew.rmvb','Pokémon - Lucario and the Mystery of Mew',2005,''),
@('Pokemon\Pokémon Ranger e o Lendário Templo Do Mar.rmvb','Pokémon Ranger and the Temple of the Sea',2006,''),
@('Pokemon\Giratina e o Cavaleiro do Céu - Pokémon Darkay byiKyoo.rmvb','Pokémon - Giratina and the Sky Warrior',2008,''),
@('Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.I.The.Phantom.Menace.1999.1080p.HDTV.x264-hV\Star.Wars.Episode.I.The.Phantom.Menace.1999 (1).1080p.HDTV.x264-hV.mkv','Star Wars - Episode I - The Phantom Menace',1999,''),
@('Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.III.Revenge.Of.The.Sith.2005.1080p.HDTV.x264-hV\Star.Wars.Episode.III.Revenge.Of.The.Sith.2005 (1).1080p.HDTV.x264-hV.mkv','Star Wars - Episode III - Revenge of the Sith',2005,''),
@('Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.IV.A.New.Hope.1977.1080p.HDTV.x264-hV\Star.Wars.Episode.IV.A.New.Hope.1977 (1).1080p.HDTV.x264-hV.mkv','Star Wars - Episode IV - A New Hope',1977,''),
@('Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.V.The.Empire.Strikes.Back.1980.1080p.HDTV.x264-hV\Star.Wars.Episode.V.The.Empire.Strikes.Back.1980 (1).1080p.HDTV.x264-hV.mkv','Star Wars - Episode V - The Empire Strikes Back',1980,''),
@('Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.VI.Return.Of.The.Jedi.1983.1080p.HDTV.x264-hV\Star.Wars.Episode.VI.Return.Of.The.Jedi.1983 (1).1080p.HDTV.x264-hV.mkv','Star Wars - Episode VI - Return of the Jedi',1983,''),
@('The.Lion.King.Trilogy.BluRay.720p.x264-WiKi.DUAL-DAViDSK8\The.Lion.King.1994.720p.BluRay.x264.DTS-WiKi.DUAL-DAViDSK8\The.Lion.King.1994.720p.BluRay (1).x264.DTS-WiKi.DUAL-DAViDSK8.mkv','The Lion King',1994,''),
@('The.Lion.King.Trilogy.BluRay.720p.x264-WiKi.DUAL-DAViDSK8\The.Lion.King.2.Simba''s.Pride.1998.720p.BluRay.x264.DTS-WiKi.DUAL-DAViDSK8\The.Lion.King.2.Simba''s.Pride.1998.720p.BluRay.x264.DTS-WiKi.DUAL-DAViDSK8.mkv','The Lion King II - Simba''s Pride',1998,''),
@('The.Lion.King.Trilogy.BluRay.720p.x264-WiKi.DUAL-DAViDSK8\The.Lion.King.3.2004.720p.BluRay.x264.DTS-WiKi.DUAL-DAViDSK8\The.Lion.King.3.2004.720p.BluRay (1).x264.DTS-WiKi.DUAL-DAViDSK8.mkv','The Lion King 1½',2004,'')
)
foreach ($item in $items) { Move-Remaining @item }

$review = Join-Path $Root '_Arquivos para revisar (ignorar no Jellyfin)'
New-Item -ItemType Directory -Path $review -Force | Out-Null
$reviewItems = @(
'Split.2016.1080p.BluRay.H264.AAC-RARBG\RARBG.mp4',
'The.Kingdom.of.Dreams.and.Madness.2013.720p.BluRay.x264-WiKi\Sample\The.Kingdom.of.Dreams.and.Madness.2013.720p.BluRay.x264-WiKi.sample.mkv',
'Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.II.Attack.Of.The.Clones.2002.1080p.HDTV.x264-hV\Star.Wars.Episode.II.Attack.Of.The.Clones.2002.1080p.HDTV.x264-hV.mkv',
'Star.Wars.Episodes.Complete.1080p.HDTV.x264-hV\Star.Wars.Episode.IV.A.New.Hope.1977.1080p.HDTV.x264-hV\Star.Wars.Episode.IV.A.New.Hope.1977.1080p.HDTV.x264-hV.mkv'
)
foreach ($relative in $reviewItems) {
    $source = Join-Path $Root $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $name = ($relative -replace '[\\/:*?"<>|]', '_')
        Move-Item -LiteralPath $source -Destination (Join-Path $review $name)
    }
}
Set-Content -LiteralPath (Join-Path $review '.ignore') -Value 'Arquivos incompletos, propaganda e samples preservados para revisão.' -Encoding UTF8
"Moved $moved valid movies. Review files preserved at $review"
