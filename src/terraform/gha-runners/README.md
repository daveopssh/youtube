# Cómo hostear GitHub runners en AWS con Terraform

GitHub Actions runners son el entorno donde se ejecuta el código de tus pipelines de CI/CD. Usar runners managed de GitHub tiene un costo, y en algunos casos también hay requisitos de seguridad o compliance que piden ejecutar jobs en infraestructura propia.

Este demo muestra cómo desplegar **self-hosted runners en AWS** con Terraform/OpenTofu, usando el módulo [terraform-aws-github-runner](https://github-aws-runners.github.io/terraform-aws-github-runner/).

Con este enfoque puedes:

- Crear runners bajo demanda cuando llega un job
- Elegir instancias **spot** u **on-demand**
- Definir labels y runner groups
- Usar runners efímeros (se destruyen al terminar el job)

## Formas de instalar runners

Hay varias formas de montar self-hosted runners:

1. **Manual** — te conectas a una EC2 e instalas el agent a mano
2. **Action Runner Controller (ARC)** — en Kubernetes
3. **Terraform** — infraestructura como código (este repo)

## Qué despliega este proyecto

| Recurso | Para qué sirve |
| --- | --- |
| Bucket S3 | Guarda los artifacts de las lambdas del módulo |
| Parámetros SSM | App ID, private key y webhook secret de la GitHub App |
| Key pair EC2 | Acceso SSH opcional a las instancias runner |
| Módulo `github-runner` | API Gateway + Lambdas + ASG/EC2 para runners on-demand |

Valores por defecto del demo:

- Región: `eu-central-1`
- Prefijo: `demo`
- Módulo: `7.10.1`
- Labels: `youtube`, `demote`
- Runner group: `demo`
- Capacidad: `spot`
- Tipos de instancia: `t3.medium`, `t3.large`
- Repo permitido: `daveopssh/demo-tf-repo`

> Ajusta VPC, subnets, repo whitelist y perfil AWS en `main.tf` / variables según tu cuenta.

## Requisitos

- Cuenta de AWS con permisos para EC2, Lambda, API Gateway, SSM, S3 e IAM
- AWS CLI configurada (en el demo se usa el profile `personal`)
- Cuenta de GitHub con permisos para crear una GitHub App
- [OpenTofu](https://opentofu.org/) o Terraform
- Una VPC con subnets donde puedan salir las EC2 (en el demo usan IP pública)

## Paso 1 — Crear la GitHub App

1. Ve a **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**
2. Dale un nombre, por ejemplo: `gha-tf-runner-demo`
3. En **Homepage URL** puedes poner cualquier URL HTTPS, por ejemplo: `https://demo.daveops.sh`
4. **Desactiva Webhook** por ahora (lo activamos al final)
5. Configura permisos:

**Repository permissions**

| Permiso | Nivel | Motivo |
| --- | --- | --- |
| Actions | Read-only | Ver jobs en cola |
| Administration | Read and write | Registrar runners a nivel repo |
| Checks | Read-only | Recibir eventos de builds |
| Metadata | Read-only | Requerido por defecto |

**Organization permissions**

| Permiso | Nivel | Motivo |
| --- | --- | --- |
| Self-hosted runners | Read and write | Gestionar runners de la org |

6. Crea la App
7. Copia el **App ID** (ejemplo del demo: `4455684`)
8. Genera y descarga la **Private key** (`.pem`) y guárdala en un lugar seguro
9. Opcional: anota también el Client ID

Todavía **no** instales la App ni actives el webhook. Eso va después del deploy.

## Paso 2 — Bootstrap de infraestructura (sin el módulo runner)

Primero creamos el bucket S3, el key pair y los parámetros SSM. El módulo de runners se deja fuera porque necesita las lambdas ya subidas al bucket y las credenciales de la GitHub App en SSM.

```bash
tofu init
tofu apply -exclude=module.github_runner
```

Esto crea, entre otras cosas:

- Bucket: `demo-gha-runner-lambda`
- SSM:
  - `/github-action-runners/demo/app/github_app_id`
  - `/github-action-runners/demo/app/github_app_key_base64` (placeholder temporal)
  - `/github-action-runners/demo/app/github_app_webhook_secret` (generado por Terraform)

## Paso 3 — Publicar las lambdas en S3

El módulo no empaqueta las lambdas por ti: hay que descargarlas del release upstream y subirlas al bucket.

```bash
./scripts/publish-github-runner-lambdas.sh s3://demo-gha-runner-lambda \
  --tag v7.10.1 \
  --profile personal
```

El script sube:

- `webhook.zip`
- `runners.zip`
- `runner-binaries-syncer.zip`

Bajo el prefijo `github-runner/7.10.1/`, alineado con `var.github_runner_module_version`.

> La versión del tag (`v7.10.1`) debe coincidir con la del módulo en Terraform (`7.10.1`).

## Paso 4 — Cargar credenciales de la GitHub App en SSM

Terraform crea los parámetros, pero el App ID real y la private key se cargan con el script helper (y quedan fuera del state como valor mutable gracias a `lifecycle.ignore_changes`).

```bash
# App ID
./scripts/put-ssm-parameter.sh "/github-action-runners/demo/app/github_app_id" \
  --github-app-id 4455684 \
  --region eu-central-1 \
  --profile personal

# Private key (se guarda en base64)
./scripts/put-ssm-parameter.sh "/github-action-runners/demo/app/github_app_key_base64" \
  --github-app-key-file gha-demo-runner-private-key.pem \
  --region eu-central-1 \
  --profile personal
```

## Paso 5 — Desplegar el módulo de runners

Con bucket + lambdas + SSM listos:

```bash
tofu apply -target=module.github_runner
```

O, si prefieres aplicar todo el stack:

```bash
tofu apply
```

Revisa los outputs importantes:

```bash
tofu output webhook
tofu output github_app_ssm_parameter_names
tofu output lambda_artifacts_bucket_name
```

El output `webhook` es la URL de API Gateway que debes pegar en la GitHub App.

## Paso 6 — Activar el webhook e instalar la App

1. Vuelve a la GitHub App → **Permissions & events**
2. Activa **Webhook**
3. En **Subscribe to events**, marca **Workflow job** (obligatorio)
4. Pega:
   - **Webhook URL** → output `webhook`
   - **Webhook secret** → valor del parámetro SSM  
     `/github-action-runners/demo/app/github_app_webhook_secret`
5. Guarda los cambios
6. Instala la App en la organización/repositorio donde vas a correr jobs  
   (en este demo el whitelist es `daveopssh/demo-tf-repo`)

Para leer el secret desde AWS:

```bash
aws ssm get-parameter \
  --name "/github-action-runners/demo/app/github_app_webhook_secret" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region eu-central-1 \
  --profile personal
```

## Paso 7 — Probar con un workflow

En el repositorio autorizado, usa un job con labels self-hosted. Ejemplo:

```yaml
name: demo-self-hosted

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: [self-hosted, youtube, demote]
    steps:
      - uses: actions/checkout@v4
      - run: echo "Corriendo en runner self-hosted de AWS"
```

Flujo esperado:

1. GitHub emite el evento `workflow_job`
2. API Gateway + Lambda webhook lo reciben
3. Se escala una EC2 runner (spot por defecto)
4. El job se ejecuta
5. El runner efímero se limpia al terminar

## Estructura útil del repo

```text
.
├── main.tf                 # Bucket, SSM, key pair y módulo github_runner
├── variables.tf            # Prefijo, spot/on-demand, tipos de instancia, versión
├── outputs.tf              # Webhook, bucket, nombres SSM
├── provider.tf             # AWS en eu-central-1
└── scripts/
    ├── publish-github-runner-lambdas.sh
    └── put-ssm-parameter.sh
```

## Costos y limpieza

- Por defecto los runners son **spot** y **efímeros**, así que en reposo el costo es bajo (lambdas, API Gateway, SSM, S3).
- Cuando termines el demo:

```bash
tofu destroy
```

También puedes borrar o desinstalar la GitHub App si ya no la necesitas.

## Referencias

- Módulo oficial: [terraform-aws-github-runner](https://github-aws-runners.github.io/terraform-aws-github-runner/)
- Docs de self-hosted runners: [GitHub Docs](https://docs.github.com/en/actions/hosting-your-own-runners)
