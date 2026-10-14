#!/usr/bin/env python3
"""Build a self-contained app using local tools; rewrite all Homebrew dylib paths."""
import pathlib,subprocess,shutil,os,json
root=pathlib.Path(__file__).resolve().parent
app=root/'build/GSMaster-gpt.app'; contents=app/'Contents'; resources=contents/'Resources'; tools=resources/'tools'
for p in [contents/'MacOS',resources/'engine',tools,contents/'Frameworks']:p.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'build/GSMaster',contents/'MacOS/GSMaster')
for name in ['engine.mjs','codecs.cjs']:shutil.copy2(root/'engine'/name,resources/'engine'/name)
# Collect dependency closure by real source path, while retaining referenced library names.
queue=[];copied={}
for name in ['node','ffmpeg','ffprobe']:
 src=pathlib.Path(shutil.which(name)).resolve();dst=tools/name;shutil.copy2(src,dst);queue.append((src,dst))
def dependencies(src):
 return [line.strip().split(' (')[0] for line in subprocess.check_output(['otool','-L',str(src)],text=True).splitlines()[1:]]
while queue:
 src,dst=queue.pop(0)
 subprocess.run(['chmod','u+w',str(dst)],check=True)
 subprocess.run(['codesign','--remove-signature',str(dst)],stderr=subprocess.DEVNULL)
 for dep in dependencies(src):
  if dep.startswith('/usr/lib/') or dep.startswith('/System/'):continue
  if dep.startswith('@rpath/'):
   candidate=src.parent/pathlib.Path(dep).name
   if not candidate.exists():raise RuntimeError('Unresolved '+dep+' in '+str(src))
  elif dep.startswith('@loader_path/'):
   candidate=src.parent/dep[len('@loader_path/'):]
  else:candidate=pathlib.Path(dep)
  if not candidate.exists():raise RuntimeError('Missing dependency '+str(candidate))
  real=candidate.resolve();name=pathlib.Path(dep).name
  lib=contents/'Frameworks'/name
  if name not in copied:copied[name]=str(real);shutil.copy2(real,lib);queue.append((real,lib))
  elif copied[name]!=str(real):raise RuntimeError('Library collision '+name)
  replacement=('@loader_path/' if dst.parent.name=='Frameworks' else '@loader_path/../../Frameworks/')+name
  subprocess.run(['install_name_tool','-change',dep,replacement,str(dst)],check=True,stderr=subprocess.DEVNULL)
 if dst.suffix=='.dylib':subprocess.run(['install_name_tool','-id','@loader_path/'+dst.name,str(dst)],check=True,stderr=subprocess.DEVNULL)
plist='''<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>GSMaster</string><key>CFBundleIdentifier</key><string>local.dcmaster.compressor</string><key>CFBundleName</key><string>GSMaster-gpt</string><key>CFBundleDisplayName</key><string>GSMaster-gpt</string><key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.2.0</string><key>CFBundleVersion</key><string>4</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>NSHighResolutionCapable</key><true/><key>NSHumanReadableCopyright</key><string>GSMaster-gpt · Local compressor</string></dict></plist>'''
(contents/'Info.plist').write_text(plist)
shutil.copy2(root/'build/AppIcon.icns',resources/'AppIcon.icns')
shutil.copy2(root/'README.md',resources/'使用说明.md')
# Preserve upstream notices for the redistributed runtimes and image codecs.
notices=resources/'Licenses';notices.mkdir(exist_ok=True)
shutil.copy2(pathlib.Path(shutil.which('node')).resolve().parent.parent/'LICENSE',notices/'Node-runtime-LICENSE.txt')
shutil.copy2(root.parent/'THIRD_PARTY_NOTICES.txt',notices/'JavaScript-dependencies.txt')
for cellar in [pathlib.Path('/opt/homebrew/Cellar'),pathlib.Path(shutil.which('node')).resolve().parent.parent]:
 if not cellar.exists():continue
 if cellar.name=='Cellar':
  used={str(pathlib.Path(v)).split('/Cellar/')[1].split('/')[0] for v in copied.values() if '/Cellar/' in v};used.add('ffmpeg')
  dirs=[cellar/n for n in used]
 else:dirs=[cellar]
 for d in dirs:
  for f in d.rglob('*'):
   if f.is_file() and f.name.lower() in ['license','license.txt','copying','copying.gplv2','copying.gplv3','copyright','notice','notice.txt']:
    dest=notices/(d.name+'-'+f.parent.name+'-'+f.name);shutil.copy2(f,dest)
(resources/'dependency-paths.json').write_text(json.dumps(copied,indent=2))
for p in list((contents/'Frameworks').glob('*'))+list(tools.glob('*'))+[contents/'MacOS/GSMaster']:
 subprocess.run(['codesign','--force','--sign','-',str(p)],check=True,stderr=subprocess.DEVNULL)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
