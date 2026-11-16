# shellcheck shell=bash
# Prebuilt release binaries, from a manifest item's install.release:
#   repo    GitHub owner/name; the latest tag comes from the
#           /releases/latest redirect (no rate-limited API), files from
#           /releases/download/{tag}/<asset>
#   asset   file name in the release
#   latest  URL used instead of repo's to find the tag: the last path segment
#           of its redirect, or its body when it does not redirect
#   url     download URL used instead of repo + asset
#   bin     name or list of names to install (default install.command, else
#           the item)
#   sums    checksum file (name next to the download, or a URL) holding
#           "<sha256>  <file>" lines or one bare hash
#   os      supported OS (linux, darwin) -> upstream name; default {linux: linux}
#   arch    supported arch (x86_64, aarch64) -> upstream name; default identity
# Templates take {version} (the tag without a leading v), {tag}, {os} and
# {arch}; sums also takes {asset}. A .tar.gz/.tgz/.tar.xz/.zip download is
# searched for each bin at its top, one directory down, or in a bin/ dir;
# any other download is the binary itself. Binaries land in
# ${DOTFILES_BIN_DIR:-~/.local/bin}, mode 755, without sudo.

release_bin_dir() {
    printf '%s\n' "${DOTFILES_BIN_DIR:-$HOME/.local/bin}"
}

# Put the release bin dir on PATH (as .commonrc does) so presence checks see
# what earlier runs installed even from a shell that has not sourced it.
release_path_add() {
    local dir="${DOTFILES_BIN_DIR:-$HOME/.local/bin}"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir:$PATH" ;;
    esac
}

# This host as release os/arch names: linux|darwin and x86_64|aarch64.
release_host() {
    local os arch
    case "$(uname -s)" in
        Linux) os=linux ;;
        Darwin) os=darwin ;;
        *) os="$(uname -s)" ;;
    esac
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) arch="$(uname -m)" ;;
    esac
    printf '%s %s\n' "$os" "$arch"
}

# Replace {key} with value for each key/value pair, literally (no glob or
# & handling in the value).
#   _release_fill <template> <key> <value> [<key> <value>...]
_release_fill() {
    local s="$1" k v out
    shift
    while [[ $# -ge 2 ]]; do
        k="{$1}" v="$2" out=""
        shift 2
        while [[ "$s" == *"$k"* ]]; do
            out+="${s%%"$k"*}$v"
            s="${s#*"$k"}"
        done
        s="$out$s"
    done
    printf '%s' "$s"
}

# Resolve a release spec (JSON) for one os/arch. Prints one 0x1F row:
#   ok <latest-url> <download-url-template> <sums-template> <bins>
#   unsupported <reason>
# Templates still hold {tag}/{version}; {os}/{arch} are filled in.
_release_plan() {
    local spec="$1" os="$2" arch="$3" row status latest url sums bins
    row="$(jq -r --arg os "$os" --arg arch "$arch" '
        . as $s
        | (($s.os // {linux: "linux"})[$os]) as $o
        | (($s.arch // {x86_64: "x86_64", aarch64: "aarch64"})[$arch]) as $a
        | if $o == null then ["unsupported", "no release for \($os)"]
          elif $a == null then ["unsupported", "no release for \($os)/\($arch)"]
          elif ($s.repo == null) and ($s.latest == null or $s.url == null) then
            ["unsupported", "release needs repo, or latest and url"]
          else ["ok", $o, $a,
                ($s.latest // "https://github.com/\($s.repo)/releases/latest"),
                ($s.url // "https://github.com/\($s.repo)/releases/download/{tag}/\($s.asset)"),
                ($s.sums // ""),
                ([$s.bin] | flatten | map(select(. != null)) | join(" "))]
          end
        | map(tostring) + ["$"] | join("\u001f")' <<<"$spec")" || return 1
    IFS=$'\x1f' read -r status os arch latest url sums bins _ <<<"$row"
    if [[ "$status" != ok ]]; then
        printf '%s\x1f%s\x1f$\n' "$status" "$os"
        return 0
    fi
    url="$(_release_fill "$url" os "$os" arch "$arch")"
    sums="$(_release_fill "$sums" os "$os" arch "$arch")"
    printf 'ok\x1f%s\x1f%s\x1f%s\x1f%s\x1f$\n' "$latest" "$url" "$sums" "$bins"
}

# Print the latest tag behind a "latest" URL: the last path segment of its
# redirect, or the first line of its body when it answers 200.
release_latest_tag() {
    local url="$1" out meta code loc tag
    if ! out="$(curl -sS --max-time 30 -w '\n%{http_code} %{redirect_url}' "$url")"; then
        _error "Could not reach $url"
        return 1
    fi
    meta="${out##*$'\n'}"
    code="${meta%% *}"
    loc="${meta#* }"
    case "$code" in
        301 | 302 | 303 | 307 | 308)
            loc="${loc%/}"
            tag="${loc##*/}"
            ;;
        200)
            out="${out%$'\n'*}"
            tag="${out%%$'\n'*}"
            tag="${tag//[[:space:]]/}"
            ;;
        *)
            _error "$url answered HTTP $code"
            return 1
            ;;
    esac
    case "$tag" in
        "" | releases | latest | *[!A-Za-z0-9._+-]*)
            _error "No release tag found at $url"
            return 1
            ;;
    esac
    printf '%s\n' "$tag"
}

_release_sha256() {
    local out
    if command -v sha256sum &>/dev/null; then
        out="$(sha256sum -- "$1")" || return 1
    else
        out="$(shasum -a 256 -- "$1")" || return 1
    fi
    printf '%s\n' "${out%% *}"
}

# The hash for <asset> in a checksum file: its "<hash>  <asset>" line, or the
# only hash in a one-line file.
_release_expected_sum() {
    local file="$1" asset="$2" hash name lines=0 only=""
    while read -r hash name _ || [[ -n "$hash" ]]; do
        [[ -n "$hash" ]] || continue
        lines=$((lines + 1))
        name="${name#\*}"
        name="${name#./}"
        if [[ "$name" == "$asset" ]]; then
            printf '%s\n' "$hash"
            return 0
        fi
        [[ -z "$name" ]] && only="$hash"
    done <"$file"
    if [[ "$lines" -eq 1 && -n "$only" ]]; then
        printf '%s\n' "$only"
        return 0
    fi
    return 1
}

# Download, verify and install one release. Runs in a subshell so the temp
# dir trap stays local to it.
#   _release_fetch <name> <latest-url> <url-template> <sums-template> <bins> <dir>
_release_fetch() (
    name="$1" latest="$2" url="$3" sums="$4" bins="$5" dir="$6"
    tag="$(release_latest_tag "$latest")" || exit 1
    version="${tag#v}"
    url="$(_release_fill "$url" tag "$tag" version "$version")"
    asset="${url##*/}"

    tmp="$(mktemp -d)" || exit 1
    trap 'rm -rf -- "$tmp"' EXIT

    _info "Downloading ${_BOLD}$name${_RESET} $tag ($asset)..."
    if ! curl -fsSL --retry 2 -o "$tmp/$asset" "$url"; then
        _error "Download failed: $url"
        exit 1
    fi

    if [[ -n "$sums" ]]; then
        sums="$(_release_fill "$sums" tag "$tag" version "$version" asset "$asset")"
        case "$sums" in
            *://*) ;;
            *) sums="${url%/*}/$sums" ;;
        esac
        if ! curl -fsSL --retry 2 -o "$tmp/.sums" "$sums"; then
            _error "Could not download checksums: $sums"
            exit 1
        fi
        if ! want="$(_release_expected_sum "$tmp/.sums" "$asset")"; then
            _error "No checksum for $asset in $sums"
            exit 1
        fi
        got="$(_release_sha256 "$tmp/$asset")" || exit 1
        if [[ "$got" != "$want" ]]; then
            _error "Checksum mismatch for $asset (expected $want, got $got)"
            exit 1
        fi
    fi

    mkdir -p "$tmp/x" || exit 1
    case "$asset" in
        *.tar.gz | *.tgz) tar -xzf "$tmp/$asset" -C "$tmp/x" || exit 1 ;;
        *.tar.xz) tar -xJf "$tmp/$asset" -C "$tmp/x" || exit 1 ;;
        *.zip) unzip -q "$tmp/$asset" -d "$tmp/x" || exit 1 ;;
        *)
            case "$bins" in
                *" "*)
                    _error "$asset is a single file but $name lists several binaries"
                    exit 1
                    ;;
            esac
            mv -- "$tmp/$asset" "$tmp/x/$bins" || exit 1
            ;;
    esac

    IFS=' ' read -r -a names <<<"$bins"
    srcs=()
    for b in "${names[@]}"; do
        src=""
        for c in "$tmp/x/$b" "$tmp/x"/*/"$b" "$tmp/x/bin/$b" "$tmp/x"/*/bin/"$b"; do
            if [[ -f "$c" ]]; then
                src="$c"
                break
            fi
        done
        if [[ -z "$src" ]]; then
            _error "$b not found in $asset"
            exit 1
        fi
        srcs+=("$src")
    done

    mkdir -p -- "$dir" || exit 1
    i=0
    for b in "${names[@]}"; do
        if ! { cp -- "${srcs[i]}" "$dir/.$b.new" && chmod 755 "$dir/.$b.new" &&
            mv -f -- "$dir/.$b.new" "$dir/$b"; }; then
            rm -f -- "$dir/.$b.new"
            _error "Could not install $dir/$b"
            exit 1
        fi
        i=$((i + 1))
    done
    _success "Installed ${_BOLD}$name${_RESET} $tag to ${_DIM}$dir${_RESET}"
)

# Install a release from a JSON spec (see the top of this file).
#   release_install_spec [--force] <name> <spec-json>
# Without --force, a no-op when the first bin is already on PATH.
release_install_spec() {
    local force=0
    if [[ "${1:-}" == --force ]]; then
        force=1
        shift
    fi
    local name="$1" spec="$2" host row status latest url sums bins first
    ensure_jq || return 1
    release_path_add
    host="$(release_host)"
    row="$(_release_plan "$spec" "${host% *}" "${host#* }")" || return 1
    IFS=$'\x1f' read -r status latest url sums bins _ <<<"$row"
    if [[ "$status" != ok ]]; then
        _error "Cannot install $name: $latest"
        return 1
    fi
    [[ -n "$bins" ]] || bins="$name"
    first="${bins%% *}"
    if ((! force)) && command -v "$first" &>/dev/null; then
        return 0
    fi
    _release_fetch "$name" "$latest" "$url" "$sums" "$bins" "$(release_bin_dir)"
}

# Install a manifest item's install.release.
#   release_install [--force] <item>
release_install() {
    local force=""
    if [[ "${1:-}" == --force ]]; then
        force=--force
        shift
    fi
    local item="$1" spec
    data_load_manifest || return 1
    spec="$(jq -c --arg i "$item" '.[$i] | select(.install.release != null)
        | .install.release + {bin: (.install.release.bin // .install.command // $i)}' <<<"$_MANIFEST_JSON")"
    if [[ -z "$spec" ]]; then
        _error "$item has no install.release in manifest.yaml"
        return 1
    fi
    release_install_spec ${force:+"$force"} "$item" "$spec"
}
