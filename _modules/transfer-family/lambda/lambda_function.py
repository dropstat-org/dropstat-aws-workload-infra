"""
AWS Transfer Family — Custom Identity Provider via Lambda.
Authenticates SFTP users against credentials stored in Secrets Manager.

Secret format (key: {serverId}/{username}):
  {
    "Password":             "...",          # plaintext password
    "Role":                 "arn:aws:iam::...:role/...",
    "HomeDirectory":        "/bucket/username",   # simple path
    "HomeDirectoryDetails": "[{\"Entry\":\"/\",\"Target\":\"/bucket/username\"}]",  # logical (virtual folders)
    "PublicKey":            "ssh-rsa AAAA...",    # for SSH key auth
    "AcceptedIpNetwork":    "10.0.0.0/8"          # optional IP filter
  }

Protocol-prefixed keys take precedence: SFTPPassword > Password
"""
import os
import json
import base64
import boto3
from ipaddress import ip_network, ip_address
from botocore.exceptions import ClientError


def lambda_handler(event, context):
    required = ["serverId", "username", "protocol", "sourceIp"]
    for p in required:
        if p not in event:
            print(f"Incoming {p} missing - Unexpected")
            return {}

    server_id   = event["serverId"]
    username    = event["username"]
    protocol    = event["protocol"]
    source_ip   = event["sourceIp"]
    password    = event.get("password", "")

    print(f"ServerId: {server_id}, Username: {username}, Protocol: {protocol}, SourceIp: {source_ip}")

    auth_type = "PASSWORD" if password else "SSH"
    if not password:
        if protocol in ("FTP", "FTPS"):
            print("Empty password not allowed for FTP/S")
            return {}
        print("Using SSH authentication")
        auth_type = "SSH"
    else:
        print("Using PASSWORD authentication")

    secret = get_secret(f"{server_id}/{username}")
    if secret is None:
        print("Secret not found - returning empty response")
        return {}

    secret_dict = json.loads(secret)

    if not authenticate_user(auth_type, secret_dict, password, protocol):
        print("Authentication failed")
        return {}

    if not check_ipaddress(secret_dict, source_ip, protocol):
        print("IP check failed")
        return {}

    print(f"User authenticated via {auth_type}")
    return build_response(secret_dict, auth_type, protocol)


def lookup(d, key, protocol):
    """Protocol-prefixed key takes precedence (e.g. SFTPPassword > Password)."""
    prefixed = protocol + key
    return d[prefixed] if prefixed in d else d.get(key)


def authenticate_user(auth_type, secret_dict, password, protocol):
    if auth_type == "SSH":
        return True
    stored_password = lookup(secret_dict, "Password", protocol)
    if not stored_password:
        print("No password field in secret")
        return False
    return password == stored_password


def check_ipaddress(secret_dict, source_ip, protocol):
    network = lookup(secret_dict, "AcceptedIpNetwork", protocol)
    if not network:
        return True
    return ip_address(source_ip) in ip_network(network)


def build_response(secret_dict, auth_type, protocol):
    response = {}

    role = lookup(secret_dict, "Role", protocol)
    response["Role"] = role if role else ""

    policy = lookup(secret_dict, "Policy", protocol)
    if policy:
        response["Policy"] = policy

    home_details = lookup(secret_dict, "HomeDirectoryDetails", protocol)
    if home_details:
        response["HomeDirectoryDetails"] = home_details
        response["HomeDirectoryType"] = "LOGICAL"
    else:
        home_dir = lookup(secret_dict, "HomeDirectory", protocol)
        if home_dir:
            response["HomeDirectory"] = home_dir

    if auth_type == "SSH":
        pub_key = lookup(secret_dict, "PublicKey", protocol)
        if not pub_key:
            print("SSH auth but no public key in secret")
            return {}
        response["PublicKeys"] = [pub_key]

    return response


def get_secret(secret_id):
    region = os.environ["SecretsManagerRegion"]
    print(f"Fetching secret: {secret_id}")
    client = boto3.client("secretsmanager", region_name=region)
    try:
        resp = client.get_secret_value(SecretId=secret_id)
        return resp.get("SecretString") or base64.b64decode(resp["SecretBinary"])
    except ClientError as e:
        print(f"SecretsManager error: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
        return None
