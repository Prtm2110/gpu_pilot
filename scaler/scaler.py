#!/usr/bin/env python3
"""GPU Pilot Scaler Service.

Automated GPU scaling service that responds to Prometheus alerts
and manages AWS Auto Scaling Groups via Terraform.
"""

from flask import Flask, request, jsonify
import subprocess
import os
import sys
import logging
import json
from datetime import datetime
import threading
import time
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.FileHandler("/var/log/gpu-scaler.log"), logging.StreamHandler()],
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
SCRIPT_DIR = Path(__file__).resolve().parent
TERRAFORM_DIR = os.environ.get(
    "TERRAFORM_DIR", str(SCRIPT_DIR.parent / "terraform-scale")
)
SECRET_TOKEN = os.environ.get("SCALER_SECRET_TOKEN", "your-secret-token-here")
COOLDOWN_PERIOD = int(os.environ.get("COOLDOWN_PERIOD", "300"))

# Track last scale operation
last_scale_time = {}


def run_command(cmd, timeout=600, cwd=None):
    """Run a subprocess command with error handling.

    Args:
        cmd: Command list to execute
        timeout: Timeout in seconds
        cwd: Working directory

    Returns:
        Tuple of (success: bool, output: str, stderr: str)
    """
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        error_msg = f"Command timed out after {timeout} seconds"
        logger.error(error_msg)
        return False, "", error_msg
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Command execution error: {error_msg}")
        return False, "", error_msg


def run_terraform_command(action, scale_up):
    """Run terraform command with proper error handling.

    Args:
        action: Either 'apply' or 'destroy'
        scale_up: Boolean indicating scale direction

    Returns:
        Tuple of (success: bool, output: str)
    """
    if not os.path.exists(TERRAFORM_DIR):
        error_msg = f"Terraform directory does not exist: {TERRAFORM_DIR}"
        logger.error(error_msg)
        return False, error_msg

    # Prepare terraform command
    if action == "apply":
        cmd = [
            "terraform",
            "apply",
            "-auto-approve",
            "-var",
            f"scale_up={str(scale_up).lower()}",
        ]
    elif action == "destroy":
        cmd = ["terraform", "destroy", "-auto-approve"]
    else:
        return False, f"Unknown action: {action}"

    logger.info(f"Running command: {' '.join(cmd)}")
    success, stdout, stderr = run_command(cmd, timeout=600, cwd=TERRAFORM_DIR)

    if success:
        logger.info(f"Terraform {action} completed successfully")
        return True, stdout
    else:
        logger.error(f"Terraform {action} failed: {stderr}")
        return False, stderr


def check_cooldown(action):
    """Check if we're in cooldown period for the given action.

    Args:
        action: The scaling action to check

    Returns:
        Tuple of (can_proceed: bool, cooldown_remaining: float)
    """
    current_time = time.time()
    if action in last_scale_time:
        time_since_last = current_time - last_scale_time[action]
        if time_since_last < COOLDOWN_PERIOD:
            return False, COOLDOWN_PERIOD - time_since_last
    return True, 0


def authenticate_request(req):
    """Validate bearer token authentication.

    Args:
        req: Flask request object

    Returns:
        Boolean indicating if request is authenticated
    """
    auth_header = req.headers.get("Authorization")
    if not auth_header:
        return False

    try:
        parts = auth_header.split(" ")
        if len(parts) != 2 or parts[0] != "Bearer":
            return False
        token = parts[1]
        return token == SECRET_TOKEN
    except (IndexError, AttributeError):
        return False


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    return (
        jsonify(
            {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "terraform_dir": TERRAFORM_DIR,
                "version": "1.0.0",
            }
        ),
        200,
    )


@app.route("/scale", methods=["POST"])
def scale():
    """Main scaling endpoint triggered by Prometheus alerts."""
    try:
        # Authenticate request
        if not authenticate_request(request):
            logger.warning(f"Unauthorized access attempt from {request.remote_addr}")
            return jsonify({"error": "Unauthorized"}), 401

        # Parse request data
        data = request.get_json(silent=True)
        if not data:
            return jsonify({"error": "Invalid JSON or no data provided"}), 400

        action = data.get("action", "").lower()
        logger.info(f"Received scale request: {action} from {request.remote_addr}")

        # Determine scale operation
        if action == "scale_up":
            scale_up = True
            terraform_action = "apply"
        elif action == "scale_down":
            scale_up = False
            terraform_action = (
                "apply"  # We use apply with scale_up=false instead of destroy
            )
        else:
            return jsonify({"error": f"Invalid action: {action}"}), 400

        # Check cooldown
        can_proceed, cooldown_remaining = check_cooldown(action)
        if not can_proceed:
            logger.info(
                f"Scale operation {action} blocked by cooldown: {cooldown_remaining:.0f}s remaining"
            )
            return (
                jsonify(
                    {
                        "status": "rejected",
                        "error": "Cooldown period active",
                        "cooldown_remaining_seconds": int(cooldown_remaining),
                    }
                ),
                429,
            )

        # Run terraform in background thread
        def run_terraform():
            success, output = run_terraform_command(terraform_action, scale_up)
            if success:
                last_scale_time[action] = time.time()
                logger.info(f"Scale operation {action} completed successfully")
            else:
                logger.error(f"Scale operation {action} failed: {output}")

        thread = threading.Thread(target=run_terraform)
        thread.daemon = True
        thread.start()

        return (
            jsonify(
                {
                    "status": "accepted",
                    "action": action,
                    "message": f"Scaling operation {action} initiated",
                    "timestamp": datetime.now().isoformat(),
                }
            ),
            202,
        )

    except Exception as e:
        logger.error(f"Error in scale endpoint: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "error": "Internal server error"}), 500


@app.route("/status", methods=["GET"])
def get_status():
    """Get current status of the auto-scaling group."""
    if not authenticate_request(request):
        return jsonify({"error": "Unauthorized"}), 401

    if not os.path.exists(TERRAFORM_DIR):
        return (
            jsonify(
                {
                    "status": "error",
                    "error": f"Terraform directory not found: {TERRAFORM_DIR}",
                }
            ),
            500,
        )

    success, stdout, stderr = run_command(
        ["terraform", "output", "-json"], timeout=30, cwd=TERRAFORM_DIR
    )

    if success:
        try:
            output_data = json.loads(stdout) if stdout else {}
        except json.JSONDecodeError:
            output_data = {}

        return (
            jsonify(
                {
                    "status": "success",
                    "terraform_outputs": output_data,
                    "last_scale_times": last_scale_time,
                    "terraform_dir": TERRAFORM_DIR,
                }
            ),
            200,
        )
    else:
        return (
            jsonify(
                {
                    "status": "error",
                    "error": stderr or "Terraform output command failed",
                }
            ),
            500,
        )


if __name__ == "__main__":
    if SECRET_TOKEN == "your-secret-token-here":
        logger.warning(
            "WARNING: Using default secret token. Set SCALER_SECRET_TOKEN environment variable."
        )

    if not os.path.exists(TERRAFORM_DIR):
        logger.error(f"Terraform directory does not exist: {TERRAFORM_DIR}")
        logger.error(
            "Please set TERRAFORM_DIR environment variable or ensure directory exists."
        )
        sys.exit(1)

    terraform_dir_path = Path(TERRAFORM_DIR)
    if not (terraform_dir_path / ".terraform").exists():
        logger.warning(
            "Terraform not initialized. Run 'terraform init' in the terraform directory."
        )

    success, _, _ = run_command(["terraform", "version"], timeout=10)
    if not success:
        logger.error(
            "Terraform binary not found or not working. Please install Terraform."
        )
        sys.exit(1)

    logger.info("Starting GPU Pilot Scaler Service")
    logger.info(f"Terraform directory: {TERRAFORM_DIR}")
    logger.info(f"Cooldown period: {COOLDOWN_PERIOD} seconds")
    logger.info("Listening on: 0.0.0.0:5000")

    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)
