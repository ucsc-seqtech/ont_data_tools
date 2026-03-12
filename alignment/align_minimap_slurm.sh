#!/bin/bash
#SBATCH --partition=long
#SBATCH --nodes=1
#SBATCH --mem=128gb
#SBATCH --cpus-per-task=64
#SBATCH --output=%x_%j_%A_%a.log
#SBATCH --time=2-00:00:00

# Set shell options
set -o pipefail      # Set exit code of a pipeline to non-zero if a command fails
set -e               # Exit immediately if a command fails
set -u               # Exit on unset variables
set -o xtrace        # Enable xtrace for debugging

# ==============================================================================
# SLURM Alignment Script for Oxford Nanopore Data using minimap2
#
# Runs as a SLURM array job — each task aligns one input file from a list.
# Supports BAM, FASTQ, and gzipped FASTQ inputs. Outputs sorted, indexed BAM.
#
# USAGE:
#   sbatch -J align_SAMPLE --array=1-N align_minimap_slurm.sh \
#     --inputlist reads.list --reference ref.fa [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --inputlist   File with one input path per line (BAM, FASTQ, or FASTQ.gz)
#   --reference   Path to reference genome (FASTA or FASTA.gz)
#
# OPTIONAL ARGUMENTS:
#   --preset      minimap2 preset (default: map-ont)
#   --mm2_opts    Extra options passed directly to minimap2
#   --project     Output base directory (default: ${BASE_DIR}/aligned)
#
# EXAMPLES:
#   # DNA alignment (default map-ont preset)
#   sbatch -J align_FlyT2T --array=1-4 align_minimap_slurm.sh \
#     --inputlist ../lists/FlyT2T_reads.list \
#     --reference /private/nanopore/references/fly_T2T.fa \
#     --preset map-ont \
#     --project /private/nanopore/aligned/FlyT2T/
#
#   # RNA alignment (splice-aware)
#   sbatch -J align_RNA --array=1-4 align_minimap_slurm.sh \
#     --inputlist ../lists/RNA_reads.list \
#     --reference /private/nanopore/references/genome.fa \
#     --preset splice \
#     --mm2_opts "--secondary=no -s 40 -G 350k" \
#     --project /private/nanopore/aligned/RNA/
# ==============================================================================

# ------------------------------------------------------------------------------
# Constants — edit BASE_DIR for your cluster
# ------------------------------------------------------------------------------
readonly BASE_DIR="/private/nanopore"
readonly TOOLS_DIR="${BASE_DIR}/tools"
readonly MINIMAP2="${TOOLS_DIR}/minimap2/current/minimap2"
readonly DEFAULT_OUTPUT_DIR="${BASE_DIR}/aligned"

# Initialize variables
INPUTLIST=""
REFERENCE=""
PRESET="map-ont"
MM2_OPTS=()
PROJECT=""
THREADS="${SLURM_CPUS_PER_TASK:-64}"

# Parse named arguments
set +e  # Temporarily disable error checking
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --inputlist)  INPUTLIST="$2"; shift ;;
        --reference)  REFERENCE="$2"; shift ;;
        --preset)     PRESET="$2"; shift ;;
        --mm2_opts)   read -ra MM2_OPTS <<< "$2"; shift ;;
        --project)    PROJECT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
set -e  # Re-enable error checking

# Validate required arguments
if [[ -z "$INPUTLIST" ]]; then
    echo "Error: Missing required argument --inputlist."
    exit 1
fi

if [[ -z "$REFERENCE" ]]; then
    echo "Error: Missing required argument --reference."
    exit 1
fi

# Validate tools
if [[ ! -x "$MINIMAP2" ]]; then
    echo "Error: minimap2 not found at $MINIMAP2."
    exit 1
fi

if ! command -v samtools &>/dev/null; then
    echo "Error: samtools not found in PATH."
    exit 1
fi

# Get input for this array task
INPUT=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$INPUTLIST")

# Derive names
FULLNAME=$(basename "$INPUT" | sed 's/\.\(bam\|fastq\.gz\|fastq\|fq\.gz\|fq\)$//')
REFNAME=$(basename "$REFERENCE" | sed 's/\.\(fa\|fasta\|fna\)\(\.gz\)\?$//')

# Build version string
MM2_VERSION=$("$MINIMAP2" --version 2>&1)
VERSIONS="minimap2-${MM2_VERSION}_${PRESET}"

# Set output directory
if [[ -n "$PROJECT" ]]; then
    OUTBASEDIR="${PROJECT}"
else
    OUTBASEDIR="${DEFAULT_OUTPUT_DIR}"
fi

mkdir -p "${OUTBASEDIR}"
BAMNAME="${OUTBASEDIR}/${FULLNAME}_${REFNAME}_${VERSIONS}"

# Align and sort
echo "Start alignment at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Input: ${INPUT}"
echo "Reference: ${REFERENCE}"
echo "Preset: ${PRESET}"
echo "Threads: ${THREADS}"
echo "Output: ${BAMNAME}.bam"

if [[ "${INPUT}" == *.bam ]]; then
    samtools fastq -T "*" "${INPUT}" \
        | "$MINIMAP2" -ax "${PRESET}" -t "${THREADS}" "${MM2_OPTS[@]}" "${REFERENCE}" - \
        | samtools sort -@ "${THREADS}" -o "${BAMNAME}.bam"
else
    "$MINIMAP2" -ax "${PRESET}" -t "${THREADS}" "${MM2_OPTS[@]}" "${REFERENCE}" "${INPUT}" \
        | samtools sort -@ "${THREADS}" -o "${BAMNAME}.bam"
fi

samtools index "${BAMNAME}.bam"

echo "End alignment at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Output BAM: ${BAMNAME}.bam"
echo "Output index: ${BAMNAME}.bam.bai"
