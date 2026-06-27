#!/usr/bin/env bash
# serve-gpu.sh - deploy a vLLM inference server on the Lesson 6 k3s GPU cluster, exposing
# an OpenAI-compatible API. Run this ON THE GPU VM.
#
# No Docker required: Lesson 6's host-setup.sh installs k3s (containerd) + the NVIDIA
# Container Toolkit, and this runs vLLM as a pod on that cluster - the same GPU runtime
# Parts A and B use. Run it on a VM that has the GPU device plugin (the Part A GPU-Operator
# VM is ideal; on a HAMi VM the pod gets a slice).
#
# vLLM server + supported flags: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"     # ~15GB, fits a 24GB+ card. Override with any HF
                                               # model that fits your VRAM (see the lab for variants).
SERVED_NAME="${SERVED_NAME:-local}"            # the name the harness passes as MODEL=
NS="inference"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Run this on the GPU VM after host-setup.sh (it installs k3s)."
  exit 1
fi
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "Can't reach the cluster. Is k3s up? Try: sudo systemctl status k3s"
  exit 1
fi

echo "==> Deploying vLLM (model ${MODEL}, served as '${SERVED_NAME}')..."
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels: { app: vllm }
  template:
    metadata:
      labels: { app: vllm }
    spec:
      runtimeClassName: nvidia
      # Don't let k8s inject Docker-link env vars (VLLM_PORT=tcp://...:8000 etc. from the
      # Service named 'vllm') - they collide with vLLM's own VLLM_PORT config variable.
      enableServiceLinks: false
      containers:
        - name: vllm
          image: vllm/vllm-openai:latest
          args: ["--model", "${MODEL}", "--served-model-name", "${SERVED_NAME}", "--host", "0.0.0.0", "--port", "8000"]
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
          # vLLM downloads + loads the model before it serves. A startupProbe gives that up
          # to ~15 min; readiness gates traffic (and 'rollout status') on /health, so "ready"
          # actually means "serving" - not just "container started".
          startupProbe:
            httpGet: { path: /health, port: 8000 }
            periodSeconds: 10
            failureThreshold: 90
          readinessProbe:
            httpGet: { path: /health, port: 8000 }
            periodSeconds: 10
          volumeMounts:
            - name: hf-cache
              mountPath: /root/.cache/huggingface
            - name: shm
              mountPath: /dev/shm
      volumes:
        - name: hf-cache
          hostPath:
            path: /root/.cache/huggingface
            type: DirectoryOrCreate
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
  namespace: ${NS}
spec:
  selector: { app: vllm }
  ports:
    - port: 8000
      targetPort: 8000
YAML

echo "==> Waiting for vLLM to pull the image, load the model, and pass its /health check..."
echo "    First run downloads the image + weights - this can take several minutes."
echo "    Watch progress in another terminal:  kubectl -n ${NS} logs -f deploy/vllm"
if ! kubectl -n "$NS" rollout status deployment/vllm --timeout=1200s; then
  echo
  echo "vLLM isn't ready yet (or failed). Check what it's doing:"
  echo "  kubectl -n ${NS} get pods"
  echo "  kubectl -n ${NS} logs deploy/vllm --tail=50"
  exit 1
fi

cat <<EOF

vLLM is running as a pod in the '${NS}' namespace, serving model '${SERVED_NAME}'.

1) Open a port-forward in ONE terminal on the VM and leave it running:

   KUBECONFIG=${KUBECONFIG} kubectl -n ${NS} port-forward svc/vllm 8000:8000

2) In ANOTHER terminal on the VM, run the drills against http://localhost:8000:

   MODEL=${SERVED_NAME} ENDPOINT=http://localhost:8000 make phase5-bench
   MODEL=${SERVED_NAME} ENDPOINT=http://localhost:8000 make phase5-overload

Tear down when done:

   KUBECONFIG=${KUBECONFIG} kubectl delete namespace ${NS}
EOF
