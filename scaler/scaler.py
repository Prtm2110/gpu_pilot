from flask import Flask, request, jsonify
import subprocess
import os
import logging
import json
from datetime import datetime
import threading
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/gpu-scaler.log'),
        logging.StreamHandler()
    ]
)

app = Flask(__name__)

# Configuration
TERRAFORM_DIR = "/home/lord_grivous/Desktop/personal_projects/gpu_pilot/terraform-scale"
SECRET_TOKEN = os.environ.get('SCALER_SECRET_TOKEN', 'your-secret-token-here')
COOLDOWN_PERIOD = 300  # 5 minutes between scale operations

# Track last scale operation
last_scale_time = {}

def run_terraform_command(action, scale_up):
    """Run terraform command with proper error handling"""
    try:
        # Change to terraform directory
        os.chdir(TERRAFORM_DIR)
        
        # Prepare terraform command
        if action == 'apply':
            cmd = [
                "terraform", "apply",
                "-auto-approve",
                "-var", f"scale_up={str(scale_up).lower()}"
            ]
        elif action == 'destroy':
            cmd = [
                "terraform", "destroy",
                "-auto-approve"
            ]
        else:
            raise ValueError(f"Unknown action: {action}")
        
        logging.info(f"Running command: {' '.join(cmd)}")
        
        # Run terraform command
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )
        
        if result.returncode == 0:
            logging.info(f"Terraform {action} completed successfully")
            logging.info(f"Output: {result.stdout}")
            return True, result.stdout
        else:
            logging.error(f"Terraform {action} failed with return code {result.returncode}")
            logging.error(f"Error: {result.stderr}")
            return False, result.stderr
            
    except subprocess.TimeoutExpired:
        logging.error(f"Terraform {action} timed out")
        return False, "Command timed out"
    except Exception as e:
        logging.error(f"Error running terraform {action}: {str(e)}")
        return False, str(e)

def check_cooldown(action):
    """Check if we're in cooldown period for the given action"""
    current_time = time.time()
    if action in last_scale_time:
        time_since_last = current_time - last_scale_time[action]
        if time_since_last < COOLDOWN_PERIOD:
            return False, COOLDOWN_PERIOD - time_since_last
    return True, 0

def authenticate_request(request):
    """Simple token-based authentication"""
    auth_header = request.headers.get('Authorization')
    if not auth_header:
        return False
    
    try:
        token = auth_header.split('Bearer ')[1]
        return token == SECRET_TOKEN
    except (IndexError, AttributeError):
        return False

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'terraform_dir': TERRAFORM_DIR
    }), 200

@app.route('/scale', methods=['POST'])
def scale():
    """Main scaling endpoint"""
    try:
        # Authenticate request
        if not authenticate_request(request):
            logging.warning(f"Unauthorized access attempt from {request.remote_addr}")
            return jsonify({'error': 'Unauthorized'}), 401
        
        # Parse request data
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        action = data.get('action', '').lower()
        logging.info(f"Received scale request: {action}")
        
        # Determine scale operation
        if action == 'scale_up':
            scale_up = True
            terraform_action = 'apply'
        elif action == 'scale_down':
            scale_up = False
            terraform_action = 'apply'  # We use apply with scale_up=false instead of destroy
        else:
            return jsonify({'error': f'Invalid action: {action}'}), 400
        
        # Check cooldown
        can_proceed, cooldown_remaining = check_cooldown(action)
        if not can_proceed:
            logging.info(f"Scale operation {action} blocked by cooldown: {cooldown_remaining:.0f}s remaining")
            return jsonify({
                'error': 'Cooldown period active',
                'cooldown_remaining': cooldown_remaining
            }), 429
        
        # Run terraform in background thread
        def run_terraform():
            success, output = run_terraform_command(terraform_action, scale_up)
            if success:
                last_scale_time[action] = time.time()
                logging.info(f"Scale operation {action} completed successfully")
            else:
                logging.error(f"Scale operation {action} failed: {output}")
        
        thread = threading.Thread(target=run_terraform)
        thread.daemon = True
        thread.start()
        
        return jsonify({
            'status': 'accepted',
            'action': action,
            'timestamp': datetime.now().isoformat()
        }), 202
        
    except Exception as e:
        logging.error(f"Error in scale endpoint: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/status', methods=['GET'])
def get_status():
    """Get current status of the auto-scaling group"""
    try:
        # Authenticate request
        if not authenticate_request(request):
            return jsonify({'error': 'Unauthorized'}), 401
        
        # Get terraform output
        os.chdir(TERRAFORM_DIR)
        result = subprocess.run(
            ["terraform", "output", "-json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            output_data = json.loads(result.stdout)
            return jsonify({
                'status': 'success',
                'terraform_outputs': output_data,
                'last_scale_times': last_scale_time
            }), 200
        else:
            return jsonify({
                'status': 'error',
                'error': result.stderr
            }), 500
            
    except Exception as e:
        logging.error(f"Error getting status: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

if __name__ == "__main__":
    # Ensure terraform directory exists
    if not os.path.exists(TERRAFORM_DIR):
        logging.error(f"Terraform directory does not exist: {TERRAFORM_DIR}")
        exit(1)
    
    # Check if terraform is initialized
    if not os.path.exists(os.path.join(TERRAFORM_DIR, ".terraform")):
        logging.warning("Terraform not initialized. Run 'terraform init' first.")
    
    logging.info(f"Starting GPU Scaler service")
    logging.info(f"Terraform directory: {TERRAFORM_DIR}")
    logging.info(f"Cooldown period: {COOLDOWN_PERIOD} seconds")
    
    # Run Flask app
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=False,
        threaded=True
    )
