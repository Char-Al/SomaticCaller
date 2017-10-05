#!/bin/bash

# ------------------------------------------------------------------
# [Charles VAN GOETHEM] SomaticCaller
#          Pipeline base on GATK best practices
# ------------------------------------------------------------------
VERSION=0.0.1
USAGE="Usage:	bashPipeline.sh [-h] -f <filename.fastq.gzip> -r <directory>"
PWD_PROJECT=$(pwd)

usage ()
{
	echo 'Pipeline for Somatic variant calling based on GATK best practice';
	echo 'Usage : bashPipeline.sh';
	echo '	Mandatory arguments :';
	echo '		* -t|--tumor <sample>	: tumor';
	echo '		* -n|--normal <sample>	: normal';
	echo '';
	echo '	General arguments';
	echo '		* -h	: show this help message and exit';
	echo '		* -t	: test mode (dont execute command just print them)';
	echo '';
	exit
}



# ==============================================================================
# ==============================================================================


function _arg_ctrl () {
	local opt="${1}"
	local value="${2}"

	if [[ $value =~ ^- ]] || [[ -z $value ]] || [[ $value == "" ]]
	then
		echo "error Option ${opt} requires an argument"
	fi
}


tumor=""
normal=""
panel=""
vcfNormal=""

# Parse command line
while [ "$1" != "" ]; do
	case $1 in
		-t | --tumor )			_arg_ctrl "-t (--tumor)" $2
								shift
								tumor=$1
								;;
		-p | --panelOfNormal )	shift
								panel=$1
								;;
		-n | --normal )	shift
								normal=$1
								;;
		-v | --vcfNormal )	shift
								vcfNormal=$1
								;;
		-h | --help )			usage
								exit
								;;
		* )						usage
								exit 1
	esac
	shift
done

################################################################################
################################################################################

GATK="/home/charles/Documents/tools/GATK/current/GenomeAnalysisTK.jar"
DBSNP="/media/charles/Datas/refData/dbSNP/138/CORRECT_dbsnp_138.hg19.vcf"
REF="/media/charles/Datas/refData/genome/hg19/hg19.fa"
PICARD="/home/charles/Documents/tools/Picard/current/picard.jar"


QUEUE="/home/vangoethemc/work-mobidic/nenufaar/software/Queue/3.6/Queue.jar"
GATK="/home/vangoethemc/work-mobidic/nenufaar/software/GenomeAnalysisTK/3.6.0/GenomeAnalysisTK.jar"
PICARD="/home/vangoethemc/work-mobidic/nenufaar/software/picard/2.6.0/picard.jar"

HAPMAP="/home/vangoethemc/work-mobidic/nenufaar/refData/HapMap/hapmap_3.3_hg19_pop_stratified_af.vcf.gz"
COSMIC="/home/vangoethemc/work-mobidic/nenufaar/refData/COSMIC/CosmicCodingMuts_withCHR.vcf"
REF="/home/vangoethemc/work-mobidic/nenufaar/refData/genome/hg19/hg19.fa"
DBSNP="/home/vangoethemc/work-mobidic/nenufaar/refData/dbSNP/138/CORRECT_dbsnp_138.hg19.vcf"

NB_THREAD=28

export JAVA_HOME=/nfs/work/mobidic/nenufaar/software/jre1.8.0_111/bin/
JAVA=/nfs/work/mobidic/nenufaar/software/jre1.8.0_111/bin/java
export PATH=${JAVA_HOME}:${PATH}
export LD_LIBRARY_PATH=/trinity/shared/apps/local/slurm-drmaa-1.0.7/lib/:${LD_LIBRARY_PATH}
QUEUE_RUNNER="-jobRunner Drmaa"
MAX_RAM=84



while read p; do
	CURRENT_SAMPLE_BASEDIR_NAME=$(basename "${p}")
	CURRENT_SAMPLE_NAME=${CURRENT_SAMPLE_BASEDIR_NAME%.bam}
	printf "\n\n\nBASENAME CURRENT SAMPLE : ${CURRENT_SAMPLE_NAME}\n\n\n"
	$JAVA -jar -Djava.io.tmpdir=out/tmp_PoN/${CURRENT_SAMPLE_NAME} -Xmx${MAX_RAM}g $QUEUE -l WARN \
	    -S queueScripts/muTect2_PoN.scala \
	    -tumor $p \
	    -dbsnp $DBSNP \
	    -o $CURRENT_SAMPLE_NAME.1_normal.vcf.gz \
	    -R $REF \
	    ${QUEUE_RUNNER} \
	    -jobSGDir out/ \
	    -run
	echo "$CURRENT_SAMPLE_NAME.1_normal.vcf.gz" >> PoN.list
done < $panel

srun --job-name=splitVCF -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar -Xmx${MAX_RAM}g $GATK \
	-T CombineVariants \
	-nt ${NB_THREAD} \
	--arg_file PoN.list \
	-minN 2 \
	--setKey "null" \
	--filteredAreUncalled \
	--filteredrecordsmergetype KEEP_IF_ANY_UNFILTERED \
	-o 2_pon_combinevariants.vcf.gz \
	-R $REF \
	--genotypemergeoption UNIQUIFY

rm PoN.list

srun --job-name=splitVCF -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD MakeSitesOnlyVcf \
	I=2_pon_combinevariants.vcf.gz \
	O=3_pon_siteonly.vcf.gz

$JAVA -jar -Djava.io.tmpdir=out/tmp_contEst -Xmx${MAX_RAM}g $QUEUE -S queueScripts/contEst.scala \
	-eval $tumor \
	-genotypes $vcfNormal \
	-popfile $HAPMAP \
	-o 4_T_contest.txt \
	-R $REF \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run

$JAVA -jar -Djava.io.tmpdir=out/tmp_contEst -Xmx${MAX_RAM}g $QUEUE -S queueScripts/contEst.scala \
	-eval $normal \
	-genotypes $vcfNormal \
	-popfile $HAPMAP \
	-o 5_N_contest.txt \
	-R $REF \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run

srun --job-name=ArtMetricsTumor -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD CollectSequencingArtifactMetrics \
	I=$tumor \
	O=6_T_artifact \
	R=$REF

srun --job-name=ArtMetricsNormal -N1 -n1 -c24 --partition=defq --account=IURC $JAVA -jar $PICARD CollectSequencingArtifactMetrics \
	I=$normal \
	O=7_N_artifact \
	R=$REF


$JAVA -Djava.io.tmpdir=out/tmpp_call/ -Xmx${MAX_RAM}g -jar $QUEUE -S queueScripts/muTect2_calling.scala \
	-tumor $tumor \
	-normal $normal \
	-dbsnp $DBSNP \
	-cosmic $COSMIC \
	-normal_panel 2_pon_combinevariants.vcf.gz \
	-o 8_mutect2.vcf.gz \
	-R $REF  \
	${QUEUE_RUNNER} \
	-jobSGDir out/ \
	-run
