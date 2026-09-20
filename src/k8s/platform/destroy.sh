#!/usr/bin/env bash
# Uninstalls Helm releases while the cluster and controllers are available,
# then creates, displays, and applies a destroy plan.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOFU_BIN="${TOFU_BIN:-tofu}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DESTROY_PLAN="${SCRIPT_DIR}/destroy-${TIMESTAMP}.tfplan"
DNS_RECORD_BACKUP="${SCRIPT_DIR}/destroy-${TIMESTAMP}-dns-records.json"

cd "${SCRIPT_DIR}"

if ! command -v "${TOFU_BIN}" >/dev/null 2>&1; then
  echo "OpenTofu executable not found: ${TOFU_BIN}" >&2
  exit 1
fi

for executable in aws helm jq kubectl; do
  if ! command -v "${executable}" >/dev/null 2>&1; then
    echo "Required executable not found: ${executable}" >&2
    exit 1
  fi
done

CLUSTER_NAME="$("${TOFU_BIN}" output -raw cluster_name)"
AWS_PROFILE="${AWS_PROFILE:-$("${TOFU_BIN}" output -raw aws_profile)}"
AWS_REGION="${AWS_REGION:-$("${TOFU_BIN}" output -raw aws_region)}"
ROUTE53_ZONE_NAME="$("${TOFU_BIN}" output -raw route53_zone_name)"
NGINX_HOSTNAME="$("${TOFU_BIN}" output -raw nginx_hostname)"

# A destroy plan still evaluates required variables but never applies this CIDR.
export TF_VAR_allowed_cidr_blocks="${TF_VAR_allowed_cidr_blocks:-[\"203.0.113.10/32\"]}"

aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --alias "${CLUSTER_NAME}" >/dev/null

TRAEFIK_LB_HOSTNAME="$(kubectl get service traefik --namespace traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

mapfile -t INITIAL_STATE_ADDRESSES < <("${TOFU_BIN}" state list)

uninstall_release() {
  local address="$1"
  local release="$2"
  local namespace="$3"
  local state_address
  local address_found=false

  for state_address in "${INITIAL_STATE_ADDRESSES[@]}"; do
    if [[ "${state_address}" == "${address}" ]]; then
      address_found=true
      break
    fi
  done

  if [[ "${address_found}" == false ]]; then
    return
  fi

  if helm status "${release}" --namespace "${namespace}" >/dev/null 2>&1; then
    echo "Uninstalling ${namespace}/${release}..."
    helm uninstall "${release}" --namespace "${namespace}" --wait --timeout 10m
  else
    echo "Helm release ${namespace}/${release} is already absent."
  fi

  "${TOFU_BIN}" state rm "${address}"
}

delete_test_dns_records() {
  local change_id
  local records
  local zone_id

  if [[ -z "${NGINX_HOSTNAME}" ]]; then
    return
  fi

  zone_id="$(
    aws route53 list-hosted-zones-by-name \
      --dns-name "${ROUTE53_ZONE_NAME}" \
      --profile "${AWS_PROFILE}" \
      --output json |
      jq -r --arg zone "${ROUTE53_ZONE_NAME%.}." \
        '.HostedZones[] | select(.Name == $zone and .Config.PrivateZone == false) | .Id' |
      { read -r id; printf '%s' "${id##*/}"; }
  )"

  if [[ -z "${zone_id}" ]]; then
    echo "Public Route53 zone not found: ${ROUTE53_ZONE_NAME}" >&2
    exit 1
  fi

  records="$(
    aws route53 list-resource-record-sets \
      --hosted-zone-id "${zone_id}" \
      --profile "${AWS_PROFILE}" \
      --output json |
      jq \
        --arg name "${NGINX_HOSTNAME%.}." \
        --arg owner "external-dns/owner=${CLUSTER_NAME}" \
        --arg target "${TRAEFIK_LB_HOSTNAME%.}." \
        '[.ResourceRecordSets[] | select(
          .Name == $name and (
            (($target | length) > 0 and (.Type == "A" or .Type == "AAAA") and .AliasTarget.DNSName == $target) or
            (.Type == "TXT" and any(.ResourceRecords[]?; .Value | contains($owner)))
          )
        )]'
  )"

  if [[ "$(jq 'length' <<<"${records}")" == 0 ]]; then
    return
  fi

  printf '%s\n' "${records}" >"${DNS_RECORD_BACKUP}"
  change_id="$(
    aws route53 change-resource-record-sets \
      --hosted-zone-id "${zone_id}" \
      --profile "${AWS_PROFILE}" \
      --change-batch "$(jq '{Changes: map({Action: "DELETE", ResourceRecordSet: .})}' <<<"${records}")" \
      --query 'ChangeInfo.Id' \
      --output text
  )"
  aws route53 wait resource-record-sets-changed --id "${change_id}" --profile "${AWS_PROFILE}"
  echo "Deleted demo DNS records; rollback data retained at ${DNS_RECORD_BACKUP}."
}

# Remove consumers before controllers so Kubernetes finalizers can clean up
# Karpenter nodes and AWS load balancers while their controllers still run.
uninstall_release 'helm_release.nginx_demo' 'nginx-demo' 'nginx-demo'
uninstall_release 'module.platform.helm_release.karpenter_spot_nodepool[0]' 'karpenter-spot-nodepool' 'kube-system'
uninstall_release 'module.platform.helm_release.traefik[0]' 'traefik' 'traefik'
delete_test_dns_records
uninstall_release 'module.platform.helm_release.external_secrets_config' 'external-secrets-config' 'external-secrets'
uninstall_release 'module.platform.helm_release.cert_manager_config' 'cert-manager-config' 'cert-manager'
uninstall_release 'module.platform.helm_release.karpenter[0]' 'karpenter' 'kube-system'
uninstall_release 'module.platform.helm_release.kube_prometheus_stack[0]' 'kube-prometheus-stack' 'monitoring'
uninstall_release 'module.platform.helm_release.external_dns' 'external-dns' 'external-dns'
uninstall_release 'module.platform.helm_release.external_secrets' 'external-secrets' 'external-secrets'
uninstall_release 'module.platform.helm_release.cert_manager' 'cert-manager' 'cert-manager'
uninstall_release 'module.platform.helm_release.aws_load_balancer_controller[0]' 'aws-load-balancer-controller' 'kube-system'

mapfile -t STATE_ADDRESSES < <("${TOFU_BIN}" state list | grep -E '(^|\.)(helm_release|kubectl_manifest)\.' || true)

if ((${#STATE_ADDRESSES[@]} > 0)); then
  echo "Unexpected Kubernetes resource addresses remain in state:" >&2
  printf '  %s\n' "${STATE_ADDRESSES[@]}"
  echo "Refusing to forget resources that may still be live." >&2
  exit 1
fi

"${TOFU_BIN}" plan -destroy -input=false -out="${DESTROY_PLAN}"
printf '\nDestroy plan artifact: %s\n\n' "${DESTROY_PLAN}"
"${TOFU_BIN}" show "${DESTROY_PLAN}"

printf '\nType destroy to apply this exact plan: '
if ! read -r confirmation || [[ "${confirmation}" != "destroy" ]]; then
  echo "Destroy cancelled. Plan retained at ${DESTROY_PLAN}."
  exit 1
fi

# Applying the generated destroy plan avoids re-planning during teardown.
"${TOFU_BIN}" apply "${DESTROY_PLAN}"
