/**
 * ============================================================================
 *  Dynamic Workflow 演化版 — evolving-builder（Anthropic `Workflow` 工具 / JS 腳本）
 * ============================================================================
 *
 *  這支是什麼？
 *  ─────────────────────────────────────────────────────────────────────────
 *  Anthropic Claude Code 內建的 **Dynamic Workflow**（`Workflow` 工具）會讓模型
 *  即時自寫一支 JS 編排腳本、在背景跑 multi-agent。本檔就是那種 JS 腳本，
 *  但是 **「演化版」**——不是工具一般自動生成的「無狀態、一次性」版本，
 *  而是我（楊政憲）自己把 podcastbrain harness 的演化紀律寫進 JS 的版本。
 *
 *  來源：原本只活在 session 暫存目錄
 *    ~/.claude/projects/C--Users-user-workspace-podcastbrain-harness/<session>/
 *      workflows/scripts/evolving-builder-demo-wf_5393fc77-fb5.js
 *  （2026-05-30 04:08 跑的第 2 代，session 清掉就沒了）→ 複製到 repo 永久保存。
 *  設計與兩代實證寫在：doc/workflow-vs-harness-演化筆記-2026-05-30.md（第六、八章）。
 *
 *  ── 核心差異總結：一般 dynamic workflow  vs  這支演化版 ──────────────────
 *
 *  ┌──────────┬───────────────────────────────┬──────────────────────────────┐
 *  │ 面向     │ 一般 dynamic workflow         │ 這支「演化版」                │
 *  │          │ (如 skills-consolidation-audit)│ (evolving-builder)           │
 *  ├──────────┼───────────────────────────────┼──────────────────────────────┤
 *  │ 狀態     │ ❌ 無狀態，跑完即忘            │ ✅ 讀寫外部 state 檔，跨 run  │
 *  │          │    重跑從零開始               │    留存（A.statePath）        │
 *  │ phase    │ Scan → Synthesize             │ Append → Build → Persist      │
 *  │          │ (一次性 fan-out + 收口)       │ (演化三段)                    │
 *  │ 重跑     │ 每次全部重跑                  │ 讀舊 state → 鎖 stable        │
 *  │          │                               │ (passes:true) → 只攻新功能    │
 *  │ 核心邏輯 │ fan-out 掃描 → 整併           │ APPEND diff：只挑 SPEC 裡     │
 *  │          │                               │ state 沒涵蓋的功能            │
 *  │ 產物     │ 不堆疊（每次獨立結果）        │ v1→v2→v3 堆疊（鎖舊、加新）   │
 *  └──────────┴───────────────────────────────┴──────────────────────────────┘
 *
 *  一句話：一般 workflow 是「無狀態、一次性、跑完即忘」的深層 fan-out；
 *  這支演化版把 podcastbrain 的三條不變量
 *    (1) 狀態外部化  (2) 冪等 + APPEND-aware  (3) 鎖 stable、只攻 new
 *  寫進了 JS，所以能像 v1→v2→v3 一樣堆疊長大，而不是每次砍掉重練。
 *
 *  ⚠️ 我「自己加進去、一般模板沒有」的段落，下方都用【演化新增】標出。
 *
 *  跑法：Workflow({ name:'evolving-builder-demo',
 *                   args:{ version:'v2', statePath:'.../feature_list.json',
 *                          spec:[{name,desc}, ...] } })
 *  重跑換 args.spec（新版功能清單）→ 讀到 state 已有的就鎖住、只 APPEND 沒涵蓋的。
 * ============================================================================
 */

export const meta = {
  name: 'evolving-builder-demo',
  description: '示範 dynamic workflow 用外部 state 檔做 podcastbrain 式 APPEND 演化堆疊（v2 代）',
  phases: [
    { title: 'Append', detail: '讀 state 檔 + diff 出新功能' },
    { title: 'Build', detail: '只建新功能（鎖 stable）', model: 'haiku' },
    { title: 'Persist', detail: '合併寫回 state 檔' },
  ],
}

// 【演化新增】args 可能以字串抵達 → 先 parse（一般 workflow 不需要；這是踩過「args 變字串」坑後的防禦）
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const STATE = A.statePath
const VERSION = A.version
const SPEC = A.spec

const STATE_READ_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['features'],
  properties: {
    features: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'name', 'passes', 'status', 'version_added'],
        properties: {
          id: { type: 'number' }, name: { type: 'string' },
          passes: { type: 'boolean' }, status: { type: 'string' },
          version_added: { type: 'string' },
        },
      },
    },
  },
}
const BUILD_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['name', 'passes', 'note'],
  properties: { name: { type: 'string' }, passes: { type: 'boolean' }, note: { type: 'string' } },
}
const PERSIST_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['written', 'count'],
  properties: { written: { type: 'boolean' }, count: { type: 'number' } },
}

// 【演化新增】Phase Append：讀外部 state 檔 → 算 APPEND diff（= harness 的 feature_list.json 邏輯翻成 JS）
//   腳本本體 sandbox 無 fs，所以讀檔一律派 agent 用 Read 做 I/O。
phase('Append')
const state = await agent(
  `讀取檔案 ${STATE}。回傳其 JSON（格式 {"features":[...]}）；不存在回 {"features":[]}。用 Read 讀。只回資料。`,
  { label: 'read-state', phase: 'Append', schema: STATE_READ_SCHEMA, model: 'haiku' }
)
const feats = state.features || []
const existingNames = new Set(feats.map(f => f.name))
const locked = feats.filter(f => f.passes)                        // 【演化新增】鎖 stable：passes:true 的不重建
const baseId = feats.reduce((m, f) => Math.max(m, f.id), 0)
const toAdd = SPEC.filter(s => !existingNames.has(s.name))        // 【演化新增】APPEND diff：只挑 state 沒涵蓋的
  .map((s, i) => ({ id: baseId + i + 1, name: s.name, desc: s.desc }))
log(`${VERSION}：既有 ${feats.length} 個（鎖 stable ${locked.length}）→ APPEND ${toAdd.length} 個新功能：${toAdd.map(f => f.name).join('、') || '無'}`)

// 【演化新增】Phase Build：只對新功能（toAdd）派 builder，既有 stable 完全不碰；用 index 對應（不靠 name）
phase('Build')
const built = await parallel(toAdd.map(f => () => agent(
  `你是迷你建置 agent（demo 用）。【嚴禁】使用 Read/Write/Edit/Bash 等任何工具，也不可建立任何檔案——只在腦中「實作」後直接回傳結構化結果。\n` +
  `功能：「${f.name}」— ${f.desc}。回傳 name 設為「${f.name}」、passes:true、note 為一句中文實作摘要。`,
  { label: `build:${f.name}`, phase: 'Build', schema: BUILD_SCHEMA, model: 'haiku' }
)))

// 【演化新增】合併：舊功能標 stable、新功能標 new + version_added（記錄是哪一代加進來的）
const merged = [
  ...feats.map(f => (f.passes ? { ...f, status: 'stable' } : f)),
  ...toAdd.map((f, i) => ({
    id: f.id, name: f.name,
    passes: built[i] ? built[i].passes : false,
    status: 'new', version_added: VERSION,
    note: built[i] ? built[i].note : '',
  })),
]

// 【演化新增】Phase Persist：把合併結果寫回 state 檔 → 達成跨 session 永久堆疊
phase('Persist')
await agent(
  `把下面 JSON 完整覆寫進 ${STATE}（UTF-8）：\n${JSON.stringify({ features: merged }, null, 2)}\n寫完回 written:true、count 為 features 數量。`,
  { label: 'write-state', phase: 'Persist', schema: PERSIST_SCHEMA, model: 'haiku' }
)

// 【演化新增】回傳演化指標（一般 workflow 回分析結果；這支回「這代鎖了幾個、APPEND 了哪些」）
return {
  version: VERSION,
  total: merged.length,
  locked_stable: locked.length,
  appended_this_run: toAdd.length,
  appended_names: toAdd.map(f => f.name),
  all_features: merged.map(f => `#${f.id} [${f.passes ? 'x' : ' '}] ${f.name} (${f.status}, ${f.version_added})`),
}
