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

# Start an SSM session on an EC2 instance; fzf if no ID
function ssm() {
    local profile="${AWS_PROFILE:-}"
    local region="${AWS_REGION:-}"
    local OPTIND opt
    while getopts ":p:r:" opt; do
        case "$opt" in
            p) profile="$OPTARG" ;;
            r) region="$OPTARG" ;;
            \?) echo "ssm: unknown option -$OPTARG" >&2; return 1 ;;
            :)  echo "ssm: -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
        local picked
        picked=$(_ssm_pick "$profile" "$region")
        [[ -z "$picked" ]] && return 1
        set -- "$picked" "$@"
    fi

    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm start-session --target "$1"
}

# Port-forward a local port to a port on an SSM instance
function ssmpf() {
    local profile="${AWS_PROFILE:-}"
    local region="${AWS_REGION:-}"
    local OPTIND opt
    while getopts ":p:r:" opt; do
        case "$opt" in
            p) profile="$OPTARG" ;;
            r) region="$OPTARG" ;;
            \?) echo "ssmpf: unknown option -$OPTARG" >&2; return 1 ;;
            :)  echo "ssmpf: -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
        local picked
        picked=$(_ssm_pick "$profile" "$region")
        [[ -z "$picked" ]] && return 1
        set -- "$picked" "$@"
    fi

    if [[ $# -lt 2 ]]; then
        echo "Usage: ssmpf [-p profile] [-r region] [instance-id] <local-port> [remote-port]" >&2
        return 1
    fi
    local remote_port="${3:-$2}"

    printf '\033[36mSSM port forward\033[0m → %s\n' "$1"
    printf '  localhost:%s → instance:%s\n' "$2" "$remote_port"
    [[ -n "$profile" ]] && printf '  profile: %s\n' "$profile"
    [[ -n "$region"  ]] && printf '  region:  %s\n' "$region"
    printf '  test:  curl http://localhost:%s\n' "$2"
    printf '  close: Ctrl+C\n\n'

    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm start-session --target "$1" \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$2\"]}"
}

# Port-forward through an SSM instance to a remote host
function ssmpfh() {
    local profile="${AWS_PROFILE:-}"
    local region="${AWS_REGION:-}"
    local OPTIND opt
    while getopts ":p:r:" opt; do
        case "$opt" in
            p) profile="$OPTARG" ;;
            r) region="$OPTARG" ;;
            \?) echo "ssmpfh: unknown option -$OPTARG" >&2; return 1 ;;
            :)  echo "ssmpfh: -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
        local picked
        picked=$(_ssm_pick "$profile" "$region")
        [[ -z "$picked" ]] && return 1
        set -- "$picked" "$@"
    fi

    if [[ $# -lt 3 ]]; then
        echo "Usage: ssmpfh [-p profile] [-r region] [instance-id] <remote-host> <remote-port> [local-port]" >&2
        return 1
    fi
    local local_port="${4:-$3}"

    printf '\033[36mSSM port forward\033[0m → %s (via %s)\n' "$2" "$1"
    printf '  localhost:%s → %s:%s\n' "$local_port" "$2" "$3"
    [[ -n "$profile" ]] && printf '  profile: %s\n' "$profile"
    [[ -n "$region"  ]] && printf '  region:  %s\n' "$region"
    printf '  test:  nc -zv localhost %s\n' "$local_port"
    printf '  close: Ctrl+C\n\n'

    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm start-session --target "$1" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$2\"],\"portNumber\":[\"$3\"],\"localPortNumber\":[\"$local_port\"]}"
}

# Run a shell command on an EC2 instance via SSM
function ssmrun() {
    local profile="${AWS_PROFILE:-}"
    local region="${AWS_REGION:-}"
    local OPTIND opt
    while getopts ":p:r:" opt; do
        case "$opt" in
            p) profile="$OPTARG" ;;
            r) region="$OPTARG" ;;
            \?) echo "ssmrun: unknown option -$OPTARG" >&2; return 1 ;;
            :)  echo "ssmrun: -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ ! "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
        local picked
        picked=$(_ssm_pick "$profile" "$region")
        [[ -z "$picked" ]] && return 1
        set -- "$picked" "$@"
    fi

    if [[ $# -lt 2 ]]; then
        echo "Usage: ssmrun [-p profile] [-r region] [instance-id] '<command>'" >&2
        return 1
    fi

    local cmd_id
    cmd_id=$(aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm send-command --instance-ids "$1" \
        --document-name AWS-RunShellScript \
        --parameters "commands=[\"$2\"]" \
        --query 'Command.CommandId' --output text)
    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm wait command-executed --command-id "$cmd_id" --instance-id "$1" 2>/dev/null
    aws ${profile:+--profile "$profile"} \
        ${region:+--region "$region"} \
        ssm get-command-invocation --command-id "$cmd_id" --instance-id "$1" \
        --query 'StandardOutputContent' --output text
}
