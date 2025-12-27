# Docker-based Smoke Test

Use these quick commands to verify the replication workflow on a clean Linux image
without provisioning a full VM. Each container is disposable: exit the shell when
you're done and Docker deletes it automatically.

## Makefile shortcuts

Run `make docker-run` from the repository root to build the Debian smoke-test
image (target `docker-image`) and drop into a fresh container in one step. The
helper honors `DOCKER_TAG=<name>` if you want to reuse an existing tag between
builds, and `DOCKER_RUN_ARGS="--entrypoint /bin/bash"` (for example) lets you
override `docker run` flags without touching the Makefile.

## Automated Dockerfile approach

The repository includes `misc/docker/Dockerfile.debian-minimal` that automates the entire smoke
test workflow:

```bash
docker build -f misc/docker/Dockerfile.debian-minimal -t risk-sharing-test .
docker run --rm -it risk-sharing-test
```

This copies your local repository into the container, installs dependencies, runs
`make results figures`, and drops you into a shell to inspect the output. The build
will fail if the replication workflow breaks. All operations run as a non-root user
(`tester`) for better security. The Docker build wipes any pre-existing `.venv` so
you always get a fresh Linux virtualenv even if your host repo already had one; the
new `.dockerignore` also keeps that host venv (plus other throwaway artifacts) out of
the build context.

## Interactive approach

If you prefer to run commands step-by-step or test variations, use the interactive
container method below. The automated Dockerfile automatically places `.venv/bin`
on `PATH`, so `poetry` and other project tools are ready as soon as you `docker run`.
For manual sessions, run `source .venv/bin/activate` (or add `.venv/bin` to `PATH`)
after bootstrapping the repo so those commands are available.

### Debian / Ubuntu image

```bash
docker run --rm -it debian:bookworm bash

apt update
# Minimal toolchain (tables + figures only) plus runtime deps for curl / pycurl / gnupg workflows
apt install -y \
  git make emacs-nox python3 python3-venv \
  curl ca-certificates bzip2 unzip gnupg \
  build-essential pkg-config libcurl4-openssl-dev
# Add LaTeX if you plan to build the PDF too
apt install -y texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended

git clone https://github.com/ligon/RiskSharing_Replication.git
cd RiskSharing_Replication
make results figures    # or plain `make` once LaTeX is installed
```

### Fedora image

```bash
docker run --rm -it fedora:40 bash

# Minimal toolchain (tables + figures only) plus runtime deps for curl / pycurl / gnupg workflows
dnf install -y git make emacs-nox python3 python3-venv
dnf install -y curl ca-certificates bzip2 unzip gnupg2 gcc gcc-c++ pkgconf-pkg-config libcurl-devel
dnf install -y texlive-scheme-medium   # optional, only needed for the PDF

git clone https://github.com/ligon/RiskSharing_Replication.git
cd RiskSharing_Replication
make results figures    # or `make` for the full build
```

These containers have outbound internet access by default, so Poetry/DVC downloads
work without extra configuration. If you only care about the lighter-weight run,
skip the LaTeX packages and stick with `make results figures`.
