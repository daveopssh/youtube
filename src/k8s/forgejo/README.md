# Cómo hostear Forgejo en Kubernetes con Helm

Forgejo es una forge de código (issues, PRs, paquetes, Actions) self-hosted,
fork comunitario de Gitea. Si quieres el Git en tu cluster en vez de en GitHub,
este demo monta una instancia local con [kind](https://kind.sigs.k8s.io/) y el
[Helm chart oficial](https://artifacthub.io/packages/helm/forgejo-helm/forgejo).

No es un cluster de producción. Es un laboratorio que enseña el mismo flujo
que usarías en un cluster real: archivo de kind, un Ingress controller, `values.yaml`
y `helm install` desde un registro OCI.

> **Por qué no ingress-nginx.** Kubernetes SIG Network retiró
> [ingress-nginx en marzo 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/):
> no hay más releases ni parches de seguridad. Aquí usamos **Traefik** (Helm,
> Ingress API). Gateway API es la vía a largo plazo; el chart de Forgejo también
> la soporta (`httpRoute`), pero para este lab nos quedamos en Ingress.

## Qué despliega este demo

| Recurso | Para qué sirve |
| --- | --- |
| Cluster kind `forgejo-demo` | Kubernetes local en Docker |
| Traefik (Helm chart 41.3.0) | HTTP (UI y git HTTP) a `git.localhost` |
| Helm release `forgejo` | Forgejo 15.x (chart 17.1.5) |
| Service `forgejo-ssh` + hostPort 2222 | Git por SSH (`ssh://git@git.localhost:2222`) |
| PVC `gitea-shared-storage` | Repos y SQLite (sobreviven un restart del pod) |

Valores por defecto del demo:

- Host: `git.localhost`
- Namespace: `forgejo`
- Admin: `daveops` / `DaveOpsDemo123`
- Base de datos: SQLite (default del chart v17)
- Persistencia: 5Gi
- Chart: `oci://code.forgejo.org/forgejo-helm/forgejo` versión `17.1.5`

> El chart sigue usando la clave `gitea:` en los values. No es un error: nace
> del chart de Gitea.

## Requisitos

- Docker (o un runtime compatible con kind)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- kubectl
- [Helm 3](https://helm.sh/docs/intro/install/)
- ~4 GB de RAM libres
- Puertos **80**, **443** y **2222** libres en el host (si 80 o 2222 están ocupados, ver más abajo)
- `ssh-keygen` si vas a clonar por SSH (la clave se crea **en esta carpeta**, no en `~/.ssh`)

## Paso 1 — Crear el cluster kind

Desde esta carpeta:

```bash
cd src/k8s/forgejo

kind create cluster --config kind.yaml
```

Eso crea el cluster `forgejo-demo` con un solo control-plane y
`extraPortMappings` de 80/443 (Traefik) y **2222** (git SSH) del host al nodo.

Comprueba el contexto:

```bash
kubectl cluster-info --context kind-forgejo-demo
```

## Paso 2 — Instalar Traefik

Mismo patrón que Forgejo: chart oficial por OCI, values en el repo.

```bash
helm install traefik oci://ghcr.io/traefik/helm/traefik \
  --version 41.3.0 \
  --namespace traefik \
  --create-namespace \
  -f traefik-values.yaml

kubectl -n traefik rollout status deployment/traefik --timeout=180s
```

`traefik-values.yaml` pone `hostPort` 80/443 y crea el `IngressClass` `traefik`
(default). No uses el chart de **ingress-nginx** (`kubernetes/ingress-nginx`):
está retirado. Tampoco lo confundas con el NGINX Ingress de F5 (`nginxinc`),
que es otro producto.

## Paso 3 — Apuntar `git.localhost` al host

```bash
# Linux / macOS. En Windows edita C:\Windows\System32\drivers\etc\hosts
echo '127.0.0.1 git.localhost' | sudo tee -a /etc/hosts
```

Si la entrada ya existe, no la dupliques.

## Paso 4 — Instalar Forgejo con Helm

```bash
helm install forgejo oci://code.forgejo.org/forgejo-helm/forgejo \
  --version 17.1.5 \
  --namespace forgejo \
  --create-namespace \
  -f values.yaml
```

No hace falta `helm repo add`: el chart se instala directo desde el registro
OCI de Forgejo.

## Paso 5 — Esperar a que esté listo

```bash
kubectl -n forgejo rollout status deployment/forgejo --timeout=5m
kubectl -n forgejo get pods,ingress,pvc,svc
```

Esperado:

- Pod `forgejo-*` en `Running`
- Service `forgejo-http` (puerto 3000) y `forgejo-ssh` (puerto 22 → pod 2222)
- Ingress `forgejo` con host `git.localhost` y class `traefik`
- PVC `gitea-shared-storage` `Bound`

El chart usa `Recreate` (no `RollingUpdate`) a propósito: Forgejo con SQLite
y un PVC `ReadWriteOnce` no se lleva bien con dos réplicas a la vez.

## Paso 6 — Abrir la UI y crear un repo

1. Abre [http://git.localhost](http://git.localhost)
2. Entra con `daveops` / `DaveOpsDemo123`
3. **New Repository** → nombre `demo` → Create
4. Clona por HTTP y empuja un commit:

```bash
git clone http://daveops:DaveOpsDemo123@git.localhost/daveops/demo.git
cd demo
echo 'hola desde kind' > README.md
git add README.md
git commit -m "primer commit"
git push
```

Si git se queja del helper de credenciales, usa el URL con usuario y password
como arriba, o configura un token en la UI (**Settings → Applications**).

## Paso 7 — Git por SSH

Traefik solo lleva HTTP. SSH es TCP aparte: el pod de Forgejo (imagen rootless)
escucha SSH en **2222**, `kind.yaml` reenvía ese puerto al host, y
`SSH_PORT: 2222` hace que la UI muestre el puerto correcto.

No uses el puerto **22** del host: casi siempre está ocupado por `sshd`.

Desde `src/k8s/forgejo` (esta carpeta). La clave **no** va a `~/.ssh`.

1. Crea el par de claves en el demo:

```bash
mkdir -p ssh
ssh-keygen -t ed25519 -f ssh/id_ed25519 -N '' -C 'forgejo-demo'
```

Quedan `ssh/id_ed25519` (privada) y `ssh/id_ed25519.pub` (pública). No las
subas al git: están en `.gitignore`.

2. En la UI: avatar → **Settings → SSH / GPG Keys → Add Key**. Pega el contenido
   de `ssh/id_ed25519.pub`.
3. Clona. El usuario SSH es **`git`**, no `daveops` (la key identifica al admin):

```bash
GIT_SSH_COMMAND='ssh -i ssh/id_ed25519 -o IdentitiesOnly=yes' \
  git clone ssh://git@git.localhost:2222/daveops/demo.git demo-ssh
cd demo-ssh
echo 'hola por ssh' >> README.md
git add README.md
git commit -m "commit por ssh"
GIT_SSH_COMMAND='ssh -i ../ssh/id_ed25519 -o IdentitiesOnly=yes' git push
```

Opcional, para no repetir `-p 2222` ni `GIT_SSH_COMMAND` (ruta absoluta a la
clave de este demo):

```text
# ~/.ssh/config
Host git.localhost
  User git
  Port 2222
  IdentityFile /ruta/al/repo/src/k8s/forgejo/ssh/id_ed25519
  IdentitiesOnly yes
```

Luego: `git clone git@git.localhost:daveops/demo.git`.

La primera conexión pide aceptar el host key de Forgejo; es normal.

### Comprobar que el PVC funciona

```bash
kubectl -n forgejo delete pod -l app.kubernetes.io/name=forgejo
kubectl -n forgejo rollout status deployment/forgejo --timeout=5m
```

Recarga [http://git.localhost](http://git.localhost): el usuario y el repo
siguen ahí.

## Puerto 80 o 2222 ocupado

Si `kind create` falla porque el puerto **80** del host está en uso, en
`kind.yaml` cambia el mapping HTTP:

```yaml
extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
```

Y en `values.yaml` usa `http://git.localhost:8080` como `ROOT_URL` (y la misma
URL en el navegador). Recrea el cluster después de editar `kind.yaml`.

Si falla el **2222**, cambia el `hostPort` de SSH en `kind.yaml` **y** en
`values.yaml` (`service.ssh.hostPort` + `gitea.config.server.SSH_PORT`) al
mismo número. Si no coinciden, la UI miente en el clone URL.

## Fallback: port-forward

Si Ingress no responde (DNS, puerto, controller), puedes entrar igual:

```bash
kubectl -n forgejo port-forward svc/forgejo-http 3000:3000
```

Abre [http://127.0.0.1:3000](http://127.0.0.1:3000). Los links que genera
Forgejo seguirán apuntando a `git.localhost` porque eso es el `ROOT_URL`.

## Limpieza

```bash
helm uninstall forgejo --namespace forgejo
helm uninstall traefik --namespace traefik
# El PVC de Forgejo tiene helm.sh/resource-policy: keep (default del chart).
# kind delete se lleva los volúmenes igual; si reinstalas en el mismo cluster:
kubectl -n forgejo delete pvc gitea-shared-storage --ignore-not-found

kind delete cluster --name forgejo-demo
```

Opcional: quita `127.0.0.1 git.localhost` de `/etc/hosts`.

## Notas de producción

Esto es un lab. Antes de hostear de verdad:

- PostgreSQL (o MySQL) en vez de SQLite; Valkey/Redis para cache/sesión/cola
- TLS (cert-manager) y un dominio real
- Password de admin fuera de git (Secret + `gitea.admin.existingSecret`)
- Backups del PVC / de la base
- Git por SSH en el 22 público (LoadBalancer / NodePort) o TCP en Traefik; este lab usa 2222 para no pelear con `sshd`

Forgejo Actions y runners en Kubernetes dan para otro vídeo.

## Estructura

```text
.
├── README.md            # Este archivo
├── kind.yaml            # Cluster kind (puertos 80/443/2222)
├── traefik-values.yaml  # Traefik: hostPort + IngressClass
├── values.yaml          # Helm values de Forgejo
└── ssh/                 # Claves del lab (gitignored; se generan en el paso 7)
```

## Referencias

- Chart Forgejo: [Artifact Hub — forgejo-helm](https://artifacthub.io/packages/helm/forgejo-helm/forgejo)
- Chart Traefik: `oci://ghcr.io/traefik/helm/traefik` (41.3.0)
- Docs Forgejo: [forgejo.org](https://forgejo.org/)
- Retiro de ingress-nginx: [Kubernetes blog, nov 2025](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- Gateway API (alternativa a Ingress): [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/guides/)
