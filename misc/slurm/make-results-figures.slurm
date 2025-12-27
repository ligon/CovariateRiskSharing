#!/bin/bash
#SBATCH --job-name=rs-results
#SBATCH --partition=savio3
#SBATCH --account=$HPC_ACCT
#SBATCH --time=06:00:00

# 1. Request the full node's power
#SBATCH --cpus-per-task=40
#SBATCH --exclusive
#SBATCH --mem=0
#SBATCH --output=log/slurm-results-%j.out
#SBATCH --error=log/slurm-results-%j.err

set -euo pipefail

module purge
module load python/3.11
module load emacs

cd "${SLURM_SUBMIT_DIR:?Need SLURM_SUBMIT_DIR}"
mkdir -p log

# 2. THE SAFETY VALVE (Crucial)
# Since we are parallelizing via Make (processes), we MUST disable 
# Python's internal multithreading.
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

# 3. Execute
# -j40 means Make will run up to 40 targets at once.
# Since we set OMP_NUM_THREADS=1, each target stays in its lane (1 core).
echo "Starting build with $SLURM_CPUS_PER_TASK parallel workers..."
make -j$SLURM_CPUS_PER_TASK results figures

