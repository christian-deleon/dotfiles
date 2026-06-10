# Category: Kubernetes completions

# internal: complete kc with context names
function _comp_kc() {
    _comp_reply "$(_comp_kctx)"
}
complete -F _comp_kc kc

# internal: complete namespace-taking commands with namespaces
function _comp_kns_cmd() {
    _comp_reply "$(_comp_kns)"
}
complete -F _comp_kns_cmd kn ktns kdp kdd kdelp ks

# internal: complete kcs with kubeconfig file basenames in ~/.kube
function _comp_kcs() {
    local files
    files=$(find "$HOME/.kube" -maxdepth 1 -type f \
        ! -name cache ! -name '*.lock' ! -name 'http-cache*' \
        -printf '%f\n' 2>/dev/null)
    _comp_reply "$files"
}
complete -F _comp_kcs kcs

# internal: kl/ke positional — namespace, then pod, then container
function _comp_kl() {
    case "$COMP_CWORD" in
        1) _comp_reply "$(_comp_kns)" ;;
        2) _comp_reply "$(_comp_kpods "${COMP_WORDS[1]}")" ;;
        3) _comp_reply "$(_comp_kcontainers "${COMP_WORDS[1]}" "${COMP_WORDS[2]}")" ;;
    esac
}
complete -F _comp_kl kl ke

# internal: k9 — contexts after -c, namespaces (+ all) after -n, else flags
function _comp_k9() {
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -c) _comp_reply "$(_comp_kctx)"; return ;;
        -n)
            local ctx="" i
            for ((i=1; i<COMP_CWORD; i++)); do
                [[ "${COMP_WORDS[i]}" == "-c" ]] && ctx="${COMP_WORDS[i+1]}"
            done
            _comp_reply "all $(_comp_kns "$ctx")"
            return ;;
    esac
    _comp_reply "-c -n"
}
complete -F _comp_k9 k9
