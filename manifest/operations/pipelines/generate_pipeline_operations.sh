#!/usr/bin/env bash
set -o pipefail  # exit if pipe command fails
[ -z "$DEBUG" ] || set -x

PROGRAM=${PROGRAM:-$(basename "${BASH_SOURCE[0]}")}
PROGRAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRAM_OPTS=$@


###

usage() {
    cat <<EOF
Usage:
    $PROGRAM [-m <generated-operations-manifest] <folder> [[config1] [config2] ...]

Generates a Bosh client operations file, next to <folder>, with the name
"<folder>.yml" including all snippets if no extra arguments are provided,
otherwise it will use the snippets given as arguments.

The output is an operations file ready to be used by bosh.

Why? Because this allows us to split the logstash configuration in different
files (snippets), making the logstash config easy to manage, and automatically
generates an operations file including these snippets.
EOF
}



add_oper_snippets() {
    local name="${1}"
    local manifest="${2}"
    local folder="${3}"
    local snippets=("${@:4}")

    cat <<OperSNIPPETS >> "${manifest}"
- type: replace
  path: /instance_groups/name=logstash/properties/logstash/conf?/xpack.management.pipeline.id?/-
  value:
    "$name"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env?/DST_HOSTS?
  value:
    "((es-host))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/ES_USER?
  value:
    "((es-user))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/ES_PASSWORD?
  value:
    "((es-password))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/ES_INDEX_PREFIX?
  value:
    "((es-index_prefix))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/CF_API?
  value:
    "((cf-api))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/SOURCE_ENV?
  value:
    "((source-env))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/env/SOURCE_PLATFORM?
  value:
    "((source-platform))"

- type: replace
  path: /instance_groups/name=logstash/properties/logstash/pipelines?
  value:
    - name: ${name}
      config:
OperSNIPPETS

    for i in ${snippets[@]}
    do
        if [ -e "${folder}/${i}" ]
        then
            echo -n "* Adding snippet '${folder}/${i}' ... "
            echo "        ${i%%.*}: |" >> "${manifest}"
            sed -e 's/[[:space:]]*$//' -e 's/^/          /' "${folder}/${i}" >> "${manifest}"
            echo "ok"
        else
            echo "* WARNING snippet '${folder}/${i}' not found!"
        fi
    done
    return 0
}


list_snippets() {
    local folder="${1}"

    local snippets=()

    while IFS=  read -r -d $'\0' line
    do
        snippets+=($(basename "${line}"))
    done < <(find ${folder} -xtype f -name "*.conf" -print0 | sort -z)
    for i in ${snippets[@]}
    do
        echo "${i}"
    done
}


main() {
    local folder="${1}"
    local manifest="${2}"
    local snippets=("${@:3}")

    local name=$(basename "${folder}")

    if [ ! -d "${folder}" ]
    then
        echo "ERROR, ${folder} is not a folder!"
        return 1
    fi
    [ ${#snippets[@]} == 0 ] && snippets=($(list_snippets "${folder}"))
    if [ ${#snippets[@]} == 0 ]
    then
        echo "ERROR, no snippets defined!. Check if fodler"
        return 1
    fi
    echo "* Generating "${manifest}" with snippets from ${folder}:"
    add_oper_snippets "${name}" "${manifest}" "${folder}" "${snippets[@]}"
    return $?
}



################################################################################

# Program
if [ "$0" == "${BASH_SOURCE[0]}" ]
then
    MANIFEST=""
    # Parse main options
    while getopts ":hm:" opt
    do
        case ${opt} in
            h)
                usage
                exit 0
                ;;
            m)
                MANIFEST="${OPTARG}"
                ;;
            :)
                echo "Option -${OPTARG} requires an argument" >&2
                exit 1
                ;;
        esac
    done
    shift $((OPTIND -1))
    FOLDER=$1
    shift
    [ -z "${MANIFEST}" ] && MANIFEST="${FOLDER}.yml"
    if [ -e "${MANIFEST}" ]
    then
        echo "* Warning file '${MANIFEST}' exists! Renaming to '${MANIFEST}.old'"
        mv "${MANIFEST}" "${MANIFEST}.old"
    fi
    if [ -z "${FOLDER}" ]
    then
        usage
        echo "* ERROR, no folder defined! Please specify a folder with snippets."
        exit 1
    fi
    main "${FOLDER}" "${MANIFEST}" $@
    RVALUE=$?
    echo "* Exit=${RVALUE}"
    exit ${RVALUE}
fi

