#!/bin/bash -e

# Script to handle the various ways soong may need to strip binaries
# Inputs:
#  Environment:
#   CLANG_BIN: path to the clang bin directory
#   CROSS_COMPILE: prefix added to readelf, objcopy tools
#   XZ: path to the xz binary
#  Arguments:
#   -i ${file}: input file (required)
#   -o ${file}: output file (required)
#   -d ${file}: deps file (required)
#   --add-gnu-debuglink
#   --keep-mini-debug-info
#   --keep-symbols
#   --use-llvm-strip

OPTSTRING=d:i:o:-:

usage() {
    cat <<EOF
Usage: strip.sh [options] -i in-file -o out-file -d deps-file
Options:
        --add-gnu-debuglink     Add a gnu-debuglink section to out-file
        --keep-mini-debug-info  Keep compressed debug info in out-file
        --keep-symbols          Keep symbols in out-file
        --use-llvm-strip        Use llvm-{strip,objcopy} instead of strip/objcopy
EOF
    exit 1
}

# With --use-llvm-strip, GNU strip is replaced with llvm-strip to work around
# old GNU strip bug on lld output files, b/80093681.
# Similary, calls to objcopy are replaced with llvm-objcopy,
# with some exceptions.

do_strip() {
    # ${CROSS_COMPILE}strip --strip-all does not strip .ARM.attributes,
    # so we tell llvm-strip to keep it too.
    if [ ! -z "${use_llvm_strip}" ]; then
        "${CLANG_BIN}/llvm-strip" --strip-all -keep=.ARM.attributes "${infile}" "${outfile}.tmp"
    else
        "${CROSS_COMPILE}strip" --strip-all "${infile}" -o "${outfile}.tmp"
    fi
}

do_strip_keep_symbols() {
    # Maybe we should replace this objcopy with llvm-objcopy, but
    # we have not found a use case that is broken by objcopy yet.
    REMOVE_SECTIONS=`"${CROSS_COMPILE}readelf" -S "${infile}" | awk '/.debug_/ {print "--remove-section " $2}' | xargs`
    if [ ! -z "${use_llvm_strip}" ]; then
        "${CROSS_COMPILE}objcopy" "${infile}" "${outfile}.tmp" ${REMOVE_SECTIONS}
    else
        "${CLANG_BIN}/llvm-objcopy" "${infile}" "${outfile}.tmp" ${REMOVE_SECTIONS}
    fi
}

do_strip_keep_mini_debug_info() {
    rm -f "${outfile}.dynsyms" "${outfile}.funcsyms" "${outfile}.keep_symbols" "${outfile}.debug" "${outfile}.mini_debuginfo" "${outfile}.mini_debuginfo.xz"
    if [ ! -z "${use_llvm_strip}" ]; then
        "${CLANG_BIN}/llvm-strip" --strip-all -keep=.ARM.attributes -remove-section=.comment "${infile}" "${outfile}.tmp"
    else
        "${CROSS_COMPILE}strip" --strip-all -R .comment "${infile}" -o "${outfile}.tmp"
    fi
    if [ "$?" == "0" ]; then
        # Current prebult llvm-objcopy does not support the following flags:
        #    --only-keep-debug --rename-section --keep-symbols
        # For the following use cases, ${CROSS_COMPILE}objcopy does fine with lld linked files,
        # except the --add-section flag.
        "${CROSS_COMPILE}objcopy" --only-keep-debug "${infile}" "${outfile}.debug"
        "${CROSS_COMPILE}nm" -D "${infile}" --format=posix --defined-only | awk '{ print $$1 }' | sort >"${outfile}.dynsyms"
        "${CROSS_COMPILE}nm" "${infile}" --format=posix --defined-only | awk '{ if ($$2 == "T" || $$2 == "t" || $$2 == "D") print $$1 }' | sort > "${outfile}.funcsyms"
        comm -13 "${outfile}.dynsyms" "${outfile}.funcsyms" > "${outfile}.keep_symbols"
        "${CROSS_COMPILE}objcopy" --rename-section .debug_frame=saved_debug_frame "${outfile}.debug" "${outfile}.mini_debuginfo"
        "${CROSS_COMPILE}objcopy" -S --remove-section .gdb_index --remove-section .comment --keep-symbols="${outfile}.keep_symbols" "${outfile}.mini_debuginfo"
        "${CROSS_COMPILE}objcopy" --rename-section saved_debug_frame=.debug_frame "${outfile}.mini_debuginfo"
        xz "${outfile}.mini_debuginfo"
        if [ ! -z "${use_llvm_strip}" ]; then
            "${CLANG_BIN}/llvm-objcopy" --add-section .gnu_debugdata="${outfile}.mini_debuginfo.xz" "${outfile}.tmp"
        else
            "${CROSS_COMPILE}objcopy" --add-section .gnu_debugdata="${outfile}.mini_debuginfo.xz" "${outfile}.tmp"
        fi
    else
        cp -f "${infile}" "${outfile}.tmp"
    fi
}

do_add_gnu_debuglink() {
    if [ ! -z "${use_llvm_strip}" ]; then
        "${CLANG_BIN}/llvm-objcopy" --add-gnu-debuglink="${infile}" "${outfile}.tmp"
    else
        "${CROSS_COMPILE}objcopy" --add-gnu-debuglink="${infile}" "${outfile}.tmp"
    fi
}

while getopts $OPTSTRING opt; do
    case "$opt" in
	d) depsfile="${OPTARG}" ;;
	i) infile="${OPTARG}" ;;
	o) outfile="${OPTARG}" ;;
	-)
	    case "${OPTARG}" in
		add-gnu-debuglink) add_gnu_debuglink=true ;;
		keep-mini-debug-info) keep_mini_debug_info=true ;;
		keep-symbols) keep_symbols=true ;;
		use-llvm-strip) use_llvm_strip=true ;;
		*) echo "Unknown option --${OPTARG}"; usage ;;
	    esac;;
	?) usage ;;
	*) echo "'${opt}' '${OPTARG}'"
    esac
done

if [ -z "${infile}" ]; then
    echo "-i argument is required"
    usage
fi

if [ -z "${outfile}" ]; then
    echo "-o argument is required"
    usage
fi

if [ -z "${depsfile}" ]; then
    echo "-d argument is required"
    usage
fi

if [ ! -z "${keep_symbols}" -a ! -z "${keep_mini_debug_info}" ]; then
    echo "--keep-symbols and --keep-mini-debug-info cannot be used together"
    usage
fi

if [ ! -z "${add_gnu_debuglink}" -a ! -z "${keep_mini_debug_info}" ]; then
    echo "--add-gnu-debuglink cannot be used with --keep-mini-debug-info"
    usage
fi

rm -f "${outfile}.tmp"

if [ ! -z "${keep_symbols}" ]; then
    do_strip_keep_symbols
elif [ ! -z "${keep_mini_debug_info}" ]; then
    do_strip_keep_mini_debug_info
else
    do_strip
fi

if [ ! -z "${add_gnu_debuglink}" ]; then
    do_add_gnu_debuglink
fi

rm -f "${outfile}"
mv "${outfile}.tmp" "${outfile}"

if [ ! -z "${use_llvm_strip}" ]; then
  USED_STRIP_OBJCOPY="${CLANG_BIN}/llvm-strip ${CLANG_BIN}/llvm-objcopy"
else
  USED_STRIP_OBJCOPY="${CROSS_COMPILE}strip"
fi

cat <<EOF > "${depsfile}"
${outfile}: \
  ${infile} \
  ${CROSS_COMPILE}nm \
  ${CROSS_COMPILE}objcopy \
  ${CROSS_COMPILE}readelf \
  ${USED_STRIP_OBJCOPY}

EOF
