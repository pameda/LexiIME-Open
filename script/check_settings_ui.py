"""Read-only checks for a freshly opened LexiIME-Open settings page.
Does not click, activate, post keys, request permissions, record, or call APIs.
"""
import argparse
import json
import pathlib
import plistlib
import subprocess

root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('page',choices=['voice','welcome','tools','input','sync'])
parser.add_argument('--app',type=pathlib.Path,help='Inspect this built settings app instead of the user installation')
args=parser.parse_args()
app=args.app or pathlib.Path.home()/'Applications/LexiIME-Open.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
nodes=json.loads(subprocess.check_output([str(root/'build/native-ax'),'tree','local.lexiime.open.settings'],timeout=20))
texts=[str(n.get('AXValue',n.get('AXDescription',n.get('AXTitle','')))) for n in nodes]
result={'page':args.page,'build':info['CFBundleVersion'],'inspectionOnly':True}
if args.page=='voice':
    labels=[t for t in texts if '语音权限：' in t or '本地识别资源可用' in t or '缺少本地识别支持' in t or '语音服务暂不可用' in t]
    assert any('语音权限：' in t for t in labels),'Voice permissions UI missing'
    assert any('本地识别资源可用' in t or '缺少本地识别支持' in t or '语音服务暂不可用' in t for t in labels),'Resource state UI missing'
    result['labels']=labels
    combined='\n'.join(str(n.get(k,'')) for n in nodes for k in ['AXValue','AXDescription','AXTitle'])
    for label in ['AI 文字处理 · 可选','个人语音术语','发送这段文字给个人 API（可能收费）']:
        assert label in combined,'Voice writing UI missing: '+label
    result['writingControlsVisible']=True
elif args.page=='welcome':
    headings=['尚未安装系统输入组件','系统尚未完整识别词伴开源版','已安装，等待启用','已启用，尚未切换到词伴开源版','系统当前选中了词伴开源版']
    heading=next((t for t in texts if t in headings),None)
    assert heading,'Availability card missing'
    assert '应用内试用 · 不影响其他应用' in texts,'Preview boundary missing'
    result['availabilityHeading']=heading
    result['previewBoundaryVisible']=True
else:
    required={'tools':['本地工具试用','自定义常用语','候选偏好','521'],'input':['模糊拼音 · z / zh、c / ch、s / sh','模糊拼音 · n / l','候选文字大小','按本机选词频率优先排序','清空本机词频记录'],'sync':['个人词库，随设备同行。','启用个人词库同步','尚未选择文件夹','同步已关闭，个人数据保存在本机。']}[args.page]
    combined='\n'.join(str(n.get(k,'')) for n in nodes for k in ['AXValue','AXDescription','AXTitle'])
    for label in required:assert label in combined,'Desktop feature UI missing: '+label
    result['verifiedLabels']=required
    if args.page in ['input','sync']:
        label='按本机选词频率优先排序' if args.page=='input' else '启用个人词库同步'
        checkbox=next((n for n in nodes if n.get('AXRole')=='AXCheckBox' and n.get('AXDescription')==label),None)
        assert checkbox is not None,'Personal data checkbox missing'
        result['checkboxValue']=checkbox.get('AXValue')
        result['checkboxEnabled']=checkbox.get('AXEnabled')
        if args.page=='sync':assert checkbox.get('AXValue')==0,'Expected sync to remain disabled'
result['inputSource']=json.loads(subprocess.check_output([str(root/'build/tisctl'),'current'],timeout=15))['id']
(root/f'build/system-test/settings-{args.page}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2))
