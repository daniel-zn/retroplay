#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regenerate AppHost/Supporting/Licenses (components.json + license texts) from
docs/licensing/inventory.json. Run after changing a bundled core or asset."""
import json, hashlib, os, re, shutil, sys
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
os.chdir(ROOT)
# Core checkouts sit next to the repository (see fetch-core-sources.sh).
PARENT=os.path.dirname(ROOT)
L='docs/licensing/sources'
OUT='AppHost/Supporting/Licenses'
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT): os.remove(os.path.join(OUT,f))
inv=json.load(open('docs/licensing/inventory.json'))
repos={
 'mGBA':('GBA core (mGBA)','https://github.com/mgba-emu/mgba/tree/aa6394c93ca24b0ff40dc9231bdb0533f415e0be'),
 'melonDS':('DS core (melonDS)','https://github.com/melonDS-emu/melonDS/tree/906e9ebb27da8c6a715cd7abab4abfe8a8d29427'),
 'mupen64plus-next':('N64 core (mupen64plus-next)','https://github.com/libretro/mupen64plus-libretro-nx/tree/f275caf4b2bfa1e6d1c51636746ea793f3d80320'),
 'PPSSPP':('PSP core (PPSSPP)','https://github.com/hrydgard/ppsspp/tree/98e70c8ca3435d532a059add0b4fb90a4a091248'),
 'MoltenVK':('PSP core (PPSSPP)','https://github.com/KhronosGroup/MoltenVK/tree/v1.4.2'),
 'Nestopia UE':('NES core (Nestopia UE)','https://github.com/libretro/nestopia/tree/135dfa6dfda5e7603d61e751b9ddd0cc42546bc3'),
 'bsnes':('SNES core (bsnes)','https://github.com/libretro/bsnes/tree/63ee22f7af8f5d1ada295c2c98fd7bf261fa62a7'),
 'ProSystem':('Atari 7800 core (ProSystem)','https://github.com/libretro/prosystem-libretro/tree/8a88014287c7a01cd568067e5a557d0a2b2a051f'),
 'clownmdemu':('Genesis core (clownmdemu)','https://github.com/Clownacy/clownmdemu-libretro/tree/d43c2708b0a31c285ce16724b6c4a2e92af07346'),
 'PCSX-ReARMed':('PS1 core (PCSX-ReARMed)','https://github.com/libretro/pcsx_rearmed/tree/c8816799b50388e61cfe237fe2cdbb7d8175f20a'),
 'RetroPlay app resources':('App','https://github.com/google/fonts/tree/dbd72d6ef9ebea750d33c02c7189633e972d6a40/ofl/pressstart2p'),
}
agent_files=[f for f in os.listdir(L) if f.endswith('.txt')]
manual=json.load(open('docs/licensing/license-map.json'))
seen={}
def slug(s): return re.sub(r'[^A-Za-z0-9]+','-',s).strip('-')[:60]
def add_text(path, name):
    data=open(path,'rb').read()
    h=hashlib.sha256(data).hexdigest()
    if h in seen: return seen[h]
    fn=slug(name)+'.txt'; i=2
    while os.path.exists(os.path.join(OUT,fn)): fn=f'{slug(name)}-{i}.txt'; i+=1
    open(os.path.join(OUT,fn),'wb').write(data); seen[h]=fn; return fn
def resolve(e):
    c=e['component']
    if c in manual: return os.path.join(L,manual[c])
    if c=='Dear ImGui': return f'{L}/imgui-LICENSE-upstream.txt'
    if c.startswith('SFMT'): return f'{L}/sfmt-LICENSE-upstream.txt'
    p=e['licenseFile'].split(' ')[0]
    if not os.path.isabs(p) and not p.startswith('docs/'): p=os.path.join(PARENT, p)
    if os.path.isfile(p) and not re.search(r'\.(c|cpp|h|hpp)$', p): return p
    if os.path.isfile(p):
        # Header-only notice: copy the file's leading comment verbatim.
        lines=open(p, encoding='utf-8', errors='replace').read().splitlines()
        out=[]
        for ln in lines[:200]:
            t=ln.strip()
            if out and t and not (t.startswith(('/*','*','//','*/')) or t.endswith('*/')):
                break
            out.append(ln)
        tmp=os.path.join(L, f"header-{slug(e['component'])}.txt")
        open(tmp,'w').write(f"Notice copied verbatim from {os.path.relpath(p, PARENT)}:\n\n"+"\n".join(out)+"\n")
        return tmp
    return None
entries=[]; unresolved=[]; skipped=[]
for e in inv:
    c=e['component']
    if c.startswith('NOT LINKED') or e['spdx'] in ('n/a',) or 'pgf' in c.lower() or 'flash0' in c.lower():
        skipped.append(c); continue
    src=resolve(e)
    if not src: unresolved.append((c, e['spdx'], e['licenseFile'][:90])); continue
    usedBy,url=repos[e['project']]
    name=re.sub(r'\s*\((?:[^()]|\([^)]*\))*\)\s*$','',c) if len(c)>34 else c
    entries.append(dict(name=name, usedBy=usedBy, license=e['spdx'], copyright=e['copyright'],
        source=url, version=e.get('version') or None, licenseFile=add_text(src, f"{name}-{e['spdx']}")))
if unresolved and '--check' in sys.argv:
    for u in unresolved: print('UNRESOLVED:', u)
    print('agent files:', ' '.join(sorted(agent_files))); sys.exit(1)
entries.append(dict(name='PPSSPP data files (PPGe atlas, VFPU tables, compat.ini, langregion.ini, knownfuncs.ini)',
    usedBy='PSP core (PPSSPP)', license='GPL-2.0-or-later', copyright='Copyright (C) 2012- PPSSPP Project and contributors',
    source=repos['PPSSPP'][1]+'/assets', version='98e70c8ca3', licenseFile=add_text(os.path.join(PARENT,'ppsspp/LICENSE.TXT'),'PPSSPP-GPL-2.0-or-later')))
shutil.copy('LICENSE', os.path.join(OUT,'GPL-3.0.txt'))
order=['App','GBA core (mGBA)','DS core (melonDS)','N64 core (mupen64plus-next)','PSP core (PPSSPP)',
       'NES core (Nestopia UE)','SNES core (bsnes)','Atari 7800 core (ProSystem)','Genesis core (clownmdemu)','PS1 core (PCSX-ReARMed)']
main={'mGBA','melonDS','mupen64plus-next','PPSSPP','MoltenVK','Nestopia','bsnes','ProSystem','clownmdemu','PCSX-ReARMed'}
entries.sort(key=lambda x:(order.index(x['usedBy']), 0 if x['name'].split(' ')[0] in main else 1, x['name'].lower()))
json.dump(entries, open(os.path.join(OUT,'components.json'),'w'), indent=1, ensure_ascii=False)
print(len(entries),'components;', len(os.listdir(OUT))-1,'license files; skipped:',skipped)

# Repository copy of the same notices.
lines=['# Third-party notices','',
 'RetroPlay bundles the components below. Full license texts are in `AppHost/Supporting/Licenses/`',
 '(shown in the app under Settings → Open Source Licenses). Exact core revisions and patches:',
 '`App/Vendor/SOURCES.md`. Inventory and evidence: `docs/licensing/`.','',
 'This file is generated by `App/Vendor/generate-license-bundle.py`; edit the inventory, not this file.','']
current=None
for e in entries:
    if e['usedBy']!=current:
        current=e['usedBy']; lines += ['', f'## {current}', '']
    ver=f" ({e['version']})" if e.get('version') else ''
    lines.append(f"- **{e['name']}**{ver} — {e['license']}. {e['copyright']}. Source: {e['source']}. License text: `AppHost/Supporting/Licenses/{e['licenseFile']}`")
open('THIRD_PARTY_NOTICES.md','w').write('\n'.join(lines)+'\n')
print('wrote THIRD_PARTY_NOTICES.md')

