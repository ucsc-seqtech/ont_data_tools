# ==============================================================================
# ont_data_tools — bashrc additions for PromethION towers
# Add the following to your ~/.bashrc on the tower.
# Not needed on the cluster — cluster users can call scripts directly.
# ==============================================================================

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/data/user_scripts/tools/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/data/user_scripts/tools/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/data/user_scripts/tools/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/data/user_scripts/tools/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# --- Summary stats convenience functions ---
# Optional aliases so tower users can run e.g. `pullstats_dna_ul --size 3.3 --dir ...`
# without needing to activate conda or remember script paths.

pullstats_dna_ul() {
    local args=("$@")
    set --
    source /data/user_scripts/tools/miniconda3/bin/activate
    python /data/user_scripts/scripts/stats/calculate_summary_stats_v3.py "${args[@]}"
}

pullstats_dna_hmw() {
    local args=("$@")
    set --
    source /data/user_scripts/tools/miniconda3/bin/activate
    python /data/user_scripts/scripts/stats/calculate_summary_stats_v3_under_100kb.py "${args[@]}"
}

pullstats_rna() {
    local args=("$@")
    set --
    source /data/user_scripts/tools/miniconda3/bin/activate
    python /data/user_scripts/scripts/stats/calculate_summary_stats_rna.py "${args[@]}"
}

export PATH="/data/user_scripts/scripts/basecalling:$PATH"
