#!/bin/bash
#SBATCH --job-name=rs-full-build
#SBATCH --partition=savio3
#SBATCH --account=$HPC_ACCT
#SBATCH --time=06:00:00

# ---------------------------------------------------------------------
# WORKER POOL CONFIGURATION
# ---------------------------------------------------------------------
# Request a pool of nodes (e.g., 10).
# One node acts as the Controller (running Make), the others are Workers.
#SBATCH --nodes=12
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=0
#SBATCH --exclusive

#SBATCH --output=log/slurm-cluster-%j.out
#SBATCH --error=log/slurm-cluster-%j.err

export XDG_CACHE_HOME=/tmp/$USER/.cache
mkdir -p "$XDG_CACHE_HOME"

set -euo pipefail

module purge
module load python/3.11
module load emacs
module load texlive/2024

# 1. Thread Safety (Global)
# We pin EVERY task on EVERY node to 1 thread to avoid explosions.
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

# 2. Output: Unbuffer Python so we see logs immediately
export PYTHONUNBUFFERED=1

# ---------------------------------------------------------------------
# DISTRIBUTED EXECUTION SETUP
# ---------------------------------------------------------------------
# Define the Launcher for heavy tasks.
# - --exclusive: Locks a full node from our pool for one specific task.
# - --nodes=1: Uses exactly one node per task.
export HEAVY_LAUNCHER="srun --nodes=1 --ntasks=1 --cpus-per-task=40 --exclusive"

# Tell the Python scripts they have 40 cores available on the remote node.
export CORES=40

echo "=================================================================="
echo "Starting Cluster Build"
echo "  - Master Node: $(hostname)"
echo "  - Total Nodes Allocated: $SLURM_JOB_NUM_NODES"
echo "  - Strategy: 'make' runs locally; 'srun' dispatches to pool."
echo "=================================================================="

# ---------------------------------------------------------------------
# PHASE 0: PROVISIONING (Serial / Local)
# ---------------------------------------------------------------------
# We run 'make src' locally to ensure the Python code exists.
# We skip 'make downloads' because compute nodes usually lack internet.
# (Assumes you ran 'make downloads' on the login node).
echo "[SLURM] Phase 0: Tangling source code..."
make src_code

# ---------------------------------------------------------------------
# PHASE 1: DISTRIBUTED BUILD (Parallel)
# ---------------------------------------------------------------------
# -j40: Allows up to 40 targets to run simultaneously.
#   - Heavy targets (using HEAVY_LAUNCHER) will consume 1 Node each.
#   - Light targets (LaTeX, tables) will run locally on the Master Node.
echo "[SLURM] Phase 1: Launching Distributed Build..."
make -j40
