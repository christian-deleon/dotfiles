# Category: Kubernetes

# Set kubeconfig (fzf if no argument)
function kcs() {
    local config="$1"

    # If no argument provided, use fzf to select
    if [[ -z "$config" ]]; then
        config=$(find "$HOME/.kube" -maxdepth 1 -type f ! -name "cache" ! -name "*.lock" ! -name "http-cache*" | \
                 sed "s|$HOME/.kube/||" | \
                 fzf --prompt="Select kubeconfig: " --height=40% --reverse)

        # Exit if no selection made
        if [[ -z "$config" ]]; then
            echo "No kubeconfig selected"
            return 1
        fi
    fi

    # Ensure the kubeconfig exists
    if [[ ! -f "$HOME/.kube/$config" ]]; then
        echo "Kubeconfig $config does not exist"
        return 1
    fi

    export KUBECONFIG=$HOME/.kube/$config
    echo "Switched to kubeconfig: $config"
}

# Set all kubeconfigs
function kca() {
    export KUBECONFIG=$(find "$HOME/.kube" -path "$HOME/.kube/cache" -prune -o -type f -print | sed 's/$/:/' | tr -d '\n' | sed 's/:$//')
}

# Unset the current kubeconfig
function kcu() {
    unset KUBECONFIG
}

# Get all pods excluding system namespaces
function kpa() {
    local pattern="$1"
    local cmd="kubectl get pods --all-namespaces --field-selector 'metadata.namespace!=kube-system,metadata.namespace!=flux-system,metadata.namespace!=metallb-system'"
    if [[ -n "$pattern" ]]; then
        eval "$cmd" | grep -i "$pattern"
    else
        eval "$cmd"
    fi
}

# Cumulative CPU/Memory for a namespace (fzf if no argument)
function ktns() {
    local namespace="$1"
    local awk_script='{cpu+=$2; memory+=$3} END {print "CPU(m):", cpu, " - ", "Memory(Mi):", memory}'

    # If no argument provided, use fzf to select namespace
    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | \
                   tr ' ' '\n' | \
                   fzf --prompt="Select namespace: " --height=40% --reverse)

        # If no selection, use current namespace context
        if [[ -z "$namespace" ]]; then
            echo "Using current namespace context"
            kubectl top pod --no-headers | awk "$awk_script"
            return
        fi
    fi

    echo "Namespace: $namespace"
    kubectl top pod --namespace "$namespace" --no-headers | awk "$awk_script"
}

# Get CPU and Memory usage of each namespace
function ktnsa() {
    kubectl get namespaces -o json | jq -r '.items[] | .metadata.name' | while read -r NAMESPACE; do
        echo "Namespace: $NAMESPACE"
        ktns "$NAMESPACE"
        echo
    done
}

# Set namespace for current context (fzf if no argument)
function kn() {
    local namespace="$1"

    # If no argument provided, use fzf to select
    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | \
                   tr ' ' '\n' | \
                   fzf --prompt="Select namespace: " --height=40% --reverse)

        # Exit if no selection made
        if [[ -z "$namespace" ]]; then
            echo "No namespace selected"
            return 1
        fi
    fi

    kubectl config set-context --current --namespace="$namespace"
    echo "Switched to namespace: $namespace"
}

# Switch kubectl context (uses fzf if no argument provided)
function kc() {
    local context="$1"

    # If no argument provided, use fzf to select
    if [[ -z "$context" ]]; then
        context=$(kubectl config get-contexts -o name | \
                 fzf --prompt="Select context: " --height=40% --reverse)

        # Exit if no selection made
        if [[ -z "$context" ]]; then
            echo "No context selected"
            return 1
        fi
    fi

    kubectl config use-context "$context"
}

# Launch k9s (-c context, -n namespace; fzf if omitted)
function k9() {
    local context="" namespace=""
    local OPTIND opt
    while getopts ":c:n:" opt; do
        case "$opt" in
            c) context="$OPTARG" ;;
            n) namespace="$OPTARG" ;;
            \?) echo "k9: unknown option -$OPTARG" >&2; return 1 ;;
            :)  echo "k9: -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # If no context provided, use fzf to select
    if [[ -z "$context" ]]; then
        context=$(kubectl config get-contexts -o name | \
                 fzf --prompt="Select context: " --height=40% --reverse)

        # Exit if no selection made
        if [[ -z "$context" ]]; then
            echo "No context selected"
            return 1
        fi
    fi

    # If no namespace provided, fzf to select (ESC = all namespaces)
    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl --context "$context" get namespaces -o jsonpath='{.items[*].metadata.name}' | \
                   tr ' ' '\n' | \
                   fzf --prompt="Select namespace (ESC for all): " --height=40% --reverse)
        # ESC/no selection -> k9s "all namespaces" view
        namespace="${namespace:-all}"
    fi

    k9s --context "$context" -n "$namespace"
}

# Delete kubectl contexts + orphaned clusters/users (fzf)
function kcd() {
    local selected

    # Multi-select contexts with fzf (TAB to mark, ENTER to confirm)
    selected=$(kubectl config get-contexts -o name | \
              fzf --multi --prompt="Select contexts to DELETE (TAB to mark): " --height=40% --reverse)

    # Exit if no selection made
    if [[ -z "$selected" ]]; then
        echo "No context selected"
        return 1
    fi

    # Confirmation prompt
    echo "Contexts to delete:"
    echo "$selected" | sed 's/^/  - /'
    echo -n "Delete these contexts and their orphaned clusters/users? (y/n): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 1
    fi

    # Snapshot the full context -> cluster/user mapping before deleting anything
    local config_json
    config_json=$(kubectl config view -o json)

    # Clusters/users referenced by the contexts being deleted (candidates for removal)
    local del_clusters del_users
    del_clusters=$(echo "$config_json" | jq -r --arg sel "$selected" \
        '($sel | split("\n")) as $s | .contexts[] | select(.name as $n | $s | index($n)) | .context.cluster' | sort -u)
    del_users=$(echo "$config_json" | jq -r --arg sel "$selected" \
        '($sel | split("\n")) as $s | .contexts[] | select(.name as $n | $s | index($n)) | .context.user' | sort -u)

    # Clusters/users still referenced by contexts we are keeping (must NOT be removed)
    local keep_clusters keep_users
    keep_clusters=$(echo "$config_json" | jq -r --arg sel "$selected" \
        '($sel | split("\n")) as $s | .contexts[] | select(.name as $n | ($s | index($n)) | not) | .context.cluster' | sort -u)
    keep_users=$(echo "$config_json" | jq -r --arg sel "$selected" \
        '($sel | split("\n")) as $s | .contexts[] | select(.name as $n | ($s | index($n)) | not) | .context.user' | sort -u)

    # Delete the selected contexts
    while IFS= read -r context; do
        [[ -z "$context" ]] && continue
        kubectl config delete-context "$context"
    done <<< "$selected"

    # Delete clusters no longer referenced by any remaining context
    while IFS= read -r cluster; do
        [[ -z "$cluster" ]] && continue
        if grep -qxF "$cluster" <<< "$keep_clusters"; then
            echo "Keeping cluster '$cluster' (still used by another context)"
        else
            kubectl config delete-cluster "$cluster"
        fi
    done <<< "$del_clusters"

    # Delete users no longer referenced by any remaining context
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        if grep -qxF "$user" <<< "$keep_users"; then
            echo "Keeping user '$user' (still used by another context)"
        else
            kubectl config delete-user "$user"
        fi
    done <<< "$del_users"
}

# Stream pod logs (pod/container args optional, else fzf)
function kl() {
    local namespace="${1}"
    local pod_name="${2}"
    local container_name="${3}"

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
                   fzf --prompt="Select pod: " --height=40% --reverse)
        if [[ -z "$pod_name" ]]; then
            echo "No pod selected"
            return 1
        fi
    fi

    if [[ -z "$container_name" ]]; then
        local container_count
        container_count=$(kubectl get pod "$pod_name" $ns_flag -o jsonpath='{.spec.containers[*].name}' | wc -w | tr -d ' ')

        if [[ "$container_count" -gt 1 ]]; then
            container_name=$(kubectl get pod "$pod_name" $ns_flag -o jsonpath='{.spec.containers[*].name}' | \
                            tr ' ' '\n' | \
                            fzf --prompt="Select container: " --height=40% --reverse)
            if [[ -z "$container_name" ]]; then
                echo "No container selected"
                return 1
            fi
        fi
    fi

    if [[ -n "$container_name" ]]; then
        kubectl logs "$pod_name" $ns_flag -c "$container_name"
    else
        kubectl logs "$pod_name" $ns_flag
    fi
}

# Exec into a pod (pod/container args optional, else fzf)
function ke() {
    local namespace="${1}"
    local pod_name="${2}"
    local container_name="${3}"

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
                   fzf --prompt="Select pod: " --height=40% --reverse)
        if [[ -z "$pod_name" ]]; then
            echo "No pod selected"
            return 1
        fi
    fi

    if [[ -z "$container_name" ]]; then
        local container_count
        container_count=$(kubectl get pod "$pod_name" $ns_flag -o jsonpath='{.spec.containers[*].name}' | wc -w | tr -d ' ')

        if [[ "$container_count" -gt 1 ]]; then
            container_name=$(kubectl get pod "$pod_name" $ns_flag -o jsonpath='{.spec.containers[*].name}' | \
                            tr ' ' '\n' | \
                            fzf --prompt="Select container: " --height=40% --reverse)
            if [[ -z "$container_name" ]]; then
                echo "No container selected"
                return 1
            fi
        fi
    fi

    if [[ -n "$container_name" ]]; then
        kubectl exec -it "$pod_name" $ns_flag -c "$container_name" -- /bin/sh
    else
        kubectl exec -it "$pod_name" $ns_flag -- /bin/sh
    fi
}

# Describe a pod (uses fzf to select pod)
function kdp() {
    local namespace="${1}"
    local pod_name

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    # Select pod with fzf
    pod_name=$(kubectl get pods $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
              fzf --prompt="Select pod: " --height=40% --reverse)

    if [[ -z "$pod_name" ]]; then
        echo "No pod selected"
        return 1
    fi

    kubectl describe pod "$pod_name" $ns_flag
}

# Delete a pod (uses fzf to select pod, requires confirmation)
function kdelp() {
    local namespace="${1}"
    local pod_name

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    # Select pod with fzf
    pod_name=$(kubectl get pods $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
              fzf --prompt="Select pod to DELETE: " --height=40% --reverse)

    if [[ -z "$pod_name" ]]; then
        echo "No pod selected"
        return 1
    fi

    # Confirmation prompt
    echo -n "Delete pod '$pod_name'? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        kubectl delete pod "$pod_name" $ns_flag
    else
        echo "Cancelled"
    fi
}

# Describe a deployment (uses fzf to select deployment)
function kdd() {
    local namespace="${1}"
    local deployment_name

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    # Select deployment with fzf
    deployment_name=$(kubectl get deployments $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
                     fzf --prompt="Select deployment: " --height=40% --reverse)

    if [[ -z "$deployment_name" ]]; then
        echo "No deployment selected"
        return 1
    fi

    kubectl describe deployment "$deployment_name" $ns_flag
}

# Scale a deployment (uses fzf to select deployment)
function ks() {
    local namespace="${1}"
    local replicas="${2}"
    local deployment_name

    # If namespace provided, use it; otherwise use current context namespace
    local ns_flag=""
    if [[ -n "$namespace" ]] && [[ ! "$namespace" =~ ^[0-9]+$ ]]; then
        ns_flag="-n $namespace"
    else
        # First arg is likely replicas, not namespace
        replicas="$namespace"
        namespace=""
    fi

    # Select deployment with fzf
    deployment_name=$(kubectl get deployments $ns_flag -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
                     fzf --prompt="Select deployment: " --height=40% --reverse)

    if [[ -z "$deployment_name" ]]; then
        echo "No deployment selected"
        return 1
    fi

    # Prompt for replicas if not provided
    if [[ -z "$replicas" ]]; then
        echo -n "Number of replicas: "
        read -r replicas
    fi

    if [[ ! "$replicas" =~ ^[0-9]+$ ]]; then
        echo "Invalid replica count: $replicas"
        return 1
    fi

    kubectl scale deployment "$deployment_name" $ns_flag --replicas="$replicas"
}
