#!/bin/bash

# Test script for GPU Pilot Auto-Scaler
# This script helps test the scaling functionality

set -e

SCALER_URL="http://localhost:5000"
SECRET_TOKEN="${SCALER_SECRET_TOKEN:-your-secret-token-here}"

echo "🧪 GPU Pilot Test Script"
echo "========================"

# Function to make authenticated requests
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        curl -s -X POST \
            -H "Authorization: Bearer $SECRET_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$SCALER_URL$endpoint"
    else
        curl -s -X GET \
            -H "Authorization: Bearer $SECRET_TOKEN" \
            "$SCALER_URL$endpoint"
    fi
}

# Test 1: Health check
echo "🏥 Testing health endpoint..."
response=$(make_request GET "/health")
if echo "$response" | grep -q "healthy"; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed: $response"
    exit 1
fi

# Test 2: Scale up
echo "📈 Testing scale up..."
response=$(make_request POST "/scale" '{"action": "scale_up"}')
if echo "$response" | grep -q "accepted"; then
    echo "✅ Scale up request accepted"
else
    echo "❌ Scale up failed: $response"
fi

sleep 5

# Test 3: Check status
echo "📊 Checking status..."
response=$(make_request GET "/status")
echo "Status response: $response"

# Test 4: Scale down (after a delay)
echo "⏳ Waiting 30 seconds before scale down test..."
sleep 30

echo "📉 Testing scale down..."
response=$(make_request POST "/scale" '{"action": "scale_down"}')
if echo "$response" | grep -q "accepted"; then
    echo "✅ Scale down request accepted"
else
    echo "❌ Scale down failed: $response"
fi

echo ""
echo "🎉 Test completed!"
echo "Check the logs for detailed information:"
echo "  sudo journalctl -u gpu-scaler -f"
