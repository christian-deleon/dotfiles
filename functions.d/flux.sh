# Category: Flux

# Flux resource picker (reconcile/suspend/resume/events)
function fx() {
    if ! command -v flux &>/dev/null; then
        echo "Error: flux is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    local list
    list=$(
        flux get kustomization -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "Kustomization", $1, $2}'
        flux get helmrelease -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "HelmRelease", $1, $2}'
        flux get source git -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "GitRepository", $1, $2}'
        flux get source helm -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "HelmRepository", $1, $2}'
        flux get source oci -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "OCIRepository", $1, $2}'
        flux get source bucket -A --no-header 2>/dev/null \
            | awk 'NF{printf "%-15s %s/%s\n", "Bucket", $1, $2}'
    )
    if [[ -z "$list" ]]; then
        echo "No Flux resources found (context: $(kubectl config current-context 2>/dev/null))"
        return 1
    fi

    local out key
    out=$(echo "$list" | fzf \
        --prompt="flux: " \
        --height=70% \
        --reverse \
        --header=$'ENTER: reconcile  |  Ctrl-S: suspend\nCtrl-R: resume    |  Ctrl-E: events' \
        --expect=ctrl-s,ctrl-r,ctrl-e \
        --preview='kubectl describe -n $(echo {2} | cut -d/ -f1) {1}/$(echo {2} | cut -d/ -f2) 2>/dev/null | head -80' \
        --preview-window=right:60%:wrap)
    [[ -z "$out" ]] && return 0

    key=$(head -n1 <<< "$out")
    local line
    line=$(tail -n +2 <<< "$out" | head -n1)
    [[ -z "$line" ]] && return 0

    local kind ns_name namespace name cli_kind
    kind=$(awk '{print $1}' <<< "$line")
    ns_name=$(awk '{print $2}' <<< "$line")
    namespace="${ns_name%%/*}"
    name="${ns_name#*/}"

    case "$kind" in
        Kustomization)  cli_kind="kustomization" ;;
        HelmRelease)    cli_kind="helmrelease" ;;
        GitRepository)  cli_kind="source git" ;;
        HelmRepository) cli_kind="source helm" ;;
        OCIRepository)  cli_kind="source oci" ;;
        Bucket)         cli_kind="source bucket" ;;
        *) echo "unknown kind: $kind" >&2; return 1 ;;
    esac

    # $cli_kind intentionally unquoted: "source git" must word-split into two args.
    case "$key" in
        ctrl-s) flux suspend $cli_kind "$name" -n "$namespace" ;;
        ctrl-r) flux resume $cli_kind "$name" -n "$namespace" ;;
        ctrl-e) flux events --for "$kind/$name" -n "$namespace" ;;
        "")     flux reconcile $cli_kind "$name" -n "$namespace" ;;
    esac
}

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
