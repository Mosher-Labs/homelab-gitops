FROM python:3.14-slim

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

ENTRYPOINT ["python", "/app/sync-tplink-devices.py"]
