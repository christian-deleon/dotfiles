# Category: AWS

# internal: pick an SSM-managed instance ID via fzf
function _ssm_pick() {
    local profile="$1" region="$2"
    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm describe-instance-information \
        --query 'InstanceInformationList[].[InstanceId,ComputerName,IPAddress]' \
        --output text \
        | fzf --header="Pick SSM instance" | awk '{print $1}'
}

# internal: parse ssm* wrapper args; echo shell code to set profile/region/instance
function _ssm_resolve() {
    # Parses [-p profile] [-r region] [instance-id] from the caller's args and
    # echoes shell code the caller evals. Sets `profile`, `region`, `instance`
    # and rewrites the caller's $@ to the remaining args.
    #
    # `eval` is used because bash functions can't return multiple values or
    # mutate the caller's positional params. Args are shell-quoted with %q.
    #
    # `profile` is only set when -p is explicitly passed; AWS_PROFILE from the
    # env is NOT inherited as --profile, because doing so makes the AWS CLI
    # ignore session env credentials (e.g. from `assume`) and resolve from the
    # profile config instead — causing spurious SSO refreshes. Leaving
    # --profile off lets the CLI's normal env-vars-first resolution kick in.
    local fn="$1"; shift
    local profile="" region="${AWS_REGION:-}"
    local OPTIND opt
    while getopts ":p:r:" opt; do
        case "$opt" in
            p) profile="$OPTARG" ;;
            r) region="$OPTARG" ;;
            \?) printf 'echo %q >&2; return 1' "$fn: unknown option -$OPTARG"; return ;;
            :)  printf 'echo %q >&2; return 1' "$fn: -$OPTARG requires an argument"; return ;;
        esac
    done
    shift $((OPTIND - 1))

    local instance="${1:-}"
    if [[ "$instance" =~ ^i-[0-9a-f]+$ ]]; then
        shift
    else
        instance=$(_ssm_pick "$profile" "$region")
        [[ -z "$instance" ]] && { printf 'return 1'; return; }
    fi

    printf 'profile=%q; region=%q; instance=%q; set --' "$profile" "$region" "$instance"
    printf ' %q' "$@"
}

# internal: invoke aws, passing --profile/--region only when set by the caller
function _ssm_aws() {
    # Relies on `profile` and `region` being local in the caller's scope,
    # which _ssm_resolve sets via eval.
    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        "$@"
}

# Start an SSM session on an EC2 instance; fzf if no ID
function ssm() {
    local profile region instance
    eval "$(_ssm_resolve ssm "$@")" || return
    _ssm_aws ssm start-session --target "$instance"
}

# Port-forward a local port to a port on an SSM instance
function ssmpf() {
    local profile region instance
    eval "$(_ssm_resolve ssmpf "$@")" || return

    if [[ $# -lt 1 ]]; then
        echo "Usage: ssmpf [-p profile] [-r region] [instance-id] <local-port> [remote-port]" >&2
        return 1
    fi
    local local_port="$1" remote_port="${2:-$1}"

    printf '\033[36mSSM port forward\033[0m → %s\n' "$instance"
    printf '  localhost:%s → instance:%s\n' "$local_port" "$remote_port"
    [[ -n "$profile" ]] && printf '  profile: %s\n' "$profile"
    [[ -n "$region"  ]] && printf '  region:  %s\n' "$region"
    printf '  test:  curl http://localhost:%s\n' "$local_port"
    printf '  close: Ctrl+C\n\n'

    _ssm_aws ssm start-session --target "$instance" \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$local_port\"]}"
}

# Port-forward through an SSM instance to a remote host
function ssmpfh() {
    local profile region instance
    eval "$(_ssm_resolve ssmpfh "$@")" || return

    if [[ $# -lt 2 ]]; then
        echo "Usage: ssmpfh [-p profile] [-r region] [instance-id] <remote-host> <remote-port> [local-port]" >&2
        return 1
    fi
    local remote_host="$1" remote_port="$2" local_port="${3:-$2}"

    printf '\033[36mSSM port forward\033[0m → %s (via %s)\n' "$remote_host" "$instance"
    printf '  localhost:%s → %s:%s\n' "$local_port" "$remote_host" "$remote_port"
    [[ -n "$profile" ]] && printf '  profile: %s\n' "$profile"
    [[ -n "$region"  ]] && printf '  region:  %s\n' "$region"
    printf '  test:  nc -zv localhost %s\n' "$local_port"
    printf '  close: Ctrl+C\n\n'

    _ssm_aws ssm start-session --target "$instance" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$remote_host\"],\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$local_port\"]}"
}

# Run a shell command on an EC2 instance via SSM
function ssmrun() {
    local profile region instance
    eval "$(_ssm_resolve ssmrun "$@")" || return

    if [[ $# -lt 1 ]]; then
        echo "Usage: ssmrun [-p profile] [-r region] [instance-id] '<command>'" >&2
        return 1
    fi
    local command="$1"

    local cmd_id
    cmd_id=$(_ssm_aws ssm send-command --instance-ids "$instance" \
        --document-name AWS-RunShellScript \
        --parameters "commands=[\"$command\"]" \
        --query 'Command.CommandId' --output text)
    _ssm_aws ssm wait command-executed --command-id "$cmd_id" --instance-id "$instance" 2>/dev/null
    _ssm_aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance" \
        --query 'StandardOutputContent' --output text
}
