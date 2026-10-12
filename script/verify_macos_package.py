"""Validate developer package/preview contents against the current build."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--installed',action='store_true',help='also compare the per-user installation')
args=parser.parse_args()
arch=subprocess.check_output(['uname','-m'],text=True).strip()
pkg=ROOT/f'dist/LexiIME-Open-macOS-{arch}-0.1.1-developer.pkg'
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
records=[]
with tempfile.TemporaryDirectory(prefix='pkg-verify.',dir=ROOT/'build') as temporary:
    expanded=pathlib.Path(temporary)/'expanded'
    subprocess.run(['/usr/sbin/pkgutil','--expand-full',str(pkg),str(expanded)],check=True)
    for name,target in [('LexiIME-Open',pathlib.Path.home()/'Applications/LexiIME-Open.app'),('LexiIME-Open Input',pathlib.Path.home()/'Library/Input Methods/LexiIME-Open Input.app')]:
        apps=list(expanded.rglob(name+'.app'))
        assert len(apps)==1,'Expected exactly one packaged app'
        packaged=apps[0]
        built=ROOT/'dist'/f'{name}.app'
        executable=pathlib.Path('Contents/MacOS/LexiIME-Open')
        assert digest(packaged/executable)==digest(built/executable),'Executable mismatch'
        info=plistlib.loads((packaged/'Contents/Info.plist').read_bytes())
        assert info==plistlib.loads((built/'Contents/Info.plist').read_bytes()),'Plist mismatch'
        for document in ['LICENSE','THIRD_PARTY_NOTICES.md']:
            assert (packaged/'Contents/Resources'/document).read_bytes()==(ROOT/document).read_bytes(),'Missing or changed license notice'
        for icon in ['menu.tiff','menu.pdf','AppIcon.icns','InputIcon.icns']:
            assert digest(packaged/'Contents/Resources'/icon)==digest(built/'Contents/Resources'/icon),'Icon resource mismatch'
        assert (packaged/'Contents/Resources'/info['CFBundleIconFile']).is_file(),'Application icon missing'
        assert info['NSMicrophoneUsageDescription'] and info['NSSpeechRecognitionUsageDescription']
        if name=='LexiIME-Open Input':
            assert 'TISInputSourceID' not in info,'Parent must not shadow the selectable mode'
            modeID=info['CFBundleIdentifier']+'.pinyin'
            modes=info['ComponentInputModeDict']
            assert modes['tsVisibleInputModeOrderedArrayKey']==[modeID]
            mode=modes['tsInputModeListKey'][modeID]
            assert mode['TISInputSourceID']==modeID and mode['tsInputModeIsVisibleKey']
            assert mode['tsInputModeScriptKey']=='smSimpChinese'
            for key in ['tsInputModeMenuIconFileKey','tsInputModeAlternateMenuIconFileKey','tsInputModePaletteIconFileKey']:
                assert mode[key]=='menu.pdf' and (packaged/'Contents/Resources'/mode[key]).is_file()
            for locale in ['en','zh-Hans']:
                strings=(packaged/'Contents/Resources'/f'{locale}.lproj/InfoPlist.strings').read_text()
                assert f'"{modeID}"' in strings,'Localized mode name missing'
            assert info['InputMethodConnectionName']==info['CFBundleIdentifier']+'_Connection'
            assert info['InputMethodServerControllerClass']=='LexiInputController'
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(packaged)],check=True)
        record={'app':name,'build':info['CFBundleVersion'],'sha256':digest(packaged/executable),'signatureVerified':True}
        if args.installed:
            assert digest(target/executable)==record['sha256'],'Installed executable mismatch'
            assert plistlib.loads((target/'Contents/Info.plist').read_bytes())==info,'Installed metadata mismatch'
            for icon in ['menu.tiff','menu.pdf','AppIcon.icns','InputIcon.icns']:
                assert digest(target/'Contents/Resources'/icon)==digest(built/'Contents/Resources'/icon),'Installed icon mismatch'
            record['installedBinaryMatches']=True
            record['installedMetadataAndIconsMatch']=True
        records.append(record)
    with zipfile.ZipFile(ROOT/f'dist/LexiIME-Open-macOS-{arch}-0.1.1-preview.zip') as archive:
        assert archive.testzip() is None
        assert hashlib.sha256(archive.read('LexiIME-Open.app/Contents/MacOS/LexiIME-Open')).hexdigest()==records[0]['sha256']
result={'package':pkg.name,'apps':records,'previewVerified':True,'unsignedInstaller':True,'notNotarized':True}
(ROOT/'build/system-test').mkdir(parents=True,exist_ok=True)
(ROOT/'build/system-test/package-current.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
