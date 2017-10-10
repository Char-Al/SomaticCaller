#!/bin/bash

# ------------------------------------------------------------------
# [Charles VAN GOETHEM] SomaticCaller
#          Pipeline base on GATK best practices
# ------------------------------------------------------------------
VERSION=0.1.0
USAGE="Usage:	bashPipeline.sh [-h] [-l 6] -t <sample_tumor.bam> -n <sample_normal.bam> -v <sample_normal.vcf> -p <panelOfNormal.list>"
PWD_PROJECT=$(pwd)

COMMAND_LINE="${0} ${@}"
CPT_ERROR=0
CPT_WARNING=0

################################################################################
################################################################################
# Log functions

function _log () {
	local log_level="${1}"
	shift

	local color_debug="\x1b[34m"
	local color_info="\x1b[32m"
	local color_notice="\x1b[35m"
	local color_warning="\x1b[33m"
	local color_error="\x1b[31m"
	local color_critical="\x1b[1;31m"
	local color_alert="\x1b[1;33;41m"
	local color_emergency="\x1b[1;4;5;33;41m"

	local colorvar="color_${log_level}"

	local color="${!colorvar:-${color_error}}"
	local color_reset="\x1b[0m"

	if [[ "${NO_COLOR:-}" = "true" ]] || ( [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]] ) || [[ ! -t 2 ]]; then
		if [[ "${NO_COLOR:-}" != "false" ]]; then
			# Don't use colors on pipes or non-recognized terminals
			color=""; color_reset=""
		fi
	fi

	# all remaining arguments are to be printed
	local log_line=""

	while IFS=$'\n' read -r log_line; do
		echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" 1>&2
	done <<< "${@:-}"
}

function emergency () {
	_log emergency "${@}";
	exit 1;
}
function alert ()     {
	[[ "${LOG_LEVEL:-0}" -ge 1 ]] && _log alert "${@}";
	true;
}
function critical ()  {
	[[ "${LOG_LEVEL:-0}" -ge 2 ]] && _log critical "${@}";
	true;
}
function error ()     {
	[[ "${LOG_LEVEL:-0}" -ge 3 ]] && _log error "${@}";
	true;
}
function warning ()   {
	[[ "${LOG_LEVEL:-0}" -ge 4 ]] && _log warning "${@}";
	true;
}
function notice ()    {
	[[ "${LOG_LEVEL:-0}" -ge 5 ]] && _log notice "${@}";
	true;
}
function info ()      {
	[[ "${LOG_LEVEL:-0}" -ge 6 ]] && _log info "${@}";
	true;
}
function debug ()     {
	[[ "${LOG_LEVEL:-0}" -ge 7 ]] && _log debug "${@}";
	true;
}

################################################################################
################################################################################
# usage

usage ()
{
	echo '';
	echo 'Pipeline for Somatic variant calling based on GATK best practice';
	echo 'Usage : bashPipeline.sh';
	echo '	Mandatory arguments :';
	echo '		* -t|--tumor <sample>	: tumor';
	echo '		* -n|--normal <sample>	: normal';
	echo '';
	echo '	General arguments';
	echo '		* -h	: show this help message and exit';
	echo '';
	exit
}

################################################################################
################################################################################
# parse arguments
tumor=""
normal=""
panel=()
vcfNormal=""
LOG_LEVEL=6

# Parse command line
_arg_ctrl () {
	local opt="${1}"
	local value="${2}"

	if [[ $value =~ ^- ]] || [[ -z $value ]] || [[ $value == "" ]]
	then
		error "Option ${opt} requires an argument."
		usage
		exit 1
	fi
}

_arg_unique () {
	local opt="${1}"
	local value="${2}"

	if [[ $value != "" ]]
	then
		warning "Option ${opt} already defined, data will be erase."
	fi
}

while [ "$1" != "" ]; do
	case $1 in
		-t | --tumor )			_arg_unique "-t (--tumor)" "${tumor}"
								_arg_ctrl "-t (--tumor)" "${2}"
								shift
								tumor=$1
								;;
		-n | --normal )			_arg_unique "-n (--normal)" "${normal}"
								_arg_ctrl "-n (--normal)" "${2}"
								shift
								normal=$1
								;;
		-p | --panelOfNormal )	_arg_ctrl "-p (--panelOfNormal)" "${2}"
								shift
								panel+=($1)
								;;
		-v | --vcfNormal )		_arg_unique "-v (--vcfNormal)" "${vcfNormal}"
								_arg_ctrl "-v (--vcfNormal)" "${2}"
								shift
								vcfNormal=$1
								;;
		-l | --log-level )		_arg_ctrl "-l (--log-level)" "${2}"
								[ -z "${2##*[!0-9]*}" ] && error "Option -l (--log-level) need integer as input. (default 6)" && usage && exit 1
								shift
								LOG_LEVEL=$1
								;;
		-h | --help )			usage
								exit
								;;
		-- ) 					shift;
								break ;;
		* )						usage
								exit 1
	esac
	shift
done

info "Command line : '$COMMAND_LINE'"


################################################################################
################################################################################
# check if args are valid

_contains_element () {
	local e match="$1"
	shift
	for e
	do
		[[ "$e" == "$match" ]] && return 0;
	done
	return 1
}

_check_file () {
	# Check if file is valid and extension (option)
	# usage : _check_file $file [$extension]
	debug "Check file '${1}'"

	local filepath="${1}"
	shift

	local authorized_ext=()
	while [ "$1" != "" ]; do
		authorized_ext+=("${1}")
		shift
	done

	local filename=$(basename "${filepath}")
	local extension="${filename##*.}"

	debug "	file : ${filepath}"
	debug "	filename : ${filename}"
	debug "	extension : ${extension}"


	if [[ ! -f ${filepath} ]]
	then
		error "File '${filepath}' is not a regular file."
		CPT_ERROR=$[$CPT_ERROR +1]
	elif [[ ! -z ${authorized_ext} ]]
	then
		debug "	authorized extension : ${authorized_ext[@]}"
		_contains_element "${extension}" "${authorized_ext[@]}"
		local ext=$?

		if [[ ${ext} == 1 ]]
		then
			warning "Expected '${authorized_ext[@]}' as extension for '${filename}'."
		fi
	fi
}

# Argument tumor
if [[ $tumor == "" ]]
then
	error "Option -t (--tumor) is mandatory"
	CPT_ERROR=$[$CPT_ERROR +1]
else
	info "Tumor file : $tumor"
	_check_file ${tumor} "bam" "sam" "cram"
fi

# Argument normal
if [[ $normal == "" ]]
then
	error "Option -n (--normal) is mandatory"
	CPT_ERROR=$[$CPT_ERROR +1]
else
	info "Normal file : $normal"
	_check_file ${normal} "bam" "sam" "cram"
fi

# Argument vcfNormal
if [[ $vcfNormal == "" ]]
then
	error "Option -v (--vcfNormal) is mandatory"
	CPT_ERROR=$[$CPT_ERROR +1]
else
	info "VCF normal : $vcfNormal"
	_check_file ${vcfNormal} "vcf"
fi


# Argument panelOfNormal
if [[ ${#panel[@]} -eq 0 ]]
then
	error "Option -p (--panelOfNormal) is mandatory (at least one time)"
	CPT_ERROR=$[$CPT_ERROR +1]
else
	info "${#panel[@]} files uses for panel of normal :"
	for p in ${panel[@]}
	do
		info "	$normal"
		_check_file ${p} "bam" "sam" "cram"
	done
fi

if [[ CPT_ERROR -gt 0 ]]
then
	alert "Script suddenly ended due to ${CPT_ERROR} error(s) previously describe."
	usage
	exit 1
fi
