#!/bin/bash
# One-time Google Cloud setup for the server deploy, run in Cloud Shell:
# turns on the services, gives the github-deploy account its roles, and lets
# GitHub Actions from this repository sign in as it without a key
# (Workload Identity Federation).
P=$(gcloud config get-value project); R=jonathanemc23/BetAssistance
N=$(gcloud projects describe $P --format='value(projectNumber)'); SA=github-deploy@$P.iam.gserviceaccount.com
gcloud services enable iamcredentials.googleapis.com sts.googleapis.com compute.googleapis.com run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com cloudscheduler.googleapis.com
for r in run.admin cloudbuild.builds.editor artifactregistry.admin storage.admin iam.serviceAccountUser cloudscheduler.admin serviceusage.serviceUsageAdmin; do gcloud projects add-iam-policy-binding $P --member=serviceAccount:$SA --role=roles/$r --condition=None -q >/dev/null; done
gcloud projects add-iam-policy-binding $P --member=serviceAccount:$N-compute@developer.gserviceaccount.com --role=roles/cloudbuild.builds.builder --condition=None -q >/dev/null
gcloud iam workload-identity-pools create github --location=global --display-name=GitHub
gcloud iam workload-identity-pools providers create-oidc github --location=global --workload-identity-pool=github --issuer-uri=https://token.actions.githubusercontent.com --attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository --attribute-condition="assertion.repository=='$R'"
gcloud iam service-accounts add-iam-policy-binding $SA --role=roles/iam.workloadIdentityUser --member=principalSet://iam.googleapis.com/projects/$N/locations/global/workloadIdentityPools/github/attribute.repository/$R -q >/dev/null
echo "PROVIDER projects/$N/locations/global/workloadIdentityPools/github/providers/github"; echo "ACCOUNT $SA"
