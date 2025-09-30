#!/usr/bin/env python3
"""
Minimal HPC reservation calculator (single job class).

Provide exactly TWO of: --Q (jobs), --R (nodes), --H (hours)
along with the job shape: --N (nodes per job), --S (hours per job).

Formulas:
  NH = N * S
  Q = floor( (R * H) / NH )          # jobs from nodes & time
  R = ceil( (Q * NH) / H )           # nodes for jobs & time
  H = (Q * NH) / R                   # hours for jobs & nodes
Optional safety buffer: --b 0.15  -> NH *= 1.15
"""

from math import floor, ceil
import argparse

def main():
    ap = argparse.ArgumentParser(description="Minimal jobs/nodes/time calculator (single class)")
    ap.add_argument("--N", type=float, required=True, help="nodes per job")
    ap.add_argument("--S", type=float, required=True, help="hours per job")
    ap.add_argument("--b", type=float, default=0.0, help="buffer fraction (e.g., 0.15 for +15%)")
    ap.add_argument("--Q", type=float, help="jobs")
    ap.add_argument("--R", type=float, help="nodes")
    ap.add_argument("--H", type=float, help="hours")
    # tiny Slurm helper (optional)
    ap.add_argument("--start", default="", help="ISO8601 start (e.g., 2025-09-30T09:00:00)")
    ap.add_argument("--partition", default="reserved")
    ap.add_argument("--users", default="")
    ap.add_argument("--accounts", default="")
    args = ap.parse_args()

    NH = args.N * args.S
    NH_eff = NH * (1 + args.b)

    known = [k for k, v in {"Q": args.Q, "R": args.R, "H": args.H}.items() if v is not None]
    if len(known) != 2:
        raise SystemExit("Provide exactly TWO of --Q --R --H.")

    Q, R, H = args.Q, args.R, args.H

    if Q is None:
        Q = floor((R * H) / NH_eff)
        print(f"Jobs Q ≈ {int(Q)}  (NH_eff={NH_eff:.3f} node-hours/job)")
    elif R is None:
        R = ceil((Q * NH_eff) / H)
        print(f"Nodes R ≈ {int(R)}  (NH_eff={NH_eff:.3f} node-hours/job)")
    else:
        H = (Q * NH_eff) / R
        print(f"Hours H ≈ {H:.2f}  (NH_eff={NH_eff:.3f} node-hours/job)")

    # Optional: print scontrol (only if R and H known)
    if R is not None and H is not None:
        hh = int(H); mm = int(round((H - hh) * 60)); ss = 0
        duration = f"{hh:02d}:{mm:02d}:{ss:02d}"
        parts = [
            "scontrol create reservation",
            f"StartTime={args.start}" if args.start else None,
            f"Duration={duration}",
            f"PartitionName={args.partition}",
            f"TRES=Nodes={int(R)}",
            f"Users={args.users}" if args.users else None,
            f"Accounts={args.accounts}" if args.accounts else None,
        ]
        cmd = " \\\n  ".join(p for p in parts if p)
        print("\n# scontrol (optional):")
        print(cmd)

if __name__ == "__main__":
    main()
