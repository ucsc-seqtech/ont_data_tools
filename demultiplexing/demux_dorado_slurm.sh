#!/bin/bash
#SBATCH --partition=long
#SBATCH --nodes=1
#SBATCH --mem=32gb
#SBATCH --cpus-per-task=16
#SBATCH --output=%x_%j_%A_%a.log
#SBATCH --time=12:00:00

# Set shell options
set -o pipefail      # Set exit code of a pipeline to non-zero if a command fails
set -e               # Exit immediately if a command fails
set -u               # Exit on unset variables
set -o xtrace        # Enable xtrace for debugging

# ==============================================================================
# SLURM Demultiplexing Script for Oxford Nanopore Data using Dorado
#
# Runs as a SLURM array job — each task processes one BAM from a list.
# Demultiplexes barcoded reads by kit name and emits per-barcode BAMs.
#
# USAGE:
#   sbatch -J demux_SAMPLE --array=1-N run_demux_dorado_slurm.sh \
#     --bamlist bams.list --kit SQK-NBD114-24 [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --bamlist     File with one BAM path per line
#   --kit         Barcoding kit name (e.g., SQK-NBD114-24)
#
# OPTIONAL ARGUMENTS:
#   --no_classify Use existing barcode tags from basecalling (skip re-classification)
#                 Use this when --kit-name was already passed during basecalling
#   --emit_fastq  Emit demultiplexed reads as FASTQ instead of BAM
#   --drd_opts    Extra options passed directly to dorado demux
#   --project     Output base directory (default: ${BASE_DIR}/demultiplexed)
#   --dorado      Dorado version (default: current symlink)
#
# EXAMPLES:
#   # Classify reads during demux (kit not used at basecalling)
#   sbatch -J demux_FlyT2T --array=1-4 demux_dorado_slurm.sh \
#     --bamlist ../lists/FlyT2T_bams.list \
#     --kit SQK-NBD114-24 \
#     --project /private/nanopore/demultiplexed/FlyT2T/
#
#   # Use existing barcode tags from basecalling (kit was passed to dorado basecaller)
#   sbatch -J demux_FlyT2T --array=1-4 demux_dorado_slurm.sh \
#     --bamlist ../lists/FlyT2T_bams.list \
#     --kit SQK-NBD114-24 \
#     --no_classify \
#     --project /private/nanopore/demultiplexed/FlyT2T/
# ==============================================================================

# ------------------------------------------------------------------------------
# Constants — edit BASE_DIR for your cluster
# ------------------------------------------------------------------------------
readonly BASE_DIR="/private/nanopore"
readonly TOOLS_DIR="${BASE_DIR}/tools"
readonly DORADO_BASE="${TOOLS_DIR}/dorado"
readonly DEFAULT_OUTPUT_DIR="${BASE_DIR}/demultiplexed"

# Initialize variables
BAMLIST=""
KIT=""
DRD_OPTS=()
PROJECT=""
DORADO_VERSION=""
EMIT_FASTQ=false
NO_CLASSIFY=false

# Parse named arguments
set +e  # Temporarily disable error checking
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --bamlist)    BAMLIST="$2"; shift ;;
        --kit)        KIT="$2"; shift ;;
        --drd_opts)   read -ra DRD_OPTS <<< "$2"; shift ;;
        --project)    PROJECT="$2"; shift ;;
        --dorado)      DORADO_VERSION="$2"; shift ;;
        --emit_fastq)  EMIT_FASTQ=true ;;
        --no_classify) NO_CLASSIFY=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
set -e  # Re-enable error checking

# Validate required arguments
if [[ -z "$BAMLIST" ]]; then
    echo "Error: Missing required argument --bamlist."
    exit 1
fi

if [[ -z "$KIT" ]]; then
    echo "Error: Missing required argument --kit."
    exit 1
fi

# Get BAM for this array task
BAM=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$BAMLIST")
FULLNAME=$(basename "$BAM" .bam)

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
VERSIONS="dorado${DORADOVERSION}_demux_${KIT}"

# Set output directory
if [[ -n "$PROJECT" ]]; then
    OUTBASEDIR="${PROJECT}"
else
    OUTBASEDIR="${DEFAULT_OUTPUT_DIR}"
fi

OUTPUT="${OUTBASEDIR}/${FULLNAME}_${VERSIONS}"
mkdir -p "${OUTPUT}"

# Build demux arguments
DEMUX_ARGS=(
    --kit-name "${KIT}"
    --output-dir "${OUTPUT}"
    --emit-summary
)

if [[ "$NO_CLASSIFY" == true ]]; then
    DEMUX_ARGS+=(--no-classify)
fi

if [[ "$EMIT_FASTQ" == true ]]; then
    DEMUX_ARGS+=(--emit-fastq)
fi

if [[ ${#DRD_OPTS[@]} -gt 0 ]]; then
    DEMUX_ARGS+=("${DRD_OPTS[@]}")
fi

# Demultiplex
echo "Start demultiplexing at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Input BAM: ${BAM}"
echo "Kit: ${KIT}"
echo "Output directory: ${OUTPUT}"

$DORADO demux "${DEMUX_ARGS[@]}" "${BAM}"

echo "End demultiplexing at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Output directory: ${OUTPUT}"
