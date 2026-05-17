// Cloudflare Pages Function: GET /api/app-version
//
// アプリのバージョン更新通知・強制更新が参照する optional integration
// エンドポイント。次の JSON を返す:
//
//   { "latest": "1.2.0", "minSupported": "1.1.0",
//     "url": "https://github.com/sahya/comerune/releases/latest" }
//
// 設計意図:
// - `latest` はサーバ側で GitHub Releases を取得しエッジキャッシュする。
//   アプリは GitHub API を直接叩かないのでレート制限を受けず、リリース
//   公開に自動追従する（version.json の手動更新が不要）。プレリリースは
//   `/releases/latest` が除外するため対象外。
// - `minSupported` は環境変数 MIN_SUPPORTED_VERSION から読む。アプリを
//   再ビルドせず Cloudflare ダッシュボードで強制更新ラインを変更できる。
//   未設定/不正なら "0.0.0"（誰も強制ブロックされない安全側）。
// - 常に HTTP 200 を返す。GitHub 障害時も latest を null にして 200 を
//   返すことで、アプリ側 fail-open（任意通知は出さない・強制は確実に
//   下限を下回ったときだけ）を成立させる。

const GITHUB_OWNER = "sahya";
const GITHUB_REPO = "comerune";
const RELEASES_PAGE = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
const LATEST_API = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;

// X.Y.Z（任意で -prerelease）。先頭 v は許容して剥がす。
const SEMVER_RE = /^v?(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?$/;

function normalizeVersion(input) {
  if (typeof input !== "string") return null;
  const m = SEMVER_RE.exec(input.trim());
  if (!m) return null;
  // 先頭 v を剥がした正規化文字列を返す。
  return input.trim().replace(/^v/, "");
}

function jsonResponse(body) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      // エッジ/クライアントに 5 分キャッシュさせ GitHub への呼び出しを抑制。
      "Cache-Control": "public, max-age=300",
      // ネイティブアプリからの参照だが将来の Web 利用も想定し許可。
      "Access-Control-Allow-Origin": "*",
    },
  });
}

export async function onRequestGet(context) {
  const minSupported =
    normalizeVersion(context.env && context.env.MIN_SUPPORTED_VERSION) ||
    "0.0.0";

  let latest = null;
  try {
    const res = await fetch(LATEST_API, {
      headers: {
        // GitHub API は User-Agent 必須。
        "User-Agent": "comerune-app-version-function",
        Accept: "application/vnd.github+json",
      },
      // エッジキャッシュ（リリース公開直後の伝播遅延は許容範囲）。
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (res.ok) {
      const data = await res.json();
      latest =
        normalizeVersion(data && data.tag_name) ||
        normalizeVersion(data && data.name);
    }
    // 404（リリース未作成 / 正式版なし）等は latest=null のまま続行。
  } catch (_e) {
    // GitHub 不達でも 200 を返し、アプリ側 fail-open に委ねる。
    latest = null;
  }

  return jsonResponse({
    latest,
    minSupported,
    url: RELEASES_PAGE,
  });
}
