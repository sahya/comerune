// ダウンロード統計ページの描画スクリプト。
// データは metrics-data ブランチ（release-metrics.yml が日次追記する JSON Lines）から取得する。
// 外部ライブラリは使わず素の SVG で描画する（サプライチェーン対策・CSP 対応）。
"use strict";

const DATA_URL =
  "https://raw.githubusercontent.com/sahya/comerune/refs/heads/metrics-data/data/release-downloads.jsonl";

// リリース別グラフで個別系列として表示する最大数。超えた分は「その他」に畳む。
// （系列色は index.html の --series-1〜5 と対応。色覚多様性の分離検証はこの 5 色で実施済み）
const MAX_SERIES = 5;
const OTHER_LABEL = "その他";

const numFmt = new Intl.NumberFormat("ja-JP");

document.addEventListener("DOMContentLoaded", init);

async function init() {
  const status = document.getElementById("status");
  let snapshots;
  try {
    const res = await fetch(DATA_URL, { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    snapshots = parseJsonl(await res.text());
  } catch (e) {
    // データ取得先が未作成・到達不能でもページ自体は壊さない
    status.textContent = "統計データを読み込めませんでした。データ収集がまだ始まっていない可能性があります。";
    status.classList.add("error");
    return;
  }

  if (snapshots.length === 0) {
    status.textContent = "まだデータがありません。収集開始後に表示されます。";
    return;
  }

  status.hidden = true;
  document.getElementById("content").hidden = false;
  render(snapshots);
}

// JSON Lines をパースする。壊れた行があっても他の行の表示は継続する。
function parseJsonl(text) {
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const snap = JSON.parse(line);
      if (typeof snap.ts !== "string" || !Array.isArray(snap.releases)) continue;
      const t = Date.parse(snap.ts);
      if (Number.isNaN(t)) continue;
      // tag は系列名・凡例に使うため、欠けているリリースは取り込まない
      out.push({ t, releases: snap.releases.filter((r) => typeof r?.tag === "string") });
    } catch (e) {
      // 1 行の破損は無視して続行
    }
  }
  out.sort((a, b) => a.t - b.t);
  return out;
}

function releaseTotal(release) {
  let sum = 0;
  for (const a of release.assets ?? []) sum += a.count ?? 0;
  return sum;
}

function render(snapshots) {
  const latest = snapshots[snapshots.length - 1];

  // スナップショットごとの tag → 累計DL数
  const perSnap = snapshots.map((s) => {
    const byTag = new Map();
    for (const r of s.releases) byTag.set(r.tag, releaseTotal(r));
    return { t: s.t, byTag };
  });

  const totalOf = (snap) => {
    let sum = 0;
    for (const v of snap.byTag.values()) sum += v;
    return sum;
  };

  renderTiles(snapshots, perSnap, totalOf);

  // 総ダウンロード数の推移（単一系列）
  renderLineChart(
    document.getElementById("chart-total"),
    perSnap.map((s) => s.t),
    [{ name: "総ダウンロード数", cssVar: "--series-1", values: perSnap.map(totalOf) }],
  );

  // リリース別: 最新時点の DL 数上位を個別系列に、残りは「その他」へ
  const latestTags = [...perSnap[perSnap.length - 1].byTag.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([tag]) => tag);
  const topTags = latestTags.slice(0, MAX_SERIES);
  const topTagSet = new Set(topTags);
  const hasOther = latestTags.length > MAX_SERIES;

  const series = topTags.map((tag, i) => ({
    name: tag,
    cssVar: `--series-${i + 1}`,
    values: perSnap.map((s) => s.byTag.get(tag) ?? null),
  }));
  if (hasOther) {
    series.push({
      name: OTHER_LABEL,
      cssVar: "--series-other",
      values: perSnap.map((s) => {
        let sum = 0;
        let seen = false;
        for (const [tag, v] of s.byTag) {
          if (topTagSet.has(tag)) continue;
          sum += v;
          seen = true;
        }
        return seen ? sum : null;
      }),
    });
  }

  renderLegend(document.getElementById("legend-by-release"), series);
  renderLineChart(
    document.getElementById("chart-by-release"),
    perSnap.map((s) => s.t),
    series,
  );

  renderTable(latest);

  document.getElementById("updated-at").textContent =
    `最終記録: ${fmtDateTime(latest.t)}（毎日 1 回自動更新）`;
}

function renderTiles(snapshots, perSnap, totalOf) {
  const latestSnap = perSnap[perSnap.length - 1];
  const latestTotal = totalOf(latestSnap);

  // 7 日前（に最も近い過去のスナップショット）との差分
  const weekAgo = latestSnap.t - 7 * 24 * 60 * 60 * 1000;
  let base = null;
  for (const s of perSnap) {
    if (s.t <= weekAgo) base = s;
  }
  const delta7 = base === null ? null : latestTotal - totalOf(base);

  // 最新リリース（published_at が最大のもの）。published_at 欠落は最古扱いにする
  const publishedAt = (r) => {
    const t = Date.parse(r.published_at ?? "");
    return Number.isNaN(t) ? -Infinity : t;
  };
  const latestRelease = snapshots[snapshots.length - 1].releases.reduce(
    (acc, r) => (acc === null || publishedAt(r) > publishedAt(acc) ? r : acc),
    null,
  );

  const tiles = [
    { label: "総ダウンロード数", value: numFmt.format(latestTotal), sub: "全リリース・全アセット合計" },
    {
      // リリースが削除されると累計が減ることがあるため符号は値から決める
      label: "直近 7 日の増加",
      value: delta7 === null ? "—" : `${delta7 >= 0 ? "+" : "−"}${numFmt.format(Math.abs(delta7))}`,
      sub: delta7 === null ? "データ蓄積中" : "",
    },
    {
      label: "最新リリース",
      value: latestRelease ? latestRelease.tag : "—",
      sub: latestRelease?.published_at ? `${fmtDate(Date.parse(latestRelease.published_at))} 公開` : "",
    },
  ];

  const root = document.getElementById("tiles");
  root.replaceChildren(
    ...tiles.map((t) => {
      const div = el("div", "tile");
      div.append(el("div", "label", t.label), el("div", "value", t.value), el("div", "sub", t.sub));
      return div;
    }),
  );
}

function renderLegend(root, series) {
  root.replaceChildren(
    ...series.map((s) => {
      const item = el("span", "item");
      const chip = el("span", "chip");
      chip.style.background = `var(${s.cssVar})`;
      item.append(chip, document.createTextNode(s.name));
      return item;
    }),
  );
}

function renderTable(latestSnapshot) {
  const rows = latestSnapshot.releases
    .map((r) => ({ tag: r.tag, published: r.published_at, total: releaseTotal(r) }))
    .sort((a, b) => b.total - a.total);
  const grand = rows.reduce((sum, r) => sum + r.total, 0);

  const tbody = document.querySelector("#table-releases tbody");
  tbody.replaceChildren(
    ...rows.map((r) => {
      const tr = document.createElement("tr");
      const share = grand > 0 ? `${((r.total / grand) * 100).toFixed(1)}%` : "—";
      tr.append(
        el("td", "", r.tag),
        el("td", "", r.published ? fmtDate(Date.parse(r.published)) : "—"),
        el("td", "num", numFmt.format(r.total)),
        el("td", "num", share),
      );
      return tr;
    }),
  );
}

// ---- SVG 折れ線グラフ ------------------------------------------------------

const SVG_NS = "http://www.w3.org/2000/svg";
const PAD = { top: 16, right: 16, bottom: 28, left: 56 };

const chartStates = new WeakMap();

// 幅が実質的に変わったときだけ再描画する。再描画は高さも変えるため、
// 無条件に再描画すると ResizeObserver が自己ループする。
const chartObserver = new ResizeObserver((entries) => {
  for (const entry of entries) {
    const state = chartStates.get(entry.target);
    if (!state) continue;
    const w = Math.round(entry.contentRect.width);
    if (w > 0 && Math.abs(w - state.w) >= 8) drawChart(entry.target, state);
  }
});

// グラフはコンテナ幅と同じ座標系で描く。viewBox を固定幅にすると
// 画面幅の狭い端末で軸ラベルが潰れて読めなくなるため。
function renderLineChart(root, times, series) {
  const state = { times, series, w: 0 };
  chartStates.set(root, state);
  drawChart(root, state);
  chartObserver.observe(root);
}

function drawChart(root, state) {
  const { times, series } = state;
  const W = Math.max(320, Math.round(root.clientWidth) || 800);
  const H = Math.round(Math.max(220, Math.min(320, W * 0.5)));
  state.w = W;

  root.replaceChildren();

  const svg = svgEl("svg", {
    viewBox: `0 0 ${W} ${H}`,
    role: "img",
    "aria-label": `${series.map((s) => s.name).join("、")} の推移グラフ`,
  });

  const tMin = times[0];
  const tMax = times[times.length - 1];
  const vMax = niceMax(Math.max(1, ...series.flatMap((s) => s.values.filter((v) => v !== null))));

  const x = (t) => (tMax === tMin
    ? PAD.left + (W - PAD.left - PAD.right) / 2
    : PAD.left + ((t - tMin) / (tMax - tMin)) * (W - PAD.left - PAD.right));
  const y = (v) => H - PAD.bottom - (v / vMax) * (H - PAD.top - PAD.bottom);

  // 横グリッドと Y 軸目盛り
  const yTicks = 4;
  for (let i = 0; i <= yTicks; i++) {
    const v = (vMax / yTicks) * i;
    const gy = y(v);
    svg.append(
      svgEl("line", {
        x1: PAD.left, x2: W - PAD.right, y1: gy, y2: gy,
        stroke: "var(--line)", "stroke-width": i === 0 ? 1.5 : 1,
      }),
      textEl(numFmt.format(v), PAD.left - 8, gy + 4, "end"),
    );
  }

  // X 軸目盛り（等間隔サンプリング）。1 ラベル約 80px を確保して重なりを避ける。
  // 両端はラベルが描画域からはみ出すため、内側に寄せて揃える。
  const plotW = W - PAD.left - PAD.right;
  const tickCount = Math.min(Math.max(2, Math.floor(plotW / 80)), 6, times.length);
  const seen = new Set();
  for (let i = 0; i < tickCount; i++) {
    const idx = tickCount === 1 ? 0 : Math.round((i * (times.length - 1)) / (tickCount - 1));
    if (seen.has(idx)) continue;
    seen.add(idx);
    let anchor = "middle";
    if (times.length > 1) {
      if (idx === 0) anchor = "start";
      else if (idx === times.length - 1) anchor = "end";
    }
    svg.append(textEl(fmtDate(times[idx]), x(times[idx]), H - PAD.bottom + 18, anchor));
  }

  // 系列を描く。まだ存在しないリリースの区間は値が null になるので、
  // null で線を分断し、連続する非 null の区間（run）ごとに線を引く。
  // 区間が 1 点しかないと線にならないため、その場合は点で示す。
  for (const s of series) {
    let path = "";
    let run = [];
    const flush = () => {
      if (run.length === 1) {
        svg.append(svgEl("circle", {
          cx: x(times[run[0]]), cy: y(s.values[run[0]]), r: 4,
          fill: `var(${s.cssVar})`,
        }));
      } else if (run.length > 1) {
        path += run.map((i, k) => `${k === 0 ? "M" : "L"}${x(times[i])},${y(s.values[i])}`).join("");
      }
      run = [];
    };
    for (let i = 0; i < s.values.length; i++) {
      if (s.values[i] === null) flush();
      else run.push(i);
    }
    flush();
    if (path) {
      svg.append(svgEl("path", {
        d: path, fill: "none",
        stroke: `var(${s.cssVar})`, "stroke-width": 2,
        "stroke-linejoin": "round", "stroke-linecap": "round",
      }));
    }
  }

  // ホバー用クロスヘア + ツールチップ
  const crosshair = svgEl("line", {
    y1: PAD.top, y2: H - PAD.bottom,
    stroke: "var(--muted)", "stroke-width": 1, "stroke-dasharray": "3 3",
    visibility: "hidden",
  });
  const markers = series.map((s) => {
    const c = svgEl("circle", { r: 5, fill: `var(${s.cssVar})`, visibility: "hidden" });
    c.style.stroke = "var(--surface)";
    c.style.strokeWidth = "2";
    return c;
  });
  svg.append(crosshair, ...markers);

  const tooltip = el("div", "tooltip");
  root.append(svg, tooltip);

  svg.addEventListener("pointermove", (ev) => {
    const rect = svg.getBoundingClientRect();
    const px = ((ev.clientX - rect.left) / rect.width) * W;
    let nearest = 0;
    for (let i = 1; i < times.length; i++) {
      if (Math.abs(x(times[i]) - px) < Math.abs(x(times[nearest]) - px)) nearest = i;
    }
    const cx = x(times[nearest]);
    crosshair.setAttribute("x1", cx);
    crosshair.setAttribute("x2", cx);
    crosshair.setAttribute("visibility", "visible");

    const rows = [el("div", "t-date", fmtDate(times[nearest]))];
    series.forEach((s, i) => {
      const v = s.values[nearest];
      if (v === null) {
        markers[i].setAttribute("visibility", "hidden");
        return;
      }
      markers[i].setAttribute("cx", cx);
      markers[i].setAttribute("cy", y(v));
      markers[i].setAttribute("visibility", "visible");
      const row = el("div", "t-row");
      const chip = el("span", "chip");
      chip.style.background = `var(${s.cssVar})`;
      row.append(chip, document.createTextNode(s.name), el("span", "t-val", numFmt.format(v)));
      rows.push(row);
    });
    tooltip.replaceChildren(...rows);

    // グラフ右半分では左側に出して見切れを防ぐ
    const cxPct = (cx / W) * 100;
    tooltip.style.visibility = "visible";
    if (cxPct > 55) {
      tooltip.style.left = "";
      tooltip.style.right = `${100 - cxPct + 2}%`;
    } else {
      tooltip.style.right = "";
      tooltip.style.left = `${cxPct + 2}%`;
    }
    tooltip.style.top = "8px";
  });
  svg.addEventListener("pointerleave", () => {
    crosshair.setAttribute("visibility", "hidden");
    for (const m of markers) m.setAttribute("visibility", "hidden");
    tooltip.style.visibility = "hidden";
  });
}

// 軸の最大値をキリのよい数字（1/2/5 × 10^n）に切り上げる
function niceMax(v) {
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 5, 10]) {
    if (v <= m * pow) return m * pow;
  }
  return 10 * pow;
}

// ---- 小物 ------------------------------------------------------------------

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

function svgEl(tag, attrs) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}

function textEl(text, x, y, anchor) {
  const node = svgEl("text", {
    x, y, "text-anchor": anchor,
    "font-size": 11, fill: "var(--muted)",
  });
  node.style.fontVariantNumeric = "tabular-nums";
  node.textContent = text;
  return node;
}

function fmtDate(t) {
  if (!Number.isFinite(t)) return "—";
  const d = new Date(t);
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}

function fmtDateTime(t) {
  const d = new Date(t);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${fmtDate(t)} ${hh}:${mm}`;
}
