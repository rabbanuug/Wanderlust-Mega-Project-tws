# Wanderlust - Local Setup with k3s

Deploy the Wanderlust MERN app locally using k3s instead of AWS EKS.

## Tech Stack

- Docker + Docker Compose (Jenkins, SonarQube)
- k3s (local Kubernetes)
- Jenkins (CI)
- SonarQube (code quality)
- Trivy (security scan)
- ArgoCD (CD)
- Helm + Prometheus + Grafana (monitoring)

---

## Prerequisites

### 1. Install Docker

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update && sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER && newgrp docker
```

### 2. Install k3s

```bash
curl -sfL https://get.k3s.io | sh -
```

Set up kubeconfig for your user:

```bash
mkdir -p ~/.kube
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
chmod 600 ~/.kube/config
```

Verify:

```bash
kubectl get nodes
```

### 3. Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 4. Install Trivy

```bash
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
    | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
```

---

## Start Jenkins & SonarQube

From the `setup/` directory:

```bash
docker compose up -d
```

- Jenkins: http://localhost:8080
- SonarQube: http://localhost:9000 (default login: `admin` / `admin`)

Get the Jenkins initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## Install ArgoCD on k3s

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
# --force-conflicts use this tag if you get conflict error
```

Wait for all pods to be ready:

```bash
kubectl get pods -n argocd -w
```

Expose ArgoCD UI via NodePort:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n argocd
```

Note the NodePort assigned to argocd-server and access ArgoCD at `http://localhost:<nodeport>`.

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
```

### ArgoCD CLI

Install the ArgoCD CLI:

```bash
# amd64
sudo curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd

# arm64
sudo curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo chmod +x /usr/local/bin/argocd

# uninstall
sudo rm /usr/local/bin/argocd
```

Login using the NodePort you noted above:

```bash
argocd login localhost:<nodeport> --username admin --insecure
```

No need to run `argocd cluster add`. Since ArgoCD runs inside k3s it already has the local cluster registered automatically. Verify with:

```bash
argocd cluster list
```

You will see `https://kubernetes.default.svc` listed as `in-cluster` — use this as the cluster URL when creating apps.

---

## Configure Jenkins

### Install Plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:

- SonarQube Scanner
- OWASP Dependency-Check
- Docker
- Pipeline: Stage View

### Configure Built-in Node as Agent

The Jenkinsfile targets the label `Node`. Configure the built-in Jenkins node to carry that label:

Go to **Manage Jenkins → Nodes → Built-In Node → Configure:**

- **Number of executors:** 2
- **Labels:** `Node`
- **Usage:** Use this node as much as possible

### Add Credentials

**Generate a SonarQube token:**

Go to `http://localhost:9000/admin/users` → **Administration → Security → Users → Token**, enter name `sonar-token` and click Generate.

**Generate a Docker Hub personal access token:**

Go to your Docker Hub account → **Account Settings → Personal access tokens → Generate new token**.

**Generate a GitHub personal access token:**

Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**, select `repo` scope (full control).

---

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials** and add:

| ID             | Kind              | Value                             |
| -------------- | ----------------- | --------------------------------- |
| `sonar-token`  | Secret text       | SonarQube user token              |
| `docker-creds` | Username/Password | Docker Hub username + access token|
| `github-token` | Username/Password | GitHub username + PAT             |

### Configure SonarQube Integration

**Manage Jenkins → System → SonarQube servers:**

- Name: `Sonar`
- URL: `http://localhost:9000`
- Token: select `sonar-token` credential

**Manage Jenkins → Tools → SonarQube Scanner installations:**

- Name: `Sonar`
- Install automatically: enabled

### Configure OWASP Dependency-Check Tool

**Manage Jenkins → Tools → Dependency-Check installations:**

- Name: `DC`
- Install automatically: enabled (select latest version)

**Get a free NVD API key** (required — without it the first run downloads 349k records and takes 1-2 hours):

Go to https://nvd.nist.gov/developers/request-an-api-key, submit your email, and the key arrives within minutes.

Add it as a credential — **Manage Jenkins → Credentials → System → Global credentials → Add Credentials:**

| Field | Value |
|---|---|
| Kind | Secret text |
| Secret | your NVD API key |
| ID | `nvd-api-key` |

### Configure Shared Library

**Manage Jenkins → System → Global Trusted Pipeline Libraries → Add:**

- Name: `Shared`
- Default version: `main`
- Retrieval method: Modern SCM → Git
- Project repository: `<URL of your Shared library GitHub repo>`
- Credentials: select `github-token`

### SonarQube Webhook

SonarQube needs to call back to Jenkins when analysis is done. Since SonarQube runs in Docker, it cannot reach `localhost:8080` — use your machine's LAN IP instead.

Get your host IP:

```bash
hostname -I | awk '{print $1}'
```

In SonarQube go to **Administration → Configuration → Webhooks → Create:**

- Name: `jenkins`
- URL: `http://<your-host-ip>:8080/sonarqube-webhook/`

### Set Docker Socket Permissions

Allow Jenkins (running as the `jenkins` user inside the container) to execute Docker commands on the host socket:

```bash
sudo chmod 666 /var/run/docker.sock
```

> **Note:** This grants all container users access to the Docker daemon. Acceptable for a local dev/lab setup; do not use in production or shared environments.

### Mount Node.js into Jenkins (arm64 requirement)

SonarQube Scanner does not ship a bundled Node.js for arm64. The Jenkins container needs Node.js from the host.

First confirm Node.js (≥ 18) is installed on the host:

```bash
node --version
```

If not installed:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Find the binary path and add it to `setup/compose.yml` under the Jenkins volumes:

```bash
which node    # note this path
```

Also mount the Docker binary and socket so Jenkins can run `docker build` and `docker push`. Find the node and docker paths and update `setup/compose.yml` if they differ:

```bash
which node    # e.g. /usr/bin/node or /home/ubuntu/.nvm/versions/node/vX.Y.Z/bin/node
which docker  # typically /usr/bin/docker
```

The `setup/compose.yml` already has entries for node, docker binary, and the Docker socket. Update the node path if `which node` returns something different, then set socket permissions and restart Jenkins:

```bash
sudo chmod 666 /var/run/docker.sock

cd setup
docker compose down && docker compose up -d

docker exec -u jenkins jenkins node --version    # verify node
docker exec -u jenkins jenkins docker info       # verify docker socket access
```

---

## Create Jenkins Pipelines

### Wanderlust-CI

Go to **Jenkins Dashboard → New Item:**

- Name: `Wanderlust-CI`
- Type: Pipeline → OK

Under **Pipeline:**

- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: your GitHub repo URL
- Credentials: select `github-token`
- Branch: `*/main`
- Script Path: `Jenkinsfile`

Save and run.

### Wanderlust-CD

Go to **Jenkins Dashboard → New Item:**

- Name: `Wanderlust-CD`
- Type: Pipeline → OK

Under **Pipeline:**

- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: your GitHub repo URL
- Credentials: select `github-token`
- Branch: `*/main`
- Script Path: `GitOps/Jenkinsfile`

Save. This pipeline is triggered automatically by Wanderlust-CI on success.

---

## Connect ArgoCD to Your Git Repo

In ArgoCD go to **Settings → Repositories → Connect Repo:**

- Type: HTTPS
- URL: your GitHub repo URL
- Username: your GitHub username
- Password: your GitHub PAT

Then go to **Applications → New App** and fill in the following:

**GENERAL**
- Application Name: `wanderlust`
- Project Name: `default`
- Sync Policy: `Automatic` (check **Prune** and **Self Heal**)
- Sync Options: check **Auto-Create Namespace**

**SOURCE**
- Repository URL: select your connected Git repo
- Revision: `main`
- Path: `kubernetes`

**DESTINATION**
- Cluster URL: `https://kubernetes.default.svc`
- Namespace: `wanderlust`

---

## Automations Scripts

The `Automations/` directory contains two pairs of scripts that patch the `.env.docker` files before Docker images are built:

| Script | Purpose | When to use |
|---|---|---|
| `updatebackendnew.sh` | Sets `FRONTEND_URL` — queries AWS EC2 for the worker node's public IP | AWS EKS setup |
| `updatefrontendnew.sh` | Sets `VITE_API_PATH` — queries AWS EC2 for the worker node's public IP | AWS EKS setup |
| `updatebackendlocal.sh` | Sets `FRONTEND_URL` to `http://localhost:31000` | Local k3s setup |
| `updatefrontendlocal.sh` | Sets `VITE_API_PATH` to `http://localhost:31100` | Local k3s setup |

The `Jenkinsfile` is already set to call the local scripts. If you switch to AWS EKS, change the two `sh "bash update*local.sh"` lines in the `Exporting environment variables` stage back to `update*new.sh`, and update the `INSTANCE_ID` in each AWS script to match your EC2 worker node.

**Accessing from another device on the network:**

If you need to open the app from a phone or another machine on the same LAN, edit both local scripts and change:

```bash
HOST_IP="localhost"
```

to your machine's LAN IP, for example:

```bash
HOST_IP="192.168.1.100"   # replace with output of: hostname -I | awk '{print $1}'
```

---

## Access the Application

Once ArgoCD syncs your manifests, verify services are up:

```bash
kubectl get svc -n wanderlust
```

Access the app:

- **Frontend:** http://localhost:31000
- **Backend API:** http://localhost:31100

---

## Monitoring (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace prometheus
helm install stable prometheus-community/kube-prometheus-stack -n prometheus
```

Verify all pods are running:

```bash
kubectl get pods -n prometheus
```

Expose Prometheus:

```bash
kubectl patch svc stable-kube-prometheus-sta-prometheus -n prometheus \
    -p '{"spec": {"type": "NodePort"}}'
```

Expose Grafana:

```bash
kubectl patch svc stable-grafana -n prometheus -p '{"spec": {"type": "NodePort"}}'
```

Check assigned ports:

```bash
kubectl get svc -n prometheus
```

Get Grafana password:

```bash
kubectl get secret --namespace prometheus stable-grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Login at `http://localhost:<grafana-nodeport>` with username `admin`.

---

## Clean Up

Stop Jenkins and SonarQube:

```bash
cd setup && docker compose down -v
```

Remove ArgoCD, monitoring, and the application:

```bash
kubectl delete namespace argocd prometheus wanderlust
```

Uninstall k3s:

```bash
/usr/local/bin/k3s-uninstall.sh
```
