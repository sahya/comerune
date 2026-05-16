#!/usr/bin/env bash
set -euo pipefail

# Upload a release APK to a PRIVATE S3 bucket under an unguessable key and
# print a time-limited presigned download URL for sharing with specific
# people only.
#
# Why this shape:
#   - The bucket stays fully private (no public bucket policy, no public
#     ACL). Access is granted solely by the signed query string in the
#     presigned URL, which expires on its own. This is the "quietly share
#     with specific people, temporarily" model.
#   - The object key embeds a random token so that even if bucket settings
#     ever change, the object is not at a predictable path (defense in
#     depth on top of the signature).
#   - Sign with a dedicated least-privilege IAM user (s3:PutObject +
#     s3:GetObject on this prefix only), NOT an admin/root key. Disabling
#     that user's key instantly revokes every outstanding presigned URL
#     without touching anything else.
#
# Required environment:
#   S3_BUCKET                 target private bucket name
#   AWS_ACCESS_KEY_ID         } credentials of the dedicated least-privilege
#   AWS_SECRET_ACCESS_KEY     } IAM user (passed via env, never committed)
#
# Optional environment:
#   AWS_REGION                bucket region (passed to aws --region)
#   APK_PATH                  default: build/app/outputs/flutter-apk/app-release.apk
#   S3_PREFIX                 default: apk
#   URL_EXPIRY                presigned lifetime in seconds. Default and
#                             SigV4 maximum: 604800 (7 days).
#
# Nothing here is written to disk and no secret is echoed. The presigned
# URL itself is a bearer credential: anyone who has it can download until
# it expires. Treat it accordingly (no public chat, no link-preview
# surfaces) and run `aws s3 rm` when distribution is done.

readonly SIGV4_MAX_EXPIRY=604800

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

err() {
  echo "[distribute-apk-s3] error: $*" >&2
  exit 1
}

command -v aws >/dev/null 2>&1 \
  || err "AWS CLI not found. Install it (https://docs.aws.amazon.com/cli/) — it is required to upload and to generate the presigned URL."

command -v openssl >/dev/null 2>&1 \
  || err "openssl not found. It is required to generate the unguessable object key."

: "${S3_BUCKET:?Set S3_BUCKET to the private destination bucket}"
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID (dedicated least-privilege IAM user, not admin/root)}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY (dedicated least-privilege IAM user, not admin/root)}"

apk_path="${APK_PATH:-build/app/outputs/flutter-apk/app-release.apk}"
s3_prefix="${S3_PREFIX:-apk}"
url_expiry="${URL_EXPIRY:-$SIGV4_MAX_EXPIRY}"

[[ "$url_expiry" =~ ^[0-9]+$ ]] \
  || err "URL_EXPIRY must be a positive integer (seconds), got: ${url_expiry}"
(( url_expiry > 0 )) \
  || err "URL_EXPIRY must be greater than 0"
(( url_expiry <= SIGV4_MAX_EXPIRY )) \
  || err "URL_EXPIRY exceeds the SigV4 presigned maximum of ${SIGV4_MAX_EXPIRY}s (7 days)"

[[ -f "$apk_path" ]] \
  || err "APK not found at '${apk_path}'. Build it first (e.g. \`make build-release\`) or set APK_PATH."

version="$(awk -F'[:+]' '/^version:/{gsub(/ /,"");print $2;exit}' pubspec.yaml)"
[[ -n "$version" ]] \
  || err "Could not derive version from pubspec.yaml"

# 128-bit random token: the secret part of the path and the filename suffix.
token="$(openssl rand -hex 16)"
key="${s3_prefix}/${token}/comerune-v${version}-${token:0:8}.apk"

region_args=()
[[ -n "${AWS_REGION:-}" ]] && region_args=(--region "$AWS_REGION")

echo "[distribute-apk-s3] uploading ${apk_path} -> s3://${S3_BUCKET}/${key}"

# No public ACL: the bucket is private and access is via the presigned URL
# only. Content-Type/Disposition make browsers download the APK correctly.
aws s3 cp "$apk_path" "s3://${S3_BUCKET}/${key}" \
  "${region_args[@]}" \
  --content-type application/vnd.android.package-archive \
  --content-disposition attachment

presigned_url="$(aws s3 presign "s3://${S3_BUCKET}/${key}" \
  "${region_args[@]}" \
  --expires-in "$url_expiry")"

expires_human="$(date -u -d "@$(( $(date -u +%s) + url_expiry ))" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
  || echo "now + ${url_expiry}s")"

cat <<INFO

[distribute-apk-s3] done.

  Presigned URL (share with specific people ONLY):
    ${presigned_url}

  Expires:  ${expires_human}  (${url_expiry}s)
  Object:   s3://${S3_BUCKET}/${key}

  Revoke immediately (before expiry):
    aws s3 rm "s3://${S3_BUCKET}/${key}"

  Reminders:
    - The URL is a bearer token: anyone who has it can download until it
      expires. Do not paste it into public chats or link-preview surfaces.
    - A full 7-day lifetime only holds when signed with a long-term IAM
      user access key. SSO / STS temporary credentials cap the URL at the
      session token's own (much shorter) expiry.
    - Add an S3 lifecycle rule on the "${s3_prefix}/" prefix to auto-delete
      stale objects as a safety net.
INFO
