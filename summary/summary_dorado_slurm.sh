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
# SLURM Summary Script for Oxford Nanopore BAMs using Dorado
#
# Runs as a SLURM array job — each task generates a summary for one BAM
# from a list. Output is a gzipped TSV alongside the BAM or in --project.
#
# USAGE:
#   sbatch -J summary_SAMPLE --array=1-N summary_dorado_slurm.sh \
#     --bamlist bams.list [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --bamlist     File with one BAM path per line
#
# OPTIONAL ARGUMENTS:
#   --project     Output directory (default: same directory as each BAM)
#   --dorado      Dorado version (default: current symlink)
#
# EXAMPLE:
#   sbatch -J summary_FlyT2T --array=1-4 summary_dorado_slurm.sh \
#     --bamlist ../lists/FlyT2T_bams.list \
#     --project /private/nanopore/summaries/FlyT2T/
# ==============================================================================

# ------------------------------------------------------------------------------
# Constants — edit BASE_DIR for your cluster
# ------------------------------------------------------------------------------
readonly BASE_DIR="/private/nanopore"
readonly TOOLS_DIR="${BASE_DIR}/tools"
readonly DORADO_BASE="${TOOLS_DIR}/dorado"

# Initialize variables
BAMLIST=""
PROJECT=""
DORADO_VERSION=""

# Parse named arguments
set +e  # Temporarily disable error checking
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --bamlist) BAMLIST="$2"; shift ;;
        --project) PROJECT="$2"; shift ;;
        --dorado)  DORADO_VERSION="$2"; shift ;;
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

# Set output directory
if [[ -n "$PROJECT" ]]; then
    OUTDIR="${PROJECT}"
else
    OUTDIR=$(dirname "$BAM")
fi

mkdir -p "${OUTDIR}"

OUTPUT="${OUTDIR}/${FULLNAME}_summary.txt.gz"

# Generate summary
echo "Start dorado summary at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Input BAM: ${BAM}"
echo "Output: ${OUTPUT}"

$DORADO summary "${BAM}" | gzip > "${OUTPUT}"

echo "End dorado summary at: $(date '+%Y-%m-%d %H:%M:%S')"
