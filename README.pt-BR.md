# cd-ripper

🇬🇧 [Read in English](README.md)

`rip-cd.sh` é um script Bash que ripa CDs de áudio no Debian/Ubuntu (e derivados), com
barras de progresso, tags automáticas e capa. Ele usa o [abcde](https://abcde.einval.com/)
e o `cdparanoia` e acrescenta o que falta neles: várias fontes de metadados com fallback
automático, ferramentas para consertar álbuns que já foram ripados (tags, capa e nomes de
arquivo) e nomes de arquivo limpos.

## Recursos

- Ripa para **MP3, FLAC, Ogg Vorbis ou Opus** (ou vários de uma vez, ex.: `-t flac,mp3`).
- **Barras de progresso** da ripagem e da conversão.
- **Cadeia de fontes de tags**: MusicBrainz → GnuDB → Retrobridge → CD-Text (lido do
  próprio disco). A primeira fonte que conhecer o disco vence; a ordem é configurável.
- **Conferência de tags depois de cada rip**: avisa se algum arquivo novo ficou sem tag de
  título (os players costumam esconder esses arquivos) e contorna um bug do `abcde` com o
  `eyeD3` 0.9.x, que não gravava tag nenhuma quando a fonte não trazia o gênero.
- **`--retag`**: corrige as tags de um álbum que você já ripou, sem ripar de novo, a partir
  de um link do MusicBrainz ou do Discogs. Embute a capa e move os arquivos para
  `Artista/Álbum/`. Funciona com álbuns de vários discos e divididos em várias pastas.
- **`--embed-cover`**: embute o `cover.jpg` da pasta (ou `folder`, `front`, `albumart`;
  JPEG ou PNG) em todos os arquivos de um álbum. Útil para players de celular, que leem a
  capa das tags. Funciona com MP3, FLAC, Ogg e Opus.
- **`--fix-names`**: tira os `_` dos nomes de arquivo de álbuns já ripados
  (`Smells_Like_Teen_Spirit.mp3` → `Smells Like Teen Spirit.mp3`). Os rips novos já saem
  com espaços.
- Detecta a pasta de músicas que já existe (prefere `~/Músicas` à pasta padrão `~/Música`).
- Se um leitor USB voltar com outro nome (`sr0` → `sr1`), usa o único leitor encontrado.
- `--install-deps` instala tudo no Debian/Ubuntu.

## Requisitos

Debian, Ubuntu ou derivados para o `--install-deps` (o script em si roda em qualquer
Linux que tenha as ferramentas abaixo).

`abcde`, `cdparanoia`, `lame`/`flac`/`vorbis-tools`/`opus-tools` (conforme os formatos que
você usa), `eject`, `eyed3`, `python3` + `python3-mutagen` (para `--retag`, `--embed-cover`,
`--fix-names` e a conferência de tags) e, opcionalmente, `icedax` (só para a fonte CD-Text).

```bash
./rip-cd.sh --install-deps      # pede confirmação; somente Debian/Ubuntu
```

## Uso

```bash
chmod +x rip-cd.sh              # desnecessário se você clonou o repositório

./rip-cd.sh                                  # ripa com os padrões
./rip-cd.sh -d /dev/sr1 -o ~/Músicas -t flac # outro leitor, destino e formato
./rip-cd.sh -m gnudb                         # força uma fonte de tags
./rip-cd.sh -i                               # escolher entre vários resultados
```

Os arquivos vão para `<pasta de músicas>/CDs-Ripados/Artista/Álbum/01 - Título.ext`,
a menos que você use `-o`.

### Corrigir as tags de um álbum já ripado

```bash
# Veja primeiro com --dry-run; depois tire a opção para aplicar
./rip-cd.sh --retag ~/Músicas/CDs-Ripados/Unknown\ Artist/Unknown\ Album \
            --release https://musicbrainz.org/release-group/<id> --dry-run
```

`--release` aceita um release ou release group do MusicBrainz, ou um release ou master do
Discogs. Com um grupo/master, o script escolhe a edição pelo número de faixas e pelas
durações. No Discogs, use `export DISCOGS_TOKEN=...` (token pessoal) para baixar a capa e
ter um limite de requisições maior. Use `--disc N` em lançamentos com vários discos e
`--force` se as durações não baterem (±4 s).

### Embutir a capa

```bash
./rip-cd.sh --embed-cover ~/Músicas/Metallica --dry-run   # só mostra
./rip-cd.sh --embed-cover ~/Músicas/Metallica/Load        # um álbum
```

Aceita a pasta de um álbum ou a de um artista (ele acha os álbuns dentro). Procura
`cover`, `folder`, `front`, `albumart` ou `album` (`.jpg`, `.jpeg` ou `.png`) na pasta de
cada álbum. Arquivos que já têm capa embutida são pulados; use `--force` para trocá-la.
Cada arquivo cresce o tamanho da imagem, então prefira capas de algumas centenas de KB.

### Tirar os underscores dos nomes

```bash
./rip-cd.sh --fix-names ~/Músicas/Nirvana --dry-run
./rip-cd.sh --fix-names ~/Músicas/Nirvana
```

Aceita a pasta de um álbum ou a de um artista. Usa a grafia da tag do título quando ela
confere com o nome do arquivo, então pontuação e apóstrofos voltam. Só arquivos de áudio
são renomeados.

`--retag`, `--embed-cover` e `--fix-names` são exclusivos: use um por execução. Os três
aceitam `--dry-run` e `--yes`.

## Opções

| Opção | O que faz |
|---|---|
| `-d, --device DEV` | Leitor de CD (padrão `/dev/sr0`; se não existir e houver só um leitor, usa esse) |
| `-o, --output DIR` | Pasta de destino |
| `-t, --type FORMATOS` | `mp3`, `flac`, `ogg`, `opus`; separados por vírgula para vários |
| `-m, --metadata FONTE` | `auto`, `musicbrainz`, `gnudb`, `retrobridge` ou `cdtext` |
| `-i, --interactive` | Escolher entre vários resultados (desliga as barras) |
| `--no-progress` | Saída crua do `abcde` |
| `--retag DIR` + `--release LINK` | Corrige tags e capa de um álbum ripado (repita `--retag` se estiver dividido) |
| `--disc N`, `--no-move`, `--no-cover` | Retag: número do disco, não mover arquivos, não baixar a capa |
| `--embed-cover DIR` | Embute a imagem de capa da pasta nos arquivos |
| `--fix-names DIR` | Troca `_` por espaço nos nomes dos arquivos de música |
| `--dry-run`, `--yes`, `--force` | Só mostrar; não pedir confirmação; aplicar mesmo com divergência / trocar capa existente |
| `--install-deps` | Instala as dependências (somente Debian/Ubuntu) |
| `-V, --version`, `--changelog`, `-h` | Versão, histórico, ajuda |

## Configuração

Tudo tem um padrão no topo do script e pode ser trocado por variáveis de ambiente:
`CD_DEVICE`, `DEST_DIR`, `OUTPUT_TYPE`, `LAME_QUALITY`, `EJECT_CD`, `METADATA_ORDER`
(ex.: `"musicbrainz cdtext"`), `GNUDB_URL`, `RETROBRIDGE_URL`.

## Dicas

- **Celular (Android):** copie as pastas dos álbuns para `Music/` no aparelho (cabo USB ou
  Syncthing). Rode o `--embed-cover` antes: players como o Musicolet usam a capa embutida
  nas tags, não o arquivo `cover.jpg`.
- **Músicas que não aparecem no Elisa, no Strawberry ou em outro player:** os players montam
  a biblioteca pelas tags. Confira com `mutagen-inspect arquivo.mp3`; se não houver tag, use
  o `--retag`.
- **Pasta `abcde.XXXXXXXX` sobrando no destino:** resto de um rip interrompido (arquivos
  WAV). Apague se nenhum rip estiver em andamento.

## Limitações

- As consultas ao GnuDB, ao Retrobridge e ao Discogs, e a detecção de "não encontrado" do
  CD-Text, foram desenvolvidas com respostas simuladas, nem todas contra os serviços reais.
  Se alguma fonte se comportar mal, o log da consulta fica em
  `~/.cache/rip-cd/ultimo-rip-consulta.log`.
- Discos arranhados podem demorar; o `cdparanoia` roda com `--never-skip=40`.
- O script não baixa capa durante o rip; o `--retag` baixa. Nos rips, coloque um `cover.jpg`
  na pasta do álbum e rode o `--embed-cover`.
- Confira se a legislação do seu país permite copiar os CDs que você ripa.

## Licença

[GPL-3.0](LICENSE)
