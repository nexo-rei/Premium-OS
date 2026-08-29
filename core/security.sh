#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/security.sh
# Cyber Lock (SHA-256 password hashing), backup encryption helpers,
# input sanitization for shell-facing operations.
#==============================================================================

[[ -n "${_POS_CORE_SECURITY_LOADED:-}" ]] && return 0
_POS_CORE_SECURITY_LOADED=1

# Requires core/utils.sh

POS_SEC_SETTINGS="${POS_HOME:-$HOME/.premium-os}/settings.json"
POS_SECURE_FILE="${POS_HOME:-$HOME/.premium-os}/cache/.secure"

#----------------------------------------
# Hash helper: SHA-256 with a per-install salt
#----------------------------------------
_pos_salt_file() {
    local f="${POS_HOME:-$HOME/.premium-os}/.salt"
    if [[ ! -f "$f" ]]; then
        { date +%s%N; cat /proc/sys/kernel/random/uuid 2>/dev/null; } \
            | sha256sum 2>/dev/null | awk '{print $1}' > "$f" 2>/dev/null
        chmod 600 "$f" 2>/dev/null
    fi
    cat "$f" 2>/dev/null
}

pos_hash_password() { # $1=plaintext → salted sha256 hex
    local salt; salt=$(_pos_salt_file)
    printf '%s::%s' "$salt" "$1" | sha256sum 2>/dev/null | awk '{print $1}'
}

#----------------------------------------
# Cyber Lock lifecycle
#----------------------------------------
cyber_lock_is_enabled() {
    [[ "$(pos_json_get "$POS_SEC_SETTINGS" security.cyber_lock_enabled)" == "true" ]]
}

cyber_lock_setup() {
    local p1 p2
    printf '%b' "${POS_YELLOW}Set Cyber Lock password:${POS_RESET} "
    read -rs p1; echo
    printf '%b' "${POS_YELLOW}Confirm password:${POS_RESET} "
    read -rs p2; echo
    if [[ -z "$p1" || "$p1" != "$p2" ]]; then
        pos_error "Passwords empty or mismatched."
        return 1
    fi
    local hash; hash=$(pos_hash_password "$p1"); p1=""; p2=""
    pos_json_set "$POS_SEC_SETTINGS" security.lock_hash "$hash" >/dev/null
    pos_json_set "$POS_SEC_SETTINGS" security.cyber_lock_enabled true bool >/dev/null
    pos_ok "Cyber Lock enabled."
}

cyber_lock_disable() {
    pos_json_set "$POS_SEC_SETTINGS" security.cyber_lock_enabled false bool >/dev/null
    pos_json_set "$POS_SEC_SETTINGS" security.lock_hash "" >/dev/null
    pos_ok "Cyber Lock disabled."
}

# cyber_lock_verify → 0 ok, 1 fail; up to 3 attempts
cyber_lock_verify() {
    cyber_lock_is_enabled || return 0
    local stored attempt tries=0
    stored=$(pos_json_get "$POS_SEC_SETTINGS" security.lock_hash)
    [[ -z "$stored" ]] && return 0
    while (( tries < 3 )); do
        printf '%b' "\n${POS_PINK}🔒 Premium-OS locked.${POS_RESET} ${POS_YELLOW}Password:${POS_RESET} "
        read -rs attempt; echo
        [[ "$(pos_hash_password "$attempt")" == "$stored" ]] && { attempt=""; return 0; }
        attempt=""; ((tries++))
        pos_error "Wrong password ($tries/3)."
    done
    return 1
}

#----------------------------------------
# Backup encryption (AES-256 via openssl when available)
#----------------------------------------
pos_aes_available() { command -v openssl >/dev/null 2>&1; }

pos_encrypt_file() { # $1=in $2=out $3=password
    pos_aes_available || return 2
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$1" -out "$2" -pass "pass:$3" 2>/dev/null
}

pos_decrypt_file() { # $1=in $2=out $3=password
    pos_aes_available || return 2
    openssl enc -d -aes-256-cbc -pbkdf2 -in "$1" -out "$2" -pass "pass:$3" 2>/dev/null
}

#----------------------------------------
# Input sanitization for paths — prevent command injection
#----------------------------------------
pos_sanitize_path() {
    local p="$1"
    # Reject shell metacharacters that smuggle in extra commands
    local bad_re='[;|&$`><()]'
    if [[ "$p" =~ $bad_re ]]; then
        echo ""
        return 1
    fi
    echo "$p"
}

pos_secure_store() { # $1=key $2=value → append to obfuscated secure file
    echo "$1=$(printf '%s' "$2" | base64)" >> "$POS_SECURE_FILE"
    chmod 600 "$POS_SECURE_FILE" 2>/dev/null
}

pos_secure_read() { # $1=key → decoded value
    [[ -f "$POS_SECURE_FILE" ]] || return 1
    local line; line=$(grep "^$1=" "$POS_SECURE_FILE" | tail -1)
    [[ -n "$line" ]] && printf '%s' "${line#*=}" | base64 -d 2>/dev/null
}
