#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2023-2026, NVIDIA CORPORATION.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

source rapids-init-pip

RAPIDS_PY_CUDA_SUFFIX="$(rapids-wheel-ctk-name-gen "${RAPIDS_CUDA_VERSION}")"

# Download the cudf, libcudf, and pylibcudf built in the previous step
CUDF_WHEELHOUSE=$(rapids-download-from-github "$(rapids-package-name "wheel_python" cudf --stable --cuda "$RAPIDS_CUDA_VERSION")")
LIBCUDF_WHEELHOUSE=$(RAPIDS_PY_WHEEL_NAME="libcudf_${RAPIDS_PY_CUDA_SUFFIX}" rapids-download-wheels-from-github cpp)
PYLIBCUDF_WHEELHOUSE=$(rapids-download-from-github "$(rapids-package-name "wheel_python" pylibcudf --stable --cuda "$RAPIDS_CUDA_VERSION")")

function ensure_cublaslt_symlink()
{
    rapids-logger "Ensure libcublasLt.so symlink exists"
    python - <<'PY'
import sysconfig
from pathlib import Path

site_packages = {
    Path(path)
    for key in ("purelib", "platlib")
    if (path := sysconfig.get_path(key)) is not None
}

for site_package in sorted(path for path in site_packages if path.is_dir()):
    for soname in ("libcublasLt.so.13", "libcublasLt.so.12"):
        matches = sorted(site_package.rglob(soname))
        if not matches:
            continue

        lib = matches[0]
        symlink = lib.with_name("libcublasLt.so")

        if symlink.is_symlink():
            symlink.unlink()
        elif symlink.exists():
            print(f"{symlink} already exists and is not a symlink; leaving it in place")
            raise SystemExit(0)

        symlink.symlink_to(lib.name)
        print(f"Created {symlink} -> {lib.name}")
        raise SystemExit(0)

print("No libcublasLt.so.12 or libcublasLt.so.13 found in site-packages; skipping")
PY
}

rapids-logger "Install pylibcudf and its basic dependencies in a virtual environment"

# generate constraints (possibly pinning to oldest support versions of dependencies)
rapids-generate-pip-constraints py_test_cudf "${PIP_CONSTRAINT}"

RESULTS_DIR=${RAPIDS_TESTS_DIR:-"$(mktemp -d)"}
RAPIDS_TESTS_DIR=${RAPIDS_TESTS_DIR:-"${RESULTS_DIR}/test-results"}/
mkdir -p "${RAPIDS_TESTS_DIR}"

# To test pylibcudf without its optional dependencies, we create a virtual environment
python -m venv env
. env/bin/activate

# notes:
#
#   * echo to expand wildcard before adding `[test]` requires for pip
#   * just providing --constraint="${PIP_CONSTRAINT}" to be explicit, and because
#     that environment variable is ignored if any other --constraint are passed via the CLI
#
rapids-pip-retry install \
    -v \
    --prefer-binary \
    --constraint "${PIP_CONSTRAINT}" \
    "$(echo "${LIBCUDF_WHEELHOUSE}"/libcudf_"${RAPIDS_PY_CUDA_SUFFIX}"*.whl)" \
    "$(echo "${PYLIBCUDF_WHEELHOUSE}"/pylibcudf_"${RAPIDS_PY_CUDA_SUFFIX}"*.whl)[test]"\
    "cuda-toolkit[cublas]"

ensure_cublaslt_symlink

rapids-logger "pytest pylibcudf without optional dependencies"
pushd python/pylibcudf/tests
timeout 30m python -m pytest \
  --cache-clear \
  --numprocesses=8 \
  --dist=worksteal \
  .
popd

deactivate

rapids-logger "Install cudf, pylibcudf, and test requirements"

# notes:
#
#   * echo to expand wildcard before adding `[test]` requires for pip
#   * just providing --constraint="${PIP_CONSTRAINT}" to be explicit, and because
#     that environment variable is ignored if any other --constraint are passed via the CLI
#
rapids-pip-retry install \
    -v \
    --prefer-binary \
    --constraint "${PIP_CONSTRAINT}" \
    "$(echo "${CUDF_WHEELHOUSE}"/cudf_"${RAPIDS_PY_CUDA_SUFFIX}"*.whl)[test]" \
    "$(echo "${LIBCUDF_WHEELHOUSE}"/libcudf_"${RAPIDS_PY_CUDA_SUFFIX}"*.whl)" \
    "$(echo "${PYLIBCUDF_WHEELHOUSE}"/pylibcudf_"${RAPIDS_PY_CUDA_SUFFIX}"*.whl)[test, pyarrow, numpy]"

ensure_cublaslt_symlink

rapids-logger "pytest pylibcudf"
pushd python/pylibcudf/tests
timeout 30m python -m pytest \
  --cache-clear \
  --numprocesses=8 \
  --dist=worksteal \
  .
popd

rapids-logger "pytest cudf"
pushd python/cudf/cudf/tests
timeout 30m python -m pytest \
  --cache-clear \
  --junitxml="${RAPIDS_TESTS_DIR}/junit-cudf.xml" \
  --numprocesses=8 \
  --dist=worksteal \
  .
popd
