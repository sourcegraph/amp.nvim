#!/bin/bash

# Test script to see what amp --stream-json outputs
# This will show you exactly what the plugin receives

echo "====== Testing amp --stream-json output ======"
echo ""
echo "Command: amp --execute \"say hello\" --stream-json"
echo ""
echo "====== RAW OUTPUT ======"
amp --execute "say hello" --stream-json 2>&1
echo ""
echo ""
echo "====== OUTPUT WITH JQ (formatted) ======"
amp --execute "say hello" --stream-json 2>&1 | jq -c '.'
echo ""
echo ""
echo "====== ASSISTANT MESSAGE ONLY ======"
amp --execute "say hello" --stream-json 2>&1 | jq -r 'select(.type == "assistant") | .message.content[] | select(.type == "text") | .text'
