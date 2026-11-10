// AI quota widget: usage of provider plans (those that expose a quota API).
// Data comes from the ai-bridge proxy: http://127.0.0.1:8801/quota/zai
// (the bridge injects the provider key server-side; nothing here holds secrets).
import { atom, useValue, Button, Tip, host } from '@hermes/plugin-sdk'
import { useEffect, useState } from 'react'
import { jsx, jsxs } from 'react/jsx-runtime'

const ID = 'ai-quota'
const ENDPOINT = 'http://127.0.0.1:8801/quota/zai'
const WEEK_ENDPOINT = 'http://127.0.0.1:8801/quota/zai-week'
const OPENAI_ENDPOINT = 'http://127.0.0.1:8801/quota/openai'
const UNITS = { 3: '5h window', 6: 'Monthly' }
const $quota = atom(null)
const $week = atom(null)
const $openai = atom(null)

async function fetchOpenai() {
    try {
        const r = await fetch(OPENAI_ENDPOINT, { signal: AbortSignal.timeout(8000) })
        if (!r.ok) throw new Error('http ' + r.status)
        const j = await r.json()
        const rl = j?.rate_limit
        if (!rl) throw new Error('no rate_limit (token expired? re-login codex)')
        $openai.set({ ok: true, plan: j.plan_type, rl })
    } catch (e) {
        $openai.set({ ok: false, error: String(e && e.message || e) })
    }
}

async function fetchQuota() {
    try {
        const r = await fetch(ENDPOINT, { signal: AbortSignal.timeout(8000) })
        if (!r.ok) throw new Error('http ' + r.status)
        const j = await r.json()
        if (!j?.success) throw new Error(j?.msg || 'bad payload')
        $quota.set({ ok: true, limits: j.data.limits, level: j.data.level })
    } catch (e) {
        $quota.set({ ok: false, error: String(e && e.message || e) })
    }
}

async function fetchWeek() {
    try {
        const fmt = (t) => new Date(t).toISOString().slice(0, 19).replace('T', ' ')
        const now = Date.now(), week = now - 7 * 86400000
        const url = WEEK_ENDPOINT + '?startTime=' + encodeURIComponent(fmt(week)) + '&endTime=' + encodeURIComponent(fmt(now))
        const r = await fetch(url, { signal: AbortSignal.timeout(10000) })
        if (!r.ok) throw new Error('http ' + r.status)
        const j = await r.json()
        if (!j?.success) throw new Error(j?.msg || 'bad payload')
        $week.set({ ok: true, total: j.data.totalUsage })
    } catch (e) {
        $week.set({ ok: false, error: String(e && e.message || e) })
    }
}

const fmtTokens = (n) => n >= 1e9 ? (n / 1e9).toFixed(2) + 'B' : n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e3 ? (n / 1e3).toFixed(0) + 'K' : String(n)
const fmtReset = (resetAt, resetAfter) => {
    if (!resetAt) return ''
    return new Date(resetAt * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + (resetAfter ? ' (через ' + Math.round(resetAfter / 3600) + 'ч)' : '')
}
const pctColor = (p) => p >= 90 ? 'var(--ui-error, #e5484d)' : p >= 70 ? 'var(--ui-warning, #f5a623)' : 'var(--ui-text-primary)'

function OpenaiRows() {
    const o = useValue($openai)
    if (!o) return null
    if (!o.ok) return jsx('div', { style: { fontSize: 12, opacity: .6 }, children: 'ChatGPT: ' + (o.error || '…') })
    const w = o.rl.primary_window, wk = o.rl.secondary_window
    return jsxs('div', { style: { display: 'grid', gap: 8 }, children: [
        jsxs('div', { style: { color: 'var(--ui-text-secondary)' }, children: ['ChatGPT (', o.plan, ')'] }),
        jsxs('div', { children: [
            jsxs('div', { style: { display: 'flex', justifyContent: 'space-between' }, children: [
                jsx('span', { children: '5h window' }),
                jsx('span', { style: { color: pctColor(w.used_percent) }, children: w.used_percent + '%' })
            ] }),
            jsx('div', { style: { fontFamily: 'var(--font-mono, monospace)', opacity: .8 }, children: bar(w.used_percent) }),
            jsx('div', { style: { opacity: .5 }, children: 'reset ' + fmtReset(w.reset_at, w.reset_after_seconds) })
        ] }),
        jsxs('div', { children: [
            jsxs('div', { style: { display: 'flex', justifyContent: 'space-between' }, children: [
                jsx('span', { children: 'Week' }),
                jsx('span', { style: { color: pctColor(wk.used_percent) }, children: wk.used_percent + '%' })
            ] }),
            jsx('div', { style: { fontFamily: 'var(--font-mono, monospace)', opacity: .8 }, children: bar(wk.used_percent) }),
            jsx('div', { style: { opacity: .5 }, children: 'reset ' + fmtReset(wk.reset_at, wk.reset_after_seconds) })
        ] })
    ] })
}

const bar = (pct) => {
    const n = 12, filled = Math.round(n * Math.min(pct, 100) / 100)
    return '▮'.repeat(filled) + '▯'.repeat(n - filled)
}

function QuotaRows() {
    const q = useValue($quota)
    if (!q) return jsx('div', { style: { fontSize: 12, opacity: .6 }, children: 'Loading…' })
    if (!q.ok) return jsx('div', { style: { fontSize: 12, color: 'var(--ui-text-quaternary)' }, children: 'Bridge unreachable (tunnel down?)' })
    return jsx('div', { style: { display: 'grid', gap: 10, fontSize: 12 }, children:
        q.limits.map((l, i) => jsxs('div', { children: [
            jsxs('div', { style: { display: 'flex', justifyContent: 'space-between', color: 'var(--ui-text-secondary)' }, children: [
                jsx('span', { children: (UNITS[l.unit] || ('unit ' + l.unit)) + ' · GLM plan (' + (q.level || '?') + ')' }),
                jsx('span', { style: { color: l.percentage >= 90 ? 'var(--ui-error, #e5484d)' : l.percentage >= 70 ? 'var(--ui-warning, #f5a623)' : 'var(--ui-text-primary)' }, children: l.percentage + '%' })
            ] }),
            jsx('div', { style: { fontFamily: 'var(--font-mono, monospace)', opacity: .8 }, children: bar(l.percentage) }),
            jsx('div', { style: { opacity: .5 }, children: 'used ' + (l.currentValue ?? '?') + ' / ' + (l.usage ?? '?') + ' · reset ' + new Date(l.nextResetTime).toLocaleString() })
        ] }, i))
    })
}

function WeekRows() {
    const w = useValue($week)
    if (!w) return null
    if (!w.ok) return jsx('div', { style: { fontSize: 11, opacity: .5 }, children: 'week: bridge unreachable' })
    const t = w.total || {}
    return jsxs('div', { style: { display: 'grid', gap: 6 }, children: [
        jsx('div', { style: { color: 'var(--ui-text-secondary)' }, children: 'Week (rolling 7d): ' + fmtTokens(t.totalTokensUsage || 0) + ' tokens · ' + (t.totalModelCallCount || 0) + ' calls' }),
        ...(t.modelSummaryList || []).map((m, i) => jsx('div', { style: { opacity: .65, paddingLeft: 10 }, children: (m.modelName || '?') + ': ' + fmtTokens(m.totalTokens || 0) }, i))
    ] })
}

function Chip() {
    const q = useValue($quota)
    const o = useValue($openai)
    const model = String(useValue(host.state.model) || '').toLowerCase()
    let label = 'AI ∅'
    if (model.includes('glm')) {
        const five = q && q.ok && q.limits.find(l => l.unit === 3)
        label = q && q.ok ? (five ? 'GLM 5h ' + five.percentage + '%' : 'GLM ?') : 'GLM ∅'
    } else if (model.includes('gpt') || model.includes('codex')) {
        const w = o && o.ok && o.rl.primary_window
        const wk = o && o.ok && o.rl.secondary_window
        label = o && o.ok ? 'GPT 5h ' + w.used_percent + '% · W ' + wk.used_percent + '%' : 'GPT ∅'
    } else if (model.includes('claude')) {
        label = 'Claude — подписка не подключена'
    } else {
        const five = q && q.ok && q.limits.find(l => l.unit === 3)
        label = five ? 'GLM 5h ' + five.percentage + '%' : 'AI ∅'
    }
    return jsx(Tip, { content: model + ' — AI quota (click to open pane)', children:
        jsx(Button, { variant: 'ghost', onClick: () => { fetchQuota(); fetchWeek(); fetchOpenai() }, children: label })
    })
}

export default {
    id: ID,
    name: 'AI Quota',
    register(ctx) {
        fetchQuota()
        fetchWeek()
        fetchOpenai()
        const t = setInterval(() => { fetchQuota(); fetchWeek(); fetchOpenai() }, 60000)
        ctx.register({
            id: 'chip', area: 'statusBar.right', order: 50,
            render() { return jsx(Chip, {}) },
            dispose() { clearInterval(t) }
        })
        ctx.register({
            id: 'pane', area: 'panes',
            data: { title: 'AI Quota', placement: 'right', width: '300px' },
            render() {
                return jsx('div', { style: { padding: 12, display: 'grid', gap: 12, alignContent: 'start' }, children: [
                    jsxs('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' }, children: [
                        jsx('div', { style: { fontSize: 13, fontWeight: 600, color: 'var(--ui-text-primary)' }, children: 'Provider quotas' }),
                        jsx(Button, { variant: 'ghost', onClick: fetchQuota, children: '↻' })
                    ] }),
                    jsx(QuotaRows, {}),
                    jsx(WeekRows, {}),
                    jsx(OpenaiRows, {}),
                    jsx('div', { style: { fontSize: 11, opacity: .5 }, children: 'z.ai exposes plan quotas. Anthropic/OpenAI subscriptions expose no quota API — API keys can be added on the bridge later.' })
                ] })
            }
        })
    }
}
