import os
import runpy
import sys

# Boots the Hermes desktop/CLI with HERMES_HOME pinned to the project home and
# every non-loopback HTTP(S) routed through the bridge SOCKS (127.0.0.1:18081),
# so agent web tools and background checks leave via the server, not directly.
#
# IO_HOME must point at your Hermes project home — the directory that contains
# hermes-agent/ (the Hermes source) and profiles/.
#   IO_HOME=<your-hermes-home> python launch.py --profile io desktop

os.environ.pop("PYTHONHOME", None)
os.environ.pop("PYTHONPATH", None)
os.environ.pop("VIRTUAL_ENV", None)

HOME = os.environ.get("IO_HOME")
if not HOME:
    sys.exit("IO_HOME is not set — point it at the dir containing hermes-agent/ and profiles/")

sys.path.insert(0, os.path.join(HOME, "hermes-agent"))
sys._hermes_pin_default_home = True  # type: ignore[attr-defined]
os.environ["HERMES_HOME"] = HOME

# Route all provider/web HTTP(S) through the bridge SOCKS. Set both cases and
# ALL_PROXY because Python, Node, CLI tools, and native SDKs differ in which
# spelling they honor. Only loopback stays direct.
_proxy = "socks5h://127.0.0.1:18081"
for _name in ("HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "https_proxy", "http_proxy", "all_proxy"):
    os.environ[_name] = _proxy
for _name in ("NO_PROXY", "no_proxy"):
    os.environ[_name] = "127.0.0.1,localhost,::1"

# Neutral locale/timezone for env-context consistency with the Linux story.
os.environ.setdefault("TZ", "Europe/Berlin")
os.environ.setdefault("LC_ALL", "en_US.UTF-8")

import hermes_bootstrap  # noqa: E402  (from hermes-agent)

runpy.run_module("hermes_cli.main", run_name="__main__", alter_sys=True)
