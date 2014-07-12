#!/bin/sh -

SHELLY_HOME=${SHELLY_HOME:-$HOME/.shelly}
load_config() {
    if [ -z "$SHELLY_VERSION" ]; then
        . "$SHELLY_HOME/config.sh"
        export SHELLY_VERSION
    fi
}

load_cim_config() {
    if [ -s "$CIM_HOME/config/current.$CIM_ID" ]; then
        . "$CIM_HOME/config/current.$CIM_ID"
    fi
}

dumped_core_path() {
    load_cim_config
    core_path="dumped-cores/$LISP_IMPL.core"
    if [ -f "$core_path" ]; then
        echo "$core_path"
    else
        echo "$SHELLY_HOME/$core_path"
    fi
}

#====================
# Options
#====================

init_cmd=
cmd=
main_cmd=

add_option() {
    if [ -z "$cmd" ]; then
        cmd="$1"$'\n'"$2"
    else
        cmd="$cmd"$'\n'"$1"$'\n'"$2"
    fi
}

add_eval_option() {
    add_option "-e" "$1"
}

add_load_path() {
    add_eval_option "(shelly.util::add-load-path (list #P\"$1\"))"
}

load_library() {
    add_option "-L" "$1"
}

run_shelly_command() {
    list=
    for a in "$@"; do
        list="$list \"$a\""
    done
    if [ -z "$main_cmd" ]; then
        main_cmd="-e"$'\n'"(shelly.core::interpret (list$list) :verbose $verbose)"
    else
        main_cmd="$main_cmd"$'\n'"-e"$'\n'"(shelly.core::interpret (list$list) :verbose $verbose)"
    fi
}

load_shelly() {
    shelly_path=${SHELLY_PATH:-$SHELLY_HOME/shelly/}
    init_cmd="-e"$'\n'"(require (quote asdf))"
    if [ -d "$shelly_path" ]; then
        init_cmd="$init_cmd"$'\n'"-e"$'\n'"(push (truename \"$shelly_path\") asdf:*central-registry*)"
    fi
    read -r -d '' cmd_load_shelly <<EOF
(let ((*standard-output* (make-broadcast-stream)) #+allegro(*readtable* (copy-readtable)))
  (handler-case #+quicklisp (ql:quickload :shelly) #-quicklisp (asdf:load-system :shelly)
    (#+quicklisp ql::system-not-found #-quicklisp asdf:missing-component (c)
     (format *error-output* "~&Error: ~A~&" c)
     #+quicklisp
     (format *error-output* "~&Try (ql:update-all-dists) to ensure your dist is up to date.~%")
     #+allegro (excl:exit 1 :quiet t)
     #+sbcl    (sb-ext:exit)
     #-(or allegro sbcl) (quit)))
  (values))
EOF
    cmd_load_shelly=$(echo $cmd_load_shelly | sed -e 's/\n/ /g')
    init_cmd="$init_cmd"$'\n'"-e"$'\n'"$cmd_load_shelly"
    init_cmd="$init_cmd"$'\n'"-e"$'\n'"(shelly.util::shadowing-use-package :shelly)"
}

load_core() {
    init_cmd="--core"$'\n'"$1"
    init_cmd="$init_cmd"$'\n'"-e"$'\n'"(shelly.util:shadowing-use-package :shelly)"
}

check_shelly_version() {
    load_config
    if [ "$SHELLY_VERSION" ]; then
        add_eval_option "(shelly.util::check-version \"$SHELLY_VERSION\")"
    fi
}


#====================
# Main
#====================

verbose="nil"

if [ "$#" = 0 ]; then
    help=1
    action="shelly::help"
    run_shelly_command "shelly::help"
fi

for ARG; do
    case "$ARG" in
        --help|-h)
            help=1
            action="shelly::help"
            run_shelly_command "shelly::help"
            break
            ;;
        -I)
            add_load_path "$2"
            shift 2
            ;;
        -I*)
            add_load_path $(echo $1 | sed -e 's/\-I//')
            shift
            ;;
        --load|-L)
            load_library "$2"
            shift 2
            ;;
        -L*)
            load_library $(echo $1 | sed -e 's/\-L//')
            shift
            ;;
        --version|-V)
            load_config
            echo "Shelly ver $SHELLY_VERSION"
            break
            ;;
        --verbose)
            verbose="t"
            shift
            ;;
        --debug)
            debug=1
            shift
            ;;
        --file|-f)
            shlyfile="$1"
            shift 2
            ;;
        -f*)
            shlyfile=$(echo $1 | sed -e 's/\-f//')
            shift
            ;;
        --*|-*)
            if [ "$1" != "-" ]; then
                echo "Unknown option '$1'."
                exit 1
            fi
            ;;
        *)
            action="$1"
            run_shelly_command "$@"
            break
            ;;
    esac
done

case "$action" in
    install)
        load_shelly
        ;;
    dump-core)
        load_shelly
        check_shelly_version
        ;;
    *)
        dumped_core_path=$(dumped_core_path)
        if [ -z "$SHELLY_PATH" ] && [ -f "$dumped_core_path" ]; then
            load_core "$dumped_core_path"
        else
            if [ -z "$SHELLY_PATH" ]; then
                load_cim_config
                case "$LISP_IMPL" in
                    sbcl*|clisp*|ccl*|alisp*)
                        echo "Warning: Core image wasn't found for $LISP_IMPL. It is probably slow, isn't it? Try \"shly dump-core\"."
                        ;;
                esac
            fi

            load_shelly
        fi

        check_shelly_version
        add_eval_option "(shelly.util::load-global-shlyfile)"
        if [ -z "$shlyfile" ]; then
            add_eval_option "(shelly.util::load-local-shlyfile)"
        else
            add_eval_option "(shelly.util::load-local-shlyfile #P\"$shlyfile\")"
        fi
        ;;
esac

main_cmd="$main_cmd"$'\n'"-e"$'\n'"(shelly.util::terminate)"

IFS=$'\n'
cmd="$init_cmd"$'\n'"$cmd"$'\n'"$main_cmd"
if [ "$debug" = 1 ]; then
    cmd_for_debug=$(echo $cmd | sed -e "s/$'\n'/ /g")
    echo "cl $cmd_for_debug"
fi
if [ "$help" = 1 ]; then
    cat <<EOF
Usage:
    $ shly.sh [options] [atom...]

Options:
    -h, --help
        Show this help.

    -I [directory]
        Specify asdf:*central-registry* directory (several -I's allowed).

    -L, --load [library]
        Specify a library to be loaded before executing the expression
        (several -L's allowed).

    -V, --version
        Print the version of Shelly and exit.

    --verbose
        Print some informations.

    --debug
        This flag is for Shelly developers.

EOF
fi

if [ "$action" = "install" ]; then
    sh cl $cmd
    if expr "$SHELL" : '.*sh' > /dev/null 2>&1; then
        rc="SHELLY_HOME=$SHELLY_HOME; [ -s \"\$SHELLY_HOME/shelly/init.sh\" ] && . \"\$SHELLY_HOME/shelly/init.sh\""
        case "$SHELL" in
            */bash) rcfile="$HOME/.bashrc" ;;
            */zsh)  rcfile="$HOME/.zshrc" ;;
            */sh)   rcfile="$HOME/.profile" ;;
            *) ;;
        esac
    fi

    if [ -n "$rcfile" ] && [ -e "$rcfile" ] && ! grep -F "$rc" "$rcfile" > /dev/null 2>&1; then
        cat <<EOF

Adding the following settings into your $rcfile:

    $rc

EOF
        echo "$rc" >> "$rcfile"
    fi
else
    exec cl $cmd
fi