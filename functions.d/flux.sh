# Category: Flux

# Push and reconcile matching Flux source + kustomizations
function fpush() {
    git rev-parse --git-dir &>/dev/null || { echo "Error: not in a git repo" >&2; return 1; }
    command -v kubectl &>/dev/null || { echo "Error: kubectl not found" >&2; return 1; }
    command -v flux &>/dev/null || { echo "Error: flux not found" >&2; return 1; }
    command -v jq &>/dev/null || { echo "Error: jq not found" >&2; return 1; }

    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null) || {
        echo "Error: no 'origin' remote configured" >&2
        return 1
    }

    echo "→ git push $*"
    git push "$@" || return 1

    # Normalize remote URL to host/owner/repo (strip scheme, user, .git, trailing /)
    local normalized basename
    normalized=$(printf '%s\n' "$remote_url" | sed -E \
        -e 's#^git@([^:]+):#\1/#' \
        -e 's#^ssh://(git@)?##' \
        -e 's#^https?://##' \
        -e 's#\.git$##' \
        -e 's#/$##')
    basename="${normalized##*/}"

    local sources
    sources=$(kubectl get gitrepositories.source.toolkit.fluxcd.io -A -o json 2>/dev/null) || {
        echo "Error: failed to query GitRepositories (context: $(kubectl config current-context 2>/dev/null))" >&2
        return 1
    }

    # Match by normalized URL first, fall back to basename
    local matches
    matches=$(printf '%s' "$sources" | jq -r --arg n "$normalized" '
        .items[]
        | (.spec.url
           | sub("^git@(?<h>[^:]+):"; "\(.h)/")
           | sub("^ssh://(git@)?"; "")
           | sub("^https?://"; "")
           | sub("\\.git$"; "")
           | sub("/$"; "")) as $url
        | select($url == $n)
        | "\(.metadata.namespace)/\(.metadata.name)"
    ')

    if [[ -z "$matches" ]]; then
        matches=$(printf '%s' "$sources" | jq -r --arg b "$basename" '
            .items[]
            | (.spec.url | sub("\\.git$"; "") | split("/") | last) as $base
            | select($base == $b)
            | "\(.metadata.namespace)/\(.metadata.name)"
        ')
        [[ -n "$matches" ]] && echo "→ no exact URL match; matched by basename: $basename"
    fi

    if [[ -z "$matches" ]]; then
        echo "Error: no GitRepository matches $remote_url" >&2
        echo "  context: $(kubectl config current-context 2>/dev/null)" >&2
        return 1
    fi

    local ns name
    while IFS=/ read -r ns name; do
        [[ -z "$ns" || -z "$name" ]] && continue
        echo "→ flux reconcile source git $name -n $ns"
        flux reconcile source git "$name" -n "$ns" || return 1

        # Cascade: reconcile every Kustomization that references this source
        local ks_list ks_ns ks_name
        ks_list=$(kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o json 2>/dev/null | \
            jq -r --arg sns "$ns" --arg sname "$name" '
                .items[]
                | select(.spec.sourceRef.kind == "GitRepository"
                         and .spec.sourceRef.name == $sname
                         and ((.spec.sourceRef.namespace // .metadata.namespace) == $sns))
                | "\(.metadata.namespace)/\(.metadata.name)"
            ')
        while IFS=/ read -r ks_ns ks_name; do
            [[ -z "$ks_ns" || -z "$ks_name" ]] && continue
            echo "→ flux reconcile kustomization $ks_name -n $ks_ns"
            flux reconcile kustomization "$ks_name" -n "$ks_ns" || return 1
        done <<< "$ks_list"
    done <<< "$matches"
}
