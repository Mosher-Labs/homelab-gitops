# checkov:skip=CKV_DOCKER_2: Runs as a CronJob that exits when done, so there is nothing to health-check
FROM python:3.14-slim@sha256:0741d101873c12ab927e6f8653feb8862b9bd58771177acb1b885b95141f91b4

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
