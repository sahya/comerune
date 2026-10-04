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
// 1 日あたりの増加は取得間隔が空くと小数になるため、桁を絞って表示する
const rateFmt = new Intl.NumberFormat("ja-JP", { maximumFractionDigits: 1 });

const DAY_MS = 24 * 60 * 60 * 1000;

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

  // リリース別: DL 数上位を個別系列に、残りは「その他」へ。
  // 対象は全スナップショットに登場した tag の和集合とする。最新時点だけを見ると、
  // 削除されたリリースの過去の推移まで表示から消えてしまうため
  // （合計は減っているのに内訳から理由が読み取れなくなる）。
  const lastKnown = new Map();
  for (const snap of perSnap) {
    for (const [tag, v] of snap.byTag) lastKnown.set(tag, v);
  }
  const rankedTags = [...lastKnown.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([tag]) => tag);
  const topTags = rankedTags.slice(0, MAX_SERIES);
  const topTagSet = new Set(topTags);
  const hasOther = rankedTags.length > MAX_SERIES;

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

  renderDailyChart(series, perSnap);

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

// 累計グラフでは「どのリリースが今伸びているか」が分かりにくいため、
// 隣り合うスナップショットの差分を 1 日あたりに直して増加ペースを見せる。
// 系列と色は累計グラフと同じものを使う（同じリリース＝同じ色を保つ）。
function renderDailyChart(series, perSnap) {
  const section = document.getElementById("section-daily");
  // 差分は 2 点目以降にしか作れないので、1 点しかない間はセクションごと出さない
  if (perSnap.length < 2) {
    section.hidden = true;
    return;
  }
  section.hidden = false;

  const daily = series.map((s) => ({
    name: s.name,
    cssVar: s.cssVar,
    values: s.values.slice(1).map((v, i) => {
      const prev = s.values[i];
      // そのリリースがまだ無かった区間は比較の基準がないので描かない
      if (v === null || prev === null) return null;
      // ワークフローが失敗して間隔が空くことがあるため 1 日あたりに正規化する
      const days = (perSnap[i + 1].t - perSnap[i].t) / DAY_MS;
      if (!(days > 0)) return null;
      return (v - prev) / days;
    }),
  }));

  renderLegend(document.getElementById("legend-daily"), daily);
  renderLineChart(
    document.getElementById("chart-daily"),
    perSnap.slice(1).map((s) => s.t),
    daily,
    rateFmt.format,
  );
}

function renderTiles(snapshots, perSnap, totalOf) {
  const latestSnap = perSnap[perSnap.length - 1];
  const latestTotal = totalOf(latestSnap);

  // 7 日前（に最も近い過去のスナップショット）との差分
  const weekAgo = latestSnap.t - 7 * DAY_MS;
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

  const root = document.getElementById("stats");
  root.replaceChildren(
    ...tiles.map((t) => {
      const div = el("div", "stat");
      div.append(
        el("p", "eyebrow", t.label),
        el("div", "value", t.value),
        el("div", "sub", t.sub),
      );
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
        el("td", "tag", r.tag),
        el("td", "dim", r.published ? fmtDate(Date.parse(r.published)) : "—"),
        el("td", "num", numFmt.format(r.total)),
        el("td", "num dim", share),
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
function renderLineChart(root, times, series, fmt) {
  const state = { times, series, w: 0, fmt };
  chartStates.set(root, state);
  drawChart(root, state);
  chartObserver.observe(root);
}

function drawChart(root, state) {
  const { times, series } = state;
  // コンテナ幅をそのまま座標系にする（下限を上回ると SVG 全体が縮小され、
  // 軸ラベルが指定より小さく描画されてしまう）
  const W = Math.max(240, Math.round(root.clientWidth) || 800);
  const H = Math.round(Math.max(220, Math.min(320, W * 0.5)));
  state.w = W;

  root.replaceChildren();

  const svg = svgEl("svg", {
    viewBox: `0 0 ${W} ${H}`,
    role: "img",
    "aria-label": `${series.map((s) => s.name).join("、")} の推移グラフ`,
  });

  const fmt = state.fmt ?? numFmt.format;
  const tMin = times[0];
  const tMax = times[times.length - 1];

  // 増加数グラフはリリース削除で負になりうるので、下限も値から決める
  const vals = series.flatMap((s) => s.values.filter((v) => v !== null));
  const { vMin, vMax, step } = niceDomain(vals);

  const x = (t) => (tMax === tMin
    ? PAD.left + (W - PAD.left - PAD.right) / 2
    : PAD.left + ((t - tMin) / (tMax - tMin)) * (W - PAD.left - PAD.right));
  const y = (v) =>
    H - PAD.bottom - ((v - vMin) / (vMax - vMin)) * (H - PAD.top - PAD.bottom);

  // 横グリッドと Y 軸目盛り。0 の線だけ基準線として太くする
  const yTicks = Math.round((vMax - vMin) / step);
  for (let i = 0; i <= yTicks; i++) {
    const v = vMin + step * i;
    const gy = y(v);
    svg.append(
      svgEl("line", {
        x1: PAD.left, x2: W - PAD.right, y1: gy, y2: gy,
        stroke: "var(--line)",
        "stroke-width": Math.abs(v) < step * 1e-6 ? 1.5 : 1,
      }),
      textEl(fmt(v), PAD.left - 8, gy + 4, "end"),
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
      row.append(chip, document.createTextNode(s.name), el("span", "t-val", fmt(v)));
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

// Y 軸の範囲と目盛り幅を決める。
// 目盛り幅を 1/2/5 × 10^n に丸めた上で範囲をその倍数に広げるので、
// 目盛りの値がキリのよい数字になり、0 が必ず目盛り線上に来る
// （増加数はリリース削除で負にもなるため、0 の位置が読み取れることが重要）。
function niceDomain(vals, targetTicks = 4) {
  const lo = Math.min(0, ...vals);
  let hi = Math.max(0, ...vals);
  if (hi === lo) hi = lo + 1;
  const step = niceStep((hi - lo) / targetTicks);
  return {
    vMin: Math.floor(lo / step) * step,
    vMax: Math.ceil(hi / step) * step,
    step,
  };
}

// 目盛り幅をキリのよい数字（1/2/2.5/5 × 10^n）に切り上げる。
// 2.5 系列がないと 95 のような範囲で幅が 50 に飛び、目盛りが 3 本しか出ず粗くなる。
// ただし 0.25 のような 1 未満の幅は表示桁を増やさないと読めないので使わない。
function niceStep(rough) {
  if (!(rough > 0)) return 1;
  const pow = Math.pow(10, Math.floor(Math.log10(rough)));
  for (const m of [1, 2, 2.5, 5]) {
    const step = m * pow;
    if (m === 2.5 && step < 1) continue;
    if (rough <= step) return step;
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

// 見た目は CSS の .chart text.tick 側で指定する（属性値はその指定が
// 効かない環境向けのフォールバック）
function textEl(text, x, y, anchor) {
  const node = svgEl("text", {
    x, y, "text-anchor": anchor, class: "tick",
    "font-size": 11, fill: "var(--muted)",
  });
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
