FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    docker-cli \
    jq \
    curl \
    bind-tools

# Create app directory
WORKDIR /app

# Copy the discovery script
COPY discover-services.sh /app/discover-services.sh
RUN chmod +x /app/discover-services.sh

# Set default environment variables
ENV DISCOVERY_INTERVAL=30
ENV HOSTS_FILE=/shared/hosts
ENV NETWORK_NAME=""
ENV PROJECT_NAME=""

# Run the discovery script
CMD ["/app/discover-services.sh"]
