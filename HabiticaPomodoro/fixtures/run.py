#!/usr/bin/env python3
"""Compile unmodified Apple sources and run isolated, offline CLI fixtures."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

FIXTURES_DIR = Path(__file__).resolve().parent
APP_ROOT = FIXTURES_DIR.parent
REPO_ROOT = APP_ROOT.parent
SOURCE_DIR = APP_ROOT / "HabiticaPomodoro"
CASES_DIR = FIXTURES_DIR / "cases"

# Keep production dependencies centralized so new cases need no bespoke runner.
SOURCE_NAMES = (
    "Managers.swift",
    "HabiticaAPI.swift",
    "PlantJournal.swift",
    "PomodoroEngine.swift",
    "BlockNotificationManager.swift",
    "BlockRewardManager.swift",
)
CASE_HELPERS = {
    "qishi_audio": ("audio_stubs.swift",),
    "foreground_recovery": ("audio_stubs.swift", "notification_stubs.swift", "activation_stubs.swift"),
}
EXCLUDED_CASES = {Path(helper).stem for helpers in CASE_HELPERS.values() for helper in helpers}
SLOW_READ_CASES = {"file_monitor", "foreground_recovery"}

# A generated top-level preflight must precede every case's manager access.
# The case itself is copied verbatim after this block into build/main.swift.
SWIFT_PREFLIGHT = r'''
import Foundation
import Darwin

setbuf(stdout, nil)
do {
    let env = ProcessInfo.processInfo.environment
    func requiredURL(_ key: String) -> URL {
        guard let value = env[key], !value.isEmpty else {
            fatalError("Missing fixture isolation variable: \(key)")
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    }
    let root = requiredURL("POMO_FIXTURE_RUN_ROOT")
    let caseRoot = requiredURL("POMO_FIXTURE_CASE_ROOT")
    let home = requiredURL("CFFIXED_USER_HOME")
    let data = requiredURL("POMO_FIXTURE_DATA_ROOT")
    let repo = requiredURL("POMO_FIXTURE_REPO_ROOT")
    precondition(root.path != "/" && root != repo && !root.path.hasPrefix(repo.path + "/"),
                 "work root must be outside the checkout")
    precondition(caseRoot.path.hasPrefix(root.path + "/"), "case root escaped work root")
    precondition(home == caseRoot.appendingPathComponent("home", isDirectory: true), "unexpected synthetic home")
    precondition(data == caseRoot.appendingPathComponent("fixture", isDirectory: true), "unexpected fixture directory")
    precondition(CommandLine.arguments.count > 1 &&
        URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path == data.path,
        "case argument does not match isolated fixture")
    let fm = FileManager.default
    let actualHome = fm.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
    precondition(actualHome == home, "CFFIXED_USER_HOME did not isolate Foundation home")
    let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .standardizedFileURL.resolvingSymlinksInPath()
    precondition(documents.path.hasPrefix(home.path + "/"), "Foundation Documents escaped synthetic home")
    #if DEBUG
    PomodoroDataDir.isolatedDirectory = data
    precondition(PomodoroDataDir.resolvedURL.standardizedFileURL == data, "DEBUG data-directory isolation failed")
    #else
    fatalError("Fixtures require -D DEBUG for data-directory isolation")
    #endif
    precondition(Bundle.main.bundleIdentifier == env["POMO_FIXTURE_BUNDLE_ID"], "unique probe bundle was not recognized")
    guard let catalog = Bundle.main.url(forResource: "qishi_presets", withExtension: "json", subdirectory: "audio") else {
        fatalError("Probe.app is missing the real bundled Qishi scene catalog")
    }
    precondition(catalog.resolvingSymlinksInPath().path.hasPrefix(caseRoot.path + "/"), "catalog escaped case root")
    print("SAFETY home=\(home.path) documents=\(documents.path) data=\(data.path) bundle=\(Bundle.main.bundleIdentifier!)")
}

'''


def inside(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def safe_work_base(value: str) -> Path:
    """Resolve aliases before any mkdir; never probe or read live app data."""
    candidate = Path(value).expanduser().absolute()
    base = candidate.resolve()
    home = Path.home().resolve()
    if base in (Path(base.anchor), home):
        raise ValueError("--work must name a scratch directory, not / or your home")
    if inside(base, REPO_ROOT):
        raise ValueError("work directory must be outside the repository")
    forbidden_components = {"documents", "mobile documents", "cloudstorage", ".habitica-pomodoro"}
    protected = tuple((home / relative).resolve() for relative in (
        "Documents", "Library/Mobile Documents", "Library/CloudStorage",
    ))
    if (any(component.casefold() in forbidden_components for component in candidate.parts + base.parts)
            or any(inside(base, directory) for directory in protected)):
        raise ValueError("work directory must be outside Documents, iCloud, CloudStorage, and live app data")
    if base.exists() and not base.is_dir():
        raise ValueError("work directory base is not a directory")
    return base


def child_environment(case_root: Path, run_root: Path, bundle_id: str) -> dict:
    env = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("DYLD_", "POMO_"))
    }
    home = case_root / "home"
    cache = case_root / "module-cache"
    env.update(
        HOME=str(home),
        CFFIXED_USER_HOME=str(home),
        TMPDIR=str(case_root / "tmp") + os.sep,
        CLANG_MODULE_CACHE_PATH=str(cache),
        SWIFT_MODULECACHE_PATH=str(cache),
        XDG_CACHE_HOME=str(home / "Library" / "Caches"),
        XDG_CONFIG_HOME=str(home / ".config"),
        XDG_DATA_HOME=str(home / ".local" / "share"),
        POMO_FIXTURE_RUN_ROOT=str(run_root),
        POMO_FIXTURE_CASE_ROOT=str(case_root),
        POMO_FIXTURE_DATA_ROOT=str(case_root / "fixture"),
        POMO_FIXTURE_REPO_ROOT=str(REPO_ROOT),
        POMO_FIXTURE_BUNDLE_ID=bundle_id,
    )
    return env


def run_command(command: list, cwd: Path, env: dict, log: Path, timeout: float) -> dict:
    started = time.monotonic()
    timed_out = False
    try:
        process = subprocess.Popen(
            command, cwd=str(cwd), env=env, text=True, encoding="utf-8", errors="replace",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
        )
    except OSError as error:
        log.write_text("COMMAND " + shlex.join(command) + "\n" + str(error) + "\n", encoding="utf-8")
        return {"returncode": 127, "seconds": time.monotonic() - started, "timed_out": False, "output": str(error)}
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        # xcrun/swiftc may have spawned a frontend; kill the whole probe group.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
    elapsed = time.monotonic() - started
    returncode = 124 if timed_out else process.returncode
    output = stdout + ("\n--- STDERR ---\n" + stderr if stderr else "")
    log.write_text(
        "COMMAND " + shlex.join(command) + "\n"
        + f"RETURN_CODE {returncode}\nTIMEOUT {timed_out}\nSECONDS {elapsed:.3f}\n"
        + "--- OUTPUT ---\n" + output,
        encoding="utf-8",
    )
    return {"returncode": returncode, "seconds": elapsed, "timed_out": timed_out, "output": output}


def copy_snapshot(source: Path, target: Path, hashes: dict) -> None:
    data = source.read_bytes()
    target.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f"snapshot verification failed: {source.name}")
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f"source changed during snapshot: {source.name}; rerun once edits settle")
    hashes[str(source.relative_to(REPO_ROOT))] = digest


def activation_body(text: str, marker: str, *, observer: bool = False) -> str:
    """Copy real hook bodies verbatim; fail if the entry seam is absent/ambiguous."""
    if text.count(marker) != 1:
        raise ValueError("foreground hook marker is missing or ambiguous")
    start = text.index(marker) + len(marker)
    if observer:
        start = text.index(") { _ in", start) + len(") { _ in")
    depth = 1
    for end in range(start, len(text)):
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
            if depth == 0:
                return text[start:end]
    raise ValueError("foreground hook body is unbalanced")


def run_case(name: str, run_root: Path, args: argparse.Namespace) -> dict:
    result = {"case": name, "status": "FAIL", "assertions": 0}
    case = CASES_DIR / (name + ".swift")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or not case.is_file() or name in EXCLUDED_CASES:
        result["error"] = "selected case is missing or is not a runnable case"
        return result
    case_root = run_root / name
    case_root.mkdir(mode=0o700)
    result["work"] = str(case_root)
    for directory in ("build", "fixture", "home", "home/Documents", "home/Library/Preferences", "tmp", "module-cache"):
        (case_root / directory).mkdir(parents=True, exist_ok=True)
    bundle_token = uuid.uuid4().hex
    executable_name = f"pomo-fixture-{name}-{bundle_token[:12]}"
    bundle_id = "org.habiticapomodoro.fixtures.probe." + bundle_token
    app = case_root / "Probe.app" / "Contents"
    executable = app / "MacOS" / executable_name
    executable.parent.mkdir(parents=True)
    resources = app / "Resources" / "audio"
    resources.mkdir(parents=True)
    with (app / "Info.plist").open("wb") as stream:
        plistlib.dump({
            "CFBundleIdentifier": bundle_id,
            "CFBundleExecutable": executable_name,
            "CFBundleName": "PomodoroFixtureProbe",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
            "LSBackgroundOnly": True,
        }, stream)
    result["bundle_id"] = bundle_id
    env = child_environment(case_root, run_root, bundle_id)
    build = case_root / "build"
    hashes = {}
    sources = []
    interposer = case_root / "slow_read.dylib"
    try:
        for source_name in SOURCE_NAMES:
            snapshot = build / source_name
            copy_snapshot(SOURCE_DIR / source_name, snapshot, hashes)
            sources.append(str(snapshot))
        # Only this actual JSON is bundled. No mp3s or DEBUG catalog overrides.
        copy_snapshot(SOURCE_DIR / "audio" / "qishi_presets.json", resources / "qishi_presets.json", hashes)
        for helper in CASE_HELPERS.get(name, ()):
            snapshot = build / helper
            copy_snapshot(CASES_DIR / helper, snapshot, hashes)
            sources.append(str(snapshot))
        if name == "foreground_recovery":
            # Compile only these exact activation bodies, not a platform UI/app.
            # The snapshots/fingerprints still cover each complete source file.
            mac = build / "ContentView.swift"
            ios = build / "HabiticaPomodoroMobileApp.swift"
            copy_snapshot(SOURCE_DIR / mac.name, mac, hashes)
            copy_snapshot(APP_ROOT / "iOS" / ios.name, ios, hashes)
            hooks = build / "foreground_hooks.swift"
            hooks.write_text(
                "import Foundation\nfunc fixtureMacDidBecomeActive() {"
                + activation_body(mac.read_text(), "func applicationDidBecomeActive(_ notification: Notification) {")
                + "\n}\nfunc fixtureIOSDidBecomeActive() {"
                + activation_body(ios.read_text(), "forName: UIApplication.didBecomeActiveNotification", observer=True)
                + "\n}\n", encoding="utf-8",
            )
            sources.append(str(hooks))
        case_bytes = case.read_bytes()
        hashes[str(case.relative_to(REPO_ROOT))] = hashlib.sha256(case_bytes).hexdigest()
        main = build / "main.swift"
        main.write_bytes(SWIFT_PREFLIGHT.encode("utf-8") + case_bytes)
        sources.append(str(main))
        (case_root / "source-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8")
        if name in SLOW_READ_CASES:
            interposer_source = build / "slow_read.c"
            copy_snapshot(FIXTURES_DIR / "slow_read.c", interposer_source, hashes)
            (case_root / "source-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8")
            stage = run_command(
                ["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-dynamiclib",
                 str(interposer_source), "-o", str(interposer)],
                case_root, env, case_root / "interposer-compile.log", args.compile_timeout,
            )
            if stage["returncode"]:
                result.update(stage="interposer-compile", returncode=stage["returncode"], log=str(case_root / "interposer-compile.log"))
                print(stage["output"], end="\n", flush=True)
                return result
        compile_log = case_root / "compile.log"
        stage = run_command(
            ["xcrun", "swiftc", "-D", "DEBUG", "-swift-version", "5", "-g",
             "-module-cache-path", str(case_root / "module-cache")]
            + sources + ["-o", str(executable)],
            case_root, env, compile_log, args.compile_timeout,
        )
        result["compile_seconds"] = round(stage["seconds"], 3)
        if stage["returncode"]:
            result.update(stage="compile", returncode=stage["returncode"], log=str(compile_log))
            print(stage["output"], end="\n", flush=True)
            return result
        if name in SLOW_READ_CASES:
            env["DYLD_INSERT_LIBRARIES"] = str(interposer)
        result_log = case_root / "result.log"
        stage = run_command(
            [str(executable), str(case_root / "fixture"), str(case_root / "home"), str(case_root)],
            case_root, env, result_log, args.run_timeout,
        )
        print(stage["output"], end="" if stage["output"].endswith("\n") else "\n", flush=True)
        result.update(
            stage="run", returncode=stage["returncode"], log=str(result_log),
            run_seconds=round(stage["seconds"], 3), timed_out=stage["timed_out"],
            assertions=sum(line.startswith("PASS ") for line in stage["output"].splitlines()),
        )
        if stage["returncode"] == 0:
            result["status"] = "PASS"
    except (OSError, RuntimeError, ValueError) as error:
        result["error"] = str(error)
        (case_root / "setup-error.log").write_text(str(error) + "\n", encoding="utf-8")
        result["log"] = str(case_root / "setup-error.log")
    return result


def positive_seconds(value: str) -> float:
    number = float(value)
    if not 0 < number < float("inf"):
        raise argparse.ArgumentTypeError("timeout must be finite and positive")
    return number


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", metavar="CASE", help="run only CASE (repeatable)")
    parser.add_argument("--work", metavar="SCRATCH_BASE", help="parent for a unique, retained run root")
    parser.add_argument("--compile-timeout", type=positive_seconds, default=180.0)
    parser.add_argument("--run-timeout", type=positive_seconds, default=60.0)
    args = parser.parse_args()
    try:
        if sys.platform != "darwin":
            raise RuntimeError("Apple fixtures require macOS and Xcode Command Line Tools")
        if not shutil.which("xcrun"):
            raise RuntimeError("xcrun is missing; Xcode Command Line Tools are required")
        if os.geteuid() == 0:
            raise RuntimeError("run as a non-root user; file_monitor requires real permission failures")
        value = args.work or os.environ.get("HERMES_SCRATCH") or os.environ.get("TMPDIR")
        if not value:
            raise ValueError("set --work, HERMES_SCRATCH, or TMPDIR to an explicit scratch base")
        base = safe_work_base(value)
        base.mkdir(parents=True, exist_ok=True)
        run_root = Path(tempfile.mkdtemp(prefix="pomo-apple-fixtures-", dir=str(base))).resolve()
        if not inside(run_root, base) or run_root == base:
            raise RuntimeError("unique work root escaped the selected scratch base")
        print(f"WORK {run_root}", flush=True)
        names = list(dict.fromkeys(args.only)) if args.only else sorted(
            path.stem for path in CASES_DIR.glob("*.swift") if path.stem not in EXCLUDED_CASES
        )
        if not names:
            raise RuntimeError("no runnable cases discovered")
        results = []
        for name in names:
            outcome = run_case(name, run_root, args)
            results.append(outcome)
            details = " ".join(f"{key}={outcome[key]}" for key in ("assertions", "returncode", "stage", "log", "error") if key in outcome)
            print(f"CASE {name} {outcome['status']} {details}", flush=True)
            # Persist every completed case, even if a later case is interrupted.
            (run_root / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        passed = sum(result["status"] == "PASS" for result in results)
        failed = len(results) - passed
        print(f"SUMMARY cases={len(results)} passed={passed} failed={failed} assertions={sum(result['assertions'] for result in results)} errors=0", flush=True)
        return 1 if failed else 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"ERROR {error}", file=sys.stderr, flush=True)
        print("SUMMARY cases=0 passed=0 failed=0 assertions=0 errors=1", flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
