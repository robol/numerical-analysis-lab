#!/usr/bin/env bash
# Install Julia + Plots + IJulia + a private Miniconda/Jupyter environment.
# Usage: bash julia_notebook.sh [notebook-directory]
# Run again to reuse the installation and launch another notebook server.
set -Eeuo pipefail
trap 'printf "Error at line %s; see the output above.\n" "$LINENO" >&2' ERR

if [[ $(uname -s) != Linux ]]; then
    printf 'This script is intended for Linux.\n' >&2
    exit 1
fi
if (( $# > 1 )); then
    printf 'Usage: bash %s [notebook-directory]\n' "$0" >&2
    exit 2
fi

# Everything is installed in your home directory; no sudo is used.
juliaup_dir="$HOME/.juliaup"
state_dir="$HOME/.local/share/julia-notebook"
notebook_dir="${1:-$HOME/notebooks}"
export JULIA_DEPOT_PATH="$state_dir/depot"
export CONDA_JL_HOME="$state_dir/miniconda"
export CONDA_JL_USE_MINIFORGE=0
export JUPYTER_DATA_DIR="$state_dir/jupyter"
# Register only the configured kernel below, rather than an additional default.
export IJULIA_NODEFAULTKERNEL=1
# An empty JUPYTER tells IJulia to use its Conda-managed Jupyter.
export JUPYTER=""
unset CONDA_JL_CONDA_EXE

# The Conda installer does not support spaces in its installation prefix.
if [[ "$CONDA_JL_HOME" == *[[:space:]]* ]]; then
    printf 'Miniconda needs a home-directory path without whitespace.\n' >&2
    exit 1
fi
mkdir -p "$state_dir" "$notebook_dir"
notebook_dir=$(cd -- "$notebook_dir" && pwd -P)

if [[ ! -x "$juliaup_dir/bin/juliaup" ]]; then
    installer=$(mktemp)
    trap 'rm -f -- "$installer"' EXIT
    if command -v curl >/dev/null 2>&1; then
        curl --fail --show-error --location https://install.julialang.org -o "$installer"
    elif command -v wget >/dev/null 2>&1; then
        wget -q https://install.julialang.org -O "$installer"
    else
        printf 'Install curl or wget, or ask your administrator to provide one.\n' >&2
        exit 1
    fi
    sh "$installer" --yes --path "$juliaup_dir" \
        --default-channel release --add-to-path=yes
    rm -f -- "$installer"
    trap - EXIT
fi
export PATH="$juliaup_dir/bin:$PATH"
"$juliaup_dir/bin/juliaup" add release
julia="$juliaup_dir/bin/julia"

printf 'Installing Julia packages and configuring Miniconda (first run can take a while)...\n'
"$julia" +release --startup-file=no --project=@v#.# -e '
    using Pkg
    Pkg.add(["Plots", "IJulia", "Conda"])
    Pkg.build("Conda")
    Pkg.build("IJulia")
'

# Start a fresh Julia process after rebuilding Conda so its settings are loaded.
"$julia" +release --startup-file=no --project=@v#.# -e '
    import Conda
    # Conda.jl strips CONDA_* environment variables; pass channel flags directly.
    Conda.add(["notebook", "ipykernel"]; channel="conda-forge",
        args=`--override-channels`)
    using IJulia
    IJulia.installkernel("Julia", "--project=@v#.#";
        env=Dict("JULIA_DEPOT_PATH" => ENV["JULIA_DEPOT_PATH"]))
    using Plots
'

jupyter=$("$julia" +release --startup-file=no --project=@v#.# -e '
    import Conda
    print(joinpath(Conda.SCRIPTDIR, "jupyter"))
')

printf '\nStarting Jupyter in %s\nChoose Python 3 or Julia from the New menu.\n' "$notebook_dir"
printf 'Keep this terminal open; press Ctrl+C to stop the server.\n'
# Jupyter opens the default browser and prints a URL if opening it fails.
exec "$jupyter" notebook --ip=127.0.0.1 \
    --ServerApp.open_browser=True --notebook-dir="$notebook_dir"
