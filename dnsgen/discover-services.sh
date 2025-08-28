#!/bin/sh

# Configuration from environment variables
INTERVAL=${DISCOVERY_INTERVAL:-30}
HOSTS_FILE=${HOSTS_FILE:-/shared/hosts}
DOMAIN_SUFFIX=${DOMAIN_SUFFIX:-.local}  # Default to .local, but configurable

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to add host entry if it doesn't exist
add_host_entry() {
    local ip="$1"
    local hostname="$2"
    local entry="$ip $hostname"
    
    # Check if this exact entry already exists
    if ! grep -Fxq "$entry" "$HOSTS_FILE"; then
        echo "$entry" >> "$HOSTS_FILE"
        log "Added: $entry"
        return 0
    else
        log "Skipped duplicate: $entry"
        return 1
    fi
}

discover_services() {
    log "Starting service discovery..."
    
    # Create base hosts file (always recreate to avoid accumulating duplicates)
    cat > "$HOSTS_FILE" << EOF
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
EOF

    # Create temporary file to track all discovered services
    TEMP_HOSTS=$(mktemp)
    
    # Auto-detect network and discover services
    CONTAINER_ID=$(hostname)
    NETWORK_NAME=$(docker inspect "$CONTAINER_ID" --format='{{range $name, $conf := .NetworkSettings.Networks}}{{if ne $name "bridge"}}{{$name}}{{end}}{{end}}' 2>/dev/null | head -1)
    
    if [ ! -z "$NETWORK_NAME" ]; then
        log "Auto-detected network: $NETWORK_NAME"
        log "Discovering services in network: $NETWORK_NAME"
        
        docker network inspect "$NETWORK_NAME" --format='{{range .Containers}}{{.Name}} {{index .IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null | while IFS= read -r line; do
            if [ ! -z "$line" ]; then
                name=$(echo "$line" | awk '{print $1}')
                ip=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
                
                # Skip self
                if [ "$name" != "$(hostname)" ] && [ ! -z "$ip" ]; then
                    # Add full container name with domain suffix
                    echo "$ip $name$DOMAIN_SUFFIX" >> "$TEMP_HOSTS"
                    
                    # Add short name (remove project prefix and instance suffix)
                    short_name=$(echo "$name" | sed 's/^[^-]*-//g' | sed 's/-[0-9]*$//')
                    if [ "$short_name" != "$name" ]; then
                        echo "$ip $short_name$DOMAIN_SUFFIX" >> "$TEMP_HOSTS"
                    fi
                fi
            fi
        done
    else
        log "No custom network detected, skipping network discovery"
    fi

    # Remove duplicates and append to hosts file
    if [ -f "$TEMP_HOSTS" ]; then
        # Sort and remove duplicate lines, then append to hosts file
        sort "$TEMP_HOSTS" | uniq | while read -r line; do
            if [ ! -z "$line" ]; then
                ip=$(echo "$line" | awk '{print $1}')
                hostname=$(echo "$line" | awk '{print $2}')
                add_host_entry "$ip" "$hostname"
            fi
        done
        rm "$TEMP_HOSTS"
    fi

    log "Service discovery completed. Found $(grep -c "$DOMAIN_SUFFIX" "$HOSTS_FILE") services."
}

# Main loop
log "DNS Generator starting..."
log "Interval: ${INTERVAL}s, Hosts file: $HOSTS_FILE, Domain: $DOMAIN_SUFFIX"

while true; do
    discover_services
    log "Sleeping for ${INTERVAL} seconds..."
    sleep "$INTERVAL"
done
