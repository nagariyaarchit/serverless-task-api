# lambda_function.py
import os
import json
import base64
import boto3

# reuse across invocations
TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

def _resp(status, payload=None):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": "" if status == 204 else json.dumps(payload or {}, default=str),
    }

def _parse_body(event):
    body = event.get("body")
    if body is None:
        return None
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    try:
        return json.loads(body)
    except Exception:
        return body  # not JSON

def handler(event, context):
    method   = event.get("httpMethod")
    resource = event.get("resource")
    pathp    = event.get("pathParameters") or {}
    query    = event.get("queryStringParameters") or {}

    print(f"method={method} resource={resource} pathp={pathp} query={query}")

    # -------- GET /tasks (list; paged) --------
    if resource == "/tasks" and method == "GET":
        scan_args = {}
        # optional pagination
        if "limit" in query:
            try:
                n = int(query["limit"])
                if 1 <= n <= 500:
                    scan_args["Limit"] = n
            except Exception:
                pass
        if "startKey" in query:
            try:
                scan_args["ExclusiveStartKey"] = json.loads(query["startKey"])
            except Exception:
                return _resp(400, {"error": "invalid startKey"})

        resp = table.scan(**scan_args)
        out = {"items": resp.get("Items", [])}
        lek = resp.get("LastEvaluatedKey")
        if lek:
            out["lastKey"] = lek
        return _resp(200, out)

    # -------- item routes: /tasks/{taskId} --------
    if resource == "/tasks/{taskId}":
        task_id = pathp.get("taskId")
        if not task_id:
            return _resp(400, {"error": "missing taskId"})

        if method == "GET":
            got = table.get_item(Key={"taskId": task_id}).get("Item")
            return _resp(200, got) if got else _resp(404, {"error": "not found"})

        if method == "PUT":
            body = _parse_body(event)
            if not isinstance(body, dict):
                return _resp(400, {"error": "body must be JSON object"})
            body["taskId"] = task_id  # path wins
            table.put_item(Item=body) # replace semantics (idempotent)
            return _resp(200, body)

        if method == "DELETE":
            table.delete_item(Key={"taskId": task_id})
            return _resp(204)

        return _resp(405, {"error": "method not allowed"})

    # unknown route
    return _resp(404, {"error": "not found"})

# if you accidentally configured Terraform with lambda_handler earlier, this keeps both working
lambda_handler = handler
