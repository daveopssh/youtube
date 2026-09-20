# Kubernetes — Demos

Código de los tutoriales de **Kubernetes**

← [Volver al índice del repo](../../README.md)

## Demos

| Demo | Descripción | Carpeta |
|------|-------------|---------|
| **platform** | Plataforma EKS con OpenTofu (`tf-eks-platform`): red, add-ons, Karpenter Spot y Nginx por HTTPS | [`platform/`](./platform/) |

### platform

- **Qué hace:** despliega una plataforma EKS en AWS y sirve Nginx en `https://nginx.demo.daveops.sh` sobre un nodo Karpenter Spot.
- **Docs del demo:** [`platform/README.md`](./platform/README.md)
- **Entrar al demo:**

  ```bash
  cd src/k8s/platform
  ```
