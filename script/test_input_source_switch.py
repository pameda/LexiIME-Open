"""Native input-source roundtrip only; does not generate or capture keystrokes."""
import json, subprocess, pathlib, time
root=pathlib.Path(__file__).resolve().parents[1]
helper=root/'build/tisctl'
def call(*args):
    completed=subprocess.run([str(helper),*args],text=True,capture_output=True,timeout=15)
    try: result=json.loads(completed.stdout)
    except json.JSONDecodeError: result={'error':'No structured response'}
    result['exit_code']=completed.returncode
    return result
before=call('current')
assert 'id' in before, 'Cannot snapshot current input source safely'
result={'before':before}
target='local.inputmethod.lexiime.open'
try:
    result['select']=call('select',target)
    result['selected']=call('current')
    result['selection_verified']=result['selected']['id']==target
finally:
    result['restore']=call('select',before['id'])
    result['after']=call('current')
    result['restore_verified']=result['after']['id']==before['id']
(root/'build/system-test/switch-roundtrip.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2))
assert result['selection_verified'] and result['restore_verified']
