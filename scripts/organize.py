#!/usr/bin/env python3
"""Organize a Wireflow graph like a codebase — modules + DRY constants.

A flat node graph reads like a single 500-line function: it runs, but nobody
can see its structure. This refactors it the way you'd refactor code:

  • CONSTANTS (DRY) — text reused by 2+ nodes is hoisted into one shared
    `input:text` node and fanned out, instead of being pasted into each config.
  • MODULES — related nodes are wrapped in a labelled `custom_group` box, so a
    pipeline reads as "① Hero  ② Audio  ③ Endcard  ④ Assembly" instead of soup.

Design: a PLAN ({modules, constants}) drives everything. The plan is either
supplied with --plan (the smart/semantic pass — an LLM picks boundaries+labels)
or auto-built by the deterministic heuristic here. `apply_plan` is the shared
mechanics: create text nodes, rewire, draw boxes, re-layout. This split keeps
"what to do" (judgement) separate from "how" (safe graph surgery).

Usage:
  organize.py <wf.json> [out.json]              # heuristic plan -> apply
  organize.py <wf.json> --dump-plan             # print heuristic plan, no changes
  organize.py <wf.json> out.json --plan p.json  # apply a hand-authored plan

Plan shape:
  {
    "modules":   [{"name": "① Hero", "color": "#2D6B4F", "nodes": ["id", ...]}],
    "constants": [{"name": "Brand voice", "text": "...",
                   "targets": [{"node": "id", "field": "system_prompt"}]}]
  }

Safe by construction: a constant is only wired when the target node actually
declares a matching input port (so the edge resolves), and the inline config
value is cleared only once the wire exists. Nothing is deleted.
"""
import sys
import json
import copy
import math
from collections import defaultdict, deque

# import the group-aware layout that lives next to this file
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import layout as _layout  # noqa: E402

# canvas group palette (WorkflowCanvas.tsx) — keep colors on-brand
PALETTE = ['#2D6B4F', '#2D4F6B', '#6B2D6B', '#6B5A2D', '#2D6B6B', '#6B2D2D']

# text config fields that are worth hoisting into shared constants, mapped to
# the input port id a consumer would expose for that field
TEXT_FIELDS = {
    'system_prompt': 'system_prompt',
    'prompt': 'prompt',
    'text': 'text',
    'negative_prompt': 'negative_prompt',
}

# nodes that merge many upstream streams — each becomes its own module
AGG_TYPES = ('video:remotion', 'compv3')

# family -> (module label, color) for heuristic naming
FAMILY_NAME = {
    'input': ('Inputs', '#6B5A2D'),
    'generate': ('Image generation', '#6B2D6B'),
    'edit': ('Image generation', '#6B2D6B'),
    'process': ('Processing', '#2D6B6B'),
    'audio': ('Audio', '#2D6B6B'),
    'video': ('Video', '#2D4F6B'),
    'compv3': ('Compositor', '#6B5A2D'),
    'utility': ('Utilities', '#6B2D2D'),
    'logic': ('Logic', '#6B2D2D'),
}


def _real(nodes):
    return [n for n in nodes
            if not _layout._is_group(n) and not _layout._is_sticky(n)]


def _family(node):
    nt = (node.get('data') or {}).get('nodeType', '') or ''
    if nt in AGG_TYPES:
        return nt
    return nt.split(':')[0] or 'utility'


def _ports(node, side):
    out = []
    for p in (node.get('data') or {}).get(side) or []:
        pid = p.get('id') or p.get('name')
        if pid:
            out.append(pid)
    return out


# --------------------------------------------------------------------------- #
#  Heuristic plan builder                                                      #
# --------------------------------------------------------------------------- #
def build_plan(wf):
    nodes = wf.get('nodes', [])
    edges = wf.get('edges', [])
    real = _real(nodes)
    ids = {n['id'] for n in real}
    by_id = {n['id']: n for n in real}

    indeg = defaultdict(int)
    und = defaultdict(set)
    for e in edges:
        s, t = e.get('source'), e.get('target')
        if s in ids and t in ids:
            indeg[t] += 1
            und[s].add(t)
            und[t].add(s)

    # aggregators: high fan-in or a known merge node — each is its own module
    aggs = [n['id'] for n in real
            if indeg[n['id']] >= 3 or _family(n) in AGG_TYPES]
    agg_set = set(aggs)

    # connected components of everything else, with aggregator edges cut so the
    # upstream chains separate instead of collapsing into one blob via the sink
    seen = set()
    comps = []
    for n in real:
        nid = n['id']
        if nid in agg_set or nid in seen:
            continue
        comp, dq = [], deque([nid])
        seen.add(nid)
        while dq:
            u = dq.popleft()
            comp.append(u)
            for v in und[u]:
                if v not in seen and v not in agg_set:
                    seen.add(v)
                    dq.append(v)
        comps.append(comp)

    modules = []
    used_colors = 0

    def _name_for(members):
        fams = defaultdict(int)
        for m in members:
            fams[_family(by_id[m])] += 1
        dom = max(fams, key=fams.get)
        return FAMILY_NAME.get(dom, ('Module', PALETTE[0]))

    # merge trivial singletons into a neighbouring component to reduce noise
    comps = [c for c in comps if c]
    big = [c for c in comps if len(c) > 1]
    for c in comps:
        if len(c) == 1:
            nid = c[0]
            host = next((bc for bc in big if any(nb in bc for nb in und[nid])),
                        None)
            if host:
                host.append(nid)
            else:
                big.append(c)
    comps = big

    for i, comp in enumerate(comps):
        label, color = _name_for(comp)
        modules.append({
            'name': label,
            'color': color,
            'nodes': sorted(comp),
        })
        used_colors = i + 1

    for j, aid in enumerate(aggs):
        label, color = _name_for([aid])
        modules.append({
            'name': label,
            'color': PALETTE[(used_colors + j) % len(PALETTE)] or color,
            'nodes': [aid],
        })

    constants = _find_duplicate_text(real)
    return {'modules': modules, 'constants': constants}


def _find_duplicate_text(real):
    """Exact-duplicate text values across 2+ nodes -> hoist candidates.

    Conservative: only fields whose consumer exposes a matching input port, so
    the resulting wire always resolves."""
    buckets = defaultdict(list)  # normalized text -> [(node, field)]
    for n in real:
        cfg = (n.get('data') or {}).get('config') or {}
        ins = _ports(n, 'inputs')
        for field, port in TEXT_FIELDS.items():
            v = cfg.get(field)
            if isinstance(v, str) and len(v.strip()) >= 12 and port in ins:
                buckets[v.strip()].append((n['id'], field))
    constants = []
    for text, targets in buckets.items():
        if len({t[0] for t in targets}) >= 2:
            constants.append({
                'name': (text[:28] + '…') if len(text) > 28 else text,
                'text': text,
                'targets': [{'node': nid, 'field': f} for nid, f in targets],
            })
    return constants


# --------------------------------------------------------------------------- #
#  Plan application (shared mechanics)                                         #
# --------------------------------------------------------------------------- #
def _text_node_template(wf):
    """Clone the shape of a real input:text node in this graph so new constant
    nodes carry the correct ports/category (never invent catalog data)."""
    for n in wf.get('nodes', []):
        if (n.get('data') or {}).get('nodeType') == 'input:text':
            t = copy.deepcopy(n)
            t['data']['config'] = {}
            t['data'].pop('output', None)
            t['data'].pop('result', None)
            return t
    return None


def _out_port(node, prefer=('prompt', 'text')):
    outs = _ports(node, 'outputs')
    for p in prefer:
        if p in outs:
            return p
    return outs[0] if outs else 'prompt'


def apply_plan(wf, plan, measured=None):
    nodes = wf.get('nodes', [])
    edges = wf.setdefault('edges', [])
    by_id = {n['id']: n for n in nodes}
    eidx = 0

    # ---- constants: hoist shared text into one input:text node, fan out ---- #
    tmpl = _text_node_template(wf)
    for ci, const in enumerate(plan.get('constants', [])):
        targets = [t for t in const.get('targets', []) if t['node'] in by_id]
        if len(targets) < 2 or not tmpl:
            continue
        cid = f'const-{ci}'
        cnode = copy.deepcopy(tmpl)
        cnode['id'] = cid
        cnode['selected'] = False
        cnode['position'] = {'x': 0, 'y': 0}
        cnode['data']['label'] = const.get('name', 'Shared text')
        cnode['data']['config'] = {'prompt': const['text']}
        cnode['data']['params'] = {'prompt': const['text']}
        out_handle = 'out-' + _out_port(cnode)
        nodes.append(cnode)
        by_id[cid] = cnode
        for t in targets:
            tgt = by_id[t['node']]
            field = t['field']
            port = TEXT_FIELDS.get(field, field)
            if port not in _ports(tgt, 'inputs'):
                continue
            edges.append({
                'id': f'edge-org-{eidx}',
                'source': cid, 'sourceHandle': out_handle,
                'target': t['node'], 'targetHandle': 'in-' + port,
            })
            eidx += 1
            # clear the now-redundant inline literal (the wire supplies it)
            cfg = tgt.setdefault('data', {}).setdefault('config', {})
            if isinstance(cfg.get(field), str):
                cfg[field] = ''

    # ---- modules: wrap each set of nodes in a labelled custom_group box ----- #
    # strip any pre-existing organize groups so re-runs are idempotent
    nodes[:] = [n for n in nodes
                if not (_layout._is_group(n)
                        and str(n.get('id', '')).startswith('group-org-'))]
    claimed = set()
    for mi, mod in enumerate(plan.get('modules', [])):
        members = [m for m in mod.get('nodes', [])
                   if m in by_id and m not in claimed]
        members = [m for m in members if not _layout._is_group(by_id[m])]
        if not members:
            continue
        claimed.update(members)
        gid = f'group-org-{mi}'
        nodes.insert(0, {
            'id': gid,
            'type': 'custom_group',
            'position': {'x': 0, 'y': 0},
            'zIndex': -1,
            'data': {
                'name': mod.get('name', f'Module {mi + 1}'),
                'color': mod.get('color', PALETTE[mi % len(PALETTE)]),
                'type': 'custom_group',
                'childNodeIds': members,
            },
            'style': {'width': 400, 'height': 300},
        })

    # ---- lay out as a 2D module grid ------------------------------------- #
    # Modules flow left->right by their dependency rank (upstream modules on the
    # left), modules of the same rank stack vertically, and each module is laid
    # out compactly inside its own box. This reads like an architecture diagram
    # (horizontal priority) instead of one tall column of bands.
    _module_grid_layout(wf, plan.get('modules', []), measured)
    return wf


INNER_HGAP = 120        # gap between dataflow columns INSIDE a module
INNER_VGAP = 60         # gap between stacked nodes inside a module column
INNER_HGAP_MEASURED = 84
INNER_VGAP_MEASURED = 50
MODULE_H_GAP = 280      # gutter between module COLUMNS (dependency ranks)
MODULE_V_GAP = 200      # gutter between modules stacked in the same rank
MAX_COL_ROWS = 3        # wrap a module column past this many siblings into a grid


def _module_grid_layout(wf, modules, measured=None):
    inner_h = INNER_HGAP_MEASURED if measured else INNER_HGAP
    inner_v = INNER_VGAP_MEASURED if measured else INNER_VGAP
    nodes = wf.get('nodes', [])
    edges = wf.get('edges', [])
    real = _real(nodes)
    by_id = {n['id']: n for n in real}
    ids = set(by_id)
    dims = {nid: _layout.est_dims(by_id[nid], measured) for nid in ids}

    # node -> module index (unassigned reals get a trailing catch-all module)
    node2mod = {}
    for mi, mod in enumerate(modules):
        for nid in mod.get('nodes', []):
            if nid in ids:
                node2mod[nid] = mi
    for nid in ids:
        node2mod.setdefault(nid, len(modules))
    members_of = defaultdict(list)
    for nid in ids:
        members_of[node2mod[nid]].append(nid)

    # ---- module dependency DAG: A->B if any edge crosses A into B --------- #
    madj = defaultdict(set)
    mindeg = defaultdict(int)
    seen_me = set()
    for e in edges:
        s, t = e.get('source'), e.get('target')
        if s in ids and t in ids:
            a, b = node2mod[s], node2mod[t]
            if a != b and (a, b) not in seen_me:
                seen_me.add((a, b))
                madj[a].add(b)
                mindeg[b] += 1
    mrank = {mi: 0 for mi in members_of}
    mindeg2 = {mi: mindeg.get(mi, 0) for mi in members_of}
    mq = deque([mi for mi in members_of if mindeg2[mi] == 0])
    while mq:
        u = mq.popleft()
        for v in madj[u]:
            if v in members_of:
                if mrank[u] + 1 > mrank[v]:
                    mrank[v] = mrank[u] + 1
                mindeg2[v] -= 1
                if mindeg2[v] == 0:
                    mq.append(v)

    # ---- compact internal layout per module (relative to its own origin) -- #
    mod_layout = {}   # mi -> (relpos {nid:(x,y)}, content_w, content_h)
    for mi, ms in members_of.items():
        mset = set(ms)
        ladj = defaultdict(list)
        lindeg = defaultdict(int)
        for e in edges:
            s, t = e.get('source'), e.get('target')
            if s in mset and t in mset:
                ladj[s].append(t)
                lindeg[t] += 1
        llayer = {n: 0 for n in ms}
        li = {n: lindeg.get(n, 0) for n in ms}
        lq = deque([n for n in ms if li[n] == 0])
        while lq:
            u = lq.popleft()
            for v in ladj[u]:
                if llayer[u] + 1 > llayer[v]:
                    llayer[v] = llayer[u] + 1
                li[v] -= 1
                if li[v] == 0:
                    lq.append(v)
        cols = defaultdict(list)
        for n in sorted(ms, key=lambda i: ((by_id[i].get('position') or {}).get('y', 0), i)):
            cols[llayer[n]].append(n)
        # crossing-reduce the module's own columns (line siblings up with neighbours)
        lpreds = {n: [] for n in ms}
        lsuccs = {n: [] for n in ms}
        for u, vs in ladj.items():
            for v in vs:
                lsuccs[u].append(v)
                lpreds[v].append(u)
        cols = _layout.order_columns(dict(cols), lpreds, lsuccs)
        maxc = max(cols) if cols else 0
        # Each dataflow column lays out top->bottom, but a column of many
        # PARALLEL siblings (e.g. 6 frame extractors, 4 pose chains) would make
        # the module very tall. Wrap such a column into a grid of sub-columns so
        # the module stays roughly square — trades height for width (the user's
        # "horizontal priority").
        relpos, content_h, x = {}, 0.0, 0.0
        for c in range(maxc + 1):
            ns = cols.get(c, [])  # already crossing-reduced
            if not ns:
                continue
            cw = max(dims[n][0] for n in ns)
            n_sub = max(1, math.ceil(len(ns) / MAX_COL_ROWS))
            rows = math.ceil(len(ns) / n_sub)
            sub_y = [0.0] * n_sub
            for idx, n in enumerate(ns):
                sub = idx // rows
                w, h = dims[n]
                relpos[n] = (x + sub * (cw + inner_h) + (cw - w) / 2, sub_y[sub])
                sub_y[sub] += h + inner_v
            x += n_sub * cw + (n_sub - 1) * inner_h + inner_h
            content_h = max(content_h, max(sub_y) - inner_v)
        content_w = (x - inner_h) if relpos else 320.0
        mod_layout[mi] = (relpos, content_w, content_h)

    # ---- place modules on the rank grid ---------------------------------- #
    by_rank = defaultdict(list)
    for mi in members_of:
        by_rank[mrank[mi]].append(mi)
    # order same-rank modules by their connections (not raw key string) so a
    # module sits next to the modules it feeds / is fed by.
    mpreds = {mi: [] for mi in members_of}
    msuccs = {mi: [] for mi in members_of}
    for a, bs in madj.items():
        for b in bs:
            if a in members_of and b in members_of:
                msuccs[a].append(b)
                mpreds[b].append(a)
    by_rank = _layout.order_columns(dict(by_rank), mpreds, msuccs)
    maxrank = max(by_rank) if by_rank else 0
    box_overhead_w = _layout.GROUP_PAD * 2
    box_overhead_h = _layout.GROUP_PAD * 2 + _layout.GROUP_LABEL_H
    col_box_w = {r: max(mod_layout[mi][1] for mi in by_rank[r]) + box_overhead_w
                 for r in by_rank}
    col_x, xx = {}, 0.0
    for r in range(maxrank + 1):
        col_x[r] = xx
        xx += col_box_w.get(r, 400) + MODULE_H_GAP

    for r in sorted(by_rank):
        mis = by_rank[r]   # already connectivity-ordered
        yy = 0.0
        for mi in mis:
            relpos, cw, ch = mod_layout[mi]
            # center the module's content within its rank column
            ox = col_x[r] + _layout.GROUP_PAD + (col_box_w[r] - box_overhead_w - cw) / 2
            oy = yy + _layout.GROUP_PAD + _layout.GROUP_LABEL_H
            for n, (rx, ry) in relpos.items():
                by_id[n]['position'] = {'x': round(ox + rx), 'y': round(oy + ry)}
            yy += ch + box_overhead_h + MODULE_V_GAP

    # stickies (README etc.): stack in a left rail so they never overlap
    rail_x = round(min(col_x.values(), default=0) - 480)
    sy = 0.0
    for n in nodes:
        if _layout._is_sticky(n):
            n['position'] = {'x': rail_x, 'y': round(sy)}
            _, sh = _layout.est_dims(n)
            sy += sh + 48

    _layout._layout_groups(nodes, by_id, dims)
    return wf


# --------------------------------------------------------------------------- #
def main():
    raw = sys.argv[1:]
    plan_path = None
    if '--plan' in raw:
        i = raw.index('--plan')
        plan_path = raw[i + 1]
        raw = raw[:i] + raw[i + 2:]
    # real pixel sizes (from the editor DOM) make spacing exact instead of
    # estimated — media/result panels are far taller than any estimate
    measured = None
    dims_arg = next((a for a in raw if a.startswith('--dims=')), None)
    if dims_arg:
        measured = json.load(open(dims_arg.split('=', 1)[1]))
        raw = [a for a in raw if not a.startswith('--dims=')]
    dump = '--dump-plan' in raw
    raw = [a for a in raw if a != '--dump-plan']

    inp = raw[0]
    out = raw[1] if len(raw) > 1 else None
    data = json.load(open(inp))
    wf = _layout._unwrap(data)

    plan = json.load(open(plan_path)) if plan_path else build_plan(wf)
    if dump:
        json.dump(plan, sys.stdout, indent=2, ensure_ascii=False)
        return

    apply_plan(wf, plan, measured)
    n_groups = sum(1 for n in wf['nodes'] if _layout._is_group(n))
    n_consts = sum(1 for n in wf['nodes']
                   if str(n.get('id', '')).startswith('const-'))
    if out:
        json.dump(wf, open(out, 'w'), indent=2, ensure_ascii=False)
        print(f'organized: {n_groups} modules, {n_consts} shared constants '
              f'-> {out}')
    else:
        json.dump(wf, sys.stdout, indent=2, ensure_ascii=False)


if __name__ == '__main__':
    main()
