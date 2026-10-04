# Purpose: Production-grade container image definition for ApexFin Banking Portal.
# Architecture/Context: Containerized deployment target for Google Cloud Run and GKE.
# Dependencies/Side Effects: Base image python:3.11-slim; exposes port 5000.

FROM python:3.11-slim

# Install system utilities (including iputils-ping required for network gateway diagnostics)
RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency definition and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Seed initial SQLite database
RUN python database.py

# Set environment variables
ENV PORT=5000 \
    HOST=0.0.0.0 \
    FLASK_ENV=production \
    PYTHONUNBUFFERED=1

EXPOSE 5000

# Run with Gunicorn WSGI server for production resilience
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--timeout", "60", "app:app"]
