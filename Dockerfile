# Use an official Python runtime as a parent image
FROM python:alpine

# Set working directory
WORKDIR /app

# Copy requirements and install
COPY event_updater/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy code
COPY event_updater/ ./

# Serve on port 8080 by default
ENV PORT=8080

# Startup command
CMD ["python", "main.py"]
