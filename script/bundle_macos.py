import plistlib, shutil, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
for ime,name,bundle in [(False,'LexiIME-Open','local.lexiime.open.settings'),(True,'LexiIME-Open Input','local.inputmethod.lexiime.open')]:
    target=root/'dist'/f'{name}.app'/'Contents'
    (target/'MacOS').mkdir(parents=True,exist_ok=True)
    (target/'Resources').mkdir(exist_ok=True)
    shutil.copy2(root/'build'/f'LexiIME-Open-{sys.argv[1]}',target/'MacOS'/'LexiIME-Open')
    shutil.copytree(root/'data',target/'Resources'/'data',dirs_exist_ok=True)
    for document in ['LICENSE','THIRD_PARTY_NOTICES.md']:
        shutil.copy2(root/document,target/'Resources'/document)
    info=dict(CFBundleExecutable='LexiIME-Open',CFBundleIdentifier=bundle,CFBundleName=name,CFBundleDisplayName='词伴开源版',CFBundlePackageType='APPL',CFBundleVersion='3',CFBundleShortVersionString='0.1.1',CFBundleInfoDictionaryVersion='6.0',CFBundleSupportedPlatforms=['MacOSX'],LSMinimumSystemVersion='13.0',NSPrincipalClass='NSApplication',NSHighResolutionCapable=True)
    for icon in ['menu.tiff','menu.pdf','AppIcon.icns','InputIcon.icns']:
        shutil.copy2(root/'build/icons'/icon,target/'Resources'/icon)
    info['CFBundleIconFile']='InputIcon.icns' if ime else 'AppIcon.icns'
    info.update(NSMicrophoneUsageDescription='点击开始语音输入后，用麦克风进行本地识别。不保存录音。',NSSpeechRecognitionUsageDescription='将你的语音转换为可预览和确认的文字，仅使用本地识别。')
    if ime:
        source=bundle
        info['CFBundleName']='词伴开源版'
        info.update(LSBackgroundOnly=True,LSMultipleInstancesProhibited=True,InputMethodConnectionName=bundle+'_Connection',InputMethodServerControllerClass='LexiInputController',tsInputMethodCharacterRepertoireKey=['Hans','Latn'],TISInputSourceID=source,TISIntendedLanguage='zh-Hans',tsInputMethodIconFileKey='menu.tiff',TISIconIsTemplate=True)
        for locale in ['en','zh-Hans']:
            localized=target/'Resources'/f'{locale}.lproj';localized.mkdir(exist_ok=True)
            (localized/'InfoPlist.strings').write_text(f'"CFBundleName" = "词伴开源版";\n"CFBundleDisplayName" = "词伴开源版";\n"{source}" = "词伴开源版";\n',encoding='utf-8')
    with (target/'Info.plist').open('wb') as f:plistlib.dump(info,f)
