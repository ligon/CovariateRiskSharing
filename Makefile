##
# Risk-Sharing Replication Package
# =============================================================================
# @file    Makefile
# @author  Ethan Ligon <ligon@berkeley.edu>
# @license BSD-3-Clause
# @version 1.3
# =============================================================================

# * Documentation & Quick Start
# -----------------------------------------------------------------------------
# This Makefile orchestrates the complete replication of the Risk Sharing paper.
# It manages Python environments (Conda/Poetry), data retrieval (S3/DVC),
# heavy computation (Slurm/Docker), and LaTeX manuscript generation.
#
# ** Key Targets
#   make all            : (Default) Runs setup, analysis, figures, and paper generation.
#   make setup          : Bootstraps the environment (Conda env -> Poetry -> .venv).
#   make results        : Generates all tables and statistical output.
#   make figures        : Generates all plots (PNG/PDF).
#   make docker-run     : Runs the entire analysis inside a pristine Docker container.
#   make docker-debug   : Shell into the Docker container to poke around.
#   make archive        : Bundles code, data, and PDF for archival deposit.
#
# ** Key Variables (Override via command line)
#   BENCHMARK=1         : (Default) Times every step and logs to build/benchmarks.txt.
#   RISKSHARING_SEED=X  : Sets the random seed for Monte Carlo/Bootstrap steps.
#   HEAVY_LAUNCHER=...  : Command prefix for heavy jobs (e.g., 'srun ...').
#   DOCKER_CLEANUP=""   : Set to empty string to keep Docker containers after run.
#
# ** Directory Structure
#   src/                : Python source code (tangled from Org files).
#   external_data/      : Submodules and DVC-tracked large datasets.
#   build/              : All intermediate artifacts (compiled code, temp files).
#   build/results/            : Final output tables and figures.
#
# ** Emacs Usage
#   This file supports Outline Mode. Press <Shift-Tab> to cycle visibility
#   of sections (Global Config, Python Setup, Analysis, Docker, etc.).
# =============================================================================

# * Global Configuration & Setup
# -----------------------------------------------------------------------------
.DEFAULT_GOAL := all
SHELL := /bin/bash
# ** Archive Mode Detection
# If the file 'ARCHIVE_MODE' exists, we are in a static replication environment.
SETUP_PREREQS := submodules .venv/pyvenv.cfg check_setup_sanity

ifneq (,$(wildcard ARCHIVE_MODE))
    $(info 📦 ARCHIVE_MODE detected: Disabling network/Conda and forcing static data.)
    
    # 1. Export the flag itself so Python/Shell scripts don't need to hunt for the file
    export ARCHIVE_MODE := 1

	# 2. Skip LSMS_Library s3 authentication
	export LSMS_SKIP_AUTH := 1

    # 3. Configure tactical behaviors
    export USE_PARQUET := 1
    export USE_CONDA := 0
    export BENCHMARK := 0
    
    .PRECIOUS: $(LSMS_LIBRARY_UGANDA_PARQUETS) $(LSMS_ISA_PARQUET)
else
    # In Dev Mode, we require AWS credentials
    SETUP_PREREQS += $(AWS_CREDS)
endif
# ** Paths & Environment
# Use := for immediate expansion (faster) where possible
VENV_DIR := $(CURDIR)/.venv
export PATH := $(VENV_DIR)/bin:$(PATH)
export POETRY_VIRTUALENVS_IN_PROJECT=true

# ** Micromamba Platform Detection 
UNAME_S := $(shell uname -s 2>/dev/null || echo unknown)
UNAME_M := $(shell uname -m 2>/dev/null || echo unknown)
MICROMAMBA_PLATFORM :=
ifeq ($(UNAME_S),Linux)
  ifneq (,$(filter x86_64 amd64,$(UNAME_M)))
    MICROMAMBA_PLATFORM := linux-64
  else ifneq (,$(filter aarch64 arm64,$(UNAME_M)))
    MICROMAMBA_PLATFORM := linux-aarch64
  endif
else ifeq ($(UNAME_S),Darwin)
  ifneq (,$(filter x86_64,$(UNAME_M)))
    MICROMAMBA_PLATFORM := osx-64
  else ifneq (,$(filter arm64,$(UNAME_M)))
    MICROMAMBA_PLATFORM := osx-arm64
  endif
endif

MICROMAMBA_DOWNLOAD_URL ?= $(if $(MICROMAMBA_PLATFORM),https://micro.mamba.pm/api/micromamba/$(MICROMAMBA_PLATFORM)/latest,)

# ** Project Paths 
# We define these early so 'setup' and 'docker' can reference them immediately.
LSMS_LIBRARY_SUBMODULE := external_data/LSMS_Library
AWS_CREDS := $(LSMS_LIBRARY_SUBMODULE)/lsms_library/countries/.dvc/s3_creds

LSMS_ISA_DATA_URL := https://github.com/lsms-worldbank/LSMS-ISA-harmonised-dataset-on-agricultural-productivity-and-welfare/releases/download/v2.0/Data.zip
LSMS_ISA_DATA_ZIP := var/downloads/lsms-isa-data.zip
LSMS_ISA_PLOT_DATA := var/Plot_dataset.dta
LSMS_ISA_PARQUET := var/lsms_isa_plots.parquet

# ** Directories (The Sentinel Pattern)
# Define directories here, create them automatically via order-only prereqs
BUILD_DIRS := build build/results build/results/figures build/results/figures/LSMS-ISA build/var

$(BUILD_DIRS):
	@mkdir -p $@

# ** Reproducibility (Seeds)
RISKSHARING_SEED = 20250118
export RISKSHARING_SEED

.PHONY: seed_notice
seed_notice:
	@printf 'Using deterministic RISKSHARING_SEED=%s (configured in Makefile).\n' "$(RISKSHARING_SEED)"

# * Benchmarking Macros
# -----------------------------------------------------------------------------
BENCHMARK ?= 1
BENCHMARK_FILE ?= build/benchmarks-raw.txt
BENCHMARK_SUMMARY ?= build/benchmarks.txt
BENCHMARK_SYSTEM_FILE ?= build/system_info.txt

# Shell function to time commands and log results
# Usage: $(call time_it,label,command)
define time_it
	@if [ "$(BENCHMARK)" = "1" ]; then \
		echo "==> Timing: $(1)"; \
		start=$$(date +%s); \
		$(2); \
		status=$$?; \
		end=$$(date +%s); \
		elapsed=$$((end - start)); \
		echo "$$(date '+%Y-%m-%d %H:%M:%S') | $(1) | $${elapsed}s" >> $(BENCHMARK_FILE); \
		echo "==> Completed $(1) in $${elapsed}s"; \
		exit $$status; \
	else \
		$(2); \
	fi
endef

# * Python, Conda & Environment Bootstrapping
# -----------------------------------------------------------------------------
# ** Variables
CONDA_ENV_NAME := risksharing
CONDA_ENV_FILE := environment.yml
CONDA_SYSDEPS  := emacs texlive-core
CONDA_SYSDEPS_CHANNEL := conda-forge
PYTHON_MIN_VERSION := 3.11
PYTHON_MAX_VERSION := 4.0

USE_CONDA ?= 0
MAMBA_AUTO_INSTALL ?= 1
MICROMAMBA_AUTO_INSTALL ?= 1
CONDA_AUTO_BOOTSTRAP ?= 1

MICROMAMBA_ROOT := $(HOME)/.cache/micromamba
MICROMAMBA_BIN  := $(MICROMAMBA_ROOT)/bin/micromamba
MICROMAMBA_ROOT_PREFIX ?= $(HOME)/.micromamba
export MAMBA_ROOT_PREFIX := $(MICROMAMBA_ROOT_PREFIX)

POETRY_BIN  := $(CURDIR)/.venv/bin/poetry
POETRY_CMD  ?= $(POETRY_BIN)
VENV_PYTHON := $(CURDIR)/.venv/bin/python
export PYTHON_CMD := $(VENV_PYTHON)

# ** Solver Detection Macro
define FIND_ENV_SOLVER
cache_dir=$${XDG_CACHE_HOME}; \
if [ -z "$$cache_dir" ]; then \
	tmp_base=$${TMPDIR:-/tmp}; \
	user=$${USER:-$$UID}; \
	cache_dir="$$tmp_base/$$user/.cache"; \
fi; \
mkdir -p "$$cache_dir/mamba"; \
export XDG_CACHE_HOME="$$cache_dir"; \
export MAMBA_APPDIR="$${MAMBA_APPDIR:-$$cache_dir/mamba}"; \
solver=""; \
if [ "$(USE_CONDA)" != "1" ]; then \
	if command -v micromamba >/dev/null 2>&1; then \
		solver=$$(command -v micromamba); \
	elif [ -x "$(MICROMAMBA_BIN)" ]; then \
		solver="$(MICROMAMBA_BIN)"; \
	elif [ "$(MICROMAMBA_AUTO_INSTALL)" = "1" ] && [ -n "$(MICROMAMBA_DOWNLOAD_URL)" ]; then \
		$(MAKE) --no-print-directory micromamba-bootstrap; \
		if [ -x "$(MICROMAMBA_BIN)" ]; then \
			solver="$(MICROMAMBA_BIN)"; \
		fi; \
	fi; \
fi; \
if [ -z "$$solver" ] && command -v mamba >/dev/null 2>&1; then \
	solver=$$(command -v mamba); \
elif [ -z "$$solver" ] && [ "$(MAMBA_AUTO_INSTALL)" = "1" ] && command -v conda >/dev/null 2>&1; then \
	echo "Installing mamba in the base Conda environment for faster solves..."; \
	if conda install -n base -c $(CONDA_SYSDEPS_CHANNEL) -y mamba >/dev/null 2>&1; then \
		solver=mamba; \
	else \
		echo "Warning: Failed to install mamba; falling back to conda." >&2; \
	fi; \
fi; \
if [ -z "$$solver" ] && command -v conda >/dev/null 2>&1; then \
	solver=$$(command -v conda); \
fi; \
if [ -z "$$solver" ]; then \
	echo "No Conda-compatible solver found (micromamba/mamba/conda)." >&2; \
	echo "Install micromamba manually or rerun with USE_CONDA=1 once conda is available." >&2; \
	exit 1; \
fi
endef
# ** Micromamba bootstrap
micromamba-bootstrap:
	@if [ "$(USE_CONDA)" = "1" ]; then \
		echo "Skipping micromamba bootstrap because USE_CONDA=1."; \
		exit 0; \
	fi
	@if [ -x "$(MICROMAMBA_BIN)" ]; then \
		echo "micromamba already installed at $(MICROMAMBA_BIN)."; \
		exit 0; \
	fi
	@if [ -z "$(MICROMAMBA_DOWNLOAD_URL)" ]; then \
		echo "Automatic micromamba install is not supported on $(UNAME_S)-$(UNAME_M); install it manually or set USE_CONDA=1." >&2; \
		exit 1; \
	fi
	@echo "Installing micromamba ($(MICROMAMBA_PLATFORM)) to $(MICROMAMBA_BIN)..."
	@mkdir -p $(MICROMAMBA_ROOT)/bin
	@tmp_dir=$$(mktemp -d); \
	set -e; \
	curl -fsSL "$(MICROMAMBA_DOWNLOAD_URL)" -o $$tmp_dir/micromamba.tar.bz2; \
	tar -xjf $$tmp_dir/micromamba.tar.bz2 -C $$tmp_dir; \
	cp $$tmp_dir/bin/micromamba $(MICROMAMBA_BIN); \
	chmod +x $(MICROMAMBA_BIN); \
	rm -rf $$tmp_dir; \
	echo "micromamba installed at $(MICROMAMBA_BIN)."

# ** Environment Targets
.PHONY: conda-env conda-update conda-sysdeps conda-python-check conda-env-ready conda-bootstrap micromamba-bootstrap clean_env setup check_setup_sanity env_ready

# Notice conditioning on 
setup: $(SETUP_PREREQS) | src_code

env_ready: .venv/pyvenv.cfg submodules $(BUILD_DIRS)

check_setup_sanity:
	@# 1. Check if the venv exists
	@if [ ! -f "$(VENV_PYTHON)" ]; then \
		echo "❌  FATAL: Virtual environment not found at $(VENV_DIR)"; \
		echo "    Run 'make setup' to create it."; \
		exit 1; \
	fi
	@# 2. Run the python-based probe
	@$(VENV_PYTHON) scripts/check_setup_sanity.py

clean_env:
	-rm -rf .venv

.venv/pyvenv.cfg: pyproject.toml poetry.lock | submodules conda-env-ready $(POETRY_BIN)
	@if ! git ls-files --error-unmatch poetry.lock >/dev/null 2>&1; then \
		echo "Warning: poetry.lock is not tracked by git; add it for reproducible builds."; \
	fi
	@poetry_cmd='$(POETRY_CMD)'; \
	if [ "$(BENCHMARK)" = "1" ]; then \
		echo "==> Timing: poetry install"; \
		start=$$(date +%s); \
		eval $$poetry_cmd install; \
		end=$$(date +%s); \
		elapsed=$$((end - start)); \
		echo "$$(date '+%Y-%m-%d %H:%M:%S') | poetry install | $${elapsed}s" >> $(BENCHMARK_FILE); \
		echo "==> Completed poetry install in $${elapsed}s"; \
	else \
		eval $$poetry_cmd install; \
	fi
	@$(VENV_PYTHON) -m pip install -e external_data/LSMS_Library >/dev/null
	@site_dir=$$($(VENV_PYTHON) -c 'import site; print(site.getsitepackages()[0])'); \
		echo "$(CURDIR)" > "$$site_dir/risksharing_repo.pth"
	@ln -sfn "$(CURDIR)/.venv" "$(LSMS_LIBRARY_SUBMODULE)/.venv"
	@touch .venv/pyvenv.cfg

$(POETRY_BIN): | conda-env-ready
	@set -e; \
	env_python=""; \
	$(FIND_ENV_SOLVER); \
	env_python=$$($$solver run -n $(CONDA_ENV_NAME) python -c 'import sys; print(sys.executable, end="")' 2>/dev/null || true); \
	if [ -z "$$env_python" ]; then \
		env_python=python3; \
		echo "Warning: falling back to $$env_python to bootstrap .venv (env python unavailable)."; \
	fi; \
	if [ ! -d ".venv" ]; then \
		echo "Bootstrapping .venv via $$env_python"; \
		"$$env_python" -m venv .venv; \
	fi
	@.venv/bin/python -m ensurepip --upgrade >/dev/null
	@.venv/bin/python -m pip install --upgrade pip setuptools wheel >/dev/null
	@.venv/bin/python -m pip install poetry >/dev/null

poetry.lock: pyproject.toml | conda-env-ready
	@set -e; \
	$(FIND_ENV_SOLVER); \
	$$solver run -n $(CONDA_ENV_NAME) poetry lock

conda-env:
	@set -e; \
	$(FIND_ENV_SOLVER); \
	echo "Using $$solver to create/update environment $(CONDA_ENV_NAME)."; \
	solver_name=$$(basename "$$solver"); \
	case "$$solver_name" in \
		micromamba) $$solver env create -f $(CONDA_ENV_FILE) ;; \
		*) $$solver env create --force -f $(CONDA_ENV_FILE) ;; \
	esac
	@$(MAKE) conda-python-check
	@echo "Activate with: micromamba activate $(CONDA_ENV_NAME) (or conda activate if using Conda)."

conda-env-ready:
	@if [ "$(CONDA_AUTO_BOOTSTRAP)" = "1" ]; then \
		if $(MAKE) --no-print-directory conda-python-check >/dev/null 2>&1; then \
			:; \
		else \
			echo "Environment $(CONDA_ENV_NAME) missing or incompatible; bootstrapping it now."; \
			$(MAKE) --no-print-directory conda-bootstrap; \
		fi; \
	else \
		$(MAKE) --no-print-directory conda-python-check; \
	fi

conda-bootstrap:
	@set -e; \
	$(FIND_ENV_SOLVER); \
	if $$solver env list --json 2>/dev/null | grep -F "\"$(CONDA_ENV_NAME)\"" >/dev/null 2>&1; then \
		echo "Updating existing environment $(CONDA_ENV_NAME) to match $(CONDA_ENV_FILE)."; \
		$(MAKE) --no-print-directory conda-update; \
	else \
		echo "Creating environment $(CONDA_ENV_NAME) from $(CONDA_ENV_FILE)."; \
		$(MAKE) --no-print-directory conda-env; \
	fi

conda-update:
	@set -e; \
	$(FIND_ENV_SOLVER); \
	echo "Using $$solver to update environment $(CONDA_ENV_NAME)."; \
	$$solver env update -n $(CONDA_ENV_NAME) -f $(CONDA_ENV_FILE) --prune
	@$(MAKE) conda-python-check

conda-sysdeps: conda-env
	@if [ -z "$(CONDA_SYSDEPS)" ]; then \
		echo "CONDA_SYSDEPS is empty; nothing to install."; \
	else \
		set -e; \
		$(FIND_ENV_SOLVER); \
		$$solver install -n $(CONDA_ENV_NAME) -c $(CONDA_SYSDEPS_CHANNEL) -y $(CONDA_SYSDEPS); \
	fi

conda-python-check:
	@set -e; \
	$(FIND_ENV_SOLVER); \
	printf '%s\n' \
		"import sys" \
		"" \
		"def parse(ver_str):" \
		"    return tuple(int(x) for x in ver_str.split('.'))" \
		"" \
		"def pad(ver, length):" \
		"    ver = tuple(ver)" \
		"    if len(ver) >= length:" \
		"        return ver[:length]" \
		"    return ver + (0,) * (length - len(ver))" \
		"" \
		'min_v = parse("$(PYTHON_MIN_VERSION)")' \
		'max_v = parse("$(PYTHON_MAX_VERSION)")' \
		"length = max(len(min_v), len(max_v), 3)" \
		"cur = pad(sys.version_info[:length], length)" \
		"min_v = pad(min_v, length)" \
		"max_v = pad(max_v, length)" \
		"" \
		"ok = min_v <= cur < max_v" \
		"if not ok:" \
		"    msg = (" \
		"        \"Python {} in environment \\\"$(CONDA_ENV_NAME)\\\" is outside the required range >= $(PYTHON_MIN_VERSION) and < $(PYTHON_MAX_VERSION).\".format(sys.version.split()[0])" \
		"    )" \
		"    raise SystemExit(msg)" \
		"print(" \
		"    \"Python {} in environment \\\"$(CONDA_ENV_NAME)\\\" satisfies >= $(PYTHON_MIN_VERSION) and < $(PYTHON_MAX_VERSION).\".format(sys.version.split()[0])" \
		")" \
	| $$solver run -n $(CONDA_ENV_NAME) python -


# * Data Pipeline & Submodules

LSMS_LIBRARY_COUNTRIES_DIR := $(LSMS_LIBRARY_SUBMODULE)/lsms_library/countries
LSMS_LIBRARY_UGANDA_DIR := $(LSMS_LIBRARY_COUNTRIES_DIR)/Uganda

# ** Target Definitions
.PHONY: submodules decrypt_creds

# Guard against running git inside Docker
submodules:
ifdef ARCHIVE_MODE
	@echo "ARCHIVE_MODE=1: Skipping git submodule update (vendored data expected)."
else ifndef IN_DOCKER
	@git submodule update --init --recursive --depth 1 $(LSMS_LIBRARY_SUBMODULE)
	@echo "Verified submodule $(LSMS_LIBRARY_SUBMODULE)."
else
	@echo "🐳 In Docker: Skipping git submodule update."
endif

# Only define the recipe if NOT in Docker
ifndef IN_DOCKER
$(AWS_CREDS): .venv/pyvenv.cfg
	@echo "🔑 Authenticating on Host..."
	@$(VENV_PYTHON) -c 'import lsms_library as ll; ll.authenticate()'
endif

decrypt_creds: $(AWS_CREDS)

$(LSMS_ISA_DATA_ZIP):
	@mkdir -p $(dir $@)
	@echo "Downloading LSMS-ISA harmonised dataset to $@"
	@curl -L -o "$@" "$(LSMS_ISA_DATA_URL)"

$(LSMS_ISA_PLOT_DATA): $(LSMS_ISA_DATA_ZIP)
	@mkdir -p $(dir $@)
	@echo "Extracting Plot_dataset.dta to $@"
	@unzip -j -o "$<" "Data/Plot_dataset.dta" -d $(dir $@)
	@touch "$@"

$(LSMS_ISA_PARQUET): $(LSMS_ISA_PLOT_DATA) | src_code env_ready
	@mkdir -p $(dir $@)
	@$(POETRY_CMD) run python src/shock_maps/data_cleaning.py --input $(LSMS_ISA_PLOT_DATA) --output $@

# LSMS Library Parquet Materialization
LSMS_LIBRARY_UGANDA_PARQUET_REL := \
	var/cluster_features.parquet \
	var/earnings.parquet \
	var/enterprise_income.parquet \
	var/food_acquired.parquet \
	var/food_expenditures.parquet \
	var/food_prices.parquet \
	var/food_quantities.parquet \
	var/household_characteristics.parquet \
	var/household_roster.parquet \
	var/income.parquet \
	var/interview_date.parquet \
	var/nutrition.parquet \
	var/other_features.parquet \
	var/locality.parquet \
	var/people_last7days.parquet \
	var/shocks.parquet

LSMS_LIBRARY_UGANDA_PARQUETS = $(addprefix $(LSMS_LIBRARY_UGANDA_DIR)/,$(LSMS_LIBRARY_UGANDA_PARQUET_REL))

$(LSMS_LIBRARY_UGANDA_DIR)/var/%.parquet: | submodules .venv/pyvenv.cfg
	@echo "Materializing Uganda table $* via LSMS_Library (DVC)."
	@poetry_cmd='$(POETRY_CMD)'; \
	PYTHON_CMD="$(CURDIR)/.venv/bin/python" eval $$poetry_cmd run python -m lsms_library.cli materialize \
		--country Uganda \
		--table $* \
		--all-waves \
		--format parquet \
        --use-parquet \
		--out $@
# * Source Management (Tangling)
# -----------------------------------------------------------------------------
PRIVATE_RISK_SHARING ?= Text/risk-sharing.org
PRIVATE_RISK_SHARING_BASENAME := $(notdir $(PRIVATE_RISK_SHARING))
PRIVATE_RISK_SHARING_TARGET := Text/$(PRIVATE_RISK_SHARING_BASENAME)

.PHONY: clean_src

src/%.py: src/.tangled
	@:

.PHONY: src_code
src_code: src/.tangled

src/.tangled: $(PRIVATE_RISK_SHARING)
	@if [ "$(BENCHMARK)" = "1" ]; then \
		echo "==> Timing: tangle source from risk-sharing.org"; \
		start=$$(date +%s); \
		emacs --batch \
		  --eval "(require 'org)" \
		  --eval "(require 'ob-tangle)" \
		  --eval "(setq org-confirm-babel-evaluate nil)" \
		  --eval "(org-babel-do-load-languages 'org-babel-load-languages '((shell . t) (python . t) (emacs-lisp . t)))" \
		  --eval "(find-file \"$<\")" \
		  --eval "(org-babel-tangle)"; \
		end=$$(date +%s); \
		elapsed=$$((end - start)); \
		echo "$$(date '+%Y-%m-%d %H:%M:%S') | org-babel-tangle | $${elapsed}s" >> $(BENCHMARK_FILE); \
		echo "==> Completed tangling in $${elapsed}s"; \
	else \
		emacs --batch \
		  --eval "(require 'org)" \
		  --eval "(require 'ob-tangle)" \
		  --eval "(setq org-confirm-babel-evaluate nil)" \
		  --eval "(org-babel-do-load-languages 'org-babel-load-languages '((shell . t) (python . t) (emacs-lisp . t)))" \
		  --eval "(find-file \"$<\")" \
		  --eval "(org-babel-tangle)"; \
	fi
	touch src/.tangled

src/shock_maps/%.py: | src_code
	@:

src/shock_maps/spatial_autocorrelation.py: | src_code
	@:

clean_src:
	@if [ -d src ]; then \
		find src -mindepth 1 -type f ! -name '.gitkeep' -delete; \
		find src -mindepth 1 -type d -empty -delete; \
	fi
	-rm -f src/.tangled

# * Analysis & Results
# -----------------------------------------------------------------------------
REGRESSION := build/var/uganda_preferred.rgsn

# ** File Lists
RESULTS := build/results/attrition.org build/results/household_characteristics.org \
	build/results/effects_of_different_shocks_last_year.org \
	build/results/by_month.org build/results/shocks_by_year.org \
	build/results/shock_affected.org build/results/how_coped.org \
	build/results/between_variance.org build/results/shocks_by_round.org

FIGURES := build/results/figures/beta_estimates.png build/results/figures/w_by_year_joyplot.png \
           build/results/figures/covariate_shocks_by_month.png \
           build/results/figures/covariate_shocks_by_month_one_way.png \
           build/results/figures/agg_shares_and_mean_shares.png \
           build/results/figures/shocks_and_farmgate_prices.png \
           build/results/figures/shocks_and_relative_prices.png \
           build/results/figures/shocks_and_level_food_quantities.png \
           build/results/figures/shocks_and_positive_food_quantities.png \
           build/results/figures/shocks_and_log_food_quantities.png \
           build/results/figures/LSMS-ISA/drought_incidence.png \
           build/results/figures/LSMS-ISA/flood_incidence.png \
           build/results/figures/LSMS-ISA/pests_incidence.png \
           build/results/figures/LSMS-ISA/shock_spacfs.png

HEAVY_OUTPUTS := build/results/between_variance.org \
	results/figures/LSMS-ISA/shock_spacfs.png

# ** Main Targets
.PHONY: all _all results figures clean_results

all: conda-env-ready seed_notice benchmark_init setup
	@echo "🚀 Build System Ready. Checking artifacts..."
	@$(MAKE) _all
	@$(MAKE) benchmark_summary
	@echo "✅ Build Complete: All targets are up-to-date."

_all: .venv/pyvenv.cfg build/var/uganda_preferred.rgsn figures results risk-sharing-results.pdf

results: | .venv/pyvenv.cfg $(REGRESSION) $(BUILD_DIRS)
	@$(MAKE) _results

_results: $(RESULTS)

figures: | .venv/pyvenv.cfg $(REGRESSION) build/results/figures
	@$(MAKE) _figures

_figures: $(FIGURES)

clean_results:
	@if [ -d build/results ]; then \
		find build/results -mindepth 1 -type f ! -name '.gitkeep' -delete; \
		find build/results -mindepth 1 -type d -empty -delete; \
	fi

# ** Demand Estimation
build/var/uganda_preferred.rgsn: src/uganda_preferred.py $(LSMS_LIBRARY_UGANDA_PARQUETS) | .venv/pyvenv.cfg build/var 
	@echo "* Building $@"
	@mkdir -p log
	@bash -o pipefail -c '$(VENV_PYTHON) $< 2>&1 | tee $(patsubst src/%.py,log/%.log,$<) >&2'
	@echo "$@ log written to $(patsubst src/%.py,log/%.log,$<)."

# ** Heavy Compute (Monte Carlo outputs)

build_heavy_data: $(HEAVY_OUTPUTS)

results/between_variance.org: $(REGRESSION) | src_code env_ready
	@echo "* Building $@"
	@bash -euo pipefail -c '\
                $(HEAVY_LAUNCHER) $(POETRY_CMD) run python src/between_variance.py \
                | grep -v "^make" \
                | grep -v "^Issue with" \
                | grep -v "^[0-9]\{4\}-[0-9]\{2\}$$" \
                > build/results/between_variance.org 2>/dev/null'

results/figures/LSMS-ISA/shock_spacfs.png:
	@echo "* Building $@"
	@$(MAKE) -f Makefile_spacf LAUNCHER="$(HEAVY_LAUNCHER)"

# ** Python Script Rules (tables & figures)
results/%.org: src/%.py $(REGRESSION) | .venv/pyvenv.cfg 
	@echo "* Building $@"
	@bash -euo pipefail -c '$(POETRY_CMD) run python "$<" | grep -v "^make" > "$@"'

results/figures/%.png: src/%.py $(REGRESSION) | .venv/pyvenv.cfg 
	@echo "* Building $@"
	$(POETRY_CMD) run python $< > $(patsubst src/%.py,log/%.log,$<)
	@echo "$@ log written to $(patsubst src/%.py,log/%.log,$<)."

# ** Pyppeteer
PYPPETEER_HOME ?= $(abspath var/pyppeteer)
export PYPPETEER_HOME
PYPPETEER_STAMP := $(PYPPETEER_HOME)/.chromium_ready
pyppeteer-browser: $(PYPPETEER_STAMP)

$(PYPPETEER_STAMP): .venv/pyvenv.cfg
	@if [ -n "$(ARCHIVE_MODE)" ] && [ ! -f "$@" ]; then \
		echo "ARCHIVE_MODE=1: expected cached pyppeteer at $(PYPPETEER_HOME). Run 'make downloads' on a networked machine and copy var/pyppeteer." >&2; \
		exit 1; \
	fi
	@echo "==> Ensuring pyppeteer Chromium assets in $(PYPPETEER_HOME)"
	@mkdir -p $(PYPPETEER_HOME)
	@PYPPETEER_HOME=$(PYPPETEER_HOME) $(POETRY_CMD) run pyppeteer-install
	@touch $@
# ** LSMS-ISA Incidence Maps
# This rule handles the specific arguments for rendering shock maps
results/figures/LSMS-ISA/%_incidence.png: $(LSMS_ISA_PARQUET) | src_code env_ready
	@echo "* Building $@"
	@bash -euo pipefail -c '\
                mkdir -p "$(dir $@)" && \
                base="$*" && shock=$${base%_incidence} && \
                $(POETRY_CMD) run python src/shock_maps/render_shock_incidence.py \
                        --data "$(LSMS_ISA_PARQUET)" \
                        --shocks "$$shock" \
                        --output-dir "$(dir $@)" \
                        --format png >/dev/null'

# * Paper & PDF Generation
# -----------------------------------------------------------------------------
build/risk-sharing-results.pdf: build/risk-sharing-results.tex 
	@set -e; \
	$(FIND_ENV_SOLVER); \
	$$solver run -n $(CONDA_ENV_NAME) bash -c 'cd build && for run in 1 2 3; do echo \"pdflatex pass $$run\"; pdflatex -halt-on-error -interaction=nonstopmode $(notdir $<); done'

build/risk-sharing-results.tex: build/risk-sharing-results.org build/org-export-helpers.el results figures
	cd build && emacs --batch -Q \
		--eval "(require 'ox-latex)" \
		--eval "(load-file \"org-export-helpers.el\")" \
		--eval "(setq org-export-exclude-tags '(\"noexport\" \"ARCHIVE\"))" \
		--eval "(find-file \"risk-sharing-results.org\")" \
		--eval "(org-latex-export-to-latex)"

risk-sharing-results.pdf: build/risk-sharing-results.pdf
	cp build/risk-sharing-results.pdf .

.PHONY: clean_text
clean_text:
	rm -f risk-sharing-results.pdf build/*.pdf build/*.tex \
          build/*.aux build/*.log build/*.out build/*.blg \
          build/*.fls

# * Docker Integration
# -----------------------------------------------------------------------------
# ** Variables
DOCKERFILE       ?= misc/docker/Dockerfile.debian-minimal
DOCKER_TAG       ?= risk-sharing-test
# Logic: Default to auto-clean (--rm). To persist: make docker-run DOCKER_CLEANUP=""
DOCKER_CLEANUP   ?= --rm
# Note: User provided DOCKER_CONTAINER in input, keeping for consistency.
DOCKER_CONTAINER ?= risk-sharing-run

# Paths
DOCKER_RESULTS_HOST := $(CURDIR)/docker-build
DOCKER_RESULTS_CONT := /RiskSharing_Replication/build

# Run Arguments
DOCKER_RUN_ARGS ?= \
    -u $(shell id -u):$(shell id -g) \
    -e IN_DOCKER=true \
    -v $(CURDIR)/$(AWS_CREDS):/RiskSharing_Replication/$(AWS_CREDS):ro \
    -v $(DOCKER_RESULTS_HOST):$(DOCKER_RESULTS_CONT)

# The Command to run inside (triggers the target below)
DOCKER_DO ?= make docker-results

# ** Targets
.PHONY: docker-image docker-run docker-clean docker-outdir docker-results

docker-image:
	@docker build -f $(DOCKERFILE) -t $(DOCKER_TAG) .

docker-outdir:
	@mkdir -p $(DOCKER_RESULTS_HOST)

docker-clean:
	-@docker rm -f $(DOCKER_CONTAINER) 2>/dev/null || true

# Main Launcher
docker-run: docker-clean docker-outdir env_ready docker-image decrypt_creds
	@echo "🚀 Launching $(DOCKER_CONTAINER)..."
	@docker run $(DOCKER_CLEANUP) \
		--name $(DOCKER_CONTAINER) \
		$(DOCKER_RUN_ARGS) \
		$(DOCKER_TAG) $(DOCKER_DO)

# This is the entry point running INSIDE the container
docker-results:
	@echo "🧹 Cleaning imported environment..."
	@rm -rf .venv
	@echo "🏗️  Starting fresh build..."
	@$(MAKE) results figures

##
# * Docker debug
#   Shell inside the built image (no host mounts by default)
#
#  Usage examples:
#
#  - Drop into a shell in an isolated container: make docker-debug
#  - Same, but auto-remove on exit: make docker-debug DOCKER_DEBUG_CLEANUP=--rm
#  - Keep host-visible build artifacts: make docker-debug DOCKER_DEBUG_MOUNTS='-v $(PWD)/docker-build:/
#    RiskSharing_Replication/build'
#  - If you need AWS creds inside: add -v $(PWD)/$(AWS_CREDS):/RiskSharing_Replication/$(AWS_CREDS):ro to
#    DOCKER_DEBUG_MOUNTS.

DOCKER_DEBUG_CONTAINER ?= risk-sharing-debug
DOCKER_DEBUG_DO        ?= /bin/bash
DOCKER_DEBUG_RUN_ARGS  ?= -it --user tester -e IN_DOCKER=true
DOCKER_DEBUG_MOUNTS    ?= -v $(PWD)/$(AWS_CREDS):/RiskSharing_Replication/$(AWS_CREDS):ro  # e.g., -v $(CURDIR)/docker-build:/RiskSharing_Replication/build
DOCKER_DEBUG_CLEANUP   ?=   # leave empty to keep container; set to --rm to auto-clean

.PHONY: docker-debug docker-debug-clean
docker-debug-clean:
	-@docker rm -f $(DOCKER_DEBUG_CONTAINER) 2>/dev/null || true

docker-debug: docker-debug-clean docker-image
	@docker run $(DOCKER_DEBUG_CLEANUP) \
        --name $(DOCKER_DEBUG_CONTAINER) \
        $(DOCKER_DEBUG_RUN_ARGS) $(DOCKER_DEBUG_MOUNTS) \
        $(DOCKER_TAG) $(DOCKER_DEBUG_DO)


# * Benchmarking (Execution)
# -----------------------------------------------------------------------------
# ** Targets
.PHONY: FORCE benchmark_init
FORCE:

benchmark_init: build $(BENCHMARK_SYSTEM_FILE)

$(BENCHMARK_SYSTEM_FILE): FORCE
	@if [ "$(BENCHMARK)" = "1" ]; then \
		echo "==> Recording system information"; \
		echo "Benchmark run started: $$(date '+%Y-%m-%d %H:%M:%S')" > $(BENCHMARK_SYSTEM_FILE); \
		echo "Hostname: $$(hostname)" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "OS: $$(uname -s -r)" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "CPU: $$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'N/A')" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "CPU cores: $$(nproc 2>/dev/null || echo 'N/A')" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "Memory: $$(free -h 2>/dev/null | awk '/^Mem:/{print $$2}' || echo 'N/A')" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "Python: $$(python3 --version 2>/dev/null || echo 'N/A')" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "" >> $(BENCHMARK_SYSTEM_FILE); \
		echo "==> Benchmark log: $(BENCHMARK_FILE)"; \
		echo "==> System info: $(BENCHMARK_SYSTEM_FILE)"; \
		echo "# Benchmark started: $$(date '+%Y-%m-%d %H:%M:%S')" > $(BENCHMARK_FILE); \
	fi

benchmark_summary:
	@if [ "$(BENCHMARK)" = "1" ] && [ -f "$(BENCHMARK_FILE)" ]; then \
		echo ""; \
		echo "==> Benchmark Summary"; \
		echo "==========================================="; \
		$(POETRY_CMD) run python scripts/summarize_benchmarks.py --input $(BENCHMARK_FILE) --output $(BENCHMARK_SUMMARY); \
		cat $(BENCHMARK_SUMMARY); \
		echo "==========================================="; \
		echo "System info saved to: $(BENCHMARK_SYSTEM_FILE)"; \
		echo "Full benchmark log: $(BENCHMARK_FILE)"; \
		echo ""; \
		$(MAKE) build/benchmarks.org; \
		echo "Generated benchmarks.org for inclusion in README"; \
	fi

build/benchmarks.org:
	@mkdir -p build
	@echo "Generating build/benchmarks.org from benchmark data"; \
	{ \
		echo "*** System Information"; \
		echo "#+begin_example"; \
		tail -n +2 $(BENCHMARK_SYSTEM_FILE) 2>/dev/null || echo "No system info available"; \
		echo "#+end_example"; \
		echo ""; \
		echo "*** Timing Results"; \
		echo "#+begin_example"; \
		cat $(BENCHMARK_SUMMARY) 2>/dev/null || echo "No benchmark data available"; \
		echo "#+end_example"; \
		echo ""; \
	} > build/benchmarks.org

# * HPC/Slurm
# -----------------------------------------------------------------------------
HEAVY_LAUNCHER ?=

.PHONY: slurm-results slurm-full slurm-spacf archive release-snapshot clean_project

slurm-results: setup downloads
	@sbatch misc/slurm/make-results-figures.slurm

slurm-full: setup downloads
	@sbatch misc/slurm/make-full.slurm

slurm-spacf: setup
	@sbatch misc/slurm/lsms-spacf.slurm

# * Archive
# -----------------------------------------------------------------------------
# Extract version from header (i.e., "# @version 1.1")
PROJECT_VERSION := $(shell grep "@version" Makefile | head -n 1 | awk '{print $$3}')
ARCHIVE_NAME    := risk-sharing-replication-v$(PROJECT_VERSION)
STAGING_DIR     := dist/staging/$(ARCHIVE_NAME)
LSMS_ARCHIVE_DIR := $(STAGING_DIR)/external_data/LSMS_Library
ARCHIVE_INCLUDE_PYPPETEER ?= 0
ARCHIVE_PYPPETEER_PREREQ :=
ifeq ($(ARCHIVE_INCLUDE_PYPPETEER),1)
ARCHIVE_PYPPETEER_PREREQ := $(PYPPETEER_STAMP)
endif

.PHONY: archive
archive: risk-sharing-results.pdf $(PYPPETEER_STAMP) $(LSMS_LIBRARY_UGANDA_PARQUETS) $(LSMS_ISA_PARQUET)
	@echo "📦 Preparing archival package $(ARCHIVE_NAME)..."
	@rm -rf dist/staging
	@mkdir -p $(STAGING_DIR)

	@echo "   [1/8] Exporting repository HEAD (tracked files only)..."
	@git archive --format=tar HEAD | tar -x -C $(STAGING_DIR)

	@echo "   [2/8] Staging minimal LSMS_Library (Uganda parquet cache)..."
	@mkdir -p $(LSMS_ARCHIVE_DIR)/lsms_library
	@rsync -a --exclude '__pycache__' --exclude 'countries' external_data/LSMS_Library/lsms_library/ $(LSMS_ARCHIVE_DIR)/lsms_library/
	@cp external_data/LSMS_Library/pyproject.toml $(LSMS_ARCHIVE_DIR)/ || true
	@cp external_data/LSMS_Library/LICENSE.txt $(LSMS_ARCHIVE_DIR)/ || true
	@cp external_data/LSMS_Library/README.org $(LSMS_ARCHIVE_DIR)/ || true
	@mkdir -p $(LSMS_ARCHIVE_DIR)/lsms_library/countries/Uganda/var
	@mkdir -p $(LSMS_ARCHIVE_DIR)/lsms_library/countries/Uganda/_
	@for f in $(LSMS_LIBRARY_UGANDA_PARQUET_REL); do \
		src="$(LSMS_LIBRARY_UGANDA_DIR)/$$f"; \
		dest="$(LSMS_ARCHIVE_DIR)/lsms_library/countries/Uganda/$$f"; \
		mkdir -p "$$(dirname "$$dest")"; \
		cp "$$src" "$$dest"; \
	done
	@cp -r $(LSMS_LIBRARY_UGANDA_DIR)/_/.\ $(LSMS_ARCHIVE_DIR)/lsms_library/countries/Uganda/_/
	@cp $(LSMS_LIBRARY_UGANDA_DIR)/dvc.* $(LSMS_ARCHIVE_DIR)/lsms_library/countries/Uganda/ 2>/dev/null || true

	@echo "   [3/8] Injecting static Parquet data..."
	@mkdir -p $(STAGING_DIR)/var
	@cp $(LSMS_ISA_PARQUET) $(STAGING_DIR)/var/

	@echo "   [4/8] Bundling cached pyppeteer (optional)..."
	@if [ "$(ARCHIVE_INCLUDE_PYPPETEER)" = "1" ]; then \
		if [ -d "var/pyppeteer" ]; then \
			mkdir -p $(STAGING_DIR)/var/pyppeteer; \
			cp -r var/pyppeteer/. $(STAGING_DIR)/var/pyppeteer/; \
		else \
			echo "Warning: var/pyppeteer is missing; offline archive will need a cached pyppeteer binary." >&2; \
		fi; \
	else \
		echo "Skipping pyppeteer bundle (ARCHIVE_INCLUDE_PYPPETEER=0); pyppeteer will download on first use."; \
	fi

	@echo "   [5/8] Setting Archive 'Cookie' and Timestamps..."
	@touch $(STAGING_DIR)/ARCHIVE_MODE
	@# Timestamp trick to prevent rebuilding
	@find $(STAGING_DIR)/external_data -name "*.parquet" -exec touch {} +
	@find $(STAGING_DIR)/var -name "*.parquet" -exec touch {} +

	@echo "   [6/8] Cleaning environment artifacts..."
	@rm -rf $(STAGING_DIR)/.venv
	@find $(STAGING_DIR) -name "__pycache__" -type d -exec rm -rf {} +

	@echo "   [7/8] Adding Reference Manuscript..."
	@cp risk-sharing-results.pdf $(STAGING_DIR)/risk-sharing-results-author-version.pdf

	@echo "   [8/8] Compressing..."
	@cd dist/staging && zip -q -r -y ../$(ARCHIVE_NAME).zip $(ARCHIVE_NAME)
	@echo "✅ Archive created at dist/$(ARCHIVE_NAME).zip"

# * Release snapshot
release-snapshot:
	@echo "📸 Creating a 'results' snapshot branch..."
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Error: Working directory not clean. Commit changes first."; \
		exit 1; \
	fi
	git checkout results
	-@git branch -D results-snapshot
	git checkout --orphan results-snapshot
	git add -f risk-sharing-results.pdf
	git add -f Text/risk-sharing.pdf
	git add -f build/results/figures/*.png
	git add -f build/results/*.org
	git add -f build/results/figures/LSMS-ISA/*.png
	git add -f README.md
	git add -f LICENSE.txt
	git commit --only -m "Build Snapshot: $$(date '+%Y-%m-%d')" \
		README.md LICENSE.txt \
		risk-sharing-results.pdf Text/risk-sharing.pdf $(FIGURES) $(RESULTS)
	git push -f public results-snapshot:results
	git checkout results
	git branch -D results-snapshot
	@echo "✅ Results snapshot pushed to branch 'results'."

.PHONY: release-public-master
release-public-master:
	@echo "📸 Creating a 'master' snapshot branch..."
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Error: Working directory not clean. Commit changes first."; \
		exit 1; \
	fi
	git checkout master
	-@git branch -D master-snapshot
	git checkout --orphan master-snapshot
	git add -A
	git commit -m "Build Snapshot: $$(date '+%Y-%m-%d')" 
	git push -f public master-snapshot:master
	git checkout master
	git branch -D master-snapshot
	@echo "✅ Master snapshot pushed to branch 'master'."


# * Project Management
PUBLIC_REMOTE ?= $(shell git -C $(CURDIR) config --get remote.public.url 2>/dev/null)

README.md: README.org
	@$(MAKE) --no-print-directory build/benchmarks.org
	@emacs --batch \
	  --eval "(require 'org)" \
	  --eval "(require 'ox-md)" \
	  --eval "(setq org-confirm-babel-evaluate nil)" \
	  --eval "(find-file \"$<\")" \
	  --eval "(org-md-export-to-markdown)"

clean_project:
	-rm README.md

clean: clean_results clean_text clean_src
	-find build/var -maxdepth 1 -type f ! -name '.gitkeep' -delete

clean_all: clean clean_env


# * Downloads
# It's sometimes useful to get all our downloads done at once.
# For example, on a cluster where not all nodes have internet access.
.PHONY: downloads
ifeq ($(ARCHIVE_MODE),1)
downloads: .venv/pyvenv.cfg $(PYPPETEER_STAMP)
	@missing=0; \
	for f in $(LSMS_LIBRARY_UGANDA_PARQUETS); do \
		if [ ! -f "$$f" ]; then \
			echo "ARCHIVE_MODE=1: missing $$f. Seed via 'make downloads' on a networked machine before going offline."; \
			missing=1; \
		fi; \
	done; \
	if [ ! -f "$(LSMS_ISA_PARQUET)" ]; then \
		echo "ARCHIVE_MODE=1: missing $(LSMS_ISA_PARQUET). Seed via 'make downloads' on a networked machine before going offline."; \
		missing=1; \
	fi; \
	if [ $$missing -ne 0 ]; then exit 1; fi
	@echo "ARCHIVE_MODE=1: Skipping network downloads; using bundled cached data."
else
downloads: conda-env-ready submodules .venv/pyvenv.cfg $(LSMS_ISA_PLOT_DATA) $(LSMS_LIBRARY_UGANDA_PARQUETS) $(PYPPETEER_STAMP) $(AWS_CREDS)
	@echo "Downloads complete."
endif

# * Emacs Configuration
# -----------------------------------------------------------------------------
# Local Variables:
# mode: makefile
# outline-regexp: "# \\*+"
# eval: (outline-minor-mode 1)
# eval: (local-set-key (kbd "<backtab>") 'outline-toggle-children)
# eval: (outline-hide-body)
# End:
