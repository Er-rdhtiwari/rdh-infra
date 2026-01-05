#!/usr/bin/env bash
set -euo pipefail

# Export .env vars so envsubst sees them
set -a
source .env
set +a

kubectl create namespace ci --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic jenkins-admin -n ci \
  --from-literal=user="${JENKINS_ADMIN_USER}" \
  --from-literal=password="${JENKINS_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

JENKINS_VALUES=$(envsubst < helm/jenkins/values.yaml > /tmp/jenkins-values.yaml; echo /tmp/jenkins-values.yaml)

helm repo add jenkins https://charts.jenkins.io
helm repo update
helm upgrade --install jenkins jenkins/jenkins -n ci -f "$JENKINS_VALUES" --version 5.6.1
