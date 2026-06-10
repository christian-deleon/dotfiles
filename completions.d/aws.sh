# Category: AWS completions

# internal: complete -p profiles / -r regions for SSM + EKS helpers ($1=flags)
function _comp_aws_pr() {
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -p) _comp_reply "$(_comp_aws_profiles)"; return ;;
        -r) _comp_reply "$(_comp_aws_regions)"; return ;;
    esac
    _comp_reply "${1:--p -r}"
}

# internal: complete ssm helpers (-p, -r; instance IDs left to fzf)
function _comp_ssm() {
    _comp_aws_pr "-p -r"
}
complete -F _comp_ssm ssm ssmpf ssmpfh ssmrun

# internal: complete eksc (-p, -r, -a; cluster name left to fzf)
function _comp_eksc() {
    _comp_aws_pr "-p -r -a"
}
complete -F _comp_eksc eksc
