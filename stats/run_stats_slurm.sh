#!/bin/bash
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --mem=16gb
#SBATCH --cpus-per-task=4
#SBATCH --output=%x_%j.log
#SBATCH --time=1:00:00

# Set shell options
set -o pipefail
set -e
set -u
set -o xtrace

# ==============================================================================
# SLURM wrapper for ONT stats Python scripts
#
# Runs any of the summary stats scripts on the cluster, redirecting stdout
# to a file for easy import into Google Sheets.
#
# USAGE:
#   sbatch -J stats_SAMPLE run_stats_slurm.sh \
#     --script SCRIPT --out OUTPUT [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   --script  Path to the Python stats script to run
#   --out     Output file for results (CSV)
#
# OPTIONAL ARGUMENTS:
#   --args    Quoted string of arguments to pass to the Python script
#
# EXAMPLES:
#   sbatch -J stats_FlyT2T run_stats_slurm.sh \
#     --script /private/nanopore/tools/scripts/ont_data_tools/stats/calculate_summary_stats_v3.py \
#     --out FlyT2T_stats.csv \
#     --args "--size 3.3 --no-append --dir /private/nanopore/basecalled/FlyT2T"
#
#   sbatch -J stats_RNA run_stats_slurm.sh \
#     --script /private/nanopore/tools/scripts/ont_data_tools/stats/calculate_summary_stats_rna.py \
#     --out RNA_stats.csv \
#     --args "--no-append --dir /private/nanopore/basecalled/RNA"
# ==============================================================================

SCRIPT=""
OUT=""
SCRIPT_ARGS=()

set +e
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --script) SCRIPT="$2"; shift ;;
        --out)    OUT="$2"; shift ;;
        --args)   read -ra SCRIPT_ARGS <<< "$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
set -e

if [[ -z "$SCRIPT" ]]; then
    echo "Error: Missing required argument --script."
    exit 1
fi

if [[ -z "$OUT" ]]; then
    echo "Error: Missing required argument --out."
    exit 1
fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "Error: Script not found: $SCRIPT"
    exit 1
fi

echo "Running stats at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Script: ${SCRIPT}"
echo "Output: ${OUT}"
echo "Args: ${SCRIPT_ARGS[*]+"${SCRIPT_ARGS[*]}"}"

python3 "${SCRIPT}" "${SCRIPT_ARGS[@]}" > "${OUT}"

echo "Done at: $(date '+%Y-%m-%d %H:%M:%S')"
