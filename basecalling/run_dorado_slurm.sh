#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --mem=128gb
##SBATCH --exclude=phoenix-00
#SBATCH --gpus-per-node=8
#SBATCH --cpus-per-task=64
#SBATCH --output=%x_%j_%A_%a.log
#SBATCH --time=6-00:00:00

# Set shell options
set -o pipefail      # Set exit code of a pipeline to non-zero if a command fails
set -e               # Exit immediately if a command fails
set -u               # Exit on unset variables
set -o xtrace        # Enable xtrace for debugging

# ==============================================================================
# SLURM Basecalling Script for Oxford Nanopore Data using Dorado
#
# Runs as a SLURM array job — each task processes one pod5 path from a list.
# Supports S3 downloads, tar extraction, fast5-to-pod5 conversion, and duplex.
#
# USAGE:
#   sbatch -J dorado_SAMPLE --array=1-N%2 run_dorado_slurm.sh \
#     --pod5list paths.list --model sup@v5.0.0 [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --pod5list    File with one pod5 path per line (local, tar, or s3://)
#   --model       Basecalling model (e.g., sup@v5.0.0)
#
# OPTIONAL ARGUMENTS:
#   --mod         Modification model(s) (e.g., 5mCG_5hmCG,6mA)
#   --duplex      Run duplex basecalling
#   --project     Output base directory (default: ${BASE_DIR}/basecalled)
#   --dorado      Dorado version (default: current symlink)
#
# EXAMPLE:
#   sbatch -J dorado_FLYT2T --array=1-2%2 run_dorado_slurm.sh \
#     --pod5list ../lists/FLYT2T_pod5.list \
#     --model sup@v5.0.0 \
#     --mod 5mCG_5hmCG,6mA \
#     --project /private/nanopore/basecalled/FlyT2T/
# ==============================================================================

# ------------------------------------------------------------------------------
# Constants — edit BASE_DIR for your cluster
# ------------------------------------------------------------------------------
readonly BASE_DIR="/private/nanopore"
readonly TOOLS_DIR="${BASE_DIR}/tools"
readonly DORADO_BASE="${TOOLS_DIR}/dorado"
readonly DEFAULT_OUTPUT_DIR="${BASE_DIR}/basecalled"
readonly SCRATCH_DIR="/data/scratch/$(whoami)/temp"

# Initialize variables
POD5LIST=""
MODEL=""
MOD=""
DUPLEX=false
PROJECT=""
DORADO_VERSION=""

# Parse named arguments
set +e  # Temporarily disable error checking
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --duplex) DUPLEX=true ;;
        --pod5list) POD5LIST="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        --mod) MOD="$2"; shift ;;
        --project) PROJECT="$2"; shift ;;
        --dorado) DORADO_VERSION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
set -e  # Re-enable error checking

# Validate required arguments
if [[ -z "$POD5LIST" ]]; then
    echo "Error: Missing required argument --pod5list."
    exit 1
fi

if [[ -z "$MODEL" ]]; then
    echo "Error: Missing required argument --model."
    exit 1
fi

# Set paths
POD5=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$POD5LIST")
INBASEDIR="${SCRATCH_DIR}"

# Set Dorado binary path
if [[ -n "$DORADO_VERSION" ]]; then
    DORADO="${DORADO_BASE}/dorado-${DORADO_VERSION}-linux-x64/bin/dorado"
else
    DORADO="${DORADO_BASE}/current/bin/dorado"
fi

if [[ ! -x "$DORADO" ]]; then
    echo "Error: Dorado not found at $DORADO."
    [[ -z "$DORADO_VERSION" ]] && echo "Hint: create a symlink: ln -sfn ${DORADO_BASE}/dorado-VERSION-linux-x64 ${DORADO_BASE}/current"
    exit 1
fi

DORADOVERSION=$($DORADO --version 2>&1 | cut -d'+' -f1)
MODELVERSION=$(echo $MODEL | sed 's/\@v//')
VERSIONS="dorado${DORADOVERSION}_${MODELVERSION}"

SAMPLEID=$(basename "$POD5" | sed 's/\(\(_fast5\.tar\|_pod5\.tar\|\.fast5\.tar\|\.pod5\.tar\)\)$//' | awk -F'_' '{print $(NF-1)}')
FLOWCELL=$(basename "$POD5" | sed 's/\(\(_fast5\.tar\|_pod5\.tar\|\.fast5\.tar\|\.pod5\.tar\)\)$//' | awk -F'_' '{print $NF}')
FULLNAME=$(basename "$POD5" | sed 's/\(\(_fast5\.tar\|_pod5\.tar\|\.fast5\.tar\|\.pod5\.tar\)\)$//')
NAME="${SAMPLEID}_${FLOWCELL}"
DATE=$(date "+%T")

# Check if PROJECT variable is set and not empty
if [[ -n $PROJECT ]]; then
    OUTBASEDIR="${PROJECT}/"
else
    OUTBASEDIR="${DEFAULT_OUTPUT_DIR}/"
fi

# Setup input and output directories
if [[ ${POD5:0:2} == "s3" && ( ${POD5: -7} == ".tar.gz" || ${POD5: -4} == ".tgz" ) ]]; then
    INPUT="${INBASEDIR}/${SAMPLEID}/${FULLNAME}"
    OUTPUT="${OUTBASEDIR}"
    mkdir -p ${INPUT}
    mkdir -p ${OUTPUT}
    # Get the size of the S3 object in bytes
    POD5_SIZE=$(aws s3 ls ${POD5} --no-sign-request | awk '{print $3}')

    # Get the size of the local directory in bytes
    if [[ -d "${INPUT}" ]]; then
        INPUT_SIZE=$(du -sb "${INPUT}" | awk '{print $1}')
    else
        INPUT_SIZE=0
    fi

    # Check if the local file size is less than the S3 object size
    if (( INPUT_SIZE < POD5_SIZE )); then
        echo "Downloading and extracting pod5 tar.gz for: ${FULLNAME}"
        aws --no-sign-request s3 cp --no-progress ${POD5} ${INPUT}
        tar xzf ${INPUT}/*.tar.gz --directory ${INPUT} 2>/dev/null || tar xzf ${INPUT}/*.tgz --directory ${INPUT}
        rm -f ${INPUT}/*.tar.gz ${INPUT}/*.tgz
    else
        echo "Local file is the same size or larger than S3 object. Skipping download."
    fi

elif [[ ${POD5:0:2} == "s3" && ${POD5: -4} == ".tar" ]]; then
    INPUT="${INBASEDIR}/${SAMPLEID}/${FULLNAME}"
    OUTPUT="${OUTBASEDIR}"
    mkdir -p ${INPUT}
    mkdir -p ${OUTPUT}
    # Get the size of the S3 object in bytes
    POD5_SIZE=$(aws s3 ls ${POD5} --no-sign-request | awk '{print $3}')

    # Get the size of the local directory in bytes
    if [[ -d "${INPUT}" ]]; then
        INPUT_SIZE=$(du -sb "${INPUT}" | awk '{print $1}')
    else
        INPUT_SIZE=0
    fi

    # Check if the local file size is less than the S3 object size
    if (( INPUT_SIZE < POD5_SIZE )); then
        echo "Downloading and extracting pod5tars for: ${FULLNAME}"
        aws --no-sign-request s3 cp --no-progress ${POD5} ${INPUT}
        tar xf ${INPUT}/*.tar --directory ${INPUT}
        rm ${INPUT}/*.tar
    else
        echo "Local file is the same size or larger than S3 object. Skipping download."
    fi

elif [[ ${POD5: -7} == ".tar.gz" || ${POD5: -4} == ".tgz" ]]; then
    INPUT="${INBASEDIR}/${SAMPLEID}/${FULLNAME}"
    OUTPUT="${OUTBASEDIR}"
    mkdir -p ${INPUT}
    mkdir -p ${OUTPUT}
    # Check if INPUT directory is not empty (i.e., POD5 may have already been extracted)
    if [ -z "$(ls -A ${INPUT})" ]; then
        echo "Extracting pod5 tar.gz for: ${FULLNAME}"
        tar xzf ${POD5} --directory ${INPUT}
    else
        echo "${FULLNAME} seems to have been already extracted to ${INPUT}. Skipping extraction."
    fi

elif [[ ${POD5: -4} == ".tar" ]]; then
    INPUT="${INBASEDIR}/${SAMPLEID}/${FULLNAME}"
    OUTPUT="${OUTBASEDIR}"
    mkdir -p ${INPUT}
    mkdir -p ${OUTPUT}
    # Check if INPUT directory is not empty (i.e., POD5 may have already been extracted)
    if [ -z "$(ls -A ${INPUT})" ]; then
        echo "Extracting pod5tars for: ${FULLNAME}"
        tar xf ${POD5} --directory ${INPUT}
    else
        echo "${FULLNAME} seems to have been already extracted to ${INPUT}. Skipping extraction."
    fi
else
    echo "Setting up pod5s for: ${FULLNAME}"
    INPUT=$POD5
    OUTPUT="${OUTBASEDIR}"
    #mkdir -p ${INPUT}
    mkdir -p ${OUTPUT}
fi

# Check for and convert fast5 data to pod5
if [[ -n $(find ${INPUT} -type d -name "fast5" -print) ]]; then
    FAST5=$(find ${INPUT} -type d -name "fast5" -print)
    newPOD5s="${INPUT}/pod5_dir"
    mkdir -p ${newPOD5s}

    # Check if output.pod5 already exists
    if [[ ! -f "${newPOD5s}/output.pod5" ]]; then
        echo "Converting fast5 to pod5..."
        pod5 convert fast5 ${FAST5}/*.fast5 -o ${newPOD5s}/output.pod5
    else
        echo "output.pod5 already exists. Skipping conversion."
    fi

    INPUT="${newPOD5s}/output.pod5"
fi

# Basecalling ONT data with dorado
echo "Start basecalling at: ${DATE}"

# Modify BAMNAME to avoid commas
if $DUPLEX && [[ -n $MOD ]]; then
    echo "This is duplex data and mod model was provided, will run duplex with modifications."
    BAMNAME=${OUTPUT}/${FULLNAME}_${VERSIONS}_${MOD//,/_}
    $DORADO duplex ${MODEL},${MOD} ${INPUT} --recursive --batchsize 256 > ${BAMNAME}.bam
elif $DUPLEX; then
    echo "This is duplex data, will run duplex."
    BAMNAME=${OUTPUT}/${FULLNAME}_${VERSIONS}
    $DORADO duplex ${MODEL} ${INPUT} --recursive --batchsize 256 > ${BAMNAME}.bam
elif [[ -n $MOD ]]; then
    echo "Mod model was provided, will run with modifications."
    BAMNAME=${OUTPUT}/${FULLNAME}_${VERSIONS}_${MOD//,/_}
    $DORADO basecaller ${MODEL},${MOD} ${INPUT} --recursive --batchsize 256 > ${BAMNAME}.bam
else
    echo "No mod model was provided, will run without modifications."
    BAMNAME=${OUTPUT}/${FULLNAME}_${VERSIONS}
    $DORADO basecaller ${MODEL} ${INPUT} --recursive --batchsize 256 > ${BAMNAME}.bam
fi

echo "End basecalling at: ${DATE}"

# Generate dorado summary
$DORADO summary ${BAMNAME}.bam | gzip > ${BAMNAME}_summary.txt.gz

# Final cleanup
if [[ $INPUT == $INBASEDIR* ]]; then
    rm -r ${INPUT}
else
    echo "$INPUT not deleted as it's not on compute node temp scratch. Please delete raw fast5 or pod5 data whenever possible."
fi
