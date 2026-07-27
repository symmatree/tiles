"""Capture layer for the mimir notebooks (tiles#644).

Every raw observation (HTTP response, command output) is recorded under a
stable name, so analysis is a pure function of the capture: a saved capture
replays identically with no network or cluster access, and old snapshots can
be re-analyzed with an improved notebook.
"""
import datetime
import io
import json
import subprocess
import time
from pathlib import Path

import pandas as pd
from IPython.display import Image as _Image, display as _display

MPL_STYLE = {'figure.dpi': 110, 'font.size': 9, 'axes.grid': True, 'grid.alpha': 0.25,
             'axes.spines.top': False, 'axes.spines.right': False}


def show(fig):
    import matplotlib.pyplot as plt
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight')
    plt.close(fig)
    _display(_Image(data=buf.getvalue()))


class Capture:
    def __init__(self, replay_file="", **meta):
        self.replay = bool(replay_file)
        if self.replay:
            self.data = json.loads(Path(replay_file).read_text())
        else:
            self.data = {'meta': dict(meta,
                                      now_unix=time.time(),
                                      run_at=datetime.datetime.now(datetime.timezone.utc)
                                      .isoformat()),
                         'calls': {}}

    @property
    def meta(self):
        return self.data['meta']

    @property
    def now(self):
        return self.meta['now_unix']

    @property
    def run_at(self):
        return self.meta['run_at']

    @property
    def mode(self):
        return 'replay' if self.replay else 'live'

    def http(self, name, url, params=None, headers=None, timeout=60):
        """GET url; record {status, json|text} or {error} under name."""
        if self.replay:
            return self.data['calls'][name]
        import requests
        rec = {'url': url, 'params': params}
        try:
            r = requests.get(url, params=params, headers=headers, timeout=timeout)
            rec['status'] = r.status_code
            try:
                rec['json'] = r.json()
            except ValueError:
                rec['text'] = r.text[:4000]
        except requests.RequestException as e:
            rec['error'] = f"{type(e).__name__}: {e}"
        self.data['calls'][name] = rec
        return rec

    def exec(self, name, argv, timeout=60):
        """Run a read-only command; record {rc, stdout, stderr} under name."""
        if self.replay:
            return self.data['calls'][name]
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        rec = {'argv': argv, 'rc': p.returncode, 'stdout': p.stdout,
               'stderr': p.stderr[-2000:]}
        self.data['calls'][name] = rec
        return rec

    def save(self, path):
        Path(path).write_text(json.dumps(self.data))


def api_result(rec):
    """Result list from a recorded Prometheus/Loki-envelope response; raises on failure."""
    if 'json' not in rec:
        raise RuntimeError(f"call failed: {rec.get('error') or rec.get('text') or rec.get('status')}")
    if rec['json'].get('status') != 'success':
        raise RuntimeError(f"query failed: {str(rec['json'])[:500]}")
    return rec['json']['data']['result']


def val(res, default=float('nan')):
    return float(res[0]['value'][1]) if res else default


def by(res, label):
    return {r['metric'].get(label, ''): float(r['value'][1]) for r in res}


def frame(res, label):
    """Matrix result -> DataFrame indexed by UTC time, one column per label value."""
    cols = {}
    for r in res:
        key = r['metric'].get(label, '') if label else 'value'
        cols[key] = pd.Series({pd.to_datetime(t, unit='s', utc=True): float(v)
                               for t, v in r['values']})
    return pd.DataFrame(cols).sort_index()


class Mimir:
    """Named, capture-recorded queries against the Mimir HTTP API."""

    def __init__(self, cap, url, tenant):
        self.cap, self.url = cap, url
        self.headers = {'X-Scope-OrgID': tenant}

    def get(self, name, path, **params):
        return self.cap.http(name, f"{self.url}{path}", params=params, headers=self.headers)

    def q(self, name, query):
        """Instant vector at the capture's pinned evaluation time."""
        return api_result(self.get(name, '/prometheus/api/v1/query',
                                   query=query, time=self.cap.now))

    def qr(self, name, query, hours, step_s):
        """Range vectors over the trailing window."""
        return api_result(self.get(name, '/prometheus/api/v1/query_range', query=query,
                                   start=self.cap.now - hours * 3600, end=self.cap.now,
                                   step=step_s))


class Loki:
    """Named, capture-recorded queries against the Loki HTTP API."""

    def __init__(self, cap, url, tenant):
        self.cap, self.url = cap, url
        self.headers = {'X-Scope-OrgID': tenant}

    def _range(self, name, params, hours):
        params = dict(params,
                      start=int((self.cap.now - hours * 3600) * 1e9),
                      end=int(self.cap.now * 1e9))
        return self.cap.http(name, f"{self.url}/loki/api/v1/query_range",
                             params=params, headers=self.headers)

    def lines(self, name, query, hours, limit):
        """Log lines as (utc-timestamp, stream-labels, line), newest first."""
        rec = self._range(name, {'query': query, 'limit': limit, 'direction': 'backward'},
                          hours)
        out = []
        for s in api_result(rec):
            for ts, line in s['values']:
                out.append((pd.to_datetime(int(ts), unit='ns', utc=True), s['stream'], line))
        out.sort(key=lambda x: x[0], reverse=True)
        return out[:limit]

    def metric_range(self, name, query, hours, step_s):
        """LogQL metric query -> matrix result (shape with frame())."""
        return api_result(self._range(name, {'query': query, 'step': step_s}, hours))


class Kube:
    """Named, capture-recorded read-only kubectl gets."""

    def __init__(self, cap):
        self.cap = cap

    def get(self, name, *args):
        rec = self.cap.exec(name, ['kubectl', 'get', *args, '-o', 'json'])
        if rec['rc'] != 0:
            raise RuntimeError(f"kubectl get {args} failed: {rec['stderr']}")
        return json.loads(rec['stdout'])
