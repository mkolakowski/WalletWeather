#!/usr/bin/env python3
"""Resource gate for the orchestrate skill: how much may run at once on this machine.

Every session on the machine shares one state folder (ORCHESTRATE_DIR, default
/tmp/claude-orchestrate), so the limits hold across projects and threads:

  status [--json]                     readings, what's running, what may start now
  claim worker|session --label L --owner O [--hours H] [--force]
                                      take a slot for a subagent or a child session
                                      (exit 75 with the reason when the machine is full)
  release <slot-id>... | --owner O    give slots back (--owner: all of one orchestrator's)
  heavy [--label L] [--wait S] -- <command…>
                                      run a build/test/simulator job under the
                                      machine-wide heavy lock; waits its turn
  list                                slots and the heavy lock, one per line

Limits come from the project's .claude/orchestrate.json (keys: see DEFAULTS),
read from the git root of the current folder. Standard library only (Python 3.9).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

DEFAULTS = {
    "max_workers": 3,          # subagents + child sessions running at once, machine-wide
    "max_sessions": 2,         # of those, child sessions (each is a whole Claude process)
    "max_heavy": 1,            # builds/tests/simulator jobs at once (heavy lock)
    "min_memory_free_pct": 25, # below: one more worker at most; below half of it: none
    "min_free_disk_gb": 8,     # below: no heavy jobs
    "load_per_core": 1.5,      # 1-minute load above cores x this counts as busy
    "slot_hours": 3,           # a slot nobody released expires after this
    "stale_heavy_hours": 2,    # a heavy job held longer than this is flagged as possibly stuck
    "extra_locks": [],         # other lock folders (with a pid file) that mean a heavy job is running
}

STATE = os.environ.get("ORCHESTRATE_DIR", "/tmp/claude-orchestrate")
SLOTS = os.path.join(STATE, "slots")
HEAVY = os.path.join(STATE, "heavy")


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def project_root():
    root = sh("git", "rev-parse", "--show-toplevel").strip()
    return root or os.getcwd()


def config():
    cfg = dict(DEFAULTS)
    path = os.path.join(project_root(), ".claude", "orchestrate.json")
    if os.path.exists(path):
        with open(path) as f:
            cfg.update({k: v for k, v in json.load(f).items() if not k.startswith("_")})
    return cfg


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


# ---- readings -------------------------------------------------------------

def memory():
    """(free percent, pressure level 1 normal / 2 warn / 4 critical, swap used MB)."""
    if sys.platform == "darwin":
        m = re.search(r"free percentage:\s*(\d+)", sh("memory_pressure", "-Q"))
        free = int(m.group(1)) if m else None
        lvl = sh("sysctl", "-n", "kern.memorystatus_vm_pressure_level").strip()
        level = int(lvl) if lvl.isdigit() else 1
        s = re.search(r"used = ([\d.]+)M", sh("sysctl", "-n", "vm.swapusage"))
        swap = float(s.group(1)) if s else 0.0
        return free, level, swap
    info = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                info[k] = int(v.split()[0])
    except OSError:
        return None, 1, 0.0
    free = round(100 * info.get("MemAvailable", 0) / max(info.get("MemTotal", 1), 1))
    swap = (info.get("SwapTotal", 0) - info.get("SwapFree", 0)) / 1024
    return free, (4 if free < 10 else 2 if free < 20 else 1), swap


def held_locks(cfg):
    """Heavy jobs running now: our own heavy lock plus the project's extra locks."""
    out = []
    for path in [HEAVY] + list(cfg["extra_locks"]):
        pid_file = os.path.join(path, "pid")
        if os.path.isdir(path):
            pid = open(pid_file).read().strip() if os.path.exists(pid_file) else ""
            if pid and not alive(pid):
                continue  # stale; its owner takes it over
            cmd_file = os.path.join(path, "command")
            cmd = open(cmd_file).read().strip()[:100] if os.path.exists(cmd_file) else ""
            since = os.stat(pid_file if os.path.exists(pid_file) else path).st_mtime
            age = (time.time() - since) / 3600
            out.append({"lock": path, "pid": pid, "command": cmd, "age_h": round(age, 1),
                        "stuck": age > cfg["stale_heavy_hours"]})
    return out


def slots():
    out, now = [], time.time()
    os.makedirs(SLOTS, exist_ok=True)
    for name in os.listdir(SLOTS):
        path = os.path.join(SLOTS, name)
        try:
            with open(path) as f:
                s = json.load(f)
        except (OSError, ValueError):
            continue
        if s.get("expires", 0) < now:
            os.remove(path)  # nobody released it in time
            continue
        out.append(s)
    return sorted(out, key=lambda s: s["started"])


def verdict(cfg):
    free, level, swap = memory()
    load1 = os.getloadavg()[0]
    cores = os.cpu_count() or 1
    disk_gb = shutil.disk_usage(project_root()).free / 1e9
    running = slots()
    sessions = sum(1 for s in running if s["kind"] == "session")
    heavy = held_locks(cfg)
    reasons = []

    room = cfg["max_workers"] - len(running)
    session_room = min(room, cfg["max_sessions"] - sessions)
    state = "green"
    lo = cfg["min_memory_free_pct"]
    if level >= 4 or (free is not None and free < lo / 2):
        state = "red"
        reasons.append("memory is critical (%s%% free, pressure %d)" % (free, level))
    elif level >= 2 or (free is not None and free < lo):
        state = "amber"
        reasons.append("memory is tight (%s%% free, pressure %d)" % (free, level))
    if load1 > cores * cfg["load_per_core"]:
        state = "red" if state == "red" else "amber"
        reasons.append("CPU is busy (load %.1f on %d cores)" % (load1, cores))
    if state == "red":
        room = session_room = 0
    elif state == "amber":
        room, session_room = min(room, 1), 0
    if room <= 0 and len(running) >= cfg["max_workers"]:
        reasons.append("%d of %d worker slots in use" % (len(running), cfg["max_workers"]))

    heavy_ok = len(heavy) < cfg["max_heavy"] and state != "red" and disk_gb >= cfg["min_free_disk_gb"]
    if disk_gb < cfg["min_free_disk_gb"]:
        reasons.append("disk is low (%.1f GB free, need %d)" % (disk_gb, cfg["min_free_disk_gb"]))
    for h in heavy:
        if h["stuck"]:
            reasons.append("a heavy job may be stuck: held %.1f h by pid %s (%s); it belongs to another"
                           " session or job, so ask the user before stopping it"
                           % (h["age_h"], h["pid"] or "?", h["command"][:60]))
        else:
            reasons.append("a heavy job is running (%s)" % h["command"][:60])

    return {
        "state": state,
        "memory_free_pct": free, "pressure_level": level, "swap_used_mb": round(swap),
        "load_1m": round(load1, 2), "cores": cores, "disk_free_gb": round(disk_gb, 1),
        "slots": running, "heavy_jobs": heavy,
        "can_start_workers": max(room, 0), "can_start_session": session_room > 0,
        "can_start_heavy": heavy_ok, "reasons": reasons,
        "limits": {k: cfg[k] for k in ("max_workers", "max_sessions", "max_heavy")},
    }


# ---- commands -------------------------------------------------------------

def cmd_status(args, cfg):
    v = verdict(cfg)
    if args.json:
        print(json.dumps(v, indent=1))
        return 0
    print("machine: %s - memory %s%% free (pressure %d), swap %d MB, load %.1f/%d cores, disk %.1f GB free"
          % (v["state"], v["memory_free_pct"], v["pressure_level"], v["swap_used_mb"],
             v["load_1m"], v["cores"], v["disk_free_gb"]))
    print("running: %d of %d workers (%d sessions), %d heavy job(s)"
          % (len(v["slots"]), cfg["max_workers"],
             sum(1 for s in v["slots"] if s["kind"] == "session"), len(v["heavy_jobs"])))
    for s in v["slots"]:
        print("  %s %-7s %s (owner %s, %d min)" % (s["id"], s["kind"], s["label"], s["owner"],
                                                   (time.time() - s["started"]) / 60))
    for h in v["heavy_jobs"]:
        print("  heavy   pid %s, %.1f h%s: %s" % (h["pid"] or "?", h["age_h"],
                                            ", POSSIBLY STUCK" if h["stuck"] else "", h["command"]))
    print("may start now: %d worker(s), session %s, heavy %s"
          % (v["can_start_workers"], "yes" if v["can_start_session"] else "no",
             "yes" if v["can_start_heavy"] else "no"))
    for r in v["reasons"]:
        print("  because " + r)
    return 0


def cmd_claim(args, cfg):
    v = verdict(cfg)
    ok = v["can_start_session"] if args.kind == "session" else v["can_start_workers"] > 0
    if not ok and not args.force:
        print("full: " + ("; ".join(v["reasons"]) or "no room"), file=sys.stderr)
        return 75
    sid = uuid.uuid4().hex[:8]
    now = time.time()
    slot = {"id": sid, "kind": args.kind, "label": args.label, "owner": args.owner,
            "project": os.path.basename(project_root()), "started": now,
            "expires": now + 3600 * (args.hours or cfg["slot_hours"])}
    with open(os.path.join(SLOTS, sid + ".json"), "w") as f:
        json.dump(slot, f)
    print(sid)
    return 0


def cmd_release(args, cfg):
    gone = 0
    for s in slots():
        if s["id"] in args.ids or (args.owner and s["owner"] == args.owner):
            os.remove(os.path.join(SLOTS, s["id"] + ".json"))
            gone += 1
    print("released %d slot(s)" % gone)
    return 0


def cmd_heavy(args, cfg):
    if not args.command:
        print("usage: orchestrate.py heavy [--label L] -- <command…>", file=sys.stderr)
        return 64
    waited, said = 0, -60
    while True:
        v = verdict(cfg)
        others = [h for h in v["heavy_jobs"] if h["lock"] != HEAVY]
        if v["can_start_heavy"] and not others:
            try:
                os.mkdir(HEAVY)
                break
            except FileExistsError:
                pid = open(os.path.join(HEAVY, "pid")).read().strip() if os.path.exists(os.path.join(HEAVY, "pid")) else ""
                if pid and not alive(pid):
                    shutil.rmtree(HEAVY, ignore_errors=True)  # stale: its holder died
                    continue
        if waited >= args.wait:
            print("orchestrate: gave up after %ds: %s" % (waited, "; ".join(v["reasons"])), file=sys.stderr)
            return 75
        if waited - said >= 60:
            print("orchestrate: waiting - %s" % ("; ".join(v["reasons"]) or "heavy lock taken"), file=sys.stderr)
            said = waited
        time.sleep(5)
        waited += 5
    try:
        with open(os.path.join(HEAVY, "pid"), "w") as f:
            f.write(str(os.getpid()))
        with open(os.path.join(HEAVY, "command"), "w") as f:
            f.write("%s: %s" % (args.label or os.path.basename(project_root()), " ".join(args.command)))
        return subprocess.call(args.command)
    except KeyboardInterrupt:
        return 130
    finally:
        shutil.rmtree(HEAVY, ignore_errors=True)


def cmd_list(args, cfg):
    for s in slots():
        print("%s\t%s\t%s\t%s" % (s["id"], s["kind"], s["owner"], s["label"]))
    for h in held_locks(cfg):
        print("heavy\t%s\t%.1fh%s\t%s" % (h["pid"], h["age_h"], " stuck" if h["stuck"] else "", h["command"]))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("status"); s.add_argument("--json", action="store_true")
    c = sub.add_parser("claim")
    c.add_argument("kind", choices=["worker", "session"])
    c.add_argument("--label", required=True); c.add_argument("--owner", required=True)
    c.add_argument("--hours", type=float); c.add_argument("--force", action="store_true")
    r = sub.add_parser("release"); r.add_argument("ids", nargs="*"); r.add_argument("--owner")
    h = sub.add_parser("heavy"); h.add_argument("--label"); h.add_argument("--wait", type=int, default=3600)
    h.add_argument("command", nargs=argparse.REMAINDER)
    sub.add_parser("list")
    args = p.parse_args()
    if getattr(args, "command", None) and args.command[:1] == ["--"]:
        args.command = args.command[1:]
    os.makedirs(SLOTS, exist_ok=True)
    cfg = config()
    return {"status": cmd_status, "claim": cmd_claim, "release": cmd_release,
            "heavy": cmd_heavy, "list": cmd_list}[args.cmd](args, cfg)


if __name__ == "__main__":
    sys.exit(main())
