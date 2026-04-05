"""TWiLL CLI entry point — delegates to twl-engine.py."""
import importlib.util
import sys
from pathlib import Path


def run() -> None:
    """Load twl-engine.py and call its main() function."""
    import os
    env_path = os.environ.get("TWL_ENGINE_PATH")
    if env_path:
        engine_path = Path(env_path)
    else:
        engine_path = Path(__file__).parent.parent.parent / "twl-engine.py"
    if not engine_path.exists():
        print(f"Error: twl-engine.py not found at {engine_path}", file=sys.stderr)
        sys.exit(1)

    spec = importlib.util.spec_from_file_location("twl_engine", engine_path)
    if spec is None or spec.loader is None:
        print(f"Error: failed to load twl-engine.py from {engine_path}", file=sys.stderr)
        sys.exit(1)

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main()
