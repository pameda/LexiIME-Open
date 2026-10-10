"""Authorized native UI test confined to a disposable LexiIME-Open document.
The passive fixture never posts events itself. The trusted caller sends only to
its PID and refuses to type after focus moves. No mic, API or real credentials.
"""
import ctypes
import json
import os
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/system-test'
APP = 'local.lexiime.open.systemtest'
TARGET = 'local.inputmethod.lexiime.open'
CONFIG = pathlib.Path.home() / 'Library/Application Support/LexiIME-Open/settings.json'
KEYS = dict(zip('asdfhgzxcvbqwertyouipljknm', [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,17,16,31,32,34,35,37,38,40,45,46]))


def call(binary, *args, strict=True):
    p = subprocess.run([str(ROOT/'build'/binary), *map(str,args)], capture_output=True, text=True, timeout=20)
    try:
        result = json.loads(p.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f'{binary} produced no structured result')
    if strict and (p.returncode or (isinstance(result,dict) and (result.get('error') or result.get('status',0)!=0))):
        raise RuntimeError(f'{binary} action failed')
    return result


def state(predicate=lambda s: True, timeout=4):
    end = time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            value = json.loads((OUT/'fixture-state.json').read_text())
            if predicate(value):
                return value
        except (FileNotFoundError,json.JSONDecodeError):
            pass
        time.sleep(.1)
    raise RuntimeError('Test fixture state did not reach the required condition')


def key(code,flags=0):
    current=state()
    if not current['active'] or not current['keyWindow']:
        raise RuntimeError('Test document lost focus; typing stopped')
    count=current['keyEventsReceived']
    call('native-ax','key',APP,code,flags)
    state(lambda s:s['keyEventsReceived']>count)


def type_text(text):
    for letter in text:
        key(KEYS[letter])


def focus(identifier):
    call('native-ax','focus',APP,identifier)
    time.sleep(.6)


def reset():
    focus('lexi-test-document')
    key(53)
    call('native-ax','clear',APP)
    state(lambda s:s['text']=='' and not s['marked'])


def page_expected():
    core=ctypes.CDLL(str(ROOT/'build/libLexiCore-test.dylib'))
    core.lexi_create.restype=ctypes.c_void_p
    core.lexi_load.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    core.lexi_query.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int]
    core.lexi_query.restype=ctypes.c_char_p
    core.lexi_destroy.argtypes=[ctypes.c_void_p]
    engine=core.lexi_create()
    try:
        for pack in sorted((ROOT/'data').glob('[0-9]*.tsv')):
            assert core.lexi_load(engine,str(pack).encode())>0
        candidates=json.loads(core.lexi_query(engine,b'w',b'pinyin',b'en',1))
        assert len(candidates)>5
        return candidates[5]['text']
    finally:
        core.lexi_destroy(engine)


def save_config(data):
    temporary=CONFIG.with_suffix('.system-test.tmp')
    temporary.write_bytes(data)
    os.replace(temporary,CONFIG)


before=CONFIG.read_bytes() if CONFIG.exists() else None
original=call('tisctl','current')['id']
result={'originalSource':original,'cases':[]}
keep_awake=None
try:
    result['desktop']=call('native-ax','session')
    if result['desktop']['screenLocked'] or result['desktop']['displayAsleep']:
        raise RuntimeError('Desktop is locked/asleep; unlock required before native typing')
    result['permissions']=call('native-ax','trust')
    if not all(result['permissions'].values()):
        raise RuntimeError('Existing native automation permissions unavailable')
    if any((CONFIG.parent/'Dictionaries').glob('*.tsv')):
        raise RuntimeError('Custom dictionaries present; use a clean test account for deterministic seed-only checks')
    keep_awake=subprocess.Popen(['/usr/bin/caffeinate','-di','-t','240'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    settings=json.loads(before) if before else {}
    settings.update(language='en',mode='pinyin',correction=True,study=False,cloudEnabled=False,frequencyRanking=False,syncEnabled=False,disabledPacks=[],candidatePageSize=5,chinesePunctuation=True)
    save_config(json.dumps(settings,ensure_ascii=False).encode())
    subprocess.run(['pkill','-x','LexiSystemTest'],check=False)
    for filename in ['fixture-state.json','probe-input.json']:
        (OUT/filename).unlink(missing_ok=True)
    subprocess.run(['/usr/bin/open','-n',str(ROOT/'build/LexiIME-Open System Test.app'),'--args','--fixture'],check=True,timeout=15)
    state()
    result['activation']=call('native-ax','activate',APP)
    state(lambda s:s['active'] and s['keyWindow'])
    call('tisctl','select','com.apple.keylayout.ABC')
    focus('lexi-test-document')
    state(lambda s:s['source']=='com.apple.keylayout.ABC')
    call('native-ax','clear',APP)
    type_text('nihao')
    calibration=state(lambda s:s['text']=='nihao')
    result['calibration']={'expected':'nihao','actual':calibration['text'],'keyEventsReceived':calibration['keyEventsReceived'],'passed':True}
    reset()
    # Register and select in the fixture's GUI context, then read actual source.
    # AXPress can time out while its synchronous diagnostic action is running.
    result['probePress']=call('native-ax','press',APP,'lexi-probe-source',strict=False)
    deadline=time.monotonic()+12
    while not (OUT/'probe-input.json').exists() and time.monotonic()<deadline:
        time.sleep(.1)
    result['registration']=json.loads((OUT/'probe-input.json').read_text())
    current=state()
    result['selectedInDocument']=current['source']
    if current['source']!=TARGET or result['registration'].get('select')!=0:
        raise RuntimeError('macOS did not enable/select LexiIME-Open; IME typing cases skipped')
    focus('lexi-test-document')
    def record(name,expected):
        time.sleep(.6)
        observed=state()
        result['cases'].append({'name':name,'expected':expected,'actual':observed['text'],'marked':observed['marked'],'source':observed['source'],'passed':observed['text']==expected and not observed['marked'] and observed['source']==TARGET})
    for name,code,expected in [('full-pinyin','nihao','你好'),('initials','nh','你好'),('correction','nihoa','你好'),('sentence','woqubeijing','我去北京')]:
        reset();type_text(code)
        if name=='full-pinyin':
            observed=state();result['compositionBeforeCommit']={'text':observed['text'],'marked':observed['marked']}
        key(49);record(name,expected)
    reset();type_text('nihao');key(51);type_text('o');key(49);record('backspace','你好')
    reset();type_text('nihao');key(53);record('escape','')
    reset();type_text('nihao');key(36);record('raw-return','nihao')
    reset();type_text('nihao');key(49);key(47);record('chinese-period','你好。')
    reset();key(56,1<<17);type_text('hello');key(47);record('english-shift','hello.')
    key(56,1<<17);reset();type_text('nihao');key(49);record('chinese-shift-return','你好')
    reset();type_text('nihao');key(18);record('number-candidate','你好')
    reset();type_text('w');key(24);key(18);record('page-next-number',page_expected())
    reset();type_text('nihao');focus('lexi-other')
    observed=state()
    result['focusChange']={'document':observed['text'],'other':observed['otherText'],'marked':observed['marked'],'passed':observed['text']=='nihao' and observed['otherText']=='' and not observed['marked']}
    focus('lexi-secure');type_text('nihao');observed=state(lambda s:s['secureTestText']=='nihao')
    result['secureField']={'testValue':observed['secureTestText'],'secureEventInput':observed['secureEventInput'],'passed':bool(observed['secureEventInput'])}
    focus('lexi-test-document')
except Exception as error:
    result['error']=str(error)
    try:
        result['lastFixtureState']=json.loads((OUT/'fixture-state.json').read_text())
    except (FileNotFoundError,json.JSONDecodeError):
        pass
finally:
    # Independent restoration steps: source failure must not skip config cleanup.
    try:
        focus('lexi-test-document')
    except Exception:
        pass
    try:
        result['restore']=call('tisctl','select',original,strict=False)
        result['after']=call('tisctl','current')['id']
        result['restoreVerified']=result['after']==original
    except Exception as error:
        result['restoreError']=type(error).__name__
        result['restoreVerified']=False
    try:
        if before is None:
            CONFIG.unlink(missing_ok=True)
        else:
            save_config(before)
        result['preferencesRestored']=CONFIG.read_bytes()==before if before is not None else not CONFIG.exists()
    except Exception as error:
        result['preferencesRestoreError']=type(error).__name__
        result['preferencesRestored']=False
    subprocess.run(['pkill','-x','LexiSystemTest'],check=False)
    if keep_awake is not None:
        keep_awake.terminate()
        keep_awake.wait(timeout=5)
    (OUT/'ui-input.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2))
passed=not result.get('error') and len(result['cases'])==12 and all(x['passed'] for x in result['cases']) and result.get('compositionBeforeCommit',{}).get('marked') and all(result.get(k,{}).get('passed',False) for k in ['focusChange','secureField']) and result.get('restoreVerified') and result.get('preferencesRestored')
raise SystemExit(0 if passed else 1)
