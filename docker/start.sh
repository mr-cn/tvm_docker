#!/bin/bash

# Help function
function show_help {
    echo "Usage: ./docker/start.sh [IMAGE_NAME] [CONTAINER_NAME] [PORT]"
    echo ""
    echo "Arguments:"
    echo "  IMAGE_NAME      Docker image to run (default: tvm.demo_cpu:latest)"
    echo "                  If you want GPU, use 'tvm.demo_gpu:latest' (or just 'demo_gpu')"
    echo "  CONTAINER_NAME  Name for the container (default: tvm_demo)"
    echo "  PORT            Host port for Jupyter Lab (default: 8888)"
    echo ""
    echo "Example:"
    echo "  ./docker/start.sh demo_cpu"
    echo "  ./docker/start.sh demo_gpu my_tvm 9999"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Defaults
IMAGE_NAME="${1:-tvm.demo_cpu:latest}"
CONTAINER_NAME="${2:-tvm_demo}"
PORT="${3:-8888}"

# Handle short names
if [[ "$IMAGE_NAME" == "demo_cpu" ]]; then
    IMAGE_NAME="tvm.demo_cpu:latest"
elif [[ "$IMAGE_NAME" == "demo_gpu" ]]; then
    IMAGE_NAME="tvm.demo_gpu:latest"
fi

# Detect GPU requirement
GPU_FLAGS=""
if [[ "$IMAGE_NAME" == *"gpu"* ]]; then
    echo "Detected GPU image, enabling GPU support..."
    GPU_FLAGS="--gpus all"
fi

# Get current user info for ownership mapping
# If running with sudo, use the original user's ID/GID to ensure file ownership on host is correct
if [ -n "$SUDO_UID" ]; then
    USER_ID="$SUDO_UID"
    GROUP_ID="$SUDO_GID"
    USER_NAME="$SUDO_USER"
    # Attempt to get the group name of the sudo user, fall back to 'root' or whatever if fails
    GROUP_NAME=$(id -gn "$SUDO_USER" 2>/dev/null || echo "users")
else
    USER_ID=$(id -u)
    GROUP_ID=$(id -g)
    USER_NAME=$(whoami)
    GROUP_NAME=$(id -g -n)
fi

# Define the command to run inside the container
# We use the existing 'with_the_same_user' script to switch from root to the host user
# This ensures files created in /workspace are owned by the host user.
# Note: We must point to the script location inside the container (/opt/tvm/docker/...)
CMD_ARGS=(
    bash /opt/tvm/docker/with_the_same_user
    jupyter lab
    --ip=0.0.0.0
    --no-browser
    --IdentityProvider.token=''
    --ServerApp.password=''
    --notebook-dir=/workspace
)

echo "Starting TVM container..."
echo "  Image: $IMAGE_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Port: $PORT"
echo "  Workspace: $(pwd) -> /workspace"

# Run docker command (using arrays to handle arguments cleanly)
# We set CI_BUILD_HOME to /workspace so the user's home matches the mount
DOCKER_CMD=(
    docker run -d
    --name "$CONTAINER_NAME"
    --restart always
    $GPU_FLAGS
    -p "$PORT":8888
    -v "$(pwd)":/workspace
    -e CI_BUILD_UID="$USER_ID"
    -e CI_BUILD_GID="$GROUP_ID"
    -e CI_BUILD_USER="$USER_NAME"
    -e CI_BUILD_GROUP="$GROUP_NAME"
    -e HOME="/workspace"
    -e CI_BUILD_HOME="/workspace"
    "$IMAGE_NAME"
    "${CMD_ARGS[@]}"
)

# Execute the command
"${DOCKER_CMD[@]}"

if [ $? -eq 0 ]; then
    echo ""
    echo "Success! Jupyter Lab is running."
    echo "Access it at: http://localhost:$PORT"
    echo "To stop: docker stop $CONTAINER_NAME"
    echo "To logs: docker logs $CONTAINER_NAME"
else
    echo "Failed to start container."
fi