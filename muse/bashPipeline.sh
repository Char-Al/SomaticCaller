#!/bin/bash

# ------------------------------------------------------------------
# [Charles VAN GOETHEM] SomaticCaller
#          Pipeline base on GATK best practices
# ------------------------------------------------------------------
VERSION=0.0.1
USAGE="Usage:	bashPipeline.sh [-h] [-l 6] -t <sample_tumor.bam> -n <sample_normal.bam> -v <sample_normal.vcf> -p <panelOfNormal.list>"
PWD_PROJECT=$(pwd)

COMMAND_LINE="${0} ${@}"
CPT_ERROR=0
CPT_WARNING=0

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")"
__base="$(basename "${__file}" .sh)"

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
output=""

LOG_LEVEL=6
NB_THREAD=1
MAX_RAM=16
NB_CORE=1

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

while [[ "${@}" != "" ]]; do
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
		-o | --output )			_arg_unique "-o (--output)" "${output}"
								_arg_ctrl "-o (--output)" "${2}"
								shift
								output=$1
								;;
		-l | --log-level )		_arg_ctrl "-l (--log-level)" "${2}"
								[ -z "${2##*[!0-9]*}" ] && error "Option -l (--log-level) need integer as input. (default 6)" && usage && exit 1
								shift
								LOG_LEVEL=$1
								;;
		-nt | --nb-thread )		_arg_ctrl "-nt (--nb-thread)" "${2}"
								[ -z "${2##*[!0-9]*}" ] && error "Option -nt ( --nb-thread) need integer as input. (default 1)" && usage && exit 1
								shift
								NB_THREAD=$1
								;;
		-m | --max-ram )		_arg_ctrl "-m (--max-ram)" "${2}"
								[ -z "${2##*[!0-9]*}" ] && error "Option -m (--max-ram) need integer as input. (default 1)" && usage && exit 1
								shift
								MAX_RAM=$1
								;;
		-c | --nb-core )		_arg_ctrl "-c (--nb-core)" "${2}"
								[ -z "${2##*[!0-9]*}" ] && error "Option -c (--nb-core) need integer as input. (default 1)" && usage && exit 1
								shift
								NB_CORE=$1
								;;
		-d | --debug )			set -o xtrace
								LOG_LEVEL="7"
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
	debug "Function : _contains_element ${@}"

	local e="${1}"
	shift

	for m
	do
		[[ "$e" == "$m" ]] && echo 0 && return 0;
	done

	echo 1
	return 1
}

_check_file () {
	# Check if file is valid and extension (option)
	# usage : _check_file $file [$extension]
	debug "Function : _check_file ${@}"

	local filepath="${1}"
	shift

	local authorized_ext=()
	while [[ "${@}" != "" ]]; do
		authorized_ext+=("${1}")
		shift
	done

	local filename=$(basename "${filepath}")
	local extension="${filename##*.}"


	if [[ ! -f ${filepath} ]]
	then
		error "File '${filepath}' is not a regular file."
		CPT_ERROR=$[$CPT_ERROR +1]
	elif [[ ! -z ${authorized_ext[@]} ]]
	then
		local ext=$(_contains_element "${extension}" "${authorized_ext[@]}")

		if [[ ${ext} == 1 ]]
		then
			warning "Expected '${authorized_ext[@]}' as extension for '${filename}'."
		fi
	fi
}

_check_output () {
	# Check if file is valid and extension (option)
	# usage : _check_file $file [$extension]
	debug "Function : _check_output ${@}"

	local out="${1}"

	if [[ -e ${out} ]]
	then
		error "Output '${out}' exists. Please make sure that repertory '${out}' is not exist."
		CPT_ERROR=$[$CPT_ERROR +1]
	else
		mkdir "${out}"
	fi

}

info "Number of thread : ${NB_THREAD}"
info "Max ram : ${MAX_RAM}G"
info "Number of core : ${NB_CORE}"

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
		info "	${p}"
		_check_file ${p} "bam" "sam" "cram"
	done
fi

# Argument output
if [[ $output == "" ]]
then
	error "Option -o (--output) is mandatory"
	CPT_ERROR=$[$CPT_ERROR +1]
else
	info "Output Repertory : $vcfNormal"
	_check_output ${output}
fi

if [[ CPT_ERROR -gt 0 ]]
then
	alert "Script suddenly ended due to ${CPT_ERROR} error(s) previously describe."
	usage
	exit 1
fi

################################################################################
################################################################################

info "__file: ${__file}"
info "__dir: ${__dir}"
info "__base: ${__base}"
info "OSTYPE: ${OSTYPE}"

QUEUE="/home/vangoethemc/work-mobidic/nenufaar/software/Queue/3.6/Queue.jar"
GATK="/home/vangoethemc/work-mobidic/nenufaar/software/GenomeAnalysisTK/3.6.0/GenomeAnalysisTK.jar"
PICARD="/home/vangoethemc/work-mobidic/nenufaar/software/picard/2.6.0/picard.jar"

HAPMAP="/home/vangoethemc/work-mobidic/nenufaar/refData/HapMap/hapmap_3.3_hg19_pop_stratified_af.vcf.gz"
COSMIC="/home/vangoethemc/work-mobidic/nenufaar/refData/COSMIC/CosmicCodingMuts_withCHR.vcf"
REF="/home/vangoethemc/work-mobidic/nenufaar/refData/genome/hg19/hg19.fa"
DBSNP="/home/vangoethemc/work-mobidic/nenufaar/refData/dbSNP/138/CORRECT_dbsnp_138.hg19.vcf"

export JAVA_HOME=/nfs/work/mobidic/nenufaar/software/jre1.8.0_111/bin/
JAVA=/nfs/work/mobidic/nenufaar/software/jre1.8.0_111/bin/java
export PATH=${JAVA_HOME}:${PATH}
export LD_LIBRARY_PATH="/trinity/shared/apps/local/slurm-drmaa-1.0.7/lib/:${LD_LIBRARY_PATH:-}"
QUEUE_RUNNER="-jobRunner Drmaa"

debug "${panel[@]}"

for e in ${panel[@]}
do
	CURRENT_SAMPLE_BASEDIR_NAME=$(basename "${e}")
	CURRENT_SAMPLE_NAME=${CURRENT_SAMPLE_BASEDIR_NAME%.bam}
	info "BASENAME CURRENT SAMPLE : ${CURRENT_SAMPLE_NAME}"
	cmd="$JAVA -jar -Djava.io.tmpdir=out/tmp_PoN/${CURRENT_SAMPLE_NAME} -Xmx${MAX_RAM}g $QUEUE -l WARN \
	    -S queueScripts/muTect2_PoN.scala \
	    -tumor $p \
	    -dbsnp $DBSNP \
	    -o $CURRENT_SAMPLE_NAME.1_normal.vcf.gz \
	    -R $REF \
	    ${QUEUE_RUNNER} \
	    -jobSGDir out/ \
	    -run"
	info "Make PoN : ${cmd}"
	info "echo \"$CURRENT_SAMPLE_NAME.1_normal.vcf.gz\" >> PoN.list"
done

cmd="srun --job-name=splitVCF -N=1 -n=1 -c=${NB_THREAD} --partition=defq --account=IURC $JAVA -jar -Xmx${MAX_RAM}g $GATK \
	-T CombineVariants \
	-nt ${NB_THREAD} \
	--arg_file PoN.list \
	-minN 2 \
	--setKey \"null\" \
	--filteredAreUncalled \
	--filteredrecordsmergetype KEEP_IF_ANY_UNFILTERED \
	-o 2_pon_combinevariants.vcf.gz \
	-R $REF \
	--genotypemergeoption UNIQUIFY"
info "Merge Variants : ${cmd}"

cmd="srun --job-name=splitVCF -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD MakeSitesOnlyVcf \
	I=2_pon_combinevariants.vcf.gz \
	O=3_pon_siteonly.vcf.gz"
info "PoN site only : ${cmd}"

cmd="$JAVA -jar -Djava.io.tmpdir=out/tmp_contEst -Xmx${MAX_RAM}g $QUEUE -S queueScripts/contEst.scala \
	-eval $tumor \
	-genotypes $vcfNormal \
	-popfile $HAPMAP \
	-o 4_T_contest.txt \
	-R $REF \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run"
info "Sample tumor contamination estimation : ${cmd}"

cmd="$JAVA -jar -Djava.io.tmpdir=out/tmp_contEst -Xmx${MAX_RAM}g $QUEUE -S queueScripts/contEst.scala \
	-eval $normal \
	-genotypes $vcfNormal \
	-popfile $HAPMAP \
	-o 5_N_contest.txt \
	-R $REF \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run "
info "Sample normal contamination estimation : ${cmd}"

cmd="srun --job-name=ArtMetricsTumor -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD CollectSequencingArtifactMetrics \
	I=$tumor \
	O=6_T_artifact \
	R=$REF"
info "Collect Sequencing Artifact Metrics tumor : ${cmd}"

cmd="srun --job-name=ArtMetricsNormal -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD CollectSequencingArtifactMetrics \
	I=$normal \
	O=7_N_artifact \
	R=$REF"
info "Collect Sequencing Artifact Metrics normal : ${cmd}"

cmd="$JAVA -Djava.io.tmpdir=out/tmpp_call/ -Xmx${MAX_RAM}g -jar $QUEUE -S queueScripts/muTect2_calling.scala \
	-tumor $tumor \
	-normal $normal \
	-dbsnp $DBSNP \
	-cosmic $COSMIC \
	-normal_panel 2_pon_combinevariants.vcf.gz \
	-o 8_mutect2.vcf.gz \
	-R $REF  \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run "
info "Calling by MuTect2 : ${cmd}"
