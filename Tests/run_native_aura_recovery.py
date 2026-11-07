"""Run the isolated native-aura regression suite using Lua 5.1 via Lupa."""
from pathlib import Path

from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
runtime = LuaRuntime(unpack_returned_tuples=True)
runtime.globals().REPOSITORY_ROOT = str(root)
runtime.execute((root / "Tests/native_aura_recovery.lua").read_text())
