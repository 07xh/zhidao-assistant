"""Check application-local dependencies. Never reads login cookies or connects to network."""
from importlib.metadata import version
import sys
try:
    assert version("zhs") == "0.1.5"
except Exception:
    sys.exit(1)
print("ZHS 0.1.5 verified")
