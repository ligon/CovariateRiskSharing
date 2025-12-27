import pytest
import lsms_library
from dvc.exceptions import PathMissingError
from pathlib import Path


def test_uganda_food_expenditures_handles_dvc_layouts():
    """
    Document the difference between running LSMS_Library from an editable checkout
    (works) and from the installed copy inside Poetry's in-project .venv (fails
    because the DVC metadata appears git-ignored).
    """

    uga = lsms_library.Country("Uganda")
    package_location = Path(lsms_library.__file__).resolve()
    running_from_site_packages = "site-packages" in package_location.parts

    if running_from_site_packages:
        missing_path = "../Data/GSEC15B.dta"
        with pytest.raises(PathMissingError) as excinfo:
            _ = uga.food_expenditures()
        assert missing_path in str(excinfo.value)
    else:
        df = uga.food_expenditures()
        assert not df.empty
