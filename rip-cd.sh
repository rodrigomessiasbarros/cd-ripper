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
# Versão do script (segue versionamento semântico: MAIOR.MENOR.CORREÇÃO).
# Veja o histórico com: ./rip-cd.sh --changelog
SCRIPT_VERSION="1.3.0"
SCRIPT_DATE="2026-11-06"

# ============================================================
#  CONFIGURAÇÃO - edite aqui os valores padrão
# ============================================================

# Leitor de CD (fonte). Para ver os seus: ls /dev/sr* ou lsblk
CD_DEVICE="${CD_DEVICE:-/dev/sr0}"

# Pasta de destino dos arquivos ripados
DEST_DIR="${DEST_DIR:-$HOME/Música/CDs-Ripados}"

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
    eyed3
    libmusicbrainz-discid-perl libwww-perl libjson-perl
)

OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
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
#  Argumentos
# ------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        -d|--device)      precisa_valor "$@"; CD_DEVICE="$2"; shift 2 ;;
        -o|--output)      precisa_valor "$@"; DEST_DIR="$2"; shift 2 ;;
        -t|--type)        precisa_valor "$@"; OUTPUT_TYPE="$2"; shift 2 ;;
        -i|--interactive) INTERACTIVE="y"; shift ;;
        -m|--metadata)    precisa_valor "$@"; METADATA_SOURCE="$2"; shift 2 ;;
        --no-progress)    MOSTRAR_PROGRESSO="n"; shift ;;
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
echo " Destino: $DEST_DIR"
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
