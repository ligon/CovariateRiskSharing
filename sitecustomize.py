"""
Site customizations for RiskSharing_Replication.

Hook into the Python import machinery so that if the `lsms_library` package fails
to decrypt its protected assets (e.g., missing passphrase), users receive guidance
on how to obtain access.
"""

import os
import random
import sys
from importlib import abc as importlib_abc
from importlib import machinery
from pathlib import Path
import warnings

import numpy as np

_REPO_ROOT = Path(__file__).resolve().parent
_LSMS_LIBRARY_PATH = _REPO_ROOT / "external_data" / "LSMS_Library"
if _LSMS_LIBRARY_PATH.exists():
    lsms_path = str(_LSMS_LIBRARY_PATH)
    if lsms_path not in sys.path:
        sys.path.insert(0, lsms_path)

_AUTH_HINT = (
    "The LSMS data are encrypted. Request the passphrase from Ethan Ligon "
    "<ligon@berkeley.edu> and provide it to `lsms_library` when prompted."
)


class _LSMSLoader(importlib_abc.Loader):
    """Wrapper loader that enriches authentication failures with a helpful message."""

    def __init__(self, wrapped_loader):
        self._wrapped = wrapped_loader

    def create_module(self, spec):
        if hasattr(self._wrapped, "create_module"):
            return self._wrapped.create_module(spec)
        return None

    def exec_module(self, module):
        try:
            self._wrapped.exec_module(module)
        except ValueError as exc:
            message = str(exc)
            if "Decryption failed" in message:
                raise ValueError(f"{message}\n\nHint: {_AUTH_HINT}") from exc
            raise

    def get_resource_reader(self, fullname):
        """Delegate resource reader requests so importlib.resources works."""
        reader = getattr(self._wrapped, "get_resource_reader", None)
        if reader:
            return reader(fullname)
        return None

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


class _LSMSFinder(importlib_abc.MetaPathFinder):
    """Finder that wraps the lsms_library module loader."""

    def find_spec(self, fullname, path, target=None):
        if fullname != "lsms_library":
            return None
        spec = machinery.PathFinder.find_spec(fullname, path, target)
        if spec and spec.loader and not isinstance(spec.loader, _LSMSLoader):
            spec.loader = _LSMSLoader(spec.loader)
        return spec


if not any(isinstance(finder, _LSMSFinder) for finder in sys.meta_path):
    # Prepend our finder so it takes precedence over default path finders.
    sys.meta_path.insert(0, _LSMSFinder())


warnings.filterwarnings(
    "ignore",
    category=SyntaxWarning,
    module=r"lsms\.tools",
)

# Global RNG seeding ----------------------------------------------------------
_seed_env_var = "RISKSHARING_SEED"
_seed_value = os.getenv(_seed_env_var)
if _seed_value:
    try:
        _seed_int = int(_seed_value, 0)
    except ValueError:
        raise ValueError(
            f"{_seed_env_var} must be an integer; got {_seed_value!r}"
        ) from None

    random.seed(_seed_int)
    np.random.seed(_seed_int)
