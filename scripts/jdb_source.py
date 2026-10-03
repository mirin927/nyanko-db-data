"""One pinned upstream revision for every converter; optionally read a local checkout."""
import io
import os
import pathlib
import re
import urllib.request

REVISION = os.environ.get('JDB_REVISION', '525a4c287e84f2261bdb7ea4cc82a03227796038')
if not re.fullmatch('[a-f0-9]{40}', REVISION):
    raise ValueError('JDB_REVISION must be a full commit SHA')
BASE = f'https://raw.githubusercontent.com/JarJarBlink/JDB/{REVISION}/'

def open_source(url, timeout=30):
    checkout = os.environ.get('JDB_SOURCE')
    if checkout and url.startswith(BASE):
        path = pathlib.Path(checkout) / url[len(BASE):]
        return io.BytesIO(path.read_bytes())
    return urllib.request.urlopen(url, timeout=timeout)
