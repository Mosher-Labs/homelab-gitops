# checkov:skip=CKV_DOCKER_2: Runs as a CronJob that exits when done, so there is nothing to health-check
FROM python:3.15-slim@sha256:533b0b2f9b5d46fd097091cf826f27902f1d6c3bca714b6dc74551356aa97a51

WORKDIR /app

# Install git for committing changes
RUN apt-get update && \
    apt-get install -y git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the sync script
COPY sync-tplink-devices.py .

# Make script executable
RUN chmod +x sync-tplink-devices.py

# Matches runAsUser in apps/tplink-sync/manifests/cronjob.yaml
RUN useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app
USER 10001:10001

ENTRYPOINT ["python", "/app/sync-tplink-devices.py"]
