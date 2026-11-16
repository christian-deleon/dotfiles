# Parse functions.d fragments and .aliases into tab-separated records for
# `dot help` and scripts/check-descriptions.sh. Each consumer applies its own
# rules; the two views differ on purpose and both are kept as they were.
#
#   awk -f descriptions.awk kind=fn functions.d/*.sh kind=alias .aliases
#
# Records:
#   check <name> <multi 0|1> <desc>      every `function NAME()` header, with the
#                                        comment run right above it
#   func  <name> <category> <desc> <body> functions outside another body, at `}`
#   alias <name> <desc> <category> <cmd>
#
# POSIX awk only (macOS awk, mawk, gawk). Captures mirror bash's
# leftmost-longest `=~` groups.

# Drop leading blanks but keep at least one character, like `[[:space:]]*(.+)`.
function lstrip1(s) {
    while (length(s) > 1 && substr(s, 1, 1) ~ /[[:space:]]/) s = substr(s, 2)
    return s
}

# `^#[[:space:]]*(.+)`; sets cap.
function is_comment(line) {
    if (substr(line, 1, 1) != "#" || length(line) < 2) return 0
    cap = lstrip1(substr(line, 2))
    return 1
}

function reset_file() {
    category = FILENAME
    sub(/.*\//, "", category)
    sub(/\.sh$/, "", category)
    h_comment = ""; h_comment_set = 0; h_in_body = 0; h_name = ""; h_desc = ""; h_body = ""
    c_comment = ""; c_multi = 0; c_prev_comment = 0
    al_cat = "General"; al_new_block = 1
}

FNR == 1 { reset_file() }

kind == "alias" {
    if (is_comment($0)) {
        if (al_new_block) { al_cat = cap; al_new_block = 0 }
    } else if ($0 ~ /^alias[[:space:]]/ && (eq = index($0, "=")) > 0) {
        pre = substr($0, 6, eq - 6)
        rest = substr($0, eq + 1)
        if (length(pre) >= 2 && pre ~ /^[[:space:]]/ && rest != "") {
            name = lstrip1(substr(pre, 2))
            cmd = rest; desc = ""
            for (i = length(rest) - 2; i >= 3; i--) {
                if (substr(rest, i, 1) == "#" && substr(rest, i - 1, 1) ~ /[[:space:]]/ && substr(rest, i + 1, 1) ~ /[[:space:]]/) {
                    cmd = substr(rest, 1, i - 2)
                    desc = lstrip1(substr(rest, i + 2))
                    break
                }
            }
            if (cmd ~ /^'.*'$/ || cmd ~ /^".*"$/) cmd = substr(cmd, 2, length(cmd) - 2)
            gsub(/\t/, " ", cmd)
            printf "alias\t%s\t%s\t%s\t%s\n", name, desc, al_cat, cmd
            al_new_block = 0
        }
    } else if ($0 == "") {
        al_new_block = 1
    }
    next
}

{
    header = ""
    if (match($0, /^function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_-]*\(\)/)) {
        header = substr($0, 9, RLENGTH - 10)
        sub(/^[[:space:]]+/, "", header)
    }

    # check-descriptions view: every header, no body tracking.
    if ($0 ~ /^#[[:space:]]*Category:/) {
        c_comment = ""; c_multi = 0; c_prev_comment = 0
    } else if (is_comment($0)) {
        if (c_prev_comment) c_multi = 1
        else c_comment = cap
        c_prev_comment = 1
    } else if (header != "") {
        printf "check\t%s\t%d\t%s\n", header, c_multi, c_comment
        c_comment = ""; c_multi = 0; c_prev_comment = 0
    } else if ($0 !~ /^[[:space:]]*$/ || $0 == "") {
        c_comment = ""; c_multi = 0; c_prev_comment = 0
    }

    # dot help view: a body runs from the header to a line that is exactly `}`.
    if (h_in_body) {
        if ($0 == "}") {
            printf "func\t%s\t%s\t%s\t%s\n", h_name, category, h_desc, h_body
            h_in_body = 0; h_body = ""
        } else {
            line = $0
            gsub(/\t/, " ", line)
            h_body = h_body " " line
        }
    } else if (is_comment($0) && cap ~ /^Category:./) {
        category = lstrip1(substr(cap, 10))
        h_comment = ""; h_comment_set = 0
    } else if (is_comment($0)) {
        if (!h_comment_set) { h_comment = cap; h_comment_set = 1 }
    } else if (header != "") {
        h_name = header; h_desc = h_comment; h_body = ""; h_in_body = 1
        h_comment = ""; h_comment_set = 0
    } else if ($0 == "") {
        h_comment = ""; h_comment_set = 0
    }
}
