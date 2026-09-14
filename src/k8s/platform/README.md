# EKS Platform Demo

Runnable OpenTofu demo for the `tf-eks-platform` module. It creates a two-AZ AWS network, installs the complete EKS platform, and serves Nginx over HTTPS from a Karpenter Spot node.

## What It Creates

- VPC module `6.7.2` with two public subnets, two private subnets, and one NAT Gateway
- EKS cluster in `eu-west-1` using AWS profile `personal`
- Two baseline `t3.medium` managed nodes
- External Secrets, External DNS, cert-manager, and their Pod Identity roles
- AWS Load Balancer Controller and Traefik behind an internet-facing NLB
- Karpenter with a Spot NodePool and interruption handling
- kube-prometheus-stack with ephemeral Prometheus and Grafana storage
- Nginx at `https://nginx.demo.daveops.sh`
- A non-sensitive AWS Secrets Manager demo value, synced into Nginx as `DEMO_SECRET`

Nginx selects `karpenter.sh/nodepool=spot`, so the application itself causes Karpenter to launch Spot capacity.

## Platform Module

The demo downloads `daveopssh/tf-eks-platform` from GitHub. Its source is pinned to commit `4c29b9b7f45fb15c7693dedfe5a9fa258fae4876` for reproducible plans. Update the `ref` in `main.tf` only after reviewing a newer module revision.

## Prerequisites

- OpenTofu `>=1.11.2`
- AWS CLI, Helm, kubectl, and jq
- AWS profile `personal` with permissions for VPC, EC2, EKS, IAM, ELBv2, Route53, SQS, and EKS Pod Identity
- Existing public Route53 hosted zone `demo.daveops.sh`

This demo incurs charges for the EKS control plane, managed nodes, NAT Gateway, NLB, Spot capacity, and related data transfer. Monitoring also increases node resource use.

## Deploy

Set the EKS public API allowlist to your current public IPv4 address. Do not use `0.0.0.0/0` unless unrestricted API access is intentional.

```bash
cd /home/daveops/Code/DaveOps/youtube/src/k8s/platform
export TF_VAR_allowed_cidr_blocks="[\"$(curl -fsS https://checkip.amazonaws.com)/32\"]"

tofu init
tofu fmt -check -recursive
tofu validate
tofu plan -out=demo.tfplan
tofu show demo.tfplan
tofu apply demo.tfplan
```

Alternatively, use `terraform.tfvars.example` as the shape for a local, ignored `terraform.tfvars` file and replace the documentation address with your own public `/32`.

## Verify

Configure kubectl using the generated command:

```bash
$(tofu output -raw kubeconfig_command)
```

Inspect the platform and application:

```bash
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type
kubectl get pods -A
kubectl get ingress,certificate -n nginx-demo
kubectl get clustersecretstore aws-secrets-manager
kubectl get externalsecret,secret -n nginx-demo
kubectl exec -n nginx-demo deploy/nginx -- printenv DEMO_SECRET
curl -4 https://nginx.demo.daveops.sh
```

Expected results:

- Nginx returns HTTP 200 over HTTPS.
- `certificate/nginx-demo` reports `Ready=True`.
- Route53 aliases `nginx.demo.daveops.sh` to Traefik's NLB.
- Nginx runs on a node labeled `karpenter.sh/nodepool=spot`.
- `DEMO_SECRET` prints `hello-from-secrets-manager`.

The AWS secret stores a deliberately non-sensitive demonstration value. Do not add credentials or other real secret values to OpenTofu configuration: values passed to OpenTofu are retained in state. Create and rotate real values outside OpenTofu, then have External Secrets reference their AWS Secrets Manager names or ARNs.

Grafana is internal and has no persistent storage:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

## Teardown

Use the provided script instead of a raw `tofu destroy`:

```bash
./destroy.sh
```

The script removes workloads before their controllers, backs up matching Route53 aliases and External DNS ownership records, creates an exact destroy plan, displays every deletion, and requires typing `destroy` before applying it. This ordering allows Kubernetes finalizers to remove the NLB and Karpenter nodes before the cluster disappears.
