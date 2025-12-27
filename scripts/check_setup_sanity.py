#!/usr/bin/env python3

import sys, importlib.util
print(f"Checking environment: {sys.executable}")
errors = []

# Check 1: DVC 
if importlib.util.find_spec("dvc") is None: 
    errors.append("❌  DVC is not installed in this venv.")
else: 
    print("✅  DVC found.")

# Check 2: Editable Install (lsms_library) 
try: 
    import lsms_library
    print(f"✅  Project package found at: {lsms_library.__file__}")
except ImportError: 
    errors.append("❌  lsms_library not found. (Consider 'rm -rf .venv && make .venv')")

if errors: 
    print("n".join(errors))
    sys.exit(1)
else: 
    print("✨ Sanity Check Passed! You are ready to run.")
	
