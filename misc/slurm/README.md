# SLURM Job Templates

Use these example scripts as starting points for running the replication on a
batch cluster. They assume you submit the job from the repository root
(`sbatch docs/slurm/make-results-figures.slurm`) and that the cluster provides
standard modules for `git`, `python`, `emacs`, and (optionally) `texlive`.

## Files

- `make-results-figures.slurm` – runs `make results figures`
  (tables, PNG figures, and the `build/var/uganda_preferred.rgsn` object). Only
  the light toolchain is required.
- `make-full.slurm` – runs the full `make` target, which also compiles
  `build/risk-sharing-results.pdf`. Load your site’s LaTeX modules (for
  `pdflatex`) before submission.
- `lsms-spacf.slurm` – runs only the spatial autocorrelation figure with an
  enlarged memory request (default 128 GB). Use this template if you’re
  generating `results/figures/LSMS-ISA/shock_spacfs.png` without the rest of the
  pipeline, or if you want to override `LSMS_ISA_MC`/`LSMS_ISA_PARQUET`.

## Usage

```bash
git clone https://github.com/ligon/RiskSharing_Replication.git
cd RiskSharing_Replication
sbatch docs/slurm/make-results-figures.slurm    # or make-full.slurm
```

### Customizing

- Tweak the `#SBATCH` directives (time, memory, CPUs, partition) to match your
  queue.
- Replace the `module load` lines with whatever package manager your cluster
  uses. The scripts assume Python ≥ 3.11, Emacs, and (for the full build) a
  LaTeX toolchain.
- If your site forbids outbound internet access from compute nodes, run
  `make downloads` on a login node first so the Poetry environment, LSMS
  parquet cache, and pyppeteer bundle are staged locally.
