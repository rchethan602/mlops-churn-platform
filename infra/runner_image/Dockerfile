# Base image - confirmed via: kubectl get ephemeralrunnerset <name> -n arc-systems -o yaml | grep image
FROM ghcr.io/actions/actions-runner:latest

USER root

# Baking everything in at build time (on a machine with working internet/proxy)
# avoids any apt-get/curl-download call from inside the cluster at job-runtime,
# which repeatedly hit the corporate transparent proxy (automotive-wan.com)
# blocking both apt and direct binary downloads (dl.k8s.io, github releases).
RUN apt-get update -qq \
    && apt-get install -y -qq python3 python3-pip curl unzip \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 - not available via apt, install the official bundle directly
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# boto3 baked in - training-trigger workflows need no pip install step at all
RUN pip3 install boto3 --break-system-packages

# jq - used by promote_model.sh / rollback_model.sh to parse MLflow API responses
RUN curl -sL -o /usr/local/bin/jq \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 \
    && chmod +x /usr/local/bin/jq

# kubectl - used to patch the KServe InferenceService on promotion/rollback.
# Pinned to a specific version (not "stable.txt") so builds are reproducible
# and don't silently change behavior on a future rebuild.
RUN curl -sL -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

USER runner