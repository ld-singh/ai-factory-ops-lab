#!/usr/bin/env bash
# probe-memory.sh - in-container isolation probes. Run AFTER share-two-pods.yaml is
# Running on the real-GPU host. Two checks:
#   1) virtualized nvidia-smi: should report the pod's memory slice (e.g. ~8000 MiB on
#      the A6000 manifest), not the card's full memory.
#   2) a CUDA allocation that grows past the slice: should be refused by HAMi-core.
#
# This demonstrates the behavior. It does NOT assert an exact byte boundary: the
# precise point an allocation is refused depends on allocator and driver behavior,
# so the precise claim is "allocations beyond the slice are refused".
#
# Isolation here is user-space CUDA interception (software), not MIG hardware fault
# isolation. See the README.
set -euo pipefail

POD="${1:-hami-share-a}"

echo "== CHECK 1/2 [$POD]: what does the container THINK the GPU is? =="
echo "   Look at the Memory column below. It should read your SLICE (e.g. 8000MiB),"
echo "   NOT the A6000's real ~49140MiB. HAMi-core fakes the card size to the container."
echo
kubectl exec "$POD" -- nvidia-smi

echo
echo "== CHECK 2/2 [$POD]: does the cap actually HOLD? =="
echo "   Allocate GPU memory 256 MiB at a time until it's refused. The physical card has"
echo "   tens of GB free - so if this pod is stopped near its slice, that's HAMi enforcing"
echo "   the limit (not the hardware running out)."
# Compile and run a tiny allocator inside the pod (the image is the CUDA devel image,
# so nvcc is present). The loop keeps cudaMalloc-ing until it fails, then prints how
# far it got. On a HAMi-capped pod this should fail near the slice limit, well below
# the physical card size.
kubectl exec "$POD" -- bash -c '
set -e
cat > /tmp/probe.cu <<EOF
#include <cuda_runtime.h>
#include <cstdio>
int main() {
  const size_t chunk = (size_t)256 * 1024 * 1024; // 256 MiB
  size_t total = 0;
  void *p = nullptr;
  for (;;) {
    cudaError_t e = cudaMalloc(&p, chunk);
    if (e != cudaSuccess) {
      printf("cudaMalloc refused after %zu MiB allocated: %s\n",
             total / (1024 * 1024), cudaGetErrorString(e));
      return 0;
    }
    total += chunk;
    printf("allocated %zu MiB\n", total / (1024 * 1024));
  }
}
EOF
nvcc -o /tmp/probe /tmp/probe.cu
/tmp/probe
'

echo
echo "================================ WHAT THIS PROVES ================================"
echo "  CHECK 1: the container saw a small GPU (your slice), not the real 48GB card."
echo "  CHECK 2: the allocation was refused at ~your slice BY HAMI-CORE - see the"
echo "           '[HAMI-core ERROR] ... OOM' line - even though the card had tens of GB free."
echo
echo "  The proof is the CONTRADICTION: 'out of memory' at your slice while the card still"
echo "  has plenty free. Only a software cap intercepting CUDA calls can do that. Stock"
echo "  Kubernetes gives a pod the WHOLE card - it cannot do this."
echo
echo "  Record CHECK 1 (nvidia-smi) + the refusal line as evidence. Claim it as 'refused"
echo "  at the slice', not an exact byte count (the exact point depends on the allocator)."
echo "================================================================================="
