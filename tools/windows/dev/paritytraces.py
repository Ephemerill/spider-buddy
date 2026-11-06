#!/usr/bin/env python3
"""Run every captured Mac trace scenario with Trace.exe on the laptop and diff each against the Mac.

    paritytraces.py <mac-traces-dir> [work-dir]

Names follow tools/capture-all.sh: <scenario>.s<seed>.<scale>.jsonl, activity-<name>.s<seed>.<scale>.jsonl.
Prints a table and writes parity-traces.md into the work dir.
"""
import glob, os, re, subprocess, sys, tempfile
mac = sys.argv[1]
work = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp()
os.makedirs(work, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
SCREEN = os.environ.get('SPIDER_SHIM_SCREEN', '0,0,1512,982,0,0,1512,949,2,32')
jobs = []
for f in sorted(glob.glob(os.path.join(mac, '*.jsonl'))):
    b = os.path.basename(f)
    if 'Onone' in b: continue
    m = re.match(r'(.+)\.s(\d+)(?:\.([0-9.]+))?\.jsonl$', b)
    if not m: continue
    name, seed, scale = m.group(1), m.group(2), m.group(3) or '0.95'
    env = {'LC_SEED': seed, 'TR_SCALE': scale}
    sc = name
    if name.startswith('activity-'):
        env['TR_ACT'] = name[9:]; sc = 'activity'
    jobs.append((b, sc, env))
ps = ["Set-Location C:\\Users\\User\\Documents\\Projects\\spider-buddy",
      "$env:PATH = \"$env:LOCALAPPDATA\\Programs\\Swift\\Runtimes\\6.4.2\\usr\\bin;$env:PATH\"",
      "$env:SWIFT_DETERMINISTIC_HASHING='1'", f"$env:SPIDER_SHIM_SCREEN='{SCREEN}'",
      "$ErrorActionPreference='Continue'",
      "Remove-Item -Recurse -Force out\\swift\\t -ErrorAction SilentlyContinue",
      "New-Item -ItemType Directory -Force out\\swift\\t | Out-Null",
      "$sw=[Diagnostics.Stopwatch]::StartNew()"]
for b, sc, env in jobs:
    ps += [f"$env:{k}='{v}'" for k, v in env.items()]
    ps.append(f"& build\\swift\\Trace.exe tests\\golden\\scenarios\\{sc}.json out\\swift\\t\\{b} 2>&1 | Out-Null")
    ps.append(f"if ($LASTEXITCODE -ne 0) {{ 'CRASH {b} ' + $LASTEXITCODE }}")
    if 'TR_ACT' in env: ps.append("Remove-Item env:TR_ACT")
ps.append("'ran in ' + [int]$sw.Elapsed.TotalSeconds + ' s'")
ps.append("Set-Location out\\swift\\t; tar -czf ..\\t.tgz *.jsonl")
script = os.path.join(work, 'run.ps1')
open(script, 'w').write('\n'.join(ps))
print(subprocess.run([os.path.join(here, 'lap'), 'ps', script], capture_output=True, text=True).stdout.strip())
subprocess.check_call(['scp', '-q', '-o', 'LogLevel=ERROR', 'laptop:C:/Users/User/Documents/Projects/spider-buddy/out/swift/t.tgz', os.path.join(work, 't.tgz')])
wd = os.path.join(work, 'win'); os.makedirs(wd, exist_ok=True)
subprocess.check_call(['tar', '-xzf', os.path.join(work, 't.tgz'), '-C', wd])
rows, npass = [], 0
for b, sc, env in jobs:
    w = os.path.join(wd, b)
    if not os.path.exists(w):
        rows.append((b, 'NO OUTPUT', '')); continue
    r = subprocess.run([sys.executable, os.path.join(here, 'difftrace.py'), os.path.join(mac, b), w, '--quiet'], capture_output=True, text=True)
    line = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr.strip()[-200:]
    ok = r.returncode == 0
    npass += ok
    rows.append((b, 'PASS' if ok else 'FAIL', line))
print(f"{npass}/{len(jobs)} scenarios pass")
with open(os.path.join(work, 'parity-traces.md'), 'w') as f:
    f.write(f"# Trace parity: {npass}/{len(jobs)} pass\n\n| Scenario | Result | Detail |\n|---|---|---|\n")
    for b, s, l in rows:
        f.write(f"| {b[:-6]} | {s} | {l} |\n")
for b, s, l in rows:
    if s != 'PASS': print(f"  {b[:-6]:44} {l}")
ws = [float(re.search(r'worstPos=([0-9.e+-]+)', l).group(1)) for b, s, l in rows if 'worstPos' in l and s == 'PASS']
if ws: print(f"worst position error over all passing scenarios: {max(ws):.3g}")
