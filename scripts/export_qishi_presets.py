#!/usr/bin/env python3
"""从本机 qishi-meditation 仓库导出场景预设快照 → pomo 共享资源 qishi_presets.json。

用法: python3 scripts/export_qishi_presets.py [qishi_repo_path]
输出: HabiticaPomodoro/audio/qishi_presets.json（三端随包分发）

规则:
- presets 数组直接从 src/data.ts 提取（纯 JSON 对象格式）
- 声音文件名 = <soundId>.mp3（data.ts file 字段为 /audio/<id>.mp3，已验证）
- 校验每个 track 的 mp3 在 public/audio/ 实际存在，缺失则报错退出
- 公开站流式 URL 基址: https://allen7wang.github.io/qishi-meditation-web/audio/<file>
"""
import json
import re
import sys
import pathlib

QISHI = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.home() / "GitHub/qishi-meditation")
POMO = pathlib.Path(__file__).resolve().parent.parent
OUT = POMO / "HabiticaPomodoro/HabiticaPomodoro/audio/qishi_presets.json"

src = (QISHI / "src/data.ts").read_text()
m = re.search(r"export const presets[^=]*=\s*(\[.*?\n\])", src, re.S)
if not m:
    sys.exit("presets array not found in data.ts")
# presets 混用 JSON 与 TS 对象字面量两种写法，用 node 求值（本地可信源码）
import subprocess
js = "console.log(JSON.stringify(%s))" % m.group(1)
r = subprocess.run(["node", "-e", js], capture_output=True, text=True, cwd=QISHI)
if r.returncode != 0:
    sys.exit("node eval failed: " + r.stderr[:400])
presets = json.loads(r.stdout)

audio_dir = QISHI / "public/audio"
missing = []
out_presets = []
for p in presets:
    tracks = []
    for sid in p["soundIds"]:
        fname = sid + ".mp3"
        if not (audio_dir / fname).is_file():
            missing.append(f"{p['id']}: {fname}")
        vol = p.get("volumes", {}).get(sid, 50)
        tracks.append({"id": sid, "file": fname, "volume": vol})
    out_presets.append({
        "id": p["id"],
        "name": p["name"],
        "subtitle": p.get("subtitle", ""),
        "tracks": tracks,
    })

if missing:
    sys.exit("missing audio files:\n" + "\n".join(missing))

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({"version": 1, "presets": out_presets}, ensure_ascii=False, indent=1))
total_tracks = sum(len(p["tracks"]) for p in out_presets)
print(f"OK: {len(out_presets)} presets, {total_tracks} tracks -> {OUT}")
