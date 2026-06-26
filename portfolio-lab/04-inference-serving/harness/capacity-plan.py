#!/usr/bin/env python3
"""capacity-plan - turn one sweep's numbers into a provisioning decision.

This is the ops exercise the SLO metrics exist FOR: given a demand target and a
single replica's measured capacity (its best row that still met your goodput SLO),
how many replicas do you run, and what does a token cost?

Two ideas:
  - Little's Law:   N = lambda * W
    requests-in-flight = arrival_rate (req/s) * mean_latency (s). This is the
    concurrency the system must sustain - compare it to one replica's budget.
  - Replica count:  ceil(target_tokens_per_s / per_replica_tokens_per_s)
    then $/1M tokens from the rented price.

Plug in numbers you MEASURED on a real-GPU server (Lesson 6). Defaults below are
illustrative so the script runs and shows the shape of the calculation.
"""
import argparse
import math


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target-tokens-per-s", type=float, default=2000.0,
                    help="demand you must serve (aggregate output tokens/sec)")
    ap.add_argument("--replica-tokens-per-s", type=float, default=550.0,
                    help="ONE replica's tok/s at its best SLO-passing concurrency (from your sweep)")
    ap.add_argument("--replica-concurrency", type=int, default=8,
                    help="that replica's concurrency at that row")
    ap.add_argument("--arrival-rate", type=float, default=20.0,
                    help="request arrival rate lambda (req/s)")
    ap.add_argument("--mean-latency-s", type=float, default=1.5,
                    help="mean end-to-end latency W (s) at that operating point")
    ap.add_argument("--price-per-hour", type=float, default=1.20,
                    help="rented GPU price per replica-hour ($)")
    args = ap.parse_args()

    # Little's Law: how many requests are in the system at once.
    in_flight = args.arrival_rate * args.mean_latency_s

    # Replica count to cover the token demand.
    replicas = math.ceil(args.target_tokens_per_s / args.replica_tokens_per_s)
    served = replicas * args.replica_tokens_per_s
    headroom = 100.0 * (served - args.target_tokens_per_s) / args.target_tokens_per_s

    # Cost per 1M output tokens at the served rate.
    tokens_per_hour = served * 3600.0
    cost_per_1m = (replicas * args.price_per_hour) / (tokens_per_hour / 1e6)

    print("Little's Law (concurrency the fleet must hold):")
    print(f"  N = lambda * W = {args.arrival_rate:.1f} req/s * {args.mean_latency_s:.2f}s "
          f"= {in_flight:.1f} requests in flight")
    print(f"  one replica budgets ~{args.replica_concurrency} concurrent -> "
          f"need >= {math.ceil(in_flight / max(args.replica_concurrency,1))} replicas for concurrency alone")
    print()
    print("Throughput sizing:")
    print(f"  ceil({args.target_tokens_per_s:.0f} / {args.replica_tokens_per_s:.0f}) "
          f"= {replicas} replicas  (serves {served:.0f} tok/s, {headroom:.0f}% headroom)")
    print()
    print("Cost:")
    print(f"  ${cost_per_1m:.3f} per 1M output tokens "
          f"({replicas} x ${args.price_per_hour:.2f}/h at {served:.0f} tok/s)")
    print()
    print("Provision for the LARGER of the two replica counts (throughput vs concurrency).")
    print("Re-run with YOUR measured replica-tokens-per-s and latency from a GPU sweep.")


if __name__ == "__main__":
    main()
