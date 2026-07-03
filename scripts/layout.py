#!/usr/bin/env python3
"""Auto-layout for Wireflow workflows — codebase-free, no browser required.

Programmatically-authored workflows have no rendered DOM, so node positions
are otherwise guessed blind and overlap (a tall system-prompt node or an
image node with a result panel is far bigger than an "average" node). This
estimates each node's rendered size from its content + port count, then runs
a layered left-to-right DAG layout so nodes never overlap and the graph reads
in flow order. wf.sh runs this automatically before `create`.

Usage:
  layout.py <workflow.json> [out.json]   # rewrite node positions in place
  layout.py --check <workflow.json>      # report overlapping node pairs (exit 1 if any)

Heuristic, not pixel-perfect: very large *cached result* panels (post-run)
can still exceed the estimate. For initial layout this is more than enough;
re-run after a workflow has results if you want it re-packed.
"""
import sys, json, math
from collections import deque

H_GAP = 130   # gap between columns (estimate mode — needs cushion)
V_GAP = 64    # gap between stacked nodes in a column (estimate mode)
H_GAP_MEASURED = 90   # tighter gaps when we have real pixel sizes
V_GAP_MEASURED = 46


def _is_sticky(node):
    return node.get('type') == 'stickyNote' or \
        (node.get('data') or {}).get('nodeType') == 'utility:sticky_note'


def _is_group(node):
    return node.get('type') == 'custom_group'


GROUP_PAD = 44      # breathing room between a module box and its member nodes
GROUP_LABEL_H = 38  # extra headroom at the top of the box for the title


def _sticky_size(node):
    """Size a sticky to fit its text and write BOTH `style.{width,height}` and
    top-level width/height. The sticky renders via a React Flow NodeResizer that
    reads `style`, so a size set only on top-level width/height (or not at all)
    silently collapses to a tiny ~200x100 default and clips the text."""
    data = node.get('data', {}) or {}
    st = node.get('style') or {}
    w = int(node.get('width') or st.get('width') or 340)
    text = data.get('text', '') or ''
    cpl = max(14, int(w / 8.2))                      # chars per line at this width
    lines = sum(max(1, math.ceil(len(l) / cpl)) for l in text.split('\n')) or 3
    h = int(max(110, 34 + lines * 20))               # always fit the text
    node['width'] = w
    node['height'] = h
    node['style'] = {**st, 'width': w, 'height': h}
    return float(w), float(h)


def est_dims(node, measured=None):
    """(width, height) of a node — measured if available, else estimated."""
    if _is_sticky(node):
        return _sticky_size(node)   # text-fit size + repairs style; ignore broken default measure
    if measured:
        m = measured.get(node.get('id'))
        if m and m.get('width') and m.get('height'):
            return float(m['width']), float(m['height'])
    data = node.get('data', {}) or {}
    nt = data.get('nodeType', '') or ''
    cfg = data.get('config', {}) or {}
    rows = max(len(data.get('inputs') or []), len(data.get('outputs') or []))
    h = 70 + rows * 30                      # header + port rows
    longest = 0
    for k in ('system_prompt', 'prompt', 'text', 'paths', 'caption', 'description'):
        v = cfg.get(k)
        if isinstance(v, str):
            longest = max(longest, len(v))
    if longest > 80:                        # inline text block expands the card
        h += min(math.ceil(longest / 38) * 18 + 30, 460)
    cat = data.get('category', '') or ''
    family = nt.split(':')[0]
    if cat in ('generate', 'video', 'audio', 'process', 'talking') or \
       family in ('generate', 'edit', 'video', 'audio', 'process', 'talking'):
        h += 120                            # media/result preview allowance
    w = 300 if cat == 'input' else 340
    return float(w), float(max(h, 96))


def _unwrap(data):
    if isinstance(data, dict) and 'nodes' not in data and 'data' in data:
        return data['data']
    return data


def _median(xs):
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def order_columns(cols, preds, succs, sweeps=6):
    """Sugiyama vertex-ordering (crossing reduction). Given columns of node ids
    (left→right by topological layer) plus each node's predecessor/successor
    lists, reorder nodes WITHIN each column so connected nodes line up — killing
    the random-stack / zig-zag look. X (the column) never changes; only the
    vertical order does. A node with no neighbour in the reference column keeps
    its current slot, so loose nodes don't jump to the top.

    `cols`: dict layer -> list of ids (initial order). Returns the same dict with
    each list reordered."""
    order = {c: list(cols[c]) for c in cols}
    layers = sorted(order)
    if len(layers) < 2:
        return order
    pos = {nid: i for c in layers for i, nid in enumerate(order[c])}
    for sweep in range(sweeps):
        down = sweep % 2 == 0
        seq = layers if down else list(reversed(layers))
        for c in seq:
            ref = preds if down else succs

            def key(nid):
                ns = [pos[m] for m in ref.get(nid, ()) if m in pos]
                return _median(ns) if ns else pos[nid]

            order[c] = sorted(order[c], key=key)
            for i, nid in enumerate(order[c]):
                pos[nid] = i
    return order


def layout(wf, measured=None):
    hgap = H_GAP_MEASURED if measured else H_GAP
    vgap = V_GAP_MEASURED if measured else V_GAP
    nodes = wf.get('nodes', [])
    edges = wf.get('edges', [])
    by_id = {n['id']: n for n in nodes}
    adj = {nid: [] for nid in by_id}
    indeg = {nid: 0 for nid in by_id}
    touched = set()
    for e in edges:
        s, t = e.get('source'), e.get('target')
        if s in by_id and t in by_id:
            adj[s].append(t)
            indeg[t] += 1
            touched.add(s)
            touched.add(t)
    dims = {n['id']: est_dims(n, measured) for n in nodes}

    # column index = longest path from a root (Kahn topological relaxation)
    layer = {nid: 0 for nid in by_id}
    indeg2 = dict(indeg)
    q = deque([nid for nid in touched if indeg[nid] == 0])
    while q:
        u = q.popleft()
        for v in adj[u]:
            if layer[u] + 1 > layer[v]:
                layer[v] = layer[u] + 1
            indeg2[v] -= 1
            if indeg2[v] == 0:
                q.append(v)

    # initial column membership, deterministically ordered by existing y then id
    # (set iteration order is otherwise arbitrary → random vertical stacking).
    col_ids = {}
    for nid in sorted(touched, key=lambda i: ((by_id[i].get('position') or {}).get('y', 0), i)):
        col_ids.setdefault(layer[nid], []).append(nid)
    # crossing-reduction: line same-column siblings up with their neighbours.
    preds = {nid: [] for nid in by_id}
    succs = {nid: [] for nid in by_id}
    for e in edges:
        s, t = e.get('source'), e.get('target')
        if s in by_id and t in by_id:
            succs[s].append(t)
            preds[t].append(s)
    col_ids = order_columns(col_ids, preds, succs)
    cols = {c: [by_id[i] for i in ids] for c, ids in col_ids.items()}
    maxcol = max(cols) if cols else 0
    colw = {c: max((dims[n['id']][0] for n in cols[c]), default=320) for c in cols}
    colx, x = {}, 0.0
    for c in range(maxcol + 1):
        colx[c] = x
        x += colw.get(c, 320) + hgap

    coltop = {}
    for c in sorted(cols):
        ordered = cols[c]  # already crossing-reduced
        total = sum(dims[n['id']][1] for n in ordered) + vgap * max(0, len(ordered) - 1)
        cy = -total / 2.0          # center each column on a shared mid-line
        coltop[c] = cy
        for n in ordered:
            w, h = dims[n['id']]
            n['position'] = {'x': round(colx[c] + (colw[c] - w) / 2), 'y': round(cy)}
            cy += h + vgap

    # annotation nodes (no edges, e.g. sticky notes): park above the nearest column.
    # custom_group module boxes are handled separately below — they wrap members.
    ann = [n for n in nodes if n['id'] not in touched and not _is_group(n)]
    groups = {}
    for a in ann:
        ax = (a.get('position') or {}).get('x', 0)
        nc = min(range(maxcol + 1), key=lambda c: abs(colx.get(c, 0) - ax)) if cols else 0
        groups.setdefault(nc, []).append(a)
    for c, items in groups.items():
        items = sorted(items, key=lambda a: (a.get('position') or {}).get('y', 0))
        cursor = coltop.get(c, 0.0) - 56
        for a in reversed(items):
            w, h = dims[a['id']]
            cursor -= h
            a['position'] = {'x': round(colx.get(c, 0)), 'y': round(cursor)}
            cursor -= 56

    # module boxes (custom_group): wrap each box around its members' final
    # positions. A group is a visual container, so it isn't laid out in the DAG —
    # instead we size+place it to enclose `data.childNodeIds` with padding and a
    # title strip. Written to data.{width,height}, top-level, and style (the
    # React Flow NodeResizer reads style, like sticky notes).
    _layout_groups(nodes, by_id, dims)
    return wf


def _layout_groups(nodes, by_id, dims):
    for g in nodes:
        if not _is_group(g):
            continue
        data = g.get('data', {}) or {}
        child_ids = [c for c in (data.get('childNodeIds') or []) if c in by_id]
        members = [by_id[c] for c in child_ids if not _is_group(by_id[c])]
        if not members:
            continue
        minx = miny = float('inf')
        maxx = maxy = float('-inf')
        for m in members:
            p = m.get('position') or {}
            mx, my = p.get('x', 0), p.get('y', 0)
            mw, mh = dims.get(m['id'], (340.0, 120.0))
            minx, miny = min(minx, mx), min(miny, my)
            maxx, maxy = max(maxx, mx + mw), max(maxy, my + mh)
        gx = round(minx - GROUP_PAD)
        gy = round(miny - GROUP_PAD - GROUP_LABEL_H)
        gw = round((maxx - minx) + GROUP_PAD * 2)
        gh = round((maxy - miny) + GROUP_PAD * 2 + GROUP_LABEL_H)
        g['position'] = {'x': gx, 'y': gy}
        g['width'] = gw
        g['height'] = gh
        g['zIndex'] = -1
        g['style'] = {**(g.get('style') or {}), 'width': gw, 'height': gh}
        data['width'] = gw
        data['height'] = gh
        g['data'] = data


def check(wf, measured=None):
    # group boxes are meant to overlap their members — exclude from overlap report
    real = [n for n in wf.get('nodes', []) if not _is_group(n)]
    dims = {n['id']: est_dims(n, measured) for n in real}
    boxes = []
    for n in real:
        p = n.get('position') or {}
        w, h = dims[n['id']]
        boxes.append((n['id'], p.get('x', 0), p.get('y', 0), w, h))
    out = []
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, ax, ay, aw, ah = boxes[i]
            b, bx, by, bw, bh = boxes[j]
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                out.append((a, b))
    return out


if __name__ == '__main__':
    raw = sys.argv[1:]
    measured = None
    dims_arg = next((a for a in raw if a.startswith('--dims=')), None)
    if dims_arg:
        measured = json.load(open(dims_arg.split('=', 1)[1]))
    args = [a for a in raw if not a.startswith('--dims=')]
    if args and args[0] == '--check':
        data = json.load(open(args[1])) if len(args) > 1 else json.load(sys.stdin)
        ov = check(_unwrap(data), measured)
        print(f'overlaps: {len(ov)}')
        for a, b in ov[:50]:
            print('  ', a, '<->', b)
        sys.exit(1 if ov else 0)
    inp = args[0] if args else None
    data = json.load(open(inp)) if inp else json.load(sys.stdin)
    wf = _unwrap(data)
    layout(wf, measured)
    if len(args) > 1:
        json.dump(wf, open(args[1], 'w'), indent=2)
        mode = 'measured' if measured else 'estimated'
        print(f'laid out {len(wf.get("nodes", []))} nodes ({mode}) -> {args[1]}')
    else:
        json.dump(wf, sys.stdout, indent=2)
