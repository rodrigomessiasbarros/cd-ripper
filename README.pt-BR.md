# cd-ripper

🇬🇧 [Read in English](README.md)

`rip-cd.sh` é um script Bash que ripa CDs de áudio no Debian/Ubuntu (e derivados), com
barras de progresso, tags automáticas e capa embutida. Ele usa o
[abcde](https://abcde.einval.com/) e o `cdparanoia` e acrescenta o que falta neles: várias
fontes de metadados com fallback automático, um modo para corrigir álbuns que já foram
ripados e nomes de arquivo limpos.

## Recursos

- Ripa para **MP3, FLAC, Ogg Vorbis ou Opus** (ou vários de uma vez, ex.: `-t flac,mp3`).
- **Barras de progresso** da ripagem e da conversão.
- **Cadeia de fontes de tags**: MusicBrainz → GnuDB → Retrobridge → CD-Text (lido do
  próprio disco). A primeira fonte que conhecer o disco vence; a ordem é configurável.
- **`--retag`**: corrige as tags de um álbum que você já ripou, sem ripar de novo, a partir
  de um link do MusicBrainz ou do Discogs. Embute a capa e move os arquivos para
  `Artista/Álbum/`. Funciona com álbuns de vários discos e divididos em várias pastas.
- **`--fix-names`**: tira os `_` dos nomes de arquivo de álbuns já ripados
  (`Smells_Like_Teen_Spirit.mp3` → `Smells Like Teen Spirit.mp3`).
- Detecta a pasta de músicas que já existe (prefere `~/Músicas` à pasta padrão `~/Música`).
- Se um leitor USB voltar com outro nome (`sr0` → `sr1`), usa o único leitor encontrado.
- `--install-deps` instala tudo no Debian/Ubuntu.

## Requisitos

Debian, Ubuntu ou derivados para o `--install-deps` (o script em si roda em qualquer
Linux que tenha as ferramentas abaixo).

`abcde`, `cdparanoia`, `lame`/`flac`/`vorbis-tools`/`opus-tools` (conforme os formatos que
você usa), `eject`, `eyed3`, `python3` + `python3-mutagen` (para `--retag` e `--fix-names`)
e, opcionalmente, `icedax` (só para a fonte CD-Text).

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

### Tirar os underscores dos nomes

```bash
./rip-cd.sh --fix-names ~/Músicas/Nirvana --dry-run
./rip-cd.sh --fix-names ~/Músicas/Nirvana
```

Aceita a pasta de um álbum ou a de um artista (ele acha os álbuns dentro). Usa a grafia
da tag do título quando ela confere com o nome do arquivo, então pontuação e apóstrofos
voltam. Só arquivos de áudio são renomeados.

Veja todas as opções com `./rip-cd.sh --help` e o histórico com `./rip-cd.sh --changelog`.

## Configuração

Tudo tem um padrão no topo do script e pode ser trocado por variáveis de ambiente:
`CD_DEVICE`, `DEST_DIR`, `OUTPUT_TYPE`, `LAME_QUALITY`, `EJECT_CD`, `METADATA_ORDER`
(ex.: `"musicbrainz cdtext"`), `GNUDB_URL`, `RETROBRIDGE_URL`.

## Limitações

- As consultas ao GnuDB, ao Retrobridge e ao Discogs, e a detecção de "não encontrado" do
  CD-Text, foram desenvolvidas com respostas simuladas, nem todas contra os serviços reais.
  Se alguma fonte se comportar mal, o log da consulta fica em
  `~/.cache/rip-cd/ultimo-rip-consulta.log`.
- Discos arranhados podem demorar; o `cdparanoia` roda com `--never-skip=40`.
- Confira se a legislação do seu país permite copiar os CDs que você ripa.

## Licença

[GPL-3.0](LICENSE)
