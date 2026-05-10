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

## Prerequisites/

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

Access ArgoCD at `http://localhost:<nodeport>`.

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
```

### ArgoCD CLI login

Install the ArgoCD CLI:

```bash
# for amd64
sudo curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd

# uninstall argo 
sudo rm /usr/local/bin/argocd

# for arm64
sudo curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo chmod +x /usr/local/bin/argocd
```

Login (accept the self-signed cert warning):

```bash
argocd login localhost:32362 --username admin --insecure
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

# Get sonarqube token
Administration → Security → Users 
http://localhost:9000/admin/users
name: sonar-token
Generate

# Get docker cred
https://app.docker.com/accounts/YOUR_USERNAME/settings/personal-access-tokens
docker login -u rabbanug1
paste the token

# Get github token
https://github.com/settings/tokens
select only Repo full control

### Add Credentials

Go to **Manage Jenkins → Credentials** and add:

| ID             | Kind              | Value                |
| -------------- | ----------------- | -------------------- |
| `sonar-token`  | Secret text       | SonarQube user token |
| `docker-creds` | Username/Password | Docker Hub login     |
| `github-token` | Username/Password | GitHub PAT           |

### Configure SonarQube Integration

**Manage Jenkins → System → SonarQube servers:**

- Name: `sonar`
- URL: `http://localhost:9000`
- Token: select `sonar-token` credential

**Manage Jenkins → Tools → SonarQube Scanner:**
- Name: Sonar
- Add a SonarQube Scanner installation (install automatically)

### SonarQube Webhook

In SonarQube go to **Administration -> Configuration -> Webhooks -> Create:**

- Name: `jenkins`
- URL: `http://[IP_ADDRESS]/sonarqube-webhook/`

---

## Connect ArgoCD to Your Git Repo

In ArgoCD go to **Settings → Repositories → Connect Repo:**

- Type: HTTPS
- URL: your GitHub repo URL
- Username + PAT token

Then go to **Applications → New App** and fill in the following:

**GENERAL**
- Application Name: `wanderlust`
- Project Name: `default`
- Sync Policy: `Automatic` (Check **Prune** and **Self Heal**)
- Sync Options: Check **Auto-Create Namespace**

**SOURCE**
- Repository URL: Select your connected Git repo
- Revision: `main` (or your default branch)
- Path: `kubernetes`

**DESTINATION**
- Cluster URL: `https://kubernetes.default.svc`
- Namespace: `wanderlust`

---

## Monitoring (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace prometheus
helm install stable prometheus-community/kube-prometheus-stack -n prometheus
```

Expose Grafana:

```bash
kubectl patch svc stable-grafana -n prometheus -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n prometheus
```

Get Grafana password:

```bash
kubectl get secret --namespace prometheus stable-grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Login at `http://localhost:<nodeport>` with username `admin`.

---

## Access the Application

Once ArgoCD syncs your manifests:

```bash
kubectl get svc -n wanderlust
```

The app will be available on the NodePort assigned to the frontend service.

---

## Clean Up

Stop Jenkins and SonarQube:

```bash
docker compose down -v
```

Remove ArgoCD and monitoring:

```bash
kubectl delete namespace argocd prometheus wanderlust
```

Uninstall k3s:

```bash
/usr/local/bin/k3s-uninstall.sh
```
