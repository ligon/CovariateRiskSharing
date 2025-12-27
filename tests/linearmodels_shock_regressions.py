# -*- coding: utf-8 -*-
rgsnfn="./var/uganda_preferred.rgsn"
FIGDIR="./Figures/"
"""Alternative shock regression path using linearmodels.PanelOLS.

This module mirrors the structure of `src/shock_regressions.py`, but swaps the
home-grown two-way fixed effects helper for `linearmodels` so we can compare
coefficients and standard errors.  It lives under `tests/` so folks can run it
locally without wiring it into the main build yet.

Usage (from the repository root):

    $ .venv/bin/python tests/linearmodels_shock_regressions.py

That command generates a small synthetic panel, runs both the existing helper
and the linearmodels variant, and prints a comparison table.
"""

from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Tuple

import numpy as np
import pandas as pd

try:
    from pyarrow.lib import ArrowInvalid
except ImportError:  # pragma: no cover
    class ArrowInvalid(Exception):  # type: ignore[override]
        """Fallback when pyarrow is unavailable."""
        pass

try:
    from linearmodels.panel import PanelOLS
except ImportError as exc:  # pragma: no cover - optional dependency
    raise SystemExit(
        "The linearmodels package is required for this comparison. "
        "Install it with `pip install linearmodels` (ideally inside .venv)."
    ) from exc

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT / "src"))

try:
    from shock_regressions import (
        twfe,
        construct_shocks,
        shock_shares,
        shocks as cached_shocks,
        covariate_shocks,
    )
except ModuleNotFoundError as exc:  # pragma: no cover - optional dependency
    if exc.name != "shock_regressions":
        raise
    raise SystemExit(
        "Unable to import shock_regressions. Run this script after tangling "
        "the literate source (e.g., `make src/shock_regressions.py`) inside "
        "an environment with the project's Python dependencies installed."
    ) from exc


@dataclass
class RegressionResult:
    params: pd.Series
    std_errors: pd.Series


def _coerce_panel(series: pd.Series, entity: str = "i", time: str = "t") -> pd.Series:
    """Ensure a Series has a MultiIndex (entity, time)."""
    if not isinstance(series.index, pd.MultiIndex):
        raise ValueError("Series must have a MultiIndex with entity and time levels.")

    if entity not in series.index.names or time not in series.index.names:
        raise ValueError(f"Index must contain levels named '{entity}' and '{time}'.")

    # Reorder levels so PanelOLS gets the expected (entity, time) structure.
    series = series.reorder_levels([entity, time] + [lvl for lvl in series.index.names if lvl not in (entity, time)])
    series = series.sort_index()
    return series


def twfe_linearmodels(
    X: pd.Series,
    Y: pd.DataFrame,
    entity: str = "i",
    time: str = "t",
    cov_type: str = "clustered",
    cluster_entity: bool = True,
    cluster_time: bool = True,
) -> RegressionResult:
    """Estimate shock regressions via linearmodels.PanelOLS."""

    X = _coerce_panel(X, entity, time).rename("shock")
    results = {}
    ses = {}

    for col in Y.columns:
        y = _coerce_panel(Y[col], entity, time).rename("outcome")
        df = pd.concat([y, X], axis=1).dropna()
        if df.empty:
            continue

        df.index = df.index.droplevel([lvl for lvl in df.index.names if lvl not in (entity, time)])
        df.index = df.index.set_names([entity, time])

        mod = PanelOLS(df["outcome"], df[["shock"]], entity_effects=True, time_effects=True)
        fit = mod.fit(
            cov_type=cov_type,
            cluster_entity=cluster_entity,
            cluster_time=cluster_time,
        )
        results[col] = fit.params["shock"]
        ses[col] = fit.std_errors["shock"]

    return RegressionResult(params=pd.Series(results), std_errors=pd.Series(ses))


def compare_with_existing(X: pd.Series, Y: pd.DataFrame) -> pd.DataFrame:
    """Run both implementations and return a tidy comparison table."""
    base_b, base_se = twfe(X, Y)
    lm_result = twfe_linearmodels(X, Y)

    comparison = pd.DataFrame(
        {
            "original_beta": base_b,
            "linearmodels_beta": lm_result.params,
            "original_se": base_se,
            "linearmodels_se": lm_result.std_errors,
        }
    )
    comparison["beta_diff"] = comparison["linearmodels_beta"] - comparison["original_beta"]
    comparison["se_diff"] = comparison["linearmodels_se"] - comparison["original_se"]
    return comparison


def _simulate_panel(n_entities: int = 40, n_periods: int = 6, seed: int = 42) -> tuple[pd.Series, pd.DataFrame]:
    """Generate a toy dataset for quick comparisons."""
    rng = np.random.default_rng(seed)
    idx = pd.MultiIndex.from_product(
        [range(n_entities), range(n_periods)],
        names=["i", "t"],
    )
    shock = pd.Series(rng.normal(size=len(idx)), index=idx, name="Shock Share")
    entity_fe = rng.normal(scale=0.5, size=n_entities)
    time_fe = rng.normal(scale=0.2, size=n_periods)
    noise = rng.normal(scale=0.3, size=len(idx))
    beta = 0.15
    outcome = beta * shock.values + entity_fe[idx.get_level_values("i")] + time_fe[idx.get_level_values("t")] + noise
    Y = pd.DataFrame({"Outcome": outcome}, index=idx)
    return shock, Y


def _standardize(series: pd.Series) -> pd.Series:
    return (series - series.mean()) / series.std()


def _ensure_panel(series: pd.Series, entity: str = "i", time: str = "t") -> pd.Series:
    """Collapse extra MultiIndex levels and ensure a clean (entity, time) index."""
    if not isinstance(series.index, pd.MultiIndex):
        raise ValueError("Expected a MultiIndex with at least entity and time.")
    missing = [lvl for lvl in (entity, time) if lvl not in series.index.names]
    if missing:
        raise ValueError(f"Series index missing required levels: {missing}")
    extra = [lvl for lvl in series.index.names if lvl not in (entity, time)]
    if extra:
        series = series.groupby([entity, time]).mean()
    series = series.sort_index()
    ent_vals = series.index.get_level_values(entity)
    time_vals = series.index.get_level_values(time)
    if not (
        pd.api.types.is_numeric_dtype(time_vals)
        or pd.api.types.is_datetime64_any_dtype(time_vals)
    ):
        time_vals = pd.Categorical(time_vals).codes
    series.index = pd.MultiIndex.from_arrays([ent_vals, time_vals], names=[entity, time])
    return series


def _to_series(obj, name: str) -> pd.Series:
    if isinstance(obj, pd.Series):
        s = obj.copy()
    elif hasattr(obj, "to_series"):
        s = obj.to_series()
    else:
        s = pd.Series(obj.values, index=obj.index)
    s.name = name
    return s


def load_actual_panel(
    shock_label: str = "Drought",
    dependent: str = "w",
    rgsn_path: Path | None = None,
) -> Tuple[pd.Series, pd.DataFrame]:
    """
    Pull the real Uganda panel used in the paper for a head-to-head comparison.

    Requirements:
      - `build/var/uganda_preferred.rgsn` must exist (run `make build/var/uganda_preferred.rgsn`).
      - The LSMS_Library editable install must be present (handled by Makefile).
    """

    if dependent != "w":
        raise ValueError("Only dependent='w' is currently supported.")

    import cfe  # noqa: WPS433
    import lsms_library as ll  # noqa: WPS433

    rgsn_path = rgsn_path or (ROOT / "build/var/uganda_preferred.rgsn")
    if not rgsn_path.exists():
        raise FileNotFoundError(
            f"{rgsn_path} not found. Run `make build/var/uganda_preferred.rgsn` first."
        )

    r = cfe.read_pickle(str(rgsn_path))
    w_raw = _to_series(r.get_w(), "w")
    w_std = _standardize(w_raw)

    uga = ll.Country("Uganda")
    shocks_df = construct_shocks(uga=uga)
    if shock_label not in shocks_df.Shock.unique():
        raise ValueError(f"Shock '{shock_label}' not found in data.")

    S = shock_shares(y=w_std.to_frame(), shocks=shocks_df, shock_labels=[shock_label])
    X = _ensure_panel(S[shock_label], entity="i", time="t")

    Y = _ensure_panel(w_std, entity="i", time="t").to_frame()
    return X, Y


def _parse_args():
    import argparse

    parser = argparse.ArgumentParser(description="Compare shock regressions.")
    parser.add_argument(
        "--real",
        action="store_true",
        help="Use the actual Uganda panel instead of a simulated toy dataset.",
    )
    parser.add_argument(
        "--shock",
        default="Drought",
        choices=covariate_shocks,
        help="Shock label to use when --real is set (default: Drought).",
    )
    return parser.parse_args()


if __name__ == "__main__":  # pragma: no cover - manual comparison utility
    args = _parse_args()
    if args.real:
        X, Y = load_actual_panel(shock_label=args.shock)
    else:
        X, Y = _simulate_panel()

    table = compare_with_existing(X, Y)
    pd.set_option("display.precision", 4)
    print("\nComparison of existing TWFE helper vs. linearmodels.PanelOLS:\n")
    print(table)
