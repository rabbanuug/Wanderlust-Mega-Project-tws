# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wanderlust is a three-tier MERN travel blog app deployed via a DevSecOps pipeline. The repo contains the app source, Kubernetes manifests, CI/CD Jenkinsfiles, Terraform for AWS infrastructure, and local setup tooling.

## Development Commands

### Backend (Node.js / Express — `backend/`)

```bash
cd backend
npm install
cp .env.sample .env      # set MONGODB_URI and REDIS_URL
npm start                # nodemon on port 5000
npm test                 # Jest (watch mode + coverage)
npm run check            # Prettier check
npm run format           # Prettier write
```

Backend uses ES modules (`"type": "module"`). Tests are transformed via `babel-jest` using `.babelrc`.

### Frontend (React / Vite / TypeScript — `frontend/`)

```bash
cd frontend
npm install
npm run dev              # Vite dev server on port 5173
npm run build            # tsc (tsconfig.prod.json) + vite build
npm run lint             # ESLint (zero warnings allowed)
npm run test             # Jest + jsdom
npm run format           # Prettier + tailwindcss plugin
```

### Full Stack via Docker Compose (root `docker-compose.yml`)

```bash
# Requires backend/.env.docker and frontend/.env.docker
docker compose up -d     # mongo, backend:31100, frontend:5173, redis:6379
docker compose down -v
```

### CI/CD tooling (Jenkins + SonarQube — `setup/compose.yml`)

```bash
cd setup
docker compose up -d     # Jenkins:8080, SonarQube:9000
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### Terraform (`terraform/`)

```bash
cd terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform destroy
```

Provisions an AWS EC2 instance (AMI/type from `variables.tf`) with a security group covering all required ports. SSH key must exist at `/home/devops/.ssh/id_ed25519_aws-practice.pub`.

## Architecture

### App tiers

- **Frontend**: React 18 + Vite + TypeScript + Tailwind + shadcn/ui (`components.json`). Routes: `/`, `/add-blog`, `/details-page/:title/:postId`, `/signin`, `/signup`. API base URL read from env at build time.
- **Backend**: Express with ESM. Routes: `POST/GET /api/posts`, `POST /api/auth`. Redis is optional — if `REDIS_URL` is unset the cache layer silently disables (`services/redis.js`). MongoDB via Mongoose.
- **Database**: MongoDB. Seed data in `backend/data/sample_posts.json`.

### CI/CD pipeline

Two Jenkinsfiles, both using a shared library (`@Library('Shared')`):

- **`Jenkinsfile` (CI — `Wanderlust-CI` pipeline)**: runs on Jenkins agent labelled `Node`. Stages: parameter validation → workspace clean → git checkout → Trivy filesystem scan → OWASP dependency check → SonarQube analysis + quality gate → parallel env-var injection (`Automations/`) → Docker build → Docker push to DockerHub (`trainwithshubham/wanderlust-{frontend,backend}-beta`). On success, triggers the CD job.
- **`GitOps/Jenkinsfile` (CD — `Wanderlust-CD` pipeline)**: patches image tags in `kubernetes/backend.yaml` and `kubernetes/frontend.yaml` via `sed`, then commits and pushes to GitHub. ArgoCD watches the repo and syncs to the cluster.

### Kubernetes manifests (`kubernetes/`)

All resources deploy into the `wanderlust` namespace. Key NodePorts: frontend → `31000`, backend → `31100`. MongoDB uses a PersistentVolume/PVC pair (`persistentVolume.yaml` / `persistentVolumeClaim.yaml`). Redis runs as a ClusterIP service.

### Automations (`Automations/`)

`updatebackendnew.sh` and `updatefrontendnew.sh` query AWS EC2 for the worker node's public IP via instance ID and patch the corresponding `.env.docker` file. The instance ID is hardcoded in each script — update it when the EC2 instance changes.

### Local k3s alternative

See `LOCAL_SETUP.md` for running the full stack on k3s instead of EKS, using the same Kubernetes manifests.
