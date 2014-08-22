ID_MAP_USER_FILE=/etc/subuid
ID_MAP_USER_FILE_BKP="${ID_MAP_USER_FILE}.lxc-backup"

ID_MAP_GROUP_FILE=/etc/subgid
ID_MAP_GROUP_FILE_BKP="${ID_MAP_GROUP_FILE}.lxc-backup"

ID_MAP_DEFAUlT_RANGE=100000

is_num()
{
    local s
    for s in "$@"; do
        expr "$s" 1>/dev/null 2>&1
        if (( $? == 2 )); then
            return 1
        fi
    done

    return 0
}

id_map_next_available_id()
{
    local file="$1" id_range="$2"

    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Error: ${FUNCNAME}: invalid or inaccesible file" >&2
        return 1
    fi

    if ! (( id_range )); then
        echo "Error: ${FUNCNAME}: invalid range"
        return 1
    fi

    local -i id_global_start=$ID_MAP_DEFAUlT_RANGE id_max=0 entry_max=0

    while IFS=':' read -r entry_user id_start id_count; do
        entry_max=$(( id_start + id_count )) 
        if (( entry_max > id_max )); then
            (( id_max = entry_max ))
        fi
    done < "$file"

    if (( id_max == 0 )); then
        (( id_max = id_global_start ))
    else
        local -i remainder=$(( id_max % id_range ))
        if (( remainder != 0 )); then
            (( id_max += id_chunk - remainder ))
        fi
    fi

    echo "$id_max"
    return 0
}

id_map_user_next_available_id()
{
    id_map_next_available_id "$ID_MAP_USER_FILE" "$@"
}

id_map_group_next_available_id()
{
    id_map_next_available_id "$ID_MAP_GROUP_FILE" "$@"
}

id_map_add()
{
    local file="$1" user="$2" dest="$3" range="$4"
    if [[ -z "$user" ]] || ! is_num "$dest" "$range"; then
        return 1
    fi

    local line="${user}:${dest}:${range}"
    if grep -q -F -x "$line" "$file"; then
        return 0
    fi

    (
        cat "$file"
        echo "$line"
    ) > "${file}.tmp" || return 1

    mv "${file}.tmp" "$file" || return 1
    return 0
}

id_map_user_add()
{
    id_map_add "$ID_MAP_USER_FILE" "$@"
}

id_map_group_add()
{
    id_map_add "$ID_MAP_GROUP_FILE" "$@"
}

id_map_add_from_lxc_cfg()
(
    set -e

    local config_file="$1"
    lxc_cfg_check_file "$config_file"

    local uid_map gid_map
    lxc_cfg_userns_get "$config_file" uid_map gid_map

    if [[ -n "$uid_map" ]]; then
        local uid_src uid_dest uid_range
        id_map_parse "$uid_map" uid_src uid_dest uid_range

        cp "$ID_MAP_USER_FILE" "$ID_MAP_USER_FILE_BKP"
        id_map_user_add root $uid_dest $uid_range
    fi

    if [[ -n "$gid_map" ]]; then
        local gid_src gid_dest gid_range
        id_map_parse "$gid_map" gid_src gid_dest gid_range

        cp "$ID_MAP_GROUP_FILE" "$ID_MAP_GROUP_FILE_BKP"
        id_map_group_add root $gid_dest $gid_range
    fi

    return 0
)

id_map_commit()
{
    rm -f "$ID_MAP_USER_FILE_BKP" "$ID_MAP_GROUP_FILE_BKP"
}

id_map_rollback()
{
    mv "$ID_MAP_USER_FILE_BKP" "$ID_MAP_USER_FILE"
    mv "$ID_MAP_GROUP_FILE_BKP" "$ID_MAP_GROUP_FILE"
}

id_map_parse()
{
    local map="$1" src_var="$2" dest_var="$3" range_var="$4"
    if [[ -z "$map" || -z "$src_var" || -z "$dest_var" || -z "$range_var" ]]; then
        return 1
    fi

    local _src _dest _range
    read -r _src _dest _range <<< "$map" || return 1
    is_num "$_src" "$_dest" "$_range" || return 1

    eval "$src_var"=\$_src
    eval "$dest_var"=\$_dest
    eval "$range_var"=\$_range

    return 0
}

_lxc_cfg_key_regex()
{
    echo "^${1}[[:blank:]]*="
}

lxc_cfg_check_file()
{
    if [[ -z "$1" || ! -f "$1" ]]; then
        echo "Error: invalid or inaccessible config file" >&2
        return 1
    fi

    return 0
}

lxc_cfg_get()
{
    local file="$1" key="$2"
    grep -E "$(_lxc_cfg_key_regex "$key")" "$file" | \
        sed -r 's/^[^=]+=[[:blank:]]*//'
}

lxc_cfg_userns_get()
{
    local config_file="$1" uid_var="$2" gid_var="$3"
    lxc_cfg_check_file "$config_file" || return 1

    if [[ -z "$uid_var" || -z "$gid_var" ]]; then
        echo "Error: $FUNCNAME: invalid output variables" >&2
        return 1
    fi

    local _uid_range _gid_range idmap_line

    while read -r idmap_line; do
        if [[ "$idmap_line" == b* ]]; then
            _uid_range="${idmap_line#b }"
            _gid_range="$_uid_range"
        elif [[ "$idmap_line" == u* ]]; then
            _uid_range="${idmap_line#u }"
        elif [[ "$idmap_line" == g* ]]; then
            _gid_range="${idmap_line#g }"
        else
            echo "Warning: $FUNCNAME: invalid lxc.id_map value of '${idmap_line}' found, skipping" >&2
            continue
        fi

        if [[ -n "$_uid_range" && -n "$_gid_range" ]]; then
            break
        fi
    done < <( lxc_cfg_get "$config_file" lxc.id_map )

    eval "$uid_var"=\$_uid_range
    eval "$gid_var"=\$_gid_range

    return 0
}

lxc_cfg_userns_set()
{
    local config_file="$1" uid_map="$2" gid_map="$3"
    lxc_cfg_check_file "$config_file" || return 1

    local -i uid_src uid_dest uid_range gid_src gid_dest git_range

    if [[ "$uid_map" == "new" ]]; then
        uid_src=0
        uid_range=$ID_MAP_DEFAUlT_RANGE
        uid_dest=$(id_map_user_next_available_id $uid_range) || return 1
    elif [[ -n "$uid_map" ]]; then
        if ! id_map_parse "$uid_map" uid_src uid_dest uid_range; then
            echo "Error: ${FUNCNAME}: invalid UID parameters" >&2
            return 1
        fi
    else
        return 1
    fi

    if [[ "$gid_map" == "new" ]]; then
        gid_src=0
        gid_range=$ID_MAP_DEFAUlT_RANGE
        gid_dest=$(id_map_user_next_available_id $gid_range) || return 1
    elif [[ -n "$gid_map" ]]; then
        if ! id_map_parse "$gid_map" gid_src gid_dest gid_range; then
            echo "Error: ${FUNCNAME}: invalid GID parameters" >&2
            return 1
        fi
    else
        return 1
    fi

    (
        sed "$config_file" \
         -e "/$(_lxc_cfg_key_regex lxc.id_map)/d" \
         -e "/^# User namespace configuration/d" \
         | perl -0pe 's/\s+\z//s'

        echo; echo; echo "# User namespace configuration"
        echo "lxc.id_map = u ${uid_src} ${uid_dest} ${uid_range}"
        echo "lxc.id_map = g ${gid_src} ${gid_dest} ${gid_range}"
    ) > "${config_file}.tmp" || return 1

    mv "${config_file}.tmp" "${config_file}" || return 1

    return 0
}

lxc_fs_check_dir()
{
    if [[ -z "$1" || ! -d "$1" ]]; then
        echo "Error: rootfs is not a directory" >&2
        return 1
    fi

    return 0
}

lxc_fs_check_uidmapshift()
{
    local src_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")
    local bin="${src_dir}/uidmapshift"
    if ! [[ -e "$bin"  ]]; then
        gcc "${src_dir}/uidmapshift.c" -o "$bin"
    fi

    [[ -x "$bin" ]] || return 1

    echo "$bin"
    return 0
}

lxc_fs_userns_apply()
(
    set -e

    local config_file="$1" rootfs="$2"
    lxc_cfg_check_file "$config_file"
    
    local uid_map gid_map
    lxc_cfg_userns_get "$config_file" uid_map gid_map

    lxc_fs_check_dir "$rootfs"
    
    # Get current UID and GID for rootfs, and assume their are the base IDs
    # of the tree        
    local rootfs_stat=$(stat -c "%g %u" "$rootfs")
    local rootfs_uid rootfs_gid
    read -r rootfs_uid rootfs_gid <<< "$rootfs_stat"

    # If UIDs are mapped, take the mapping from the container, replace the 
    # source UID (usually 0) with the current UID for the root fs before doing
    # the ownership shifting
    if [[ -n "$uid_map" ]]; then
        local uid_src uid_dest uid_range
        id_map_parse "$uid_map" uid_src uid_dest uid_range
        uid_map="${rootfs_uid} ${uid_dest} ${uid_range}"
    fi

    # Same as above for GIDs
    if [[ -n "$gid_map" ]]; then
        local gid_src gid_dest gid_range
        id_map_parse "$gid_map" gid_src gid_dest gid_range
        gid_map="${rootfs_gid} ${gid_dest} ${gid_range}"
    fi

    # Optimize shifting if UID and GID maps are equal, and don't do anything
    # if no mappings are specified
    if [[ -z "$uid_map" && -z "$gid_map" ]]; then
        return 0
    fi

    local uidmapshift=$(lxc_fs_check_uidmapshift)
 
    if [[ "$uid_map" == "$gid_map" ]]; then
        $uidmapshift -b "$rootfs" $uid_map
    else
        [[ -z "$uid_map" ]] || $uidmapshift -u "$rootfs" $uid_map
        [[ -z "$gid_map" ]] || $uidmapshift -g "$rootfs" $gid_map
    fi

    return 0
)

lxc_userns_currently_in_ns()
{
    [ -e /proc/self/uid_map ] || return 1
    [ "$(wc -l /proc/self/uid_map | awk '{ print $1 }')" -eq 1 ] || return 0
    
    local line=$(awk '{ print $1 " " $2 " " $3 }' /proc/self/uid_map)
    [ "$line" = "0 0 4294967295" ] && return 1
    return 0
}

lxc_userns_maybe_reexec()
{
    local config_file="$1"
    shift

    [[ "$1" != -- ]] || shift
    (( $# )) || return 1

    lxc_cfg_check_file "$config_file" || return 1

    lxc_userns_currently_in_ns && return 0

    local uid_map gid_map
    lxc_cfg_userns_get "$config_file" uid_map gid_map || return 1

    [[ -z "$uid_map" && -z "$gid_map" ]] && return 0
    
    uid_map=$(echo "$uid_map" | tr ' ' ':')
    gid_map=$(echo "$gid_map" | tr ' ' ':')
    echo exec lxc-usernsexec \
     ${uid_map:+-m u:${uid_map}} \
     ${gid_map:+-m g:${gid_map}} \
     -- "$@"
}

lxc_hook_check_params()
{
    local _container="$1" _section="$2" _hook_type="$3"

    if [[ -z "$_container" || "$_section" != lxc  ]]; then
        echo "Error: Invalid parameters" >&2
        return 1
    fi

    lxc_fs_check_dir "$LXC_ROOTFS_MOUNT" || return 1

    eval "lxc_hook_container"=\$_container
    eval "lxc_hook_type"=\$_hook_type

    return 0
}