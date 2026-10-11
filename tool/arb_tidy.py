import glob
import json
import os

ROOT = os.path.join('lib', 'l10n')
order = [k for k in json.load(open(os.path.join(ROOT, 'app_en.arb'), encoding='utf-8')) if not k.startswith('@')]

for path in sorted(glob.glob(os.path.join(ROOT, 'app_*.arb'))):
    code = os.path.basename(path)[4:-4]
    if code == 'en':
        continue
    data = json.load(open(path, encoding='utf-8'))
    keys = [k for k in order if k in data] + [k for k in data if not k.startswith('@') and k not in order]
    lines = [f'  "@@locale": "{code}"'] + [f'  {json.dumps(k)}: {json.dumps(data[k], ensure_ascii=False)}' for k in keys]
    text = '{\n' + ',\n'.join(lines) + '\n}\n'
    json.loads(text)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
