@echo on
setlocal EnableDelayedExpansion

rem Windows (MSVC + Qt6) build script for KLayout in conda-forge / rattler-build.
rem
rem Unlike KLayout's upstream build.bat (which expects a pre-packaged KLAYOUT_BITS
rem bundle), this script invokes conda-forge's qmake6 directly against
rem src/klayout.pro using headers and import libraries from %LIBRARY_PREFIX% and
rem Python from %PREFIX%.
rem
rem Note: When testing on Windows against KLayout v0.30.13 sources, verify the
rem win32-msvc library names / optional feature flags in src/klayout.pri
rem (e.g. HAVE_PNG, HAVE_CURL, HAVE_EXPAT, HAVE_GIT2, and zlib/libpng/libcurl/
rem expat/libgit2 .lib names in %LIBRARY_LIB%).

if "%CPU_COUNT%"=="" set "CPU_COUNT=2"

set "KLAYOUT_DIR=%LIBRARY_PREFIX%\lib\klayout"
set "BUILD_DIR=%SRC_DIR%\build-release"
set "LIB_ALIAS_DIR=%BUILD_DIR%\lib-aliases"

rem Locate qmake6 from conda-forge's qt6-main package.
set "QMAKE="
if exist "%LIBRARY_BIN%\qmake6.exe" (
    set "QMAKE=%LIBRARY_BIN%\qmake6.exe"
) else if exist "%LIBRARY_PREFIX%\lib\qt6\bin\qmake6.exe" (
    set "QMAKE=%LIBRARY_PREFIX%\lib\qt6\bin\qmake6.exe"
) else if exist "%LIBRARY_BIN%\qmake.exe" (
    set "QMAKE=%LIBRARY_BIN%\qmake.exe"
) else (
    for /f "delims=" %%Q in ('where qmake6.exe 2^>nul') do if "!QMAKE!"=="" set "QMAKE=%%Q"
)
if "%QMAKE%"=="" (
    echo ERROR: Could not find qmake6.exe in %LIBRARY_BIN% or PATH.
    exit /b 1
)
echo Using QMAKE=%QMAKE%

rem Compute Python build paths and normalize backslashes to forward slashes
rem for qmake (backslashes in qmake assignments can be treated as escapes).
"%PYTHON%" -c "import os, sys, sysconfig; v = f'{sys.version_info.major}{sys.version_info.minor}'; py_lib = os.path.join(sys.base_prefix, 'libs', f'python{v}.lib'); norm = lambda p: p.replace(chr(92), '/'); q = chr(34); env = {'PY_EXE_FWD': norm(sys.executable), 'PY_INC_FWD': norm(sysconfig.get_path('include')), 'PY_LIB_WIN': py_lib, 'PY_LIB_FWD': norm(py_lib), 'PY_EXT': sysconfig.get_config_var('EXT_SUFFIX') or '.pyd', 'KLAYOUT_DIR_FWD': norm(os.environ['KLAYOUT_DIR']), 'LIB_INC_FWD': norm(os.environ['LIBRARY_INC']), 'LIB_LIB_FWD': norm(os.environ['LIBRARY_LIB']), 'LIB_ALIAS_FWD': norm(os.environ['LIB_ALIAS_DIR']), 'SRC_DIR_FWD': norm(os.environ['SRC_DIR'])}; open('_klayout_env.bat', 'w').writelines(f'set {q}{k}={val}{q}\n' for k, val in env.items())"
if errorlevel 1 exit /b 1
call _klayout_env.bat
if errorlevel 1 exit /b 1
del _klayout_env.bat

if not exist "%PY_LIB_WIN%" (
    echo ERROR: Python import library not found: "%PY_LIB_WIN%"
    exit /b 1
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if errorlevel 1 exit /b 1

rem KLayout's qmake files link Unix-style short names (curl, expat, png, z, git2),
rem which MSVC resolves as curl.lib, expat.lib, png.lib, etc., whereas conda-forge
rem ships libcurl.lib, libexpat.lib, libpng16.lib, zlib.lib, git2.lib.
rem Create build-time import-library aliases outside %PREFIX% so MSVC links
rem cleanly against the real conda-forge DLLs without polluting the package.
"%PYTHON%" -c "import os, pathlib, shutil; lib = pathlib.Path(os.environ['LIBRARY_LIB']); dst = pathlib.Path(os.environ['LIB_ALIAS_DIR']); dst.mkdir(parents=True, exist_ok=True); mapping = {'curl.lib': ('libcurl.lib', 'libcurl_imp.lib'), 'expat.lib': ('libexpat.lib', 'libexpatMD.lib'), 'png.lib': ('libpng16.lib', 'libpng.lib', 'png16.lib'), 'z.lib': ('zlib.lib', 'zdll.lib'), 'zlib.lib': ('z.lib', 'zdll.lib'), 'git2.lib': ('libgit2.lib',), 'libgit2.lib': ('git2.lib',)}; print('Host libs:', sorted(p.name for p in lib.glob('*.lib') if any(t in p.name.lower() for t in ('curl', 'expat', 'png', 'zlib', 'zdll', 'git2')) or p.name.lower() == 'z.lib')); [print(f'Alias {k} -> {h}') or shutil.copyfile(lib / h, dst / k) for k, cands in mapping.items() if not (lib / k).is_file() for h in [next((c for c in cands if (lib / c).is_file()), None)] if h]"
if errorlevel 1 exit /b 1

set "INCLUDE=%LIBRARY_INC%;%INCLUDE%"
set "LIB=%LIB_ALIAS_DIR%;%LIBRARY_LIB%;%LIB%"

pushd "%BUILD_DIR%"
if errorlevel 1 exit /b 1

"%QMAKE%" ^
    -spec win32-msvc ^
    -recursive ^
    "CONFIG+=release" ^
    "CONFIG+=c++20" ^
    "HAVE_CPP20=1" ^
    "QMAKE_CXXFLAGS+=/std:c++20" ^
    "PREFIX=%KLAYOUT_DIR_FWD%" ^
    "KLAYOUT_VERSION=%PKG_VERSION%" ^
    "KLAYOUT_VERSION_DATE=unknown" ^
    "KLAYOUT_VERSION_REV=conda-forge" ^
    "HAVE_RUBY=0" ^
    "HAVE_QTBINDINGS=0" ^
    "HAVE_PYTHON=1" ^
    "PYTHON=%PY_EXE_FWD%" ^
    "PYTHONINCLUDE=%PY_INC_FWD%" ^
    "PYTHONLIBFILE=%PY_LIB_FWD%" ^
    "PYTHONEXTSUFFIX=%PY_EXT%" ^
    "HAVE_PNG=1" ^
    "HAVE_CURL=1" ^
    "HAVE_EXPAT=1" ^
    "HAVE_GIT2=1" ^
    "INCLUDEPATH+=%LIB_INC_FWD%" ^
    "LIBS+=-L%LIB_ALIAS_FWD%" ^
    "LIBS+=-L%LIB_LIB_FWD%" ^
    "LIBS+=-lzlib" ^
    "LIBS+=-lpng" ^
    "%SRC_DIR_FWD%/src/klayout.pro"
if errorlevel 1 (
    popd
    exit /b 1
)

rem Pre-create pymod output directories so parallel jom QMAKE_POST_LINK steps
rem do not race on "if not exist ...\pymod\klayout mkdir ...\pymod\klayout".
for %%D in (klayout klayout\db klayout\pex klayout\tl klayout\rdb klayout\lib klayout\lay klayout\pya pya) do (
    if not exist "%BUILD_DIR%\pymod\%%D" mkdir "%BUILD_DIR%\pymod\%%D"
)

where jom >nul 2>&1
if %errorlevel% equ 0 (
    jom /J%CPU_COUNT%
    if errorlevel 1 (
        popd
        exit /b 1
    )
    jom /J1 install
    if errorlevel 1 (
        popd
        exit /b 1
    )
) else (
    nmake
    if errorlevel 1 (
        popd
        exit /b 1
    )
    nmake install
    if errorlevel 1 (
        popd
        exit /b 1
    )
)

popd

rem Move the Python modules into site-packages, keeping executables,
rem klayout_*.dll, db_plugins/, and lay_plugins/ together in %KLAYOUT_DIR%.
if not exist "%SP_DIR%" mkdir "%SP_DIR%"
if errorlevel 1 exit /b 1

if not exist "%KLAYOUT_DIR%\pymod\klayout" (
    echo ERROR: Expected "%KLAYOUT_DIR%\pymod\klayout" was not installed.
    exit /b 1
)
move "%KLAYOUT_DIR%\pymod\klayout" "%SP_DIR%\klayout"
if errorlevel 1 exit /b 1

if exist "%KLAYOUT_DIR%\pymod\pya" (
    move "%KLAYOUT_DIR%\pymod\pya" "%SP_DIR%\pya"
    if errorlevel 1 exit /b 1
)

if exist "%KLAYOUT_DIR%\pymod" rmdir "%KLAYOUT_DIR%\pymod"

rem On Windows (Python 3.8+), register %LIBRARY_PREFIX%\lib\klayout so
rem importing klayout.* / pya can locate klayout_*.dll (and klayout_db.dll
rem resolves db_plugins/ and lay_plugins/ relative to itself).
"%PYTHON%" -c "import os, pathlib; q = chr(34); nl = chr(10); hook = nl.join(['import os as _os, sys as _sys', '_klayout_dll_dirs = []', f'if hasattr(_os, {q}add_dll_directory{q}):', f'    for _p in (_os.path.join(_sys.prefix, {q}Library{q}, {q}lib{q}, {q}klayout{q}), _os.path.join(_sys.prefix, {q}Library{q}, {q}bin{q})):', '        if _os.path.isdir(_p):', '            _klayout_dll_dirs.append(_os.add_dll_directory(_p))', '', '']); sp = pathlib.Path(os.environ['SP_DIR']); [p.write_text(hook + p.read_text(encoding='utf-8'), encoding='utf-8') for p in (sp / 'klayout' / '__init__.py', sp / 'pya' / '__init__.py') if p.is_file()]"
if errorlevel 1 exit /b 1

rem Create .bat launcher shims in %LIBRARY_BIN% pointing to executables in
rem %KLAYOUT_DIR% (avoids symlink permission issues on Windows and preserves
rem inst_path() == ...\Library\lib\klayout). Set KLAYOUT_PYTHONHOME to %PREFIX%
rem (%~dp0..\..) so KLayout's embedded Python finds the conda env's Lib/ and DLLs/
rem instead of defaulting to inst_path() (%PREFIX%\Library\lib\klayout).
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"
if errorlevel 1 exit /b 1

"%PYTHON%" -c "import os, pathlib; q, pct, bs, crlf = chr(34), chr(37), chr(92), chr(13) + chr(10); kdir = pathlib.Path(os.environ['KLAYOUT_DIR']); lbin = pathlib.Path(os.environ['LIBRARY_BIN']); exes = sorted(kdir.glob('*.exe')); assert exes, f'No .exe found in {kdir}'; mk = lambda name: crlf.join(['@echo off', 'setlocal', f'if not defined KLAYOUT_PYTHONHOME for {pct}{pct}I in ({q}{pct}~dp0..{bs}..{q}) do set {q}KLAYOUT_PYTHONHOME={pct}{pct}~fI{q}', f'{q}{pct}~dp0..{bs}lib{bs}klayout{bs}{name}{q} {pct}*', f'exit /b {pct}errorlevel{pct}', '']).encode('ascii'); [(lbin / f'{e.stem}.bat').write_bytes(mk(e.name)) for e in exes]; app = kdir / 'klayout_app.exe'; (lbin / 'klayout.bat').write_bytes(mk('klayout_app.exe')) if app.is_file() and not (lbin / 'klayout.bat').exists() else None"
if errorlevel 1 exit /b 1
