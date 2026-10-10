from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import os
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
checkout=subprocess.run(['git','-C',str(root),'rev-parse','--show-toplevel'],capture_output=True,text=True)
if checkout.returncode or Path(checkout.stdout.strip()).resolve()!=root:
    raise SystemExit('Source packaging requires this project Git checkout; stage the project source first.')
tracked=subprocess.check_output(['git','-C',str(root),'ls-files','-z']).split(b'\0')
files=[root/os.fsdecode(name) for name in tracked if name]
for path in files:
    resolved=path.resolve()
    if not path.is_file() or path.is_symlink() or root not in resolved.parents:
        raise SystemExit(f'Unusable or redirected tracked file: {path.relative_to(root)}')
    if path.relative_to(root).parts[0] in ['build','dist','.git']:
        raise SystemExit('Generated or runtime directories must not be tracked.')
for required in ['LICENSE','THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','README.md']:
    if root/required not in files: raise SystemExit(f'Stage required document: {required}')
(root/'dist').mkdir(exist_ok=True)
target=root/'dist'/'LexiIME-Open-source-0.1.1.zip'
with tempfile.NamedTemporaryFile(prefix='source.',suffix='.zip',dir=root/'dist',delete=False) as temporary:
    staging=Path(temporary.name)
try:
    with ZipFile(staging,'w',ZIP_DEFLATED) as archive:
        for path in sorted(files): archive.write(path,Path('LexiIME-Open')/path.relative_to(root))
    staging.replace(target)
finally:
    staging.unlink(missing_ok=True)
print(f'Created source archive with {len(files)} tracked project files, including license notices; untracked and ignored files excluded.')
