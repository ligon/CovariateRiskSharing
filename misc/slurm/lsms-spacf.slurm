#!/bin/bash
#SBATCH --job-name=rs-spacf
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=40
#SBATCH --output=log/slurm-spacf-%j.out
#SBATCH --error=log/slurm-spacf-%j.err
#SBATCH --account=$HPC_ACCT
#SBATCH --partition=savio3

export PYTHONUNBUFFERED=1 # Don't buffer logging info

export XDG_CACHE_HOME=/tmp/$USER/.cache
mkdir -p "$XDG_CACHE_HOME"
export MAMBA_APPDIR="$XDG_CACHE_HOME/mamba"
mkdir -p "$MAMBA_APPDIR"

set -euo pipefail

module purge
module load python/3.11

cd "${SLURM_SUBMIT_DIR:?Need SLURM_SUBMIT_DIR}"
mkdir -p log

# 1. STOP NUMPY FROM MULTITHREADING
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# 2. CALCULATE RESOURCES
MAKE_JOBS=3
CORES_PER_JOB=$((SLURM_CPUS_PER_TASK / MAKE_JOBS))

echo "Resource Plan:"
echo "  - Total Allocation: $SLURM_CPUS_PER_TASK cores"
echo "  - Make Parallelism: $MAKE_JOBS concurrent jobs"
echo "  - Joblib Workers:   $CORES_PER_JOB per job"
echo "  - NumPy Threads:    1 per worker"
echo "  - Total Utilization: $((MAKE_JOBS * CORES_PER_JOB)) / $SLURM_CPUS_PER_TASK cores"

# 3. EXECUTE
poetry run make -j$MAKE_JOBS -f Makefile_spacf \
    DRAWS=1000 \
    CORES=$CORES_PER_JOB

