#!/usr/bin/env bash
#
# rip-cd.sh - Ripa CDs de áudio, converte e organiza em Artista/Álbum/
#
# Usa o abcde (que por baixo usa cdparanoia). As tags vêm do MusicBrainz e,
# se o disco não estiver lá, do CDDB (gnudb.org).
# Mostra barras de progresso de ripagem e de conversão.
#
# Instalação das dependências (SOMENTE Debian, Ubuntu e derivados):
#   ./rip-cd.sh --install-deps
#
# Uso:
#   ./rip-cd.sh                          # usa os valores padrão abaixo
#   ./rip-cd.sh -d /dev/sr1              # outro leitor de CD
#   ./rip-cd.sh -o /mnt/hd/Musicas       # outro destino
#   ./rip-cd.sh -t flac,mp3              # guarda FLAC e MP3
#   ./rip-cd.sh -d /dev/sr1 -o ~/Musicas -t mp3
#   ./rip-cd.sh -i                       # escolher o álbum do MusicBrainz (sem barras)
#   ./rip-cd.sh -m cddb                  # força o gnudb.org (ou: -m musicbrainz)
#
# Corrigir as tags de um álbum que já foi ripado (sem ripar de novo):
#   ./rip-cd.sh --retag ~/Músicas/CDs-Ripados/Unknown_Artist/Unknown_Album \
#               --release https://musicbrainz.org/release-group/ID --dry-run
#   (tire o --dry-run para aplicar; use o link de um release para fixar a edição)
#
# Versão do script (segue versionamento semântico: MAIOR.MENOR.CORREÇÃO).
# Veja o histórico com: ./rip-cd.sh --changelog
SCRIPT_VERSION="1.4.0"
SCRIPT_DATE="2026-11-06"

# detectar_pasta_musica
# Escolhe a pasta de músicas que JÁ EXISTE na sua home. Pastas criadas por
# você (plural: Músicas, Musicas) têm prioridade sobre a pasta padrão do
# sistema (Música / Music), que o Debian cria no primeiro login e costuma
# ficar vazia. Se nenhuma existir, usa a do sistema (xdg-user-dir) ou ~/Music.
detectar_pasta_musica() {
    local xdg="" c
    if command -v xdg-user-dir >/dev/null 2>&1; then
        xdg="$(xdg-user-dir MUSIC 2>/dev/null || true)"
    fi
    for c in "$HOME/Músicas" "$HOME/Musicas" "$xdg" \
             "$HOME/Música" "$HOME/Musica" "$HOME/Music"; do
        if [[ -n "$c" && "$c" != "$HOME" && -d "$c" ]]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    if [[ -n "$xdg" && "$xdg" != "$HOME" ]]; then
        printf '%s\n' "$xdg"
    else
        printf '%s\n' "$HOME/Music"
    fi
}

# ============================================================
#  CONFIGURAÇÃO - edite aqui os valores padrão
# ============================================================

# Leitor de CD (fonte). Para ver os seus: ls /dev/sr* ou lsblk
CD_DEVICE="${CD_DEVICE:-/dev/sr0}"

# Pasta de destino dos arquivos ripados.
# Se você não definir (nem aqui, nem com -o, nem na variável DEST_DIR), o
# script procura a sua pasta de músicas existente (detectar_pasta_musica)
# e cria "CDs-Ripados" dentro dela.
DEST_AUTO="n"
if [[ -z "${DEST_DIR:-}" ]]; then
    DEST_AUTO="y"
    DEST_DIR="$(detectar_pasta_musica)/CDs-Ripados"
fi

# Formato(s) de saída: mp3, flac, ogg, opus
# Use vírgula para mais de um, ex.: "flac,mp3"
# Dica: guardar FLAC evita ter que ripar de novo no futuro.
OUTPUT_TYPE="${OUTPUT_TYPE:-mp3}"

# Qualidade do MP3 (LAME VBR): 0 = melhor ... 9 = pior. V0 ~ 245 kbps
LAME_QUALITY="${LAME_QUALITY:-0}"

# Modo interativo: "y" pergunta qual resultado do MusicBrainz usar
# quando houver mais de um; "n" escolhe o primeiro automaticamente.
# (No modo interativo as barras de progresso ficam desligadas, porque
#  as perguntas do abcde precisam da tela inteira.)
INTERACTIVE="${INTERACTIVE:-n}"

# Ejetar o CD ao terminar? (y/n)
EJECT_CD="${EJECT_CD:-y}"

# Onde guardar o log completo do último rip
LOG_FILE="${LOG_FILE:-$HOME/.cache/rip-cd/ultimo-rip.log}"

# Fonte das tags (artista, álbum e nome das faixas):
#   auto         tenta o MusicBrainz e, se não achar o disco, o CDDB (gnudb.org)
#   musicbrainz  só o MusicBrainz
#   cddb         só o CDDB (gnudb.org)
METADATA_SOURCE="${METADATA_SOURCE:-auto}"

# Servidor CDDB do fallback. O freedb.org foi desativado; o gnudb.org o substitui.
GNUDB_URL="${GNUDB_URL:-http://gnudb.gnudb.org/~cddb/cddb.cgi}"

# Identificação enviada ao servidor CDDB (o protocolo exige usuario@host)
HELLOINFO="${HELLOINFO:-${USER:-rip-cd}@${HOSTNAME:-localhost}}"

# ============================================================
#  FIM DA CONFIGURAÇÃO
# ============================================================

set -euo pipefail

# Pacotes instalados por --install-deps (nomes do Debian/Ubuntu)
PACOTES_DEBIAN=(
    abcde cdparanoia flac lame eject
    vorbis-tools opus-tools
    eyed3 python3 python3-mutagen
    libmusicbrainz-discid-perl libwww-perl libjson-perl
)

OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
RETAG_DIRS=()
RETAG_RELEASE=""
RETAG_DISC=0
RETAG_MOVE="y"
RETAG_COVER="y"
RETAG_DRY="n"
RETAG_FORCE="n"
MOSTRAR_PROGRESSO="y"
INSTALAR_DEPS="n"
ASSUMIR_SIM="n"

# ------------------------------------------------------------
#  Utilidades
# ------------------------------------------------------------

erro() {
    echo "Erro: $*" >&2
    exit 1
}

uso() {
    cat <<EOF
$(basename "$0") v$SCRIPT_VERSION

Uso: $(basename "$0") [opções]

Ripagem:
  -d, --device DISPOSITIVO   Leitor de CD            (padrão: $CD_DEVICE)
  -o, --output DESTINO       Pasta de destino        (padrão: $DEST_DIR)
  -t, --type FORMATOS        mp3, flac, ogg, opus    (padrão: $OUTPUT_TYPE)
                             Vários separados por vírgula, ex.: flac,mp3
  -i, --interactive          Escolher o resultado quando houver vários
                             (desliga as barras de progresso)
  -m, --metadata FONTE       auto, musicbrainz ou cddb (padrão: $METADATA_SOURCE)
                             auto = MusicBrainz e, se não achar, gnudb.org
      --no-progress          Mostra a saída crua do abcde, sem barras

Corrigir as tags de um álbum já ripado (sem ripar de novo):
      --retag PASTA          Pasta com os arquivos do álbum (repita a opção se o
                             álbum estiver dividido em mais de uma pasta)
      --release LINK         Link (ou ID) da edição no MusicBrainz. Também aceita o
                             link do release group: o script escolhe a edição pelo
                             número de faixas e pelas durações
      --disc N               Disco do release, se ele tiver vários
      --no-move              Só grava as tags; não renomeia nem move os arquivos
      --no-cover             Não baixa a capa
      --dry-run              Mostra o que seria feito, sem alterar nada
      --force                Aplica mesmo se a duração da faixa não bater (±4 s)
  Os arquivos vão para DESTINO/Artista/Álbum/ (veja -o).

Dependências (somente Debian, Ubuntu e derivados):
      --install-deps         Instala os pacotes necessários com apt-get
  -y, --yes                  Não pedir confirmação no --install-deps

  -V, --version              Mostra a versão do script
      --changelog            Mostra o histórico de versões
  -h, --help                 Mostra esta ajuda
EOF
}

precisa_valor() {
    (( $# >= 2 )) || erro "a opção $1 precisa de um valor."
}

mostrar_versao() {
    echo "$(basename "$0") versão $SCRIPT_VERSION ($SCRIPT_DATE)"
}

mostrar_changelog() {
    mostrar_versao
    cat <<'EOF'

Histórico de versões:

  1.4.0  Detecta a pasta de músicas que já existe (prefere Músicas, criada
         por você, à pasta padrão do sistema, Música). Novo modo --retag:
         corrige as tags de um álbum já ripado a partir de um link do
         MusicBrainz, sem ripar de novo, e embute a capa em cada arquivo.
  1.3.0  Adiciona --version e --changelog.
  1.2.0  Fallback para o CDDB (gnudb.org) quando o MusicBrainz não acha o
         disco; nova opção --metadata (auto, musicbrainz, cddb).
  1.1.2  Arquivos temporários (WAV) passam a ficar na pasta de destino, em
         vez da pasta onde o script foi executado.
  1.1.1  Corrige dependência faltando: eyeD3 (pacote eyed3), necessário
         para gravar as tags ID3 dos MP3.
  1.1.0  Barras de progresso (ripando e convertendo); --install-deps para
         Debian/Ubuntu e derivados; opções longas (--device, --output...).
  1.0.0  Versão inicial: rip com abcde, leitor e destino configuráveis,
         saída em Artista/Álbum/, MP3 ou FLAC.
EOF
}

# ------------------------------------------------------------
#  Instalação de dependências (apenas Debian/Ubuntu e derivados)
# ------------------------------------------------------------

instalar_dependencias() {
    local ID="" ID_LIKE="" PRETTY_NAME=""

    if [[ ! -r "$OS_RELEASE" ]]; then
        erro "não consegui ler $OS_RELEASE para identificar a distribuição."
    fi
    # shellcheck disable=SC1090
    . "$OS_RELEASE"

    case " ${ID:-} ${ID_LIKE:-} " in
        *" debian "*|*" ubuntu "*) ;;
        *)
            {
                echo "Erro: --install-deps só funciona em Debian, Ubuntu e derivados."
                echo "      Sistema detectado: ${PRETTY_NAME:-${ID:-desconhecido}}"
                echo
                echo "Instale manualmente os equivalentes destes pacotes:"
                echo "  ${PACOTES_DEBIAN[*]}"
            } >&2
            exit 1
            ;;
    esac

    command -v apt-get >/dev/null 2>&1 || erro "apt-get não encontrado neste sistema."

    local sudo_cmd=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 \
            || erro "você não é root e o sudo não está instalado. Rode como root."
        sudo_cmd=(sudo)
    fi

    echo "Sistema detectado: ${PRETTY_NAME:-$ID} (Debian/Ubuntu ou derivado)"
    echo "Pacotes que serão instalados:"
    echo "  ${PACOTES_DEBIAN[*]}"
    echo

    if [[ "$ASSUMIR_SIM" != "y" ]]; then
        local resp=""
        read -r -p "Continuar com apt-get install? [s/N] " resp || resp=""
        case "${resp,,}" in
            s|sim|y|yes) ;;
            *) echo "Cancelado."; exit 0 ;;
        esac
    fi

    "${sudo_cmd[@]}" apt-get update
    "${sudo_cmd[@]}" apt-get install -y "${PACOTES_DEBIAN[@]}"

    echo
    echo "Dependências instaladas. Agora é só rodar: $0"
}

# ------------------------------------------------------------
#  Modo --retag: corrigir as tags de um álbum já ripado
# ------------------------------------------------------------
#
# Em vez de ripar de novo, lê uma edição do MusicBrainz (link do release ou
# do release group), grava artista/álbum/título/número das faixas nos
# arquivos, renomeia para "NN - Título.ext" dentro de Artista/Álbum/ e baixa
# a capa. O trabalho pesado é feito por um pequeno programa em Python
# (biblioteca mutagen) gerado abaixo.

gerar_helper_retag() {
    cat <<'PY'
#!/usr/bin/env python3
# Helper do rip-cd.sh --retag
import argparse
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request

try:
    import mutagen
except ImportError:
    print("Erro: o módulo mutagen não está instalado (sudo apt install python3-mutagen).",
          file=sys.stderr)
    sys.exit(1)

UUID_RE = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
EXTS = (".mp3", ".flac", ".ogg", ".opus")
TOL = 4.0          # tolerância entre a duração do arquivo e a da faixa (segundos)
REL_INC = "recordings+artist-credits+release-groups+media"
UA = "rip-cd.sh"
_ultima = 0.0      # o MusicBrainz pede no máximo 1 requisição por segundo


def die(msg):
    print("Erro: " + msg, file=sys.stderr)
    sys.exit(1)


def http_get(url, binario=False):
    global _ultima
    for tent in (1, 2, 3):
        espera = 1.1 - (time.time() - _ultima)
        if espera > 0:
            time.sleep(espera)
        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Accept": "*/*" if binario else "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                dados = r.read()
            _ultima = time.time()
            return dados if binario else json.loads(dados.decode("utf-8"))
        except urllib.error.HTTPError as e:
            _ultima = time.time()
            if e.code in (429, 502, 503, 504) and tent < 3:
                time.sleep(3 * tent)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            _ultima = time.time()
            if tent < 3:
                time.sleep(2 * tent)
                continue
            raise


def mb(caminho):
    sep = "&" if "?" in caminho else "?"
    return http_get("https://musicbrainz.org/ws/2/" + caminho + sep + "fmt=json")


def fetch_release(mbid):
    return mb("release/" + mbid + "?inc=" + REL_INC)


def credito(ac):
    partes = []
    for c in (ac or []):
        nome = c.get("name") or (c.get("artist") or {}).get("name", "")
        partes.append(nome + (c.get("joinphrase") or ""))
    return "".join(partes)


def seguro(s):
    s = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", s)
    s = re.sub(r"\s+", " ", s).strip().strip(".")
    return s or "_"


def comp(t):
    ms = t.get("length")
    if ms is None:
        ms = (t.get("recording") or {}).get("length")
    return ms / 1000.0 if ms else None


def listar_audio(pastas):
    itens = []
    for pasta in pastas:
        nomes = sorted(n for n in os.listdir(pasta)
                       if n.lower().endswith(EXTS) and os.path.isfile(os.path.join(pasta, n)))
        for n in nomes:
            m = re.match(r"\s*(\d{1,3})(?!\d)", n)
            itens.append({"nome": n, "caminho": os.path.join(pasta, n), "pasta": pasta,
                          "num": int(m.group(1)) if m else None})
    if any(it["num"] is None for it in itens):       # sem número no nome: vale a ordem
        if len(pastas) > 1:
            die("com mais de uma pasta, os nomes dos arquivos precisam começar com o número da faixa.")
        for i, it in enumerate(itens, 1):
            it["num"] = i
    nums = [it["num"] for it in itens]
    if len(set(nums)) != len(nums):
        die("há dois arquivos com o mesmo número de faixa; use só as pastas de um álbum.")
    for it in itens:
        try:
            f = mutagen.File(it["caminho"])
            it["dur"] = float(f.info.length) if f is not None and f.info else None
        except Exception:
            it["dur"] = None
    return itens


def escolher_medium(rel, n, disc):
    media = rel.get("media") or []
    if not media:
        raise ValueError("o release não tem lista de faixas")
    if disc:
        for md in media:
            if md.get("position") == disc:
                return md
        raise ValueError("o release não tem o disco %d" % disc)
    if len(media) == 1:
        return media[0]
    certos = [md for md in media if len(md.get("tracks", [])) == n]
    if len(certos) == 1:
        return certos[0]
    raise ValueError("o release tem %d discos; indique qual com --disc N" % len(media))


def pontuar(medium, arquivos):
    """Quanto menor, melhor: faixas sem par pesam muito; depois a diferença média de duração."""
    tm = {t["position"]: t for t in medium.get("tracks", [])}
    casados, soma = 0, 0.0
    for a in arquivos:
        t = tm.get(a["num"])
        if not t:
            continue
        casados += 1
        l = comp(t)
        soma += abs(a["dur"] - l) if (l is not None and a["dur"] is not None) else 10.0
    return (len(arquivos) - casados) * 1000 + (soma / casados if casados else 1000)


def escolher_do_grupo(rgid, arquivos, args):
    n = len(arquivos)
    lista = mb("release?release-group=" + rgid + "&inc=media&limit=100").get("releases", [])
    if not lista:
        die("o release group não tem edições.")

    def contagens(r):
        return [md.get("track-count", 0) for md in r.get("media", [])]

    cand = [r for r in lista if n in contagens(r) or sum(contagens(r)) == n]
    if not cand:
        print("Nenhuma edição tem %d faixas. Edições deste álbum:" % n)
        for r in sorted(lista, key=lambda r: (r.get("date") or "9999", r["id"])):
            print("  %-10s %-3s %s faixas  https://musicbrainz.org/release/%s" % (
                r.get("date") or "?", r.get("country") or "??",
                "+".join(str(c) for c in contagens(r)), r["id"]))
        die("passe o link da edição certa em --release (ou confira se faltam arquivos na pasta).")
    cand.sort(key=lambda r: (r.get("date") or "9999", r["id"]))
    pont = []
    for r in cand[:8]:
        full = fetch_release(r["id"])
        try:
            md = escolher_medium(full, n, args.disc)
        except ValueError:
            continue
        pont.append((pontuar(md, arquivos), full))
    if not pont:
        die("não consegui comparar as edições; passe o link do release em --release.")
    pont.sort(key=lambda x: x[0])
    print("%d edição(ões) com %d faixas; melhores pela duração:" % (len(cand), n))
    for i, (sc, full) in enumerate(pont[:5], 1):
        print("  %d. %-10s %-3s %s  (dif. média %.1fs)  https://musicbrainz.org/release/%s" % (
            i, full.get("date") or "?", full.get("country") or "??", full["title"], sc, full["id"]))
    print("-> usando a opção 1. Para outra, rode de novo com o link da edição em --release.")
    return pont[0][1]


def resolver_release(ref, arquivos, args):
    m = UUID_RE.search(ref)
    if not m:
        die("não encontrei um ID do MusicBrainz em: " + ref)
    mbid = m.group(0).lower()
    if "release-group" in ref:
        tipo = "grupo"
    elif "/release/" in ref:
        tipo = "release"
    else:
        tipo = "auto"
    try:
        if tipo == "release":
            return fetch_release(mbid)
        if tipo == "auto":
            try:
                return fetch_release(mbid)
            except urllib.error.HTTPError as e:
                if e.code != 404:
                    raise
        return escolher_do_grupo(mbid, arquivos, args)
    except urllib.error.HTTPError as e:
        die("o MusicBrainz respondeu HTTP %d para %s." % (e.code, mbid))
    except (urllib.error.URLError, TimeoutError) as e:
        die("não consegui falar com o MusicBrainz: %s" % e)


def montar_plano(medium, arquivos, forcar):
    tm = {t["position"]: t for t in medium.get("tracks", [])}
    plano = []
    for a in sorted(arquivos, key=lambda x: x["num"]):
        t = tm.get(a["num"])
        if not t:
            plano.append({"a": a, "t": None, "d": None, "estado": "sem faixa"})
            continue
        l = comp(t)
        d = (a["dur"] - l) if (l is not None and a["dur"] is not None) else None
        ok = forcar or d is None or abs(d) <= TOL
        plano.append({"a": a, "t": t, "d": d, "estado": "ok" if ok else "duracao"})
    return plano


def etiquetar(caminho, rel, medium, t):
    rec = t.get("recording") or {}
    ac_rel = rel.get("artist-credit") or []
    ac_t = t.get("artist-credit") or rec.get("artist-credit") or ac_rel
    tags = {
        "title": t["title"],
        "artist": credito(ac_t),
        "album": rel["title"],
        "albumartist": credito(ac_rel),
        "tracknumber": "%d/%d" % (t["position"], len(medium["tracks"])),
        "discnumber": "%d/%d" % (medium.get("position") or 1, len(rel["media"])),
    }
    if rel.get("date"):
        tags["date"] = rel["date"]
    extras = {
        "musicbrainz_albumid": rel["id"],
        "musicbrainz_trackid": rec.get("id"),
        "musicbrainz_artistid": [c["artist"]["id"] for c in ac_t if c.get("artist")],
        "musicbrainz_albumartistid": [c["artist"]["id"] for c in ac_rel if c.get("artist")],
        "musicbrainz_releasegroupid": (rel.get("release-group") or {}).get("id"),
    }
    f = mutagen.File(caminho, easy=True)
    if f is None:
        raise ValueError("formato não suportado")
    if f.tags is None:
        f.add_tags()
    for k, v in tags.items():
        f[k] = [v]
    for k, v in extras.items():
        if not v:
            continue
        try:
            f[k] = v if isinstance(v, list) else [v]
        except Exception:
            pass                                    # o formato não tem esse campo
    f.save()


def pasta_album(dest, rel, medium):
    nome = seguro(rel["title"])
    if len(rel["media"]) > 1:
        nome += " (Disc %d)" % (medium.get("position") or 1)
    return os.path.join(dest, seguro(credito(rel.get("artist-credit"))), nome)


def obter_capa(mbid):
    """Baixa a capa frontal (500 px) do Cover Art Archive. Devolve os bytes ou None."""
    try:
        dados = http_get("https://coverartarchive.org/release/" + mbid + "/front-500", binario=True)
        return dados if len(dados) >= 1000 else None
    except Exception:
        return None


def _imagem(dados):
    from mutagen.flac import Picture
    p = Picture()
    p.type = 3                       # capa frontal
    p.mime = "image/jpeg"
    p.desc = "Front"
    p.data = dados
    return p


def embutir_capa(caminho, dados):
    ext = os.path.splitext(caminho)[1].lower()
    if ext == ".mp3":
        from mutagen.id3 import ID3, APIC
        t = ID3(caminho)
        t.delall("APIC")
        t.add(APIC(encoding=3, mime="image/jpeg", type=3, desc="Front", data=dados))
        t.save(caminho)
    elif ext == ".flac":
        from mutagen.flac import FLAC
        f = FLAC(caminho)
        f.clear_pictures()
        f.add_picture(_imagem(dados))
        f.save()
    elif ext in (".ogg", ".opus"):
        import base64
        f = mutagen.File(caminho)
        f["metadata_block_picture"] = [base64.b64encode(_imagem(dados).write()).decode("ascii")]
        f.save()


def salvar_capa(dados, pasta):
    alvo = os.path.join(pasta, "cover.jpg")
    if os.path.exists(alvo):
        return False
    with open(alvo, "wb") as f:
        f.write(dados)
    return True


def limpar_pasta_antiga(pasta, album_dir):
    """Depois de mover os arquivos: se só sobrou uma capa, leva ou descarta; remove pastas vazias."""
    imagens = {"cover.jpg", "folder.jpg", "cover.png", "folder.png"}
    try:
        restos = os.listdir(pasta)
    except OSError:
        return
    if os.path.abspath(pasta) == os.path.abspath(album_dir):
        return
    if restos and all(n.lower() in imagens for n in restos):
        for n in restos:
            origem, alvo = os.path.join(pasta, n), os.path.join(album_dir, n)
            try:
                if os.path.exists(alvo):
                    os.remove(origem)
                else:
                    shutil.move(origem, alvo)
            except OSError:
                pass
    home = os.path.expanduser("~")
    for d in (pasta, os.path.dirname(pasta)):        # só remove se estiver vazia
        d = os.path.abspath(d)
        if d == os.path.abspath(album_dir):
            continue
        if d != os.path.abspath(pasta) and os.path.dirname(d) == home:
            continue                                  # nunca apaga pastas direto na home (ex.: ~/Música)
        try:
            os.rmdir(d)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", action="append", required=True)
    ap.add_argument("--release", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--disc", type=int, default=0)
    ap.add_argument("--no-move", action="store_true")
    ap.add_argument("--no-cover", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--script-version", default="0")
    args = ap.parse_args()

    global UA
    UA = "rip-cd.sh/" + args.script_version

    pastas = []
    for d in args.dir:
        pasta = os.path.abspath(os.path.expanduser(d))
        if not os.path.isdir(pasta):
            die("'%s' não é uma pasta." % pasta)
        if pasta not in pastas:
            pastas.append(pasta)
    arquivos = listar_audio(pastas)
    if not arquivos:
        die("nenhum arquivo de áudio (mp3, flac, ogg, opus) em: " + ", ".join(pastas))
    print("%d arquivo(s) de áudio em %d pasta(s):" % (len(arquivos), len(pastas)))
    for pasta in pastas:
        print("  " + pasta)

    rel = resolver_release(args.release, arquivos, args)
    try:
        medium = escolher_medium(rel, len(arquivos), args.disc)
    except ValueError as e:
        die(str(e))
    plano = montar_plano(medium, arquivos, args.force)

    print("\nEdição: %s - %s (%s%s)" % (
        credito(rel.get("artist-credit")), rel["title"], (rel.get("date") or "?")[:4],
        ", " + rel["country"] if rel.get("country") else ""))
    print("        https://musicbrainz.org/release/" + rel["id"])
    print("        %d faixa(s) nesta edição\n" % len(medium["tracks"]))
    for p in plano:
        a, t = p["a"], p["t"]
        if t is None:
            print("  %-34.34s -> (sem faixa nesta edição; ficará intacto)" % a["nome"])
            continue
        dif = "[%+.1fs]" % p["d"] if p["d"] is not None else "[?]"
        aviso = "   ATENÇÃO: duração não bate, será pulado (use --force)" if p["estado"] == "duracao" else ""
        print("  %-34.34s -> %02d %s  %s%s" % (a["nome"], t["position"], t["title"], dif, aviso))

    aplicaveis = [p for p in plano if p["estado"] == "ok"]
    if not aplicaveis:
        die("nenhuma faixa desta edição combina com os arquivos.")

    if args.dry_run:
        print("\n(--dry-run: nada foi alterado.)")
        return 0
    if not args.yes:
        if not sys.stdin.isatty():
            die("sem terminal para confirmar; use --yes.")
        resp = input("\nAplicar estas mudanças? [s/N] ").strip().lower()
        if resp not in ("s", "sim", "y", "yes"):
            print("Cancelado.")
            return 0

    dest = os.path.abspath(os.path.expanduser(args.dest))
    album_dir = None if args.no_move else pasta_album(dest, rel, medium)
    ok = pulados = falhas = embutidas = 0
    pastas_ok = set()
    capa = None if args.no_cover else obter_capa(rel["id"])
    print("capa: %s\n" % ("encontrada no Cover Art Archive" if capa
                          else ("desligada (--no-cover)" if args.no_cover
                                else "não encontrada no Cover Art Archive")))
    for p in plano:
        a, t = p["a"], p["t"]
        if p["estado"] != "ok":
            pulados += 1
            continue
        try:
            etiquetar(a["caminho"], rel, medium, t)
            if capa:
                try:
                    embutir_capa(a["caminho"], capa)
                    embutidas += 1
                except Exception as e:
                    print("  AVISO: não consegui embutir a capa em %s: %s" % (a["nome"], e))
            destino = album_dir or a["pasta"]
            final = a["caminho"]
            if not args.no_move:
                ext = os.path.splitext(a["nome"])[1].lower()
                final = os.path.join(album_dir, "%02d - %s%s" % (t["position"], seguro(t["title"]), ext))
                if os.path.abspath(final) != os.path.abspath(a["caminho"]):
                    if os.path.exists(final):
                        print("  AVISO: já existe %s; etiquetei mas não movi %s" % (final, a["nome"]))
                        ok += 1
                        pastas_ok.add(destino)
                        continue
                    os.makedirs(album_dir, exist_ok=True)
                    shutil.move(a["caminho"], final)
            print("  OK  %s" % os.path.relpath(final, os.path.dirname(destino)))
            ok += 1
            pastas_ok.add(destino)
        except Exception as e:
            falhas += 1
            print("  FALHOU %s: %s" % (a["nome"], e))

    if capa:
        for d in sorted(pastas_ok):
            if os.path.isdir(d) and salvar_capa(capa, d):
                print("  cover.jpg salvo em %s" % d)

    if not args.no_move:
        for pasta in pastas:
            limpar_pasta_antiga(pasta, album_dir)

    print("\nEtiquetados: %d | capa embutida: %d | pulados: %d | falhas: %d" % (
        ok, embutidas, pulados, falhas))
    restantes = [p["a"]["caminho"] for p in plano if p["estado"] != "ok"]
    if restantes:
        print("Ficaram intactos:")
        for n in restantes:
            print("  - " + n)
        print("Se o seu disco é de outra edição, rode de novo com o link do release group")
        print("para o script escolher a edição que tem o mesmo número de faixas.")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
PY
}

executar_retag() {
    command -v python3 >/dev/null 2>&1 \
        || erro "python3 não encontrado. No Debian/Ubuntu: $0 --install-deps"
    python3 -c 'import mutagen' 2>/dev/null \
        || erro "módulo mutagen ausente. No Debian/Ubuntu: $0 --install-deps (pacote python3-mutagen)"
    local d helper rc=0 args=()
    for d in "${RETAG_DIRS[@]}"; do
        [[ -d "$d" ]] || erro "'$d' não é uma pasta."
        args+=(--dir "$d")
    done

    helper="$(mktemp --suffix=.retag.py)"
    gerar_helper_retag > "$helper"

    args+=(--release "$RETAG_RELEASE" --dest "$DEST_DIR"
           --script-version "$SCRIPT_VERSION")
    if (( RETAG_DISC > 0 )); then args+=(--disc "$RETAG_DISC"); fi
    if [[ "$RETAG_MOVE"  == "n" ]]; then args+=(--no-move);  fi
    if [[ "$RETAG_COVER" == "n" ]]; then args+=(--no-cover); fi
    if [[ "$RETAG_DRY"   == "y" ]]; then args+=(--dry-run);  fi
    if [[ "$RETAG_FORCE" == "y" ]]; then args+=(--force);    fi
    if [[ "$ASSUMIR_SIM" == "y" ]]; then args+=(--yes);      fi

    python3 -I "$helper" "${args[@]}" || rc=$?
    rm -f "$helper"
    return "$rc"
}

# ------------------------------------------------------------
#  Argumentos
# ------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        -d|--device)      precisa_valor "$@"; CD_DEVICE="$2"; shift 2 ;;
        -o|--output)      precisa_valor "$@"; DEST_DIR="$2"; DEST_AUTO="n"; shift 2 ;;
        -t|--type)        precisa_valor "$@"; OUTPUT_TYPE="$2"; shift 2 ;;
        -i|--interactive) INTERACTIVE="y"; shift ;;
        -m|--metadata)    precisa_valor "$@"; METADATA_SOURCE="$2"; shift 2 ;;
        --no-progress)    MOSTRAR_PROGRESSO="n"; shift ;;
        --retag)          precisa_valor "$@"; RETAG_DIRS+=("$2"); shift 2 ;;
        --release)        precisa_valor "$@"; RETAG_RELEASE="$2"; shift 2 ;;
        --disc)           precisa_valor "$@"; RETAG_DISC="$2"; shift 2 ;;
        --no-move)        RETAG_MOVE="n"; shift ;;
        --no-cover)       RETAG_COVER="n"; shift ;;
        --dry-run)        RETAG_DRY="y"; shift ;;
        --force)          RETAG_FORCE="y"; shift ;;
        --install-deps)   INSTALAR_DEPS="y"; shift ;;
        -y|--yes)         ASSUMIR_SIM="y"; shift ;;
        -V|--version)     mostrar_versao; exit 0 ;;
        --changelog)      mostrar_changelog; exit 0 ;;
        -h|--help)        uso; exit 0 ;;
        *) echo "Erro: opção inválida '$1'" >&2; echo >&2; uso >&2; exit 1 ;;
    esac
done

if [[ "$INSTALAR_DEPS" == "y" ]]; then
    instalar_dependencias
    exit 0
fi

if (( ${#RETAG_DIRS[@]} > 0 )) || [[ -n "$RETAG_RELEASE" ]]; then
    (( ${#RETAG_DIRS[@]} > 0 )) && [[ -n "$RETAG_RELEASE" ]] \
        || erro "--retag e --release devem ser usados juntos."
    [[ "$RETAG_DISC" =~ ^[0-9]+$ ]] || erro "--disc deve ser um número."
    rc_retag=0
    executar_retag || rc_retag=$?
    exit "$rc_retag"
fi

# ------------------------------------------------------------
#  Verificações
# ------------------------------------------------------------

case "$METADATA_SOURCE" in
    auto|musicbrainz|cddb) ;;
    *) erro "--metadata deve ser auto, musicbrainz ou cddb (recebi '$METADATA_SOURCE')." ;;
esac

faltando=()
for cmd in abcde cdparanoia eject timeout; do
    command -v "$cmd" >/dev/null 2>&1 || faltando+=("$cmd")
done
[[ "$OUTPUT_TYPE" == *mp3*  ]] && { command -v lame    >/dev/null 2>&1 || faltando+=("lame"); }
[[ "$OUTPUT_TYPE" == *mp3*  ]] && { command -v eyeD3   >/dev/null 2>&1 || faltando+=("eyeD3 (pacote eyed3)"); }
[[ "$OUTPUT_TYPE" == *flac* ]] && { command -v flac    >/dev/null 2>&1 || faltando+=("flac"); }
[[ "$OUTPUT_TYPE" == *ogg*  ]] && { command -v oggenc  >/dev/null 2>&1 || faltando+=("oggenc (vorbis-tools)"); }
[[ "$OUTPUT_TYPE" == *opus* ]] && { command -v opusenc >/dev/null 2>&1 || faltando+=("opusenc (opus-tools)"); }

if (( ${#faltando[@]} > 0 )); then
    echo "Erro: comandos não encontrados: ${faltando[*]}" >&2
    echo "No Debian/Ubuntu, instale tudo com: $0 --install-deps" >&2
    exit 1
fi

if [[ ! -b "$CD_DEVICE" ]]; then
    echo "Erro: '$CD_DEVICE' não é um dispositivo de bloco válido." >&2
    echo "Dispositivos de CD/DVD encontrados:" >&2
    ls /dev/sr* 2>/dev/null >&2 || echo "  (nenhum)" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"
[[ -w "$DEST_DIR" ]] || erro "sem permissão de escrita em '$DEST_DIR'."

mkdir -p "$(dirname "$LOG_FILE")"

# ------------------------------------------------------------
#  Configuração temporária do abcde
# ------------------------------------------------------------

CONFIG="$(mktemp --suffix=.abcde.conf)"
CONFIG_LOOKUP=""     # config da consulta de tags (some depois de cada consulta)
LOOKUP_TMP=""        # pasta temporária da consulta
ABCDE_PID=""

limpar() {
    if [[ -n "$ABCDE_PID" ]] && kill -0 "$ABCDE_PID" 2>/dev/null; then
        kill "$ABCDE_PID" 2>/dev/null || true
    fi
    rm -f "$CONFIG"
    [[ -z "$CONFIG_LOOKUP" ]] || rm -f "$CONFIG_LOOKUP"
    [[ -z "$LOOKUP_TMP" ]] || rm -rf "$LOOKUP_TMP"
    if [[ -t 1 ]]; then printf '\033[?25h'; fi   # devolve o cursor
}
trap limpar EXIT
trap 'echo; echo "Interrompido."; exit 130' INT TERM

# Com mais de um formato, separa em subpastas (ex.: DEST/flac/Artista/Álbum)
if [[ "$OUTPUT_TYPE" == *,* ]]; then
    PREFIXO='${OUTPUT}/'
else
    PREFIXO=''
fi

# gerar_config ARQUIVO MÉTODO PASTA_SAÍDA PASTA_WAV
gerar_config() {
    local arq="$1" metodo="$2" saida="$3" wav="$4" bloco_meta
    case "$metodo" in
        cddb) bloco_meta="CDDBMETHOD=cddb
CDDBURL=\"$GNUDB_URL\"
HELLOINFO=\"$HELLOINFO\"" ;;
        *)    bloco_meta="CDDBMETHOD=musicbrainz" ;;
    esac

    cat > "$arq" <<EOF
CDROM="$CD_DEVICE"
OUTPUTDIR="$saida"
WAVOUTPUTDIR="$wav"
OUTPUTTYPE="$OUTPUT_TYPE"
$bloco_meta

# Estrutura: [formato/]Artista/Álbum/01 - Faixa.ext
OUTPUTFORMAT='${PREFIXO}\${ARTISTFILE}/\${ALBUMFILE}/\${TRACKNUM} - \${TRACKFILE}'
VAOUTPUTFORMAT='${PREFIXO}Various Artists/\${ALBUMFILE}/\${TRACKNUM} - \${ARTISTFILE} - \${TRACKFILE}'
ONETRACKOUTPUTFORMAT='${PREFIXO}\${ARTISTFILE}/\${ALBUMFILE}/\${ALBUMFILE}'

MP3ENCODERSYNTAX=lame
LAME=lame
LAMEOPTS='-V $LAME_QUALITY'

CDPARANOIAOPTS='--never-skip=40'
INTERACTIVE=$INTERACTIVE
EJECTCD=$EJECT_CD
PADTRACKS=y
MAXPROCS=2
EOF
}

# consultar_metadados MÉTODO
# Roda só a ação de consulta do abcde (nada é ripado nem ejetado).
# Retorna 0 se o disco foi encontrado; 1 se não foi ou se a consulta falhou.
consultar_metadados() {
    local metodo="$1" saida rc=0
    CONFIG_LOOKUP="$(mktemp --suffix=.abcde-lookup.conf)"
    LOOKUP_TMP="$(mktemp -d)"
    gerar_config "$CONFIG_LOOKUP" "$metodo" "$LOOKUP_TMP" "$LOOKUP_TMP"
    # a consulta nunca pergunta nada nem ejeta o disco
    sed -i -e 's/^INTERACTIVE=.*/INTERACTIVE=n/' -e 's/^EJECTCD=.*/EJECTCD=n/' "$CONFIG_LOOKUP"

    saida="$(timeout 90 abcde -c "$CONFIG_LOOKUP" -d "$CD_DEVICE" -a cddb,clean </dev/null 2>&1)" || rc=$?
    printf '===== consulta: %s (código de saída %s) =====\n%s\n\n' "$metodo" "$rc" "$saida" >> "$LOG_LOOKUP"

    rm -rf "$LOOKUP_TMP" "$CONFIG_LOOKUP"
    LOOKUP_TMP=""; CONFIG_LOOKUP=""

    (( rc == 0 )) || return 1
    if grep -qiE 'no lookup matches|unknown artist / unknown album|lookup returned an error' <<< "$saida"; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------
#  Barras de progresso
# ------------------------------------------------------------
#
# O abcde roda em segundo plano gravando tudo em $LOG_FILE. Este script
# lê o log enquanto ele cresce e conta as linhas "Grabbing track N",
# "Encoding track N" e "Tagging track N". Se o abcde mudar essas
# mensagens, as barras ficam imprecisas, mas o rip não é afetado.

USAR_PROGRESSO="n"
if [[ "$MOSTRAR_PROGRESSO" == "y" && "$INTERACTIVE" != "y" && -t 1 ]]; then
    USAR_PROGRESSO="y"
fi

TOTAL=0          # nº de faixas do CD
N_GRAB=0         # linhas "Grabbing track" vistas
N_ENC=0          # linhas "Encoding track" vistas
N_TAG=0          # linhas "Tagging track" vistas
ULT_GRAB=""      # última faixa lida
ULT_ENC=""       # última faixa em conversão
MAX_FAIXA=0
CONCLUIDO="n"
DESENHADO=0
QUADRO=0
_virgulas="${OUTPUT_TYPE//[^,]/}"      # só as vírgulas de OUTPUT_TYPE
N_FORMATOS=$(( ${#_virgulas} + 1 ))     # nº de formatos de saída

COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
(( COLS >= 40 )) || COLS=40

# Caracteres e cores (cai para ASCII se o terminal não for UTF-8)
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*|*UTF8*|*utf-8*)
        C_CHEIO='█'; C_VAZIO='░'; SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'); C_OK='✔' ;;
    *)
        C_CHEIO='#'; C_VAZIO='-'; SPIN=('|' '/' '-' '\'); C_OK='OK' ;;
esac

if [[ -z "${NO_COLOR:-}" ]]; then
    COR_VERDE=$'\033[32m'; COR_CIANO=$'\033[36m'; COR_NEG=$'\033[1m'; COR_FIM=$'\033[0m'
else
    COR_VERDE=""; COR_CIANO=""; COR_NEG=""; COR_FIM=""
fi

contar_faixas() {
    cdparanoia -Q -d "$CD_DEVICE" 2>&1 | grep -cE '^[[:space:]]*[0-9]+\.' || true
}

processar_linha() {
    local linha="$1" n=""
    shopt -s nocasematch
    if [[ $linha =~ ^[[:space:]]*(grabbing|ripping)[[:space:]]+track[[:space:]]+([0-9]+) ]]; then
        n=$((10#${BASH_REMATCH[2]})); N_GRAB=$((N_GRAB + 1)); ULT_GRAB=$n
    elif [[ $linha =~ ^[[:space:]]*encoding[[:space:]]+track[[:space:]]+([0-9]+) ]]; then
        n=$((10#${BASH_REMATCH[1]})); N_ENC=$((N_ENC + 1)); ULT_ENC=$n
    elif [[ $linha =~ ^[[:space:]]*tagging[[:space:]]+track[[:space:]]+([0-9]+) ]]; then
        n=$((10#${BASH_REMATCH[1]})); N_TAG=$((N_TAG + 1))
    fi
    shopt -u nocasematch
    if [[ -n "$n" ]] && (( n > MAX_FAIXA )); then MAX_FAIXA=$n; fi
    return 0
}

calcular() {
    local f=$N_FORMATOS iniciadas feitas_enc feitas_tag
    iniciadas=$(( (N_ENC + f - 1) / f ))          # faixas cuja conversão já começou
    feitas_enc=$(( iniciadas > 0 ? iniciadas - 1 : 0 ))
    feitas_tag=$(( N_TAG / f ))

    # Uma faixa está lida quando a conversão dela começa
    RIP_FEITAS=$(( N_GRAB > 0 ? N_GRAB - 1 : 0 ))
    (( iniciadas > RIP_FEITAS )) && RIP_FEITAS=$iniciadas
    CONV_FEITAS=$(( feitas_tag > feitas_enc ? feitas_tag : feitas_enc ))

    TOT=$TOTAL
    (( TOT > 0 )) || TOT=$MAX_FAIXA
    (( RIP_FEITAS  <= TOT )) || RIP_FEITAS=$TOT
    (( CONV_FEITAS <= TOT )) || CONV_FEITAS=$TOT

    if [[ "$CONCLUIDO" == "y" ]]; then
        RIP_FEITAS=$TOT; CONV_FEITAS=$TOT
    fi
}

barra() {   # rótulo feitas total largura
    local rotulo="$1" feitas="$2" total="$3" larg="$4"
    local pct=0 cheio=0 vazio s1 s2
    if (( total > 0 )); then
        pct=$(( feitas * 100 / total ))
        cheio=$(( feitas * larg / total ))
    fi
    vazio=$(( larg - cheio ))
    printf -v s1 '%*s' "$cheio" ''
    printf -v s2 '%*s' "$vazio" ''
    printf '%s%-12s%s[%s%s%s%s] %3d%%  %d/%d' \
        "$COR_NEG" "$rotulo" "$COR_FIM" \
        "$COR_VERDE" "${s1// /$C_CHEIO}" "$COR_FIM" "${s2// /$C_VAZIO}" \
        "$pct" "$feitas" "$total"
}

desenhar() {
    calcular
    local larg=$(( COLS - 33 )) tempo status
    (( larg >= 10 )) || larg=10
    (( larg <= 50 )) || larg=50

    printf -v tempo '%02d:%02d' $(( SECONDS / 60 )) $(( SECONDS % 60 ))

    if [[ "$CONCLUIDO" == "y" ]]; then
        status="$C_OK Concluído em $tempo"
    else
        QUADRO=$(( (QUADRO + 1) % ${#SPIN[@]} ))
        status="${SPIN[$QUADRO]} "
        if [[ -n "$ULT_GRAB" ]]; then status+="lendo faixa $ULT_GRAB"; else status+="aguardando o abcde..."; fi
        if [[ -n "$ULT_ENC"  ]]; then status+=" · convertendo faixa $ULT_ENC"; fi
        status+=" · $tempo"
    fi
    status="${status:0:$(( COLS - 1 ))}"

    if (( DESENHADO == 1 )); then printf '\033[3A'; fi
    printf '\r\033[K'; barra "Ripando"     "$RIP_FEITAS"  "$TOT" "$larg"; printf '\n'
    printf '\r\033[K'; barra "Convertendo" "$CONV_FEITAS" "$TOT" "$larg"; printf '\n'
    printf '\r\033[K%s%s%s\n' "$COR_CIANO" "$status" "$COR_FIM"
    DESENHADO=1
}

drenar_log() {
    local linha
    while IFS= read -r -u3 linha; do
        processar_linha "$linha"
    done
    return 0
}

# ------------------------------------------------------------
#  Execução
# ------------------------------------------------------------

echo "============================================"
echo " Leitor : $CD_DEVICE"
echo " Destino: $DEST_DIR$([[ "$DEST_AUTO" == "y" ]] && echo "  (pasta de músicas detectada)" || true)"
echo " Formato: $OUTPUT_TYPE"
echo " Log    : $LOG_FILE"
echo "============================================"

TOTAL="$(contar_faixas)"
if (( TOTAL > 0 )); then
    echo "CD de áudio detectado: $TOTAL faixas."
else
    echo "Aviso: não consegui ler o índice do CD (sem disco, disco que não é de áudio"
    echo "       ou sem permissão; seu usuário está no grupo 'cdrom'?). Tentando assim mesmo."
fi
# --- Fonte das tags -------------------------------------------
METODO_ESCOLHIDO="musicbrainz"
SEM_METADADOS="n"
LOG_LOOKUP="${LOG_FILE%.log}-consulta.log"
: > "$LOG_LOOKUP"

case "$METADATA_SOURCE" in
    musicbrainz|cddb)
        METODO_ESCOLHIDO="$METADATA_SOURCE"
        echo "Fonte das tags: $METODO_ESCOLHIDO (definida por --metadata)"
        ;;
    auto)
        echo "Procurando as tags do disco..."
        if consultar_metadados musicbrainz; then
            echo "  $C_OK encontrado no MusicBrainz"
        else
            echo "  x não encontrado no MusicBrainz; tentando o CDDB (gnudb.org)..."
            if consultar_metadados cddb; then
                METODO_ESCOLHIDO="cddb"
                echo "  $C_OK encontrado no gnudb.org"
            else
                SEM_METADADOS="y"
                echo "  x não encontrado no gnudb.org"
                echo "  Seguindo com nomes genéricos (Unknown_Artist, Track_N)."
            fi
        fi
        echo "  (log da consulta: $LOG_LOOKUP)"
        ;;
esac
echo

gerar_config "$CONFIG" "$METODO_ESCOLHIDO" "$DEST_DIR" "$DEST_DIR"

echo "Iniciando o rip... (Ctrl+C para cancelar)"
echo

SECONDS=0
rc=0

if [[ "$USAR_PROGRESSO" == "y" ]]; then
    : > "$LOG_FILE"
    abcde -c "$CONFIG" -d "$CD_DEVICE" > "$LOG_FILE" 2>&1 &
    ABCDE_PID=$!
    exec 3< "$LOG_FILE"
    printf '\033[?25l'                              # esconde o cursor

    while :; do
        drenar_log
        desenhar
        kill -0 "$ABCDE_PID" 2>/dev/null || break
        sleep 0.5
    done

    wait "$ABCDE_PID" || rc=$?
    ABCDE_PID=""
    drenar_log
    exec 3<&-

    if (( rc == 0 )); then CONCLUIDO="y"; fi
    desenhar
    printf '\033[?25h'
elif [[ "$INTERACTIVE" == "y" ]]; then
    # Interativo: o abcde precisa do terminal inteiro, sem filtros
    abcde -c "$CONFIG" -d "$CD_DEVICE" || rc=$?
else
    set +e
    abcde -c "$CONFIG" -d "$CD_DEVICE" 2>&1 | tee "$LOG_FILE"
    rc=${PIPESTATUS[0]}
    set -e
fi

echo
if (( rc == 0 )); then
    echo "Concluído! Arquivos em: $DEST_DIR"
    if [[ "$SEM_METADADOS" == "y" ]]; then
        echo
        echo "O disco não está no MusicBrainz nem no gnudb, então os arquivos ficaram sem tags."
        echo "Abra a pasta no MusicBrainz Picard e use \"Escanear\" (impressão digital de áudio)."
    fi
else
    echo "O abcde terminou com erro (código $rc)." >&2
    if [[ "$INTERACTIVE" != "y" && -s "$LOG_FILE" ]]; then
        echo "Últimas linhas do log ($LOG_FILE):" >&2
        tail -n 15 "$LOG_FILE" | sed 's/^/  /' >&2
    fi
    exit "$rc"
fi
