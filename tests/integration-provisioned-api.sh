#!/usr/bin/env sh
set -eu

api_url=http://pi-app:8080
api_body=$(mktemp)
trap 'rm -f "$api_body"' 0

if [ -z "${PI_ADMIN_USER:-}" ] || [ -z "${PI_ADMIN_PASSWORD:-}" ]; then
    echo "PI_ADMIN_USER and PI_ADMIN_PASSWORD must be set" >&2
    exit 1
fi

api_request() {
    method=$1
    path=$2
    body=${3:-}
    if [ -n "$body" ]; then
        http_status=$(curl --silent --show-error --output "$api_body" --write-out '%{http_code}' \
            --request "$method" --header "PI-Authorization: $api_token" \
            --header 'Content-Type: application/json' --data "$body" "$api_url$path")
    else
        http_status=$(curl --silent --show-error --output "$api_body" --write-out '%{http_code}' \
            --request "$method" --header "PI-Authorization: $api_token" "$api_url$path")
    fi
    if [ "$http_status" -lt 200 ] || [ "$http_status" -ge 300 ] || \
        ! jq -e '.result.status == true' "$api_body" >/dev/null; then
        echo "privacyIDEA API $method $path failed (HTTP $http_status):" >&2
        jq -c . "$api_body" >&2 2>/dev/null || cat "$api_body" >&2
        return 1
    fi
}

echo "Authenticating test runner"
http_status=$(curl --silent --show-error --output "$api_body" --write-out '%{http_code}' \
    --request POST --data-urlencode "username=$PI_ADMIN_USER" \
    --data-urlencode "password=$PI_ADMIN_PASSWORD" "$api_url/auth")
if [ "$http_status" -lt 200 ] || [ "$http_status" -ge 300 ] || \
    ! jq -e '.result.status == true and (.result.value.token | type == "string" and length > 0)' \
        "$api_body" >/dev/null; then
    echo "privacyIDEA admin authentication failed (HTTP $http_status)" >&2
    jq -c . "$api_body" >&2 2>/dev/null || cat "$api_body" >&2
    exit 1
fi
api_token=$(jq -r '.result.value.token' "$api_body")
echo "Admin API authentication succeeded"

resolver=integration-smoke-passwd
realm=integration-smoke-realm
policy=integration-smoke-policy
user=root

echo "Creating and listing passwd resolver"
api_request POST "/resolver/$resolver" '{"type":"passwdresolver","Filename":"/etc/passwd"}'
api_request GET /resolver/
jq -e --arg resolver "$resolver" '.result.value | has($resolver)' "$api_body" >/dev/null || {
    echo "Resolver $resolver was not listed" >&2
    exit 1
}

echo "Creating and listing realm"
api_request POST "/realm/$realm" "{\"resolvers\":[\"$resolver\"]}"
api_request GET /realm/
jq -e --arg realm "$realm" '.result.value | has($realm)' "$api_body" >/dev/null || {
    echo "Realm $realm was not listed" >&2
    exit 1
}

echo "Looking up passwd user in realm"
api_request GET "/user/?realm=$realm&username=$user"
jq -e '.result.value | length > 0' "$api_body" >/dev/null || {
    echo "User $user was not found in realm $realm" >&2
    exit 1
}

echo "Enrolling HOTP token and verifying OTP"
otpkey=3132333435363738393031323334353637383930
api_request POST /token/init \
    "{\"type\":\"hotp\",\"otpkey\":\"$otpkey\",\"otpkeyformat\":\"hex\",\"user\":\"$user\",\"realm\":\"$realm\",\"otplen\":6}"
token_serial=$(jq -r '.detail.serial // empty' "$api_body")
if [ -z "$token_serial" ]; then
    echo "Token enrollment response did not include a serial" >&2
    exit 1
fi
api_request GET "/token/?serial=$token_serial"
jq -e --arg serial "$token_serial" '.. | strings | select(. == $serial)' "$api_body" >/dev/null || {
    echo "Enrolled token $token_serial was not retrievable" >&2
    exit 1
}
otp=$(python3 -c 'import hmac, hashlib
key = bytes.fromhex("3132333435363738393031323334353637383930")
digest = hmac.new(key, (0).to_bytes(8, "big"), hashlib.sha1).digest()
offset = digest[-1] & 0x0f
code = (int.from_bytes(digest[offset:offset + 4], "big") & 0x7fffffff) % 1000000
print(f"{code:06d}")')
http_status=$(curl --silent --show-error --output "$api_body" --write-out '%{http_code}' \
    --request POST --data-urlencode "user=$user" --data-urlencode "realm=$realm" \
    --data-urlencode "pass=$otp" "$api_url/validate/check")
if [ "$http_status" -lt 200 ] || [ "$http_status" -ge 300 ] || \
    ! jq -e '.result.status == true and .result.value == true' "$api_body" >/dev/null; then
    echo "HOTP validation failed (HTTP $http_status):" >&2
    jq -c . "$api_body" >&2 2>/dev/null || cat "$api_body" >&2
    exit 1
fi
echo "HOTP token validated successfully"

echo "Creating and listing user policy"
api_request POST "/policy/$policy" \
    "{\"scope\":\"user\",\"action\":\"\",\"realm\":\"$realm\",\"description\":\"Integration smoke policy\"}"
api_request GET /policy/
jq -e --arg policy "$policy" \
    '.result.value | if type == "object" then has($policy) else any(.[]; .name == $policy) end' \
    "$api_body" >/dev/null || {
    echo "Policy $policy was not listed" >&2
    exit 1
}
echo "Resolver, realm, user, token, OTP, and policy checks passed"
