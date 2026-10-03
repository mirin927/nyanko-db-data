#!/usr/bin/env python3
"""Record the published feed and UTC month, keeping scheduled repository activity."""
import datetime
import json
import pathlib
import sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
state = {'checkedMonth': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m'),
         'release': manifest['id'], 'sourceRevision': manifest['sourceRevision'],
         'sequence': manifest['sequence']}
pathlib.Path(sys.argv[2]).write_text(json.dumps(state, indent=2, sort_keys=True) + '\n')
