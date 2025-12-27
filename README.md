
# Table of Contents

1.  [Overview](#org84d9ad6)
2.  [Two Modes](#org9c14281)
    1.  [Online Streaming Mode](#org817bcde)
    2.  [Offline Archival Mode](#org569f92d)
3.  [Data Provenance](#orgbc14446)
    1.  [Uganda National Panel Surveys](#org2ee9c14)
4.  [License](#orge67f7fb)
5.  [Replication](#orgeed48c7)
    1.  [Idea of replication workflow](#org1407a57)
    2.  [Install Dependencies](#orgcc52f00)
        1.  [Quick install recipes](#org912e8d5)
        2.  [Full paper build (`make`)](#orga1bcc14)
    3.  [Build and workflow](#orgcb93618)
        1.  [Clone repository](#org7290f8b)
        2.  [Micromamba bootstrap (default)](#org27ccf5d)
        3.  [Use `make` to build and run analyses](#org6e86f81)
        4.  [Two-stage offline workflow](#orgaa00928)
    4.  [Randomness](#org9518469)
    5.  [Computational requirements and benchmarking](#orgb2cef34)
        1.  [Required storage space](#orgd5546f8)
        2.  [Benchmarked operations](#org333eead)
        3.  [Disabling benchmarks](#org8424704)
        4.  [Benchmark results](#org0ffa5e9)
    6.  [Practical Notes on Computation](#orge9f29ac)
6.  [Directory structure](#org277d00d)
7.  [Other key packages](#orgb39ff60)
8.  [References](#org5e0e11e)

A reproducible research environment for replicating results from Ethan Ligon (2025), now (<span class="timestamp-wrapper"><span class="timestamp">&lt;2025-11-12 Wed&gt;</span></span>) conditionally accepted at the *American Economic Review*:

    @Unpublished{	  ligon25,
      author	= {Ethan Ligon},
      title		= {Risk sharing tests and covariate shocks: Drought, Floods,
                      and Pests in {Uganda}},
      year		= 2025,
      url		= {https://escholarship.org/uc/item/2zr503fq}
    }


<a id="org84d9ad6"></a>

# Overview

This replication package provides the manuscript <./Text/risk-sharing.md> used to construct [Ligon (2025)](https://escholarship.org/uc/item/2zr503fq).  This is a [literate programming](https://en.wikipedia.org/wiki/Literate_programming) document which provides both the text of the manuscript as well as all the code required to construct the analysis datasets from the [LSMS data](https://microdata.worldbank.org/index.php/catalog/lsms/) available from the World Bank ({Uganda Bureau of Statistics}, ????), and then to estimate or construct all figures and tables in the paper. 

A helper is provided via the <./Makefile>, which can be used to extract ("tangle") all code, run it, and compile the complete set of empirical results in the paper.  Given a linux environment with some [minimal dependencies](#orgcc52f00) one simply (hopefully?) need only type `make`.


<a id="org9c14281"></a>

# Two Modes


<a id="org817bcde"></a>

## Online Streaming Mode

In the default (online) mode, make streams the mirrored primitive LSMS World
Bank data via the vendored LSMS\_Library submodule, tangles the Org sources,
rebuilds the Ugandan analysis parquet tables, and then produces the regression
object plus all tables/figures (and the PDF if \LaTeX is present). On first run
you’ll be prompted for the LSMS data passphrase (email [ligon@berkeley.edu](mailto:ligon@berkeley.edu) if you
need one); after that the library caches the parquet outputs under
`external_data/LSMS_Library/Uganda/var/`, so subsequent builds reuse the cached
data while still reconstructing every analysis step.


<a id="org569f92d"></a>

## Offline Archival Mode

Offline archival mode. For archival or air-gapped replication, a packaged
checkout includes all required Parquet artifacts and an ARCHIVE\_MODE file at
repo root. When that file exists, the Makefile disables network access, skips
LSMS authentication, forces `USE_CONDA=0` and `USE_PARQUET=1` and treats the
bundled Parquet data as immutable inputs. In this mode `make` (or `make results
figures`) runs entirely offline using the prebuilt parquet tables under
`external_data/LSMS_Library/Uganda/var/` and `var/ lsms_isa_plots.parquet`,
and reuses the cached headless Chromium bundle in `var/pyppeteer`. If that
directory is absent—or if `.venv` does not already exist—seed both by running
`make downloads` on a connected machine (this works even with `ARCHIVE_MODE` set),
then copy the prepared tree (including `.venv` and `var/pyppeteer`) to the offline
box.


<a id="orgbc14446"></a>

# Data Provenance

The paper uses data from the Living Standards Measurement Surveys in two different forms.  


<a id="org2ee9c14"></a>

## Uganda National Panel Surveys

The main data we use are Uganda-specific data.  Data is subject to a redistribution restriction, but can be freely downloaded from <https://microdata.worldbank.org/index.php/catalog/lsms/>.  Choose "Uganda" for country, and then download the seven "National Panel Surveys".  You will need to fill out registration forms, including a brief description of the project, and agree to the conditions of use. Note: "the data files themselves are not redistributed" and other conditions. 

**Alternatively** (and recommended), if building from scratch then all the necessary Uganda data can be streamed using the [LSMS\_Library](https://github.com/ligon/LSMS_Library) package.  However, as I do not have permission to publicly redistribute these data you will need to affirm that the use of this library is strictly for purposes of replication, and obtain a passphrase by emailing `ligon@berkeley.edu`.  The code for replication assumes that these data are available.  

If you prefer to download the LSMS files directly from the World Bank, unzip the downloads and drop the various files into the directories `./external_data/LSMS_Library/Uganda/WAVE/Data/`, where `WAVE` is a year (e.g., "2005-06") corresponding to the survey wave.  For each file "foo" you should see an existing and corresponding file "foo.dvc".  This path avoids the need to get a passphrase from me, but would be tedious.

A second collection of data ultimately derived from the Living Standards Measurement Surveys covers eight different countries in Africa, and is provided in a dataset described by (Bentze, Thomas Patrick and Wollburg, Philip Randolph, 2024), and publicly distributed at <https://github.com/lsms-worldbank/LSMS-ISA-harmonised-dataset-on-agricultural-productivity-and-welfare/>  (v 2.0) under a Creative Commons license (CC0 1.0 Universal).   However, this paper actually relies on an earlier version of these same data no longer distributed on that website.  The earlier dataset has more information on shocks in Uganda than the dataset linked above.  A more manageable parquet file of the data we need on shocks is extracted here as [./external\_data/lsms\_ag.parquet](./external_data/lsms_ag.parquet).  


<a id="orge67f7fb"></a>

# License

This repository is a "literate programming" project where code and text are interleaved. To facilitate both academic citation and software reuse, this package is licensed under a hybrid model.  Narrative text, documentation, and data files are licensed under the Creative Commons Attribution 4.0 International Public License (CC-BY 4.0).      The code chunks, scripts, software logic, and Makefiles contained within this package are licensed under the BSD 3-Clause License.  See the [./LICENSE.txt](./LICENSE.txt) for details.


<a id="orgeed48c7"></a>

# Replication


<a id="org1407a57"></a>

## Idea of replication workflow

The basic theory of the repository: type `make`. Then, automagically:

1.  All python dependencies will be installed by `poetry` (always offline if `ARCHIVE_MODE` is present).
2.  All source code will be [tangled](https://orgmode.org/manual/Extracting-Source-Code.html) from the ur-source [risk-sharing.org](./Text/risk-sharing.md) (which is also the actual manuscript).
3.  Passphrase prompt (Online Streaming Mode only): you may be prompted for a passphrase to stream Uganda data via [LSMS\_Library](https://github.com/ligon/LSMS_Library); in `ARCHIVE_MODE` this is skipped and no network is used.
4.  Demand system estimation via [CFEDemands](https://github.com/ligon/CFEDemands/):
    -   Online Streaming Mode: streams LSMS data via [LSMS\_Library](https://github.com/ligon/LSMS_Library) to create [./build/var/uganda\_preferred.rgsn](./build/var/uganda_preferred.rgsn).
    -   Offline Archival Mode (`ARCHIVE_MODE` file present): reuses bundled parquet inputs under  `external_data/LSMS_Library/Uganda/var/` and `var/lsms_isa_plots.parquet` (no downloads).
5.  The source code to handle estimation and build tables and figures from [risk-sharing.org](./Text/risk-sharing.md) will be run.
6.  All tables and figures will be included in a pdf built from [./build/risk-sharing-results.org](./build/risk-sharing-results.md).


<a id="orgcc52f00"></a>

## Install Dependencies

This project can bootstrap itself with only a modest set of dependencies, assuming a `linux/bash` environment with:

-   [git](https://git-scm.com/)
-   [python3](https://www.python.org/) with the `venv` module (>=3.11)
-   [GNU make](https://www.gnu.org/software/make/)
-   [GNU Emacs](https://www.gnu.org/software/emacs/) (used in batch mode to tangle `risk-sharing.org`)
-   \LaTeX (`pdflatex` and friends.  Optional; only required to actually compile the final documents to pdf)

> Poetry, DVC, CFEDemands, LSMS\_Library, etc. need **not** be pre-installed: the Makefile bootstraps the python environment `.venv`, installs Poetry inside it, and wires the LSMS submodule to that same environment automatically. All you need system-wide is the short list above.

Exact `python` dependencies are specified in [./pyproject.toml](./pyproject.toml).


<a id="org912e8d5"></a>

### Quick install recipes

Ideas for quickly setting up the required environment

1.  Debian / Ubuntu

        sudo apt update
        # Minimal toolchain (tables + figures only)
        sudo apt install git make emacs-nox python3 python3-venv
        # Add these if you want the PDF too (~600 MB instead of texlive-full)
        sudo apt install texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended
        # optional but handy
        sudo apt install pipx

2.  RHEL / Fedora / CentOS Stream (not tested)

        sudo dnf install git make emacs-nox python3 python3-venv
        # Optional LaTeX stack for the PDF (scheme-medium is enough)
        sudo dnf install texlive-scheme-medium
    
    On older RHEL releases without `python3-venv`, install `python3` and `python3-virtualenv`.
    
    Running `make results figures` with just those four packages installs every Python dependency into `.venv`, tangles the Org sources, rebuilds the CFEDemands regression, and writes all tables/figures under `results/` and `results/figures`. This is the quickest path if you only need the replication deliverables cited in the paper (tables + PNGs).


<a id="orga1bcc14"></a>

### Full paper build (`make`)

Install everything from (a) *plus* a LaTeX toolchain with `pdflatex` support (e.g., `texlive-latex-extra`). The default `make` target produces the PDF (`risk-sharing-results.pdf`) in addition to all tables/figures, so \LaTeX is required here. 


<a id="orgcb93618"></a>

## Build and workflow


<a id="org7290f8b"></a>

### Clone repository

    git clone https://github.com/ligon/CovariateRiskSharing.git
    cd CovariateRiskSharing
    # optional: git submodule update --init --recursive  # normally handled by `make submodules`


<a id="org27ccf5d"></a>

### Micromamba bootstrap (default)

The Makefile defaults to installing/using [micromamba](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html) to construct the build
environment. When you run `make`, it will automatically download a tiny static
micromamba binary into `~/.cache/micromamba` (configurable via
`MICROMAMBA_ROOT`) and reuse it for future builds, installing environments under
`~/.micromamba` (`MICROMAMBA_ROOT_PREFIX`). No manual `conda activate` step is
required for bootstrapping `.venv`; the Makefile invokes micromamba directly.

Set `MICROMAMBA_AUTO_INSTALL=0 to skip the download (expecting micromamba to
already exist in =PATH`) or `USE_CONDA=1 if you explicitly want to use your site
Conda instead. In that mode the previous behaviour (optionally auto-installing
=mamba` inside base Conda when `MAMBA_AUTO_INSTALL=1) remains available. For
interactive hacking you can still =micromamba activate risksharing` (or use
`conda activate` when `USE_CONDA=1`) to drop into the same environment that the
build uses under the hood.

On clusters where `$HOME/.cache` lives on NFS (and thus cannot host POSIX
locks), micromamba falls back to a node-local cache directory (`/tmp/$USER/.cache`) 
so `mamba run` can acquire its lock files without manual tweaking. If your site requires a 
different scratch path, export `XDG_CACHE_HOME` (or `MAMBA_APPDIR`) before running 
`make` and the build will honor it while keeping the staged environments under `~/.micromamba`.

After `poetry install` finishes, the build now runs `pip install -e
external_data/LSMS_Library` inside `.venv` and writes a small `.pth` file
pointing back to the repository root, so both `sitecustomize.py` and the LSMS
package are always importable (even on offline nodes where Poetry cannot refresh
the lock file).


<a id="org6e86f81"></a>

### Use `make` to build and run analyses

The [Makefile](./Makefile) defines all dependencies, and should be the first thing you review in the event of build difficulties.  The graph of dependencies is not trivial, and I strongly recommend using `make` as your principal entry into the build process.

Pick the tier that matches what you need.

1.  Tables + figures only
    
        make results figures
    
    Produces every Org table under `results/`, every PNG under `results/figures/`, and the
    regression object `build/var/uganda_preferred.rgsn`. Only the “small” dependency set is required.

2.  Full paper (tables, figures, PDF)
    
        make
    
    Builds everything above *and* compiles `build/risk-sharing-results.pdf` via LaTeX.

The default target first checks whether the `risksharing` Conda environment exists
and meets the Python version constraint; if the check fails and `CONDA_AUTO_BOOTSTRAP` (default
`1`) is enabled, the build automatically creates or updates the environment (mirroring
`make conda-env` / `make conda-update`) so replicators on a fresh machine don't have to remember
the bootstrap command. Disable this auto-provisioning with `CONDA_AUTO_BOOTSTRAP=0 make` if you
prefer to manage the environment yourself.

> Running on a SLURM cluster? See `misc/slurm/README.md` for ready-to-submit job templates, or run
> `make slurm-results`, `make slurm-full`, or `make slurm-spacf` to submit those scripts directly.

> Want a more isolated environment? See `misc/docker/` for a ready-to-submit Dockerfile, or run `make docker-results`, or `make docker-run`, to produce results in a docker container.  By default these are written to the host in the `docker-build/` directory.
> 
> Note that for reasons of efficiency we do *not* provide the \TeX tools in the docker image that one would need to compile the final results.  For this you should rely on a \TeX distribution in the host environment, or modify the Dockerfile.


<a id="orgaa00928"></a>

### Two-stage offline workflow

Need to stage downloads on a slower, internet-facing box and crunch on a faster offline machine?  First run:

    make downloads

This installs the Poetry environment into `.venv`, updates the `external_data/LSMS_Library` submodule, grabs the harmonized LSMS-ISA release, downloads the headless Chromium binary required by `pyppeteer` into `var/pyppeteer` (the Makefile exports `PYPPETEER_HOME` to point there), and materializes the Uganda parquet caches (e.g., `external_data/LSMS_Library/lsms_library/countries/Uganda/var/food_expenditures.parquet`) via DVC so all network traffic finishes up front.  Copy or mount the synced checkout on the fast computer (which now reuses the prepared `.venv`, LSMS caches, `var/pyppeteer` browser bundle, and downloaded data) and run `make` there to perform the heavy computation without needing internet access.

The first time you do this, if you are in online streaming mode (the defaults) you may be prompted for a passphrase, necessary for gaining access to the LSMS data files (these are the primitive files obtained from the World Bank; I don't have permission to distribute them publicly).  If you don't know the passphrase email `ligon@berkeley.edu` to request one.


<a id="org9518469"></a>

## Randomness

Monte Carlo steps (e.g., demand bootstraps, permutation tests) run with a deterministic seed (`RISKSHARING_SEED`, defined in the Makefile and currently `20250118`) so the full build is reproducible out of the box.  Edit that constant (or temporarily clear it with `make RISKSHARING_SEED=`  if you need fresh randomness.


<a id="orgb2cef34"></a>

## Computational requirements and benchmarking

The build system is tooled to permit one to complete all calculations using three different models.  The first model is simply to use `poetry` and run using "make". All results can be computed with only modest computing resources (e.g., a chromebook is able to produce all the results of this paper).

The second model uses `docker`.  Type `make docker-run`.   This permits greater isolation.

The third model involves using a HPC cluster; this is useful if one is in a hurry, particularly for the bootstrapping/monte carlo exercises (see `$(HEAVY_RESULTS)` in the Makefile).  The approach here involve SLURM scripts which will need to be adapted to local circumstances; see the scripts in <./misc/slurm>.  After adjusting these appropriately, from a node in the cluster type `make slurm-full`.

The build system automatically tracks computational time for major tasks. When you run `make`, timing information is recorded to `benchmarks.txt` and system information is saved to `system_info.txt`.


<a id="orgd5546f8"></a>

### Required storage space

Because the data is streamed, total storage requirements for the replication are very modest, at less than 100 MB.  If one then adds the python environment, actual computed results and some intermediary files then grand total remains less than 3 GB.


<a id="org333eead"></a>

### Benchmarked operations

-   **`poetry install`:** Installing Python dependencies
-   **`org-babel-tangle`:** Extracting source code from risk-sharing.org
-   **`uganda_preferred`:** Estimating the CFE demand system (typically the most time-consuming step)
-   **`generate results`:** Building all result tables
-   **`generate figures`:** Creating all figures
-   **`compile PDF`:** LaTeX compilation (if building the full PDF)


<a id="org8424704"></a>

### Disabling benchmarks

To disable benchmarking (enabled only in online streaming mode):

    make BENCHMARK=0


<a id="org0ffa5e9"></a>

### Benchmark results

Raw timings accumulate in `benchmarks-raw.txt`, while the latest summarized table (grouped by target) lives in `benchmarks.txt` and is embedded below.

1.  System Information

        Hostname: n0234.savio3
        OS: Linux 4.18.0-553.34.1.el8_10.x86_64
        CPU: Intel(R) Xeon(R) Gold 6230 CPU @ 2.10GHz
        CPU cores: 1
        Memory: 93Gi
        Python: Python 3.13.11

2.  Timing Results

        ## Benchmark summary generated 2025-12-11 18:00:00
        Raw log: benchmarks-raw.txt
        
        Target                         Count   Median      Max      Total
        ----------------------------------------------------------------------
        compile PDF                        1       29s       29s         29s
        generate figures                   1       25s       25s         25s
        generate results                   1     1377s     1377s       1377s
        uganda_preferred (demand estimation)     1      214s      214s        214s
    
    Runtime depends on CPU speed, available memory (recommend ≥8GB), network speed (for initial downloads), and whether the data passphrase is cached.


<a id="orge9f29ac"></a>

## Practical Notes on Computation

-   If `poetry` is not installed in your environment, you'll need some method (e.g., [pipx](https://pipx.pypa.io/stable/installation/)) to add it.
-   Non-python dependencies (`Emacs`, `make`, `pipx`, some \LaTeX distribution) must be installed via your platform's package manager (e.g., apt, brew, pacman).
-   This repository vendors [LSMS\_Library](https://github.com/ligon/LSMS_Library) as a git submodule under
    `external_data/LSMS_Library`.  The build runs `make submodules` (which shells out
    to `git submodule update --init --recursive external_data/LSMS_Library`) before
    `poetry install`, so manual submodule setup is usually unnecessary unless you want
    to control it explicitly.  Set `PRIVATE_LSMS_ISA_FIGURES` if you maintain alternate paths.
-   Want fresh LSMS-ISA figures?  After downloading the plot-level data run
    `make results/figures/LSMS-ISA/drought_incidence.png` (and the analogous `flood` and
    `pests` targets) to build the PNGs directly from the harmonized dataset.
-   The spatial autocorrelation figure (`shock_spacfs.png`) is costly to compute, because of the bootstrapped acceptance regions.  We provide it with a dedicated flow.  Invoke `make results/figures/LSMS-ISA/shock_spacfs.png` (which shells out to
    `Makefile_spacf`) or run `make -f Makefile_spacf DRAWS=1000 CORES=32` directly when you
    need to tune the Monte Carlo draws/cores.  On Savio or other clusters submit `misc/slurm/lsms-spacf.slurm` via sbatch (making whatever local adjustments are necessary).
-   The between-variance Monte Carlo parallelizes across CPU cores.  Set
    `BETWEEN_VARIANCE_WORKERS=<n>` to control worker count (defaults to ~√CPUs, capped
    to avoid monopolizing shared boxes).  Each wave’s permutations use deterministic
    seeds tied to the wave label, so output stays reproducible unless you override
    the env var for more/less parallelism.
-   On clusters where the working tree lives on NFS, DVC’s default reflink cache mode
    isn’t supported; run `dvc config cache.type copy` once inside this repo so DVC
    falls back to copying cached outputs during `make downloads` or Uganda materialization
    stages.
-   The spatial autocorrelation permutations are expensive, so the main build
    never runs them automatically. Use the commands above (locally or via Slurm)
    and adjust `DRAWS=/=CORES` to balance precision against runtime.
-   The LSMS-ISA renderer now screenshots Folium maps using a headless Chromium via
    `pyppeteer`.  The command `make downloads` now runs `pyppeteer-install` and caches the browser
    (~100MB) inside `var/pyppeteer` (where `PYPPETEER_HOME` points by default), so
    subsequent builds&#x2014;including offline ones&#x2014;reuse the cached binary with no lazy downloads.
-   See `Makefile` for specific build tasks.
-   You can use the `CFEDemands` package to examine or play with the estimated demand system <./build/var/uganda_preferred.rgsn>.
-   If you need the passphrase for LSMS data access, email `ligon@berkeley.edu` to request one.
-   Complaints, questions, bugs?  Open an [issue](https://github.com/ligon/CovariateRiskSharing/issues).


<a id="org277d00d"></a>

# Directory structure

-   **Text/risk-sharing.org:** The ur-file.  This is the paper, with all code.  This is a [literate programming](https://en.wikipedia.org/wiki/Literate_programming) project.
-   **Makefile:** Build instructions
-   **pyproject.toml:** Python dependency specification
-   **src/ :** Python source code (initially empty)
-   **build/:** Where things are built
    -   **build/risk-sharing-results.org:** Scaffolding file: compiles to a pdf with all results & figures.
    -   **build/results/:** Where tables are constructed
        -   **build/results/figures/:** Where figures are kept
    -   **build/var:** Where intermediate files live
-   **log/:** Logs from build processes


<a id="orgb39ff60"></a>

# Other key packages

Aside from standard python tooling such as `numpy`, `pandas` and similar there are two critical research related packages.  One, already mentioned, provides the Ugandan data for the main analysis (Ethan Ligon, 2025a); here we use the `use_parquet` branch of the software available at <https://github.com/ligon/LSMS_Library/tree/use_parquet>.  The second is the code to estimate the Constant Frisch Elasticity (CFE) demand system  (Ethan Ligon, 2025a), available at <https://github.com/ligon/CFEDemands>.


<a id="org5e0e11e"></a>

# References

Bentze, Thomas Patrick and Wollburg, Philip Randolph (2024). *A Longitudinal Cross-Country Dataset on Agricultural Productivity and Welfare in Sub-Saharan Africa*, World Bank.

Ethan Ligon (2025). *Risk sharing tests and covariate shocks: Drought, Floods, and Pests in Uganda*.

Ethan Ligon (2025a). *\tt LSMS\_Library: Abstraction layer for working with Living Standards Measurement Surveys*.

Ethan Ligon (2025a). *\tt CFEDemands: Tools for estimating and computing Constant Frisch Elasticity (CFE) demands*.

{Uganda Bureau of Statistics} (). *National Panel Surveys*, World Bank, Development Data Group.

