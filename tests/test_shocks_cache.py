import sys
import types
from pathlib import Path

# Stub heavy dependencies before importing shocks.
if 'pandas' not in sys.modules:
    pd_stub = types.ModuleType('pandas')
    sys.modules['pandas'] = pd_stub

if 'matplotlib' not in sys.modules:
    matplotlib_stub = types.ModuleType('matplotlib')
    pyplot_stub = types.ModuleType('matplotlib.pyplot')
    matplotlib_stub.pyplot = pyplot_stub
    sys.modules['matplotlib'] = matplotlib_stub
    sys.modules['matplotlib.pyplot'] = pyplot_stub

if 'cfe' not in sys.modules:
    cfe_stub = types.ModuleType('cfe')
    df_utils_stub = types.ModuleType('cfe.df_utils')
    df_utils_stub.drop_missing = lambda *args, **kwargs: None
    df_utils_stub.df_to_orgtbl = lambda *args, **kwargs: None
    df_utils_stub.ols = lambda *args, **kwargs: (None, None)
    df_utils_stub.arellano_robust_cov = lambda *args, **kwargs: None
    cfe_stub.df_utils = df_utils_stub
    sys.modules['cfe'] = cfe_stub
    sys.modules['cfe.df_utils'] = df_utils_stub

if 'numpy' not in sys.modules:
    numpy_stub = types.ModuleType('numpy')
    numpy_stub.linalg = types.SimpleNamespace(inv=lambda *args, **kwargs: None)
    numpy_stub.ndarray = object
    numpy_stub.array = lambda *args, **kwargs: None
    sys.modules['numpy'] = numpy_stub

if 'lsms_library' not in sys.modules:
    lsms_stub = types.ModuleType('lsms_library')
    lsms_stub.Country = lambda *args, **kwargs: None
    sys.modules['lsms_library'] = lsms_stub

if 'lsms_library.local_tools' not in sys.modules:
    local_tools_stub = types.ModuleType('lsms_library.local_tools')
    def default_raise(*args, **kwargs):
        raise FileNotFoundError
    local_tools_stub.to_parquet = lambda *args, **kwargs: None
    local_tools_stub.get_dataframe = default_raise
    sys.modules['lsms_library.local_tools'] = local_tools_stub

# Ensure relative imports work
sys.path.append(str(Path(__file__).resolve().parents[1] / 'src'))

import shocks


def test_load_shocks_prefers_cache(monkeypatch):
    fake = {'Shock': ['Drought'], 'Year': [2005]}

    calls = []

    def fake_get_dataframe(path):
        calls.append(path)
        return fake

    monkeypatch.setattr(shocks, 'get_dataframe', fake_get_dataframe)

    result = shocks.load_shocks()

    assert calls == ['var/shocks.parquet']
    assert result is fake


def test_load_shocks_falls_back_to_main(monkeypatch):
    fake = {'Shock': ['Floods'], 'Year': [2009]}

    def fake_get_dataframe(path):
        raise FileNotFoundError

    def fake_main():
        return fake, None

    monkeypatch.setattr(shocks, 'get_dataframe', fake_get_dataframe)
    monkeypatch.setattr(shocks, 'main', fake_main)

    result = shocks.load_shocks()

    assert result is fake
