# PyInstaller spec for the OCR sidecar - produces a one-dir build at
# dist/stockcalc_ocr/, which setup_flutter.bat/run_flutter.bat copy into
# app/build/windows/x64/runner/Release/ocr_sidecar/ next to the Flutter
# app's own exe (ocr_sidecar_launcher.dart looks for it there).
#
# Build with: pyinstaller build_sidecar.spec
# Prerequisite: run prefetch_models.py first so the model cache exists to
# bundle (see the `datas` entry below).
#
# paddlepaddle is known to need explicit hidden-import/binary handling
# with PyInstaller - its C-extension/.pyd loading isn't always picked up
# by static analysis. collect_all() pulls in each package's full data +
# binary + submodule set, which is the documented way to bundle it; if the
# frozen exe still fails to start, the first things to check are missing
# .pyd/.dll files under paddle's installed package directory and missing
# `paddle.*`/`paddleocr.*` submodules in hiddenimports.

import os
from pathlib import Path

from PyInstaller.utils.hooks import collect_all

block_cipher = None

datas = []
binaries = []
hiddenimports = []

# Conda-based Pythons keep libffi/openssl/etc. in <prefix>\Library\bin, which
# PyInstaller does not scan, so the frozen exe dies at startup with
# "DLL load failed while importing _ctypes". Bundle them explicitly. (A
# python.org Python has none of these files there, so this is a no-op.)
import glob
import sys

for _dll_dir in (Path(sys.base_prefix) / "Library" / "bin", Path(sys.base_prefix) / "DLLs"):
    for _pattern in ("ffi*.dll", "libffi*.dll", "libssl*.dll", "libcrypto*.dll",
                     "liblzma*.dll", "libbz2*.dll", "sqlite3*.dll", "zlib*.dll"):
        for _dll in glob.glob(str(_dll_dir / _pattern)):
            binaries.append((_dll, "."))

# Several of PaddleOCR's dependencies (imageio, scikit-image, ...) call
# importlib.metadata.version() at import time; without their *.dist-info
# the frozen exe dies with PackageNotFoundError. Bundle the metadata of
# everything installed from requirements.txt (missing ones are skipped).
from PyInstaller.utils.hooks import copy_metadata

for _dist in ("imageio", "imgaug", "scikit-image", "scipy", "numpy", "pillow", "tifffile",
              "lazy_loader", "networkx", "shapely", "pyclipper", "opencv-python",
              "opencv-contrib-python", "opencv-python-headless", "albumentations", "albucore",
              "packaging", "tqdm", "requests", "paddlepaddle", "paddleocr", "lmdb", "rapidfuzz",
              "python-docx", "beautifulsoup4", "lxml", "pyyaml", "fire", "cython", "pydantic",
              "pydantic-core", "protobuf", "astor", "decorator", "opt-einsum", "httpx", "matplotlib",
              "scikit-learn", "joblib", "threadpoolctl", "contourpy", "kiwisolver", "cycler",
              "fonttools", "pyparsing", "python-dateutil", "six", "certifi", "idna", "urllib3",
              "charset-normalizer", "anyio", "h11", "httpcore", "colorama", "termcolor",
              "typing-extensions", "annotated-types", "typing-inspection", "cloudpickle",
              "soupsieve", "imageio-ffmpeg", "attrs"):
    try:
        datas += copy_metadata(_dist)
    except Exception:
        pass

for pkg in ("paddle", "paddleocr", "paddlex"):
    pkg_datas, pkg_binaries, pkg_hidden = collect_all(pkg)
    datas += pkg_datas
    binaries += pkg_binaries
    hiddenimports += pkg_hidden

# Bundle the pre-fetched model cache (run prefetch_models.py first) so the
# shipped app is offline-capable immediately instead of downloading models
# on first use.
paddleocr_cache = Path.home() / ".paddleocr"
if paddleocr_cache.exists():
    datas.append((str(paddleocr_cache), ".paddleocr"))
else:
    print(
        f"WARNING: {paddleocr_cache} not found - run prefetch_models.py "
        "before building, or the shipped app will try to download models "
        "on first use instead of working offline."
    )

a = Analysis(
    ["server.py"],
    pathex=[os.path.dirname(os.path.abspath("server.py"))],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    cipher=block_cipher,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="stockcalc_ocr",
    debug=False,
    strip=False,
    upx=False,
    console=True,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name="stockcalc_ocr",
)
