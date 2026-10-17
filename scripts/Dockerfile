# checkov:skip=CKV_DOCKER_2: Runs as a CronJob that exits when done, so there is nothing to health-check
FROM python:3.15-slim@sha256:f48fda6d59b2b3437781d1c3ccf4aa0e26ae871de3cdd758b49ab45ee7291619

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
