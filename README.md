# DaveOps — Demos de YouTube

Repositorio con el **código fuente de todos los demos** del canal
[**DaveOps**](https://www.youtube.com/@DaveOps).

Aquí encontrarás los ejemplos usados en los tutoriales, organizados por tema
para que puedas clonar, explorar y reproducir cada demo por tu cuenta.

## Secciones

| Sección | Descripción | Carpeta |
|--------|-------------|---------|
| **[Terraform](./src/terraform/)** | Infraestructura como código (IaC) | [`src/terraform/`](./src/terraform/) |
| **[Kubernetes](./src/k8s/)** | Clusters, Helm y workloads | [`src/k8s/`](./src/k8s/) |
| **[Cloud](./src/cloud/)** | Cloud, AWS y plataformas | [`src/cloud/`](./src/cloud/) |
| **[AI](./src/ai/)** | Inteligencia artificial aplicada a DevOps | [`src/ai/`](./src/ai/) |

> Haz clic en una sección para ver los directorios de demos de ese tema.

---

## Terraform

Demos de infraestructura como código con [Terraform](https://www.terraform.io/).

| Demo | Descripción | Código |
|------|-------------|--------|
| **gha-runners** | Runners self-hosted de GitHub Actions en AWS (Lambda, SSM, S3, etc.) | [`src/terraform/gha-runners/`](./src/terraform/gha-runners/) |

Índice de la sección: [`src/terraform/README.md`](./src/terraform/README.md)

---

## Kubernetes

Demos de Kubernetes: clusters locales, Helm y aplicaciones self-hosted.

| Demo | Descripción | Código |
|------|-------------|--------|
| **forgejo** | Forgejo en kind con Helm (Traefik Ingress, values de demo) | [`src/k8s/forgejo/`](./src/k8s/forgejo/) |

Índice de la sección: [`src/k8s/README.md`](./src/k8s/README.md)

---

## Cloud

Demos de cloud y servicios gestionados.

| Demo | Descripción | Código |
|------|-------------|--------|
| — | Próximamente | [`src/cloud/`](./src/cloud/) |

Índice de la sección: [`src/cloud/README.md`](./src/cloud/README.md)

---

## AI

Demos de inteligencia artificial aplicada a flujos DevOps.

| Demo | Descripción | Código |
|------|-------------|--------|
| — | Próximamente | [`src/ai/`](./src/ai/) |

Índice de la sección: [`src/ai/README.md`](./src/ai/README.md)

---

## Cómo usar un demo

1. Clona el repositorio:

   ```bash
   git clone https://github.com/daveopssh/youtube.git
   cd youtube
   ```

2. Entra en la carpeta del demo (por ejemplo Terraform):

   ```bash
   cd src/terraform/gha-runners
   ```

3. Sigue el `README.md` de ese demo para requisitos, variables y pasos.

> Cada demo es autónomo: su propio código, scripts y documentación.

## Estructura del repositorio

```text
.
├── README.md                 # Este archivo (índice del canal)
└── src/
    ├── terraform/            # Demos de Terraform
    │   ├── README.md
    │   └── gha-runners/
    ├── k8s/                  # Demos de Kubernetes
    │   ├── README.md
    │   └── forgejo/
    ├── cloud/                # Demos de Cloud
    │   └── README.md
    └── ai/                   # Demos de AI
        └── README.md
```

## Canal

- YouTube: [youtube.com/@DaveOps](https://www.youtube.com/@DaveOps)

## Contribuciones y feedback

Si un demo no cuadra con el vídeo o falta algún paso, ábrelo en el canal o deja
un comentario en el vídeo correspondiente. Este repo crece con cada tutorial.
