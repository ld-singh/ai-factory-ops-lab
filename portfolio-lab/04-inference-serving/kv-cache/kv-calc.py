#!/usr/bin/env python3
"""kv-calc - size the KV cache, the real capacity limit of an LLM server.

"How many requests fit on one GPU" is a MEMORY question, not a speed one. After the
model weights are loaded, the leftover GPU memory is split among the in-flight
requests as KV cache, and each request holds one slice for every token of its
context. So concurrency is bounded by:

    available_KV_memory  /  (KV bytes per token  x  context length)

This script makes that arithmetic concrete: it prints the KV cost per token and per
request, how many requests fit, how context length trades against concurrency, and
what prefix caching (sharing a common prompt) buys back.

The KV cache size per token, for one sequence, is:

    2  x  num_layers  x  num_kv_heads  x  head_dim  x  bytes_per_element
    ^                                                  ^
    K and V                                            fp16/bf16 = 2, fp8 = 1

Get the three architecture numbers from the model's config.json, not from memory:
    num_layers   = num_hidden_layers
    num_kv_heads = num_key_value_heads   (< num_attention_heads means GQA, which
                                          shrinks the KV cache; that is the point of GQA)
    head_dim     = hidden_size / num_attention_heads   (or head_dim if listed)

Defaults below are ILLUSTRATIVE (a 7B-class GQA model) so the script runs and shows
the SHAPE of the calculation. Confirm real values against the model you serve.
"""
import argparse

GiB = 1024 ** 3
MiB = 1024 ** 2

DTYPE_BYTES = {"fp32": 4.0, "fp16": 2.0, "bf16": 2.0, "fp8": 1.0, "int8": 1.0, "int4": 0.5}


def kv_bytes_per_token(layers, kv_heads, head_dim, elem_bytes):
    # 2 = one slice for K, one for V.
    return 2 * layers * kv_heads * head_dim * elem_bytes


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--layers", type=int, default=28,
                    help="num_hidden_layers (config.json)")
    ap.add_argument("--kv-heads", type=int, default=4,
                    help="num_key_value_heads (config.json); < attention heads = GQA")
    ap.add_argument("--head-dim", type=int, default=128,
                    help="head dimension (hidden_size / num_attention_heads)")
    ap.add_argument("--dtype", choices=DTYPE_BYTES, default="fp16",
                    help="KV cache element type (serving dtype)")
    ap.add_argument("--params-b", type=float, default=7.0,
                    help="model size in BILLIONS of parameters (for the weights estimate)")
    ap.add_argument("--weight-dtype", choices=DTYPE_BYTES, default="fp16",
                    help="dtype the WEIGHTS are loaded in (quantized weights free KV room)")
    ap.add_argument("--gpu-mem-gib", type=float, default=48.0,
                    help="physical GPU memory (e.g. 24, 48, 80)")
    ap.add_argument("--overhead-gib", type=float, default=2.0,
                    help="reserve for activations / fragmentation / CUDA context")
    ap.add_argument("--context", type=int, default=4096,
                    help="context length (prompt + generated) per request")
    ap.add_argument("--prefix-tokens", type=int, default=1024,
                    help="length of a shared prompt prefix (for the prefix-caching estimate)")
    ap.add_argument("--prefix-requests", type=int, default=50,
                    help="how many requests share that prefix")
    args = ap.parse_args()

    elem = DTYPE_BYTES[args.dtype]
    per_tok = kv_bytes_per_token(args.layers, args.kv_heads, args.head_dim, elem)
    per_req = per_tok * args.context

    weights = args.params_b * 1e9 * DTYPE_BYTES[args.weight_dtype]
    gpu = args.gpu_mem_gib * GiB
    overhead = args.overhead_gib * GiB
    avail = gpu - weights - overhead

    print()
    print("KV cache calculator  (ILLUSTRATIVE arch; confirm against config.json)")
    print("-" * 68)
    print(f"Model      : {args.layers} layers, {args.kv_heads} KV heads, "
          f"head_dim {args.head_dim}, KV dtype {args.dtype} ({elem:g} B)")
    print(f"Weights    : ~{args.params_b:g}B params @ {args.weight_dtype}  ->  "
          f"{weights / GiB:.2f} GiB")
    print(f"GPU memory : {args.gpu_mem_gib:g} GiB   (reserve {args.overhead_gib:g} GiB "
          f"for activations/overhead)")
    if avail <= 0:
        print()
        print("Weights + overhead already exceed GPU memory: no room for KV cache.")
        print("Use a bigger GPU, quantize the weights (--weight-dtype), or shard the model.")
        return
    print(f"Free for KV: {avail / GiB:.2f} GiB")
    print()

    print(f"KV per token (one sequence):  2 x {args.layers} x {args.kv_heads} x "
          f"{args.head_dim} x {elem:g} B  =  {per_tok:,.0f} B  "
          f"({per_tok / MiB:.4f} MiB/token)")
    print(f"KV per request @ {args.context:,} tokens:  {per_req / MiB:,.1f} MiB")
    print()

    max_conc = int(avail // per_req)
    print(f"Max concurrent requests @ {args.context:,} context:  ~{max_conc}")
    print("(This, not tokens/sec, is usually what caps how many users you serve at once.)")
    print()

    print("Context length vs concurrency (same GPU):")
    print(f"  {'context':>8}  {'KV/req':>11}  {'max concurrent':>14}")
    ctxs = [c for c in (1024, 2048, 4096, 8192, 16384, 32768) if c <= max(args.context, 8192) * 4]
    if args.context not in ctxs:
        ctxs = sorted(set(ctxs + [args.context]))
    for c in ctxs:
        req = per_tok * c
        conc = int(avail // req)
        mark = "  <- your setting" if c == args.context else ""
        print(f"  {c:>8,}  {req / MiB:>8,.1f} MiB  {conc:>14}{mark}")
    print("  Double the context, halve the concurrency. Context length is a capacity cost.")
    print()

    saved = (args.prefix_requests - 1) * args.prefix_tokens * per_tok
    extra = int(saved // per_req) if per_req else 0
    print(f"Prefix caching: {args.prefix_requests} requests sharing a "
          f"{args.prefix_tokens:,}-token prompt")
    print(f"  store the shared prefix ONCE instead of {args.prefix_requests} times  ->  "
          f"save {saved / GiB:.2f} GiB  (~{extra} more concurrent @ {args.context:,} ctx)")
    print("  This is why a shared system prompt / few-shot preamble is nearly free to reuse.")
    print()


if __name__ == "__main__":
    main()
