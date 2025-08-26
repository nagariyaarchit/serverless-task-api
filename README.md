# Serverless Task API (Terraform + AWS Lambda + API Gateway + DynamoDB)

A minimal, production-shaped serverless CRUD API for **tasks**, provisioned end-to-end with **Terraform**.  
Runtime: **Python 3.12** on AWS Lambda, exposed via **API Gateway (REST)**, persisted in **DynamoDB**.

> TL;DR: `terraform apply` → call the endpoints → list/read/create-or-replace/delete with proper status codes.

---

## What this project is (short)

- Terraform creates:
  - a DynamoDB table: `Tasks-dev`
  - an IAM role + custom policy for Lambda (DynamoDB + CloudWatch Logs)
  - a Python Lambda function (ZIP packaged from local source)
  - API Gateway REST API with routes for listing and item operations
  - a `dev` stage + deployment
- Lambda implements:
  - **GET `/tasks`** → list (DynamoDB `Scan`, paginatable)
  - **GET `/tasks/{taskId}`** → read one
  - **PUT `/tasks/{taskId}`** → create/replace one (idempotent)
  - **DELETE `/tasks/{taskId}`** → delete one

> Note: There’s **no POST** route here; “create” is done with **PUT** at a known `taskId`.

---

## What this project is (in depth)

### Architecture (Terraform)

- **DynamoDB**
  - Table: **`Tasks-dev`**
  - PK: `taskId` (String)
  - TTL on `expireAt` (expects **Unix epoch seconds**)

- **IAM**
  - Execution role for Lambda
  - Custom policy with: `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Scan`
  - AWS managed: `service-role/AWSLambdaBasicExecutionRole` for logs

- **Lambda (Python 3.12)**
  - Handler: `lambda_function.handler`
  - Env var: `TABLE_NAME=Tasks-dev` (wired from Terraform)
  - Packaged via `data "archive_file"` from local source

- **API Gateway (REST)**
  - Resources:
    - `/tasks` with **GET**
    - `/tasks/{taskId}` with **GET**, **PUT**, **DELETE**
  - AWS_PROXY integration to the Lambda
  - Deployed + staged as **`dev`**

### Why PUT for create?

- **PUT** to `/tasks/{taskId}` is idempotent → same request ⇒ same final state.  
- If you later want server-generated IDs, add **POST** `/tasks` and keep PUT for replace.

---

## Project structure

.
├─ main.tf / variables.tf / outputs.tf
├─ lambda_py/
│ └─ lambda_function.py
├─ build/
│ └─ lambda.zip # generated
├─ README.md
└─ .gitignore

**Suggested `.gitignore`:**
Terraform
.terraform/
*.tfstate
.tfstate.
crash.log
terraform.tfvars
override.tf
override.tf.json
*_override.tf
*_override.tf.json

Build artifacts
build/
*.zip

Python
pycache/
.venv/

---

## Getting started

### Prerequisites

- Terraform ≥ 1.5
- AWS credentials that can create the above resources
- Region set (e.g., `us-east-1`)

### Configure variables

Use a simple `terraform.tfvars` (literals only):

```hcl
region       = "us-east-1"
billing_mode = "PAY_PER_REQUEST"
source_dir   = "lambda_py"
output_path  = "build/lambda.zip"
Create the build folder:

bash
Copy code
mkdir -p build
Deploy
bash
Copy code
terraform init
terraform apply
Terraform outputs (minimal, copy-paste ready):

api_base_url

tasks_collection_url

task_item_url_template

API
Base URL (example):
https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev

List tasks
GET /tasks
200 OK

json
Copy code
{
  "items": [
    { "taskId": "demo-1", "title": "first task", "done": false }
  ],
  "lastKey": { "...": "..." }  // present only if more pages exist
}
Pagination (optional): ?limit=50&startKey=<url-encoded json from lastKey>

Read one
GET /tasks/{taskId}
200 OK

json
Copy code
{ "taskId": "demo-1", "title": "first task", "done": false }
404 Not Found if missing.

Create/replace one
PUT /tasks/{taskId}
Body: JSON object representing the task (the taskId from path wins).
200 OK (replace) or 201 Created (if you choose to return it that way).

Delete one
DELETE /tasks/{taskId}
204 No Content

Quick test (curl)
bash
Copy code
# Replace <API_ID>/<REGION> or copy URLs from Terraform outputs

# Create/replace
curl -i -X PUT -H 'Content-Type: application/json' \
  -d '{"title":"first task","done":false}' \
  "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/tasks/demo-1"

# Read one
curl -i "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/tasks/demo-1"

# List
curl -i "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/tasks"

# Delete
curl -i -X DELETE "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/tasks/demo-1"
Implementation notes & gotchas
Event fields (REST proxy):
httpMethod, resource, path, pathParameters, queryStringParameters, headers, body, isBase64Encoded, requestContext.*

DynamoDB numbers are Decimal → convert/stringify when returning JSON.

TTL: write expireAt as epoch seconds; expired items may linger briefly until TTL sweeper removes them.

Scan limits: ~1 MB/page; return lastKey for pagination. API Gateway response max ~10 MB.

CORS (if calling from a browser): add Access-Control-Allow-Origin (and friends) in Lambda responses, or add OPTIONS MOCK methods.

Least privilege: the Lambda policy covers basic ops; drop unused actions. If you add GSIs + queries later, include ".../index/*" ARNs and dynamodb:Query.

Reflections
This took ~5 days end-to-end: reading Terraform docs to model resources correctly, deploying reliably, then learning Python’s AWS SDK for DynamoDB—operations mapping, pagination, and JSON serialization quirks. After wiring everything, I deployed and verified with live API calls. It works.

Future improvements
Add POST /tasks (server-generated IDs) and PATCH for partial updates.

Switch from table-wide Scan to Query on a GSI (e.g., userId or status).

Add auth (Cognito/JWT authorizer), per-route throttling, and request validation.

Structured logs + log retention via Terraform.

CI/CD (lint/test, build ZIP, terraform plan/apply) via GitHub Actions.
