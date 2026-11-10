import os
import runpy
import sys

# Boots the Hermes desktop/CLI with HERMES_HOME pinned to the project home and
# every non-loopback HTTP(S) routed through the bridge SOCKS (127.0.0.1:18081),
# so agent web tools and background checks leave via the server, not directly.
#
# IO_HOME must point at the directory that contains `hermes-agent` (the Hermes
# source) and `profiles/`. Defaults to the parent of this file's `client/hermes`.
# Example: IO_HOME="D:\\Programms\\IO" python launch.py --profile io desktop

os.environ.pop("PYTHONHOME", None)
os.environ.pop("PYTHONPATH", None)
os.environ.pop("VIRTUAL_ENV", None)

# this file lives at <IO_HOME>/client/hermes/launch.py -> two levels up.
_default = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HOME = os.environ.get("IO_HOME") or _default
sys.path.insert(0, os.path.join(HOME, "hermes-agent"))
sys._hermes_pin_default_home = True
os.environ["HERMES_HOME"] = HOME

# Route non-loopback HTTP(S) through the bridge SOCKS; loopback (8801) stays direct.
os.environ["HTTPS_PROXY"] = "socks5h://127.0.0.1:18081"
os.environ["HTTP_PROXY"] = "socks5h://127.0.0.1:18081"
os.environ["NO_PROXY"] = "127.0.0.1,localhost"

# Neutral locale/timezone for env-context consistency with the Linux story.
os.environ.setdefault("TZ", "Europe/Berlin")
os.environ.setdefault("LC_ALL", "en_US.UTF-8")

import hermes_bootstrap  # noqa: E402  (from hermes-agent)

runpy.run_module("hermes_cli.main", run_name="__main__", alter_sys=True)
