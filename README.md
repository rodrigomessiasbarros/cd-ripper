# cd-ripper

🇧🇷 [Leia em português](README.pt-BR.md)

`rip-cd.sh` is a Bash script that rips audio CDs on Debian/Ubuntu (and derivatives) with
progress bars, automatic tagging and embedded cover art. It wraps
[abcde](https://abcde.einval.com/) and `cdparanoia`, and adds what they lack: several
metadata sources with automatic fallback, a retag mode for albums that were already
ripped, and clean file names.

> The script's messages and `--help` are in Brazilian Portuguese.

## Features

- Rips to **MP3, FLAC, Ogg Vorbis or Opus** (or several at once, e.g. `-t flac,mp3`).
- **Progress bars** for ripping and encoding.
- **Metadata fallback chain**: MusicBrainz → GnuDB → Retrobridge → CD-Text (read from
  the disc itself). The first source that knows the disc wins; the order is configurable.
- **`--retag`**: fix the tags of an album you already ripped, without ripping again, from
  a MusicBrainz or Discogs link. Embeds the cover art and moves the files to
  `Artist/Album/`. Handles multi-disc albums and albums split across folders.
- **`--fix-names`**: removes the `_` from file names of already-ripped albums
  (`Smells_Like_Teen_Spirit.mp3` → `Smells Like Teen Spirit.mp3`).
- Detects your existing music folder (prefers `~/Músicas` over the system default `~/Música`).
- If a USB drive comes back under another name (`sr0` → `sr1`), uses the only drive found.
- `--install-deps` installs everything on Debian/Ubuntu.

## Requirements

Debian, Ubuntu or derivatives for `--install-deps` (the script itself runs on any Linux
that has the tools below).

`abcde`, `cdparanoia`, `lame`/`flac`/`vorbis-tools`/`opus-tools` (for the formats you use),
`eject`, `eyed3`, `python3` + `python3-mutagen` (for `--retag` and `--fix-names`), and the
optional `icedax` (only for the CD-Text source).

```bash
./rip-cd.sh --install-deps      # asks for confirmation; Debian/Ubuntu only
```

## Usage

```bash
chmod +x rip-cd.sh              # not needed if you cloned the repository

./rip-cd.sh                                  # rip with the defaults
./rip-cd.sh -d /dev/sr1 -o ~/Music -t flac   # other drive, destination and format
./rip-cd.sh -m gnudb                         # force one metadata source
./rip-cd.sh -i                               # choose between multiple matches
```

Files go to `<music folder>/CDs-Ripados/Artist/Album/01 - Title.ext` unless you pass `-o`.

### Fix the tags of an album you already ripped

```bash
# Preview first, then drop --dry-run to apply
./rip-cd.sh --retag ~/Music/Unknown\ Artist/Unknown\ Album \
            --release https://musicbrainz.org/release-group/<id> --dry-run
```

`--release` accepts a MusicBrainz release or release group, or a Discogs release or master.
With a group/master the script picks the edition by track count and durations. For Discogs,
`export DISCOGS_TOKEN=...` (a personal token) to download the cover and raise the rate limit.
Use `--disc N` for multi-disc releases and `--force` if the durations don't match (±4 s).

### Remove underscores from file names

```bash
./rip-cd.sh --fix-names ~/Music/Nirvana --dry-run
./rip-cd.sh --fix-names ~/Music/Nirvana
```

Accepts an album folder or an artist folder (it finds the albums inside). It uses the
spelling of the track title tag when it matches the file name, so punctuation and
apostrophes are restored. Only audio files are renamed.

Run `./rip-cd.sh --help` for every option and `./rip-cd.sh --changelog` for the history.

## Configuration

Everything has a default at the top of the script and can be overridden with environment
variables: `CD_DEVICE`, `DEST_DIR`, `OUTPUT_TYPE`, `LAME_QUALITY`, `EJECT_CD`,
`METADATA_ORDER` (e.g. `"musicbrainz cdtext"`), `GNUDB_URL`, `RETROBRIDGE_URL`.

## Limitations

- The lookups against GnuDB, Retrobridge, Discogs and the CD-Text "not found" detection
  were developed against simulated responses, not all of them against the live services.
  If a source misbehaves, the lookup log is at `~/.cache/rip-cd/ultimo-rip-consulta.log`.
- Ripping scratched discs can be slow; `cdparanoia` is run with `--never-skip=40`.
- Make sure you are allowed to copy the discs you rip where you live.

## License

[GPL-3.0](LICENSE)
