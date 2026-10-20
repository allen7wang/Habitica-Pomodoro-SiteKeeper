#!/usr/bin/env python3
"""Offline fixture harness for HabiticaPomodoroAndroid.

Compiles the real production sources (data/Models.kt, data/BlockModels.kt,
data/TopThreeCloudSync.kt, data/LocalStore.kt, engine/PomodoroViewModel.kt)
against stub plumbing (android/androidx/services/HabiticaAPI substitutes, see
stubs/) with kotlin-compiler-embeddable, then compiles and runs every case in
cases/ one by one, printing `CASE <name> EXIT=<code>` per case.

No network at run time: the HabiticaAPI stub is a pure in-memory substitute
(HTTP 0 by construction). The toolchain jars are resolved from, in order:
  1. --toolchain DIR  (or env POMO_FIXTURES_TOOLCHAIN)
  2. fixtures/.toolchain/   (gitignored repo-local cache)
  3. the local Gradle cache (~/.gradle/caches/modules-2/files-2.1)
  4. the local Maven repo  (~/.m2/repository)
  5. download from Maven Central into fixtures/.toolchain/ (pinned versions)

Build/log output goes to --work DIR (or env POMO_FIXTURES_WORK, or
$TMPDIR/pomo-fixtures-work, or fixtures/.work). JVM tmpdir is pinned
explicitly (-Djava.io.tmpdir) under the work dir; nothing is written to /tmp.

Usage:
  python3 run.py                # full suite
  python3 run.py --only d1_03,d1_04
  python3 run.py --list
  python3 run.py --fresh        # wipe work dir first

Exit code: 0 when every case exits 0, else 1 (2 for toolchain/compile-plumbing
failures). A case that fails to compile counts as EXIT=1 (that is the RED
signal for TDD cases referencing not-yet-existing production API).
"""

import argparse
import glob
import hashlib
import os
import shutil
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)  # HabiticaPomodoroAndroid/
SRC = os.path.join(MODULE, "app", "src", "main", "java", "com", "habitica", "pomodoro")

# Pinned toolchain. Do not float versions: production compiles with Kotlin 2.0.21.
KOTLIN_VERSION = "2.0.21"
JARS = [
    # (name, group_path, artifact, version, required)
    ("kotlin-compiler-embeddable", "org/jetbrains/kotlin", "kotlin-compiler-embeddable", KOTLIN_VERSION, True),
    ("kotlin-stdlib", "org/jetbrains/kotlin", "kotlin-stdlib", KOTLIN_VERSION, True),
    ("kotlinx-coroutines-core-jvm", "org/jetbrains/kotlinx", "kotlinx-coroutines-core-jvm", "1.7.3", True),
    ("json", "org/json", "json", "20240303", True),
    ("annotations", "org/jetbrains", "annotations", "23.0.0", False),
    # Runtime dependencies of kotlin-compiler-embeddable itself (launch classpath).
    ("kotlin-script-runtime", "org/jetbrains/kotlin", "kotlin-script-runtime", KOTLIN_VERSION, True),
    ("kotlin-daemon-embeddable", "org/jetbrains/kotlin", "kotlin-daemon-embeddable", KOTLIN_VERSION, True),
    ("trove4j", "org/jetbrains/intellij/deps", "trove4j", "1.0.20200330", True),
]
MAVEN_CENTRAL = "https://repo1.maven.org/maven2"

# Production sources under test (real files, never modified by the harness).
PROD_SOURCES = [
    os.path.join(SRC, "data", "Models.kt"),
    os.path.join(SRC, "data", "BlockModels.kt"),
    os.path.join(SRC, "data", "TopThreeCloudSync.kt"),
    os.path.join(SRC, "data", "LocalStore.kt"),
    os.path.join(SRC, "engine", "PomodoroViewModel.kt"),
]
# Substituted plumbing: these production files are deliberately NOT compiled.
SUBSTITUTED = ["data/HabiticaAPI.kt (stub: HTTP 0)", "service/PomodoroTimerService.kt (stub)",
               "service/BlockReminderReceiver.kt (stub)", "ui/* (compose, verified separately)"]


def find_java():
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        cand = os.path.join(java_home, "bin", "java")
        if os.path.exists(cand):
            return cand
    found = shutil.which("java")
    if found:
        return found
    sys.exit("ERROR: no java found (set JAVA_HOME)")


def gradle_cache_glob(group_path, artifact, version, filename):
    base = os.path.expanduser("~/.gradle/caches/modules-2/files-2.1")
    # Gradle stores groups as dotted directory names: org.jetbrains.kotlin/
    pattern = os.path.join(base, group_path.replace("/", "."), artifact, version, "*", filename)
    hits = sorted(glob.glob(pattern))
    return hits[0] if hits else None


def m2_glob(group_path, artifact, version, filename):
    cand = os.path.expanduser(os.path.join("~/.m2/repository", group_path, artifact, version, filename))
    return cand if os.path.exists(cand) else None


def resolve_jars(toolchain_dirs, allow_download):
    resolved = {}
    for name, group_path, artifact, version, required in JARS:
        filename = "%s-%s.jar" % (artifact, version)
        for d in toolchain_dirs:
            cand = os.path.join(d, filename)
            if os.path.exists(cand):
                resolved[name] = cand
                break
        if name not in resolved:
            hit = gradle_cache_glob(group_path, artifact, version, filename) or m2_glob(group_path, artifact, version, filename)
            if hit:
                resolved[name] = hit
        if name not in resolved and allow_download:
            url = "%s/%s/%s/%s/%s" % (MAVEN_CENTRAL, group_path, artifact, version, filename)
            dest_dir = toolchain_dirs[0]
            os.makedirs(dest_dir, exist_ok=True)
            dest = os.path.join(dest_dir, filename)
            print("toolchain: downloading %s" % url)
            try:
                urllib.request.urlretrieve(url, dest)
                resolved[name] = dest
            except Exception as e:  # noqa: BLE001
                if required:
                    sys.exit("ERROR: cannot obtain %s (%s) and it is required" % (filename, e))
        if name not in resolved and required:
            sys.exit("ERROR: required jar %s not found (searched: %s, gradle cache, ~/.m2). "
                     "Re-run with network to auto-download." % (filename, ", ".join(toolchain_dirs)))
    return resolved


def kotlinc(java, compiler_cp, cp_entries, out_dir, sources, log):
    os.makedirs(out_dir, exist_ok=True)
    cmd = [java, "-Djava.io.tmpdir=" + os.path.join(out_dir, "..", "tmp"),
           "-cp", compiler_cp, "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
           "-no-stdlib", "-no-reflect", "-nowarn", "-jvm-target", "17",
           "-cp", os.pathsep.join(cp_entries), "-d", out_dir] + sources
    proc = subprocess.run(cmd, capture_output=True, text=True)
    with open(log, "w") as f:
        f.write("CMD: %s\n\n" % " ".join(cmd))
        f.write("== stdout ==\n%s\n== stderr ==\n%s\n== exit %d ==\n" % (proc.stdout, proc.stderr, proc.returncode))
    return proc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated case names")
    ap.add_argument("--work", help="work/log directory")
    ap.add_argument("--toolchain", help="directory holding pinned jars")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--no-download", action="store_true")
    args = ap.parse_args()

    case_files = sorted(f for f in glob.glob(os.path.join(HERE, "cases", "*.kt"))
                        if os.path.basename(f) != "Support.kt")
    cases = [os.path.basename(f)[:-3] for f in case_files]
    if args.list:
        print("\n".join(cases))
        return 0

    work = args.work or os.environ.get("POMO_FIXTURES_WORK") or \
        os.path.join(os.environ.get("TMPDIR", HERE), "pomo-fixtures-work")
    work = os.path.abspath(work)
    if args.fresh and os.path.exists(work):
        shutil.rmtree(work)
    for sub in ("prod", "support", "cases", "logs", "tmp"):
        os.makedirs(os.path.join(work, sub), exist_ok=True)

    toolchain_dirs = [d for d in [args.toolchain, os.environ.get("POMO_FIXTURES_TOOLCHAIN"),
                                  os.path.join(HERE, ".toolchain")] if d]
    jars = resolve_jars(toolchain_dirs, allow_download=not args.no_download)
    java = find_java()
    # kotlin-compiler-embeddable is not self-sufficient: launch it with the
    # same stdlib/coroutines/annotations jars the compiled code uses.
    compiler_cp = os.pathsep.join([jars["kotlin-compiler-embeddable"], jars["kotlin-stdlib"],
                                   jars["kotlinx-coroutines-core-jvm"], jars["kotlin-script-runtime"],
                                   jars["kotlin-daemon-embeddable"], jars["trove4j"]] +
                                  ([jars["annotations"]] if "annotations" in jars else []))
    compile_cp = [jars["kotlin-stdlib"], jars["kotlinx-coroutines-core-jvm"], jars["json"]]
    if "annotations" in jars:
        compile_cp.append(jars["annotations"])

    for p in PROD_SOURCES:
        if not os.path.exists(p):
            sys.exit("ERROR: missing production source %s" % p)
    stubs = sorted(glob.glob(os.path.join(HERE, "stubs", "*.kt")))
    support = os.path.join(HERE, "cases", "Support.kt")
    if not os.path.exists(support):
        sys.exit("ERROR: missing cases/Support.kt")

    # 1. production + stubs
    prod_out = os.path.join(work, "prod")
    print("compiling production sources + stubs (kotlin %s) ..." % KOTLIN_VERSION)
    proc = kotlinc(java, compiler_cp, compile_cp, prod_out,
                   PROD_SOURCES + stubs, os.path.join(work, "logs", "prod-compile.log"))
    if proc.returncode != 0:
        print("PRODUCTION COMPILE FAILED (see %s)" % os.path.join(work, "logs", "prod-compile.log"))
        print(proc.stderr[-4000:])
        return 2

    # 2. shared case support
    support_out = os.path.join(work, "support")
    proc = kotlinc(java, compiler_cp, compile_cp + [prod_out], support_out,
                   [support], os.path.join(work, "logs", "support-compile.log"))
    if proc.returncode != 0:
        print("SUPPORT COMPILE FAILED (see %s)" % os.path.join(work, "logs", "support-compile.log"))
        print(proc.stderr[-4000:])
        return 2

    run_cp_base = [prod_out, support_out, jars["kotlin-stdlib"],
                   jars["kotlinx-coroutines-core-jvm"], jars["json"]]
    if "annotations" in jars:
        run_cp_base.append(jars["annotations"])

    only = set(args.only.split(",")) if args.only else None
    selected = [(n, f) for n, f in zip(cases, case_files) if only is None or n in only]
    if only:
        missing = only - {n for n, _ in selected}
        if missing:
            print("WARNING: unknown case(s): %s" % ", ".join(sorted(missing)))

    results = []
    for name, path in selected:
        log = os.path.join(work, "logs", name + ".log")
        out = os.path.join(work, "cases", name)
        shutil.rmtree(out, ignore_errors=True)
        proc = kotlinc(java, compiler_cp, compile_cp + [prod_out, support_out],
                       out, [path], log)
        if proc.returncode != 0:
            # Compile failure is a legitimate RED for cases targeting new API.
            results.append((name, 1))
            print("CASE %s EXIT=1  (compile failure — see %s)" % (name, log))
            continue
        runcmd = [java, "-Djava.io.tmpdir=" + os.path.join(work, "tmp"),
                  "-cp", os.pathsep.join(run_cp_base + [out]), name[0].upper() + name[1:] + "Kt"]
        with open(log, "a") as lf:
            lf.write("\n== run ==\nCMD: %s\n" % " ".join(runcmd))
        run = subprocess.run(runcmd, capture_output=True, text=True,
                             env={**os.environ, "TMPDIR": os.path.join(work, "tmp")})
        with open(log, "a") as lf:
            lf.write("== run stdout ==\n%s\n== run stderr ==\n%s\n== run exit %d ==\n"
                     % (run.stdout, run.stderr, run.returncode))
        results.append((name, run.returncode))
        line = "CASE %s EXIT=%d" % (name, run.returncode)
        print(line)
        if run.returncode != 0:
            tail = (run.stdout + run.stderr).strip().splitlines()
            for t in tail[-12:]:
                print("    | " + t)

    passed = sum(1 for _, rc in results if rc == 0)
    print("SUITE %d/%d PASS" % (passed, len(results)))
    if passed != len(results):
        print("FAILED: %s" % ", ".join(n for n, rc in results if rc != 0))
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
