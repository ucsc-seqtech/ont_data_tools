#!/bin/bash
# ==============================================================================
# Script for Basecalling Oxford Nanopore Data using Dorado
#
# DESCRIPTION:
#   Processes a list of directories containing pod5 files using Dorado.
#   Each directory is processed sequentially, with Dorado managing GPU resources.
#
# USAGE:
#   ./dorado_dirs.sh --dirlist FILE --model MODEL [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --dirlist     File containing input directories (one per line)
#   --model       Basecalling model (e.g., sup@v5.0.0)
#
# OPTIONAL ARGUMENTS:
#   --mod         Modification model(s) (e.g., 5mCG_5hmCG,6mA)
#   --drd_opts    Extra options passed directly to dorado (e.g., "--estimate-poly-a")
#   --dryrun      Print commands only; do not execute
#   --output      Output directory (default: .)
#   --dorado      Dorado version (default: current symlink)
#
# EXAMPLES:
#   # Basecall DNA with mods (real run)
#   ./dorado_dirs.sh \
#     --dirlist dna_dirs.txt \
#     --model sup@v5.0.0 \
#     --mod 5mCG_5hmCG,6mA \
#     --output ./dna_output \
#
#   # Basecall RNA with poly-A estimation
#   ./dorado_dirs.sh \
#     --dirlist rna_dirs.txt \
#     --model rna004_130bps_sup@v5.1.0 \
#     --drd_opts "--estimate-poly-a" \
#     --output ./rna_output \
#
#   # Dryrun: show commands without executing
#   ./dorado_dirs.sh \
#     --dirlist test_dirs.txt \
#     --model sup@v5.0.0 \
#     --mod 5mCG_5hmCG,6mA \
#     --dryrun \
# ==============================================================================
set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Constants and Defaults
# ------------------------------------------------------------------------------
readonly DEFAULT_OUTPUT_DIR="./"
readonly TOOLS_DIR="/data/user_scripts"
readonly DORADO_BASE="${TOOLS_DIR}/tools/dorado"

# ------------------------------------------------------------------------------
# Global Variable Initialization
# ------------------------------------------------------------------------------
DIRLIST=""
MODEL=""
MOD=""
DRD_OPTS=()
DRY_RUN=false
OUTPUT=""
DORADO_VERSION=""

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dirlist)           DIRLIST="$2"; shift 2 ;;  
        --model)             MODEL="$2"; shift 2 ;;  
        --mod)               MOD="$2"; shift 2 ;;
        --drd_opts)          read -ra DRD_OPTS <<< "$2"; shift 2 ;;
        --dryrun)            DRY_RUN=true; shift 1 ;;
        --output)            OUTPUT="$2"; shift 2 ;;
        --dorado)            DORADO_VERSION="$2"; shift 2 ;;
        *) echo "Error: Unknown parameter '$1'" >&2; exit 1 ;;  
    esac
done

# ------------------------------------------------------------------------------
# Pre-flight Summary
# ------------------------------------------------------------------------------
echo "DRYRUN mode: ${DRY_RUN}"

# ------------------------------------------------------------------------------
# Input Validation
# ------------------------------------------------------------------------------
if [[ "$DRY_RUN" != true ]]; then
  if [[ -z "$DIRLIST" ]]; then
      echo "Error: --dirlist is required" >&2
      exit 1
  fi
  if [[ ! -f "$DIRLIST" ]]; then
      echo "Error: Directory list file '$DIRLIST' not found" >&2
      exit 1
  fi
  if [[ -z "$MODEL" ]]; then
      echo "Error: --model is required" >&2
      exit 1
  fi
fi

# ------------------------------------------------------------------------------
# Setup Output & Dorado Path
# ------------------------------------------------------------------------------
OUTPUT=${OUTPUT:-${DEFAULT_OUTPUT_DIR}}
mkdir -p "$OUTPUT"
if [[ -n "$DORADO_VERSION" ]]; then
    DORADO="${DORADO_BASE}/dorado-${DORADO_VERSION}-linux-x64/bin/dorado"
else
    DORADO="${DORADO_BASE}/current/bin/dorado"
fi

# Check executable when not in dryrun
if [[ "$DRY_RUN" != true && ! -x "$DORADO" ]]; then
    echo "Error: Dorado not found at $DORADO" >&2
    [[ -z "$DORADO_VERSION" ]] && echo "Hint: create a symlink: ln -sfn ${DORADO_BASE}/dorado-VERSION-linux-x64 ${DORADO_BASE}/current" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Version String Construction
# ------------------------------------------------------------------------------
if [[ -x "$DORADO" ]]; then
    DORADO_VERSION_SHORT=$("$DORADO" --version 2>&1 | cut -d'+' -f1)
else
    DORADO_VERSION_SHORT="${DORADO_VERSION:-unknown}"
fi
MODEL_BASENAME=$(basename "$MODEL")
MODEL_NAME=$(echo "$MODEL_BASENAME" | cut -d'@' -f1)
MODEL_VERSION=$(echo "$MODEL_BASENAME" | grep -o '@.*' | sed 's/@//')
VERSION_STRING="dorado${DORADO_VERSION_SHORT}_${MODEL_NAME}${MODEL_VERSION}"
if [[ -n "$MOD" ]]; then
    MOD_CLEAN=$(echo "$MOD" | tr ',' '_')
    VERSION_STRING+="_${MOD_CLEAN}"
fi
mkdir -p "./logs"

# ------------------------------------------------------------------------------
# Function: process_directory
# ------------------------------------------------------------------------------
process_directory() {
    local INPUT_DIR="$1"
    local DIRNAME=$(basename "$INPUT_DIR")
    local LOG_FILE="./logs/${DIRNAME}_${VERSION_STRING}.log"

    # Construct basecaller args
    local BASECALL_MODEL="$MODEL"
    if [[ -n "$MOD" ]]; then
        BASECALL_MODEL="${BASECALL_MODEL},${MOD}"
    fi

    # Build final command
    local CMD="${DORADO} basecaller ${BASECALL_MODEL} ${INPUT_DIR} --recursive ${DRD_OPTS[*]} -x cuda:0,1,2,3"

    # Logging
    echo "==================== JOB START ====================" | tee -a "$LOG_FILE"
    echo "Directory: ${DIRNAME}" | tee -a "$LOG_FILE"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
    echo "Version String: ${VERSION_STRING}" | tee -a "$LOG_FILE"
    echo "Command: ${CMD}" | tee -a "$LOG_FILE"

    # Execute or dryrun
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRYRUN] Output BAM would be: ${OUTPUT}/${DIRNAME}_${VERSION_STRING}.bam" | tee -a "$LOG_FILE"
    else
        eval "$CMD" 2>> "$LOG_FILE" > "${OUTPUT}/${DIRNAME}_${VERSION_STRING}.bam"
        echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
        echo "Output BAM: ${OUTPUT}/${DIRNAME}_${VERSION_STRING}.bam" | tee -a "$LOG_FILE"
        "${DORADO}" summary "${OUTPUT}/${DIRNAME}_${VERSION_STRING}.bam" | gzip > "${OUTPUT}/${DIRNAME}_${VERSION_STRING}_summary.txt.gz"
    fi

    echo "==================== JOB END =======================" | tee -a "$LOG_FILE"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

mapfile -t DIRECTORIES < "$DIRLIST"
TOTAL=${#DIRECTORIES[@]}

echo "Found ${TOTAL} directories to process."
echo "Using version string: ${VERSION_STRING}"

echo "Processing in dryrun mode: ${DRY_RUN}"
for (( i=0; i<TOTAL; i++ )); do
    DIR="${DIRECTORIES[$i]}"
    echo "Processing directory $((i+1))/${TOTAL}: $DIR"
    process_directory "$DIR"
done

echo "All directories processed at: $(date '+%Y-%m-%d %H:%M:%S')"
