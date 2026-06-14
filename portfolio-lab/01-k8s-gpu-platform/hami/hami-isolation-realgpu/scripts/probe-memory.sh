#!/usr/bin/env bash
# probe-memory.sh - in-container isolation probes. Run AFTER share-two-pods.yaml is
# Running on the real-GPU host. Two checks:
#   1) virtualized nvidia-smi: should report the pod's ~4000 MiB slice, not the
#      card's full 24 GB.
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

echo "== [$POD] virtualized nvidia-smi (expect ~4000 MiB total, not the full card) =="
kubectl exec "$POD" -- nvidia-smi

echo
echo "== [$POD] memory-cap probe: allocate in 256 MiB chunks until refused =="
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
echo "Interpretation: the allocation should be refused well below the physical card"
echo "size, near the pod slice. Record nvidia-smi output and the refusal line as the"
echo "isolation evidence. Do not report an exact byte boundary."
