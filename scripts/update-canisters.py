import os
import json

JSON_FILE = "src/frontend/src/our-canisters.json"

try:
    j = json.load(JSON_FILE)
except:
    j = {}

for k in os.environ.keys():
    j[k] = os.environ[k]

with open(JSON_FILE, 'w') as f:
    json.dump(j, f)
