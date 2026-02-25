# ONT Data Tools

Tools for Oxford Nanopore sequencing data: basecalling with Dorado, summary statistics, and archival/data management.

For detailed workflow documentation, see the [Workflow Overview](https://ucsc-cgl.atlassian.net/wiki/spaces/~63c888081d7734b550c2052b/pages/2553348107/Workflow+Overview#).

## Prerequisites

- [Dorado](https://github.com/nanoporetech/dorado) (basecaller)
- [Miniconda](https://docs.conda.io/en/latest/miniconda.html) with Python 3, pandas, numpy
- [samtools](http://www.htslib.org/)
- GNU coreutils (parallel, gzip, tar)

## Directory Structure

The tools expect a standard layout at `/data/user_scripts/`:

```
/data/user_scripts/
├── scripts/            # This repo
│   ├── basecalling/
│   │   ├── run_dorado_local_dirs.sh
│   │   └── run_dorado_slurm.sh
│   ├── stats/
│   │   ├── calculate_summary_stats_v3.py
│   │   ├── calculate_summary_stats_v3_under_100kb.py
│   │   └── calculate_summary_stats_rna.py
│   ├── archival/
│   │   ├── tar_flowcells.sh
│   │   ├── tar_cleanup.sh
│   │   └── tar_report.sh
│   ├── utilities/
│   │   ├── cleanup.sh
│   │   └── organize.sh
│   └── bashrc_additions.sh
├── tools/              # External tools (dorado, miniconda3, samtools)
└── ref_files/          # Reference genomes
```

## Scripts

### Basecalling

- **`basecalling/run_dorado_local_dirs.sh`** — Tower basecalling. Processes a list of directories containing pod5 files sequentially with Dorado. Supports DNA/RNA models, modification calling, and dry-run mode.
- **`basecalling/run_dorado_slurm.sh`** — SLURM cluster basecalling. Runs as an array job — each task processes one pod5 path from a list. Supports S3 downloads, tar extraction, and fast5-to-pod5 conversion. Edit `BASE_DIR` at the top for your cluster paths.

### Summary Statistics

- **`stats/calculate_summary_stats_v3.py`** — Coverage, N50, and read length distribution for DNA runs (UL bins: 100kb–1Mb+).
- **`stats/calculate_summary_stats_v3_under_100kb.py`** — Same metrics with finer bins for shorter reads (20kb–100kb+).
- **`stats/calculate_summary_stats_rna.py`** — RNA-specific metrics: total reads (millions), quality score bins (Q5–Q25).

### Archival

- **`archival/tar_flowcells.sh`** — Tar flowcell directories in parallel for transfer.
- **`archival/tar_cleanup.sh`** — Verify tar archives against source directories and clean up originals.
- **`archival/tar_report.sh`** — Generate a CSV report comparing tar archives to source data.

### Utilities

- **`utilities/cleanup.sh`** — Verify archived data against a remote destination and optionally delete local copies.
- **`utilities/organize.sh`** — Sort files into an organized upload folder structure by sample ID.

## Deployment

1. Clone this repo as `scripts` under `/data/user_scripts/`:
   ```bash
   git clone <repo_url> /data/user_scripts/scripts
   ```
2. Append the contents of `bashrc_additions.sh` to your `~/.bashrc`
3. Install Dorado and miniconda into `/data/user_scripts/tools/`
4. Create a `current` symlink pointing to the active Dorado version:
   ```bash
   ln -sfn /data/user_scripts/tools/dorado/dorado-1.3.0-linux-x64 \
           /data/user_scripts/tools/dorado/current
   ```
   Update the symlink when upgrading Dorado — the basecalling scripts use it by default.
5. Install Python dependencies: `conda install pandas numpy`

## Usage

### Basecalling (Tower)

```bash
# DNA basecalling with modifications
run_dorado_local_dirs.sh \
  --dirlist dna_dirs.txt \
  --model sup@v5.0.0 \
  --mod 5mCG_5hmCG,6mA \
  --output ./dna_output

# RNA basecalling with poly-A estimation
run_dorado_local_dirs.sh \
  --dirlist rna_dirs.txt \
  --model rna004_130bps_sup@v5.1.0 \
  --drd_opts "--estimate-poly-a" \
  --output ./rna_output

# Dry run (print commands without executing)
run_dorado_local_dirs.sh \
  --dirlist dirs.txt \
  --model sup@v5.0.0 \
  --dryrun
```

### Basecalling (SLURM cluster)

```bash
# Submit array job for 10 pod5 paths, 2 at a time
sbatch -J dorado_SAMPLE --array=1-10%2 run_dorado_slurm.sh \
  --pod5list paths.list \
  --model sup@v5.0.0 \
  --mod 5mCG_5hmCG,6mA \
  --project /private/nanopore/basecalled/MyProject/

# RNA basecalling with poly-A estimation
sbatch -J dorado_RNA --array=1-4%2 run_dorado_slurm.sh \
  --pod5list rna_paths.list \
  --model rna004_130bps_sup@v5.1.0 \
  --drd_opts "--estimate-poly-a" \
  --project /private/nanopore/basecalled/MyRNAProject/
```

### Summary Statistics

```bash
# DNA stats for all runs matching a pattern
pullstats_dna_ul --size 3.3 --dir "/data/run_*"

# DNA stats with finer bins (HMW / under-100kb focus)
pullstats_dna_hmw --size 3.3 --dir "/data/run_*"

# RNA stats
pullstats_rna --dir "/data/rna_run_*"
```

The `pullstats_*` shell functions (defined in `bashrc_additions.sh`) activate conda and call the appropriate Python script.
