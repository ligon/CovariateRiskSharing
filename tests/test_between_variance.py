import pandas as pd
import pytest
import sys
import types


def _install_shocks_stub():
    """Provide a lightweight shocks module so imports don't hit DVC."""
    if "shocks" in sys.modules:
        return
    stub = types.ModuleType("shocks")
    stub.load_shocks = lambda: pd.DataFrame()
    def _dummy(*args, **kwargs):
        return None
    stub.my_arellano_robust_cov = _dummy
    stub.smoothing_regression = _dummy
    stub.any_shock_effect = _dummy
    stub.shock_effect = _dummy
    stub.construct_shocks = _dummy
    stub.shock_shares = _dummy
    stub.covariate_shocks = []
    stub.idiosyncratic_shocks = []
    stub.infrequent = []
    stub.shock_labels = []
    stub.howcoped_labels = []
    sys.modules["shocks"] = stub


_install_shocks_stub()

def _install_lsms_stub():
    if "lsms_library" in sys.modules:
        return
    stub = types.ModuleType("lsms_library")
    class _DummyCountry:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("Country stub should not be instantiated in unit tests.")
    stub.Country = _DummyCountry
    sys.modules["lsms_library"] = stub


_install_lsms_stub()

from src.between_variance import _prepare_cluster_dataframe  # noqa: E402


def _mock_index():
    return pd.MultiIndex.from_tuples(
        [
            ('hh1', '2005-06', 'Central'),
            ('hh2', '2005-06', 'Central'),
        ],
        names=['i', 't', 'm'],
    )


def test_prepare_cluster_dataframe_prefers_other_features_v():
    idx = _mock_index()
    other = pd.DataFrame({'v': ['A', 'B'], 'Rural': [1, 0]}, index=idx)

    result = _prepare_cluster_dataframe(other)

    pd.testing.assert_series_equal(result['v'], other['v'])
    pd.testing.assert_series_equal(result['Rural'], other['Rural'])


def test_prepare_cluster_dataframe_uses_locality_when_needed():
    idx = _mock_index()
    other = pd.DataFrame({'Rural': [1, 1]}, index=idx)
    locality = pd.DataFrame({'v': ['A', 'B']}, index=idx)

    result = _prepare_cluster_dataframe(other, locality)

    pd.testing.assert_series_equal(result['v'], locality['v'])
    pd.testing.assert_series_equal(result['Rural'], other['Rural'])


def test_prepare_cluster_dataframe_errors_when_v_missing():
    idx = _mock_index()
    other = pd.DataFrame({'Rural': [1, 1]}, index=idx)

    with pytest.raises(RuntimeError):
        _prepare_cluster_dataframe(other, locality_df=None, locality_error=None)
