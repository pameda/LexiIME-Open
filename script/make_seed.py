"""Original demonstration vocabulary. No external dictionary is downloaded."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
packs = {
'日常': '''我|wo|trnt|I; me|私|yo
你|ni|wqiy|you|あなた|tú
好|hao|vbg|good|良い|bueno
你好|ni hao|wqvb|hello|こんにちは|hola
谢谢|xie xie||thank you|ありがとう|gracias
再见|zai jian||goodbye|さようなら|adiós
是|shi|jghu|to be|〜です|ser
的|de|rqyy|possessive particle|〜の|de
们|men||plural suffix|〜たち|sufijo plural
我们|wo men||we; us|私たち|nosotros
他们|ta men||they; them|彼ら|ellos
这|zhe||this|これ|esto
那|na||that|それ|eso
有|you||to have|ある; いる|tener
不|bu||not|〜ない|no
在|zai||at; in|〜に|en
和|he||and|〜と|y
喜欢|xi huan||to like|好き|gustar
想|xiang||to want; to think|〜したい; 思う|querer; pensar
去|qu||to go|行く|ir
来|lai||to come|来る|venir
吃|chi||to eat|食べる|comer
喝|he||to drink|飲む|beber
水|shui|iiii|water|水|agua
茶|cha||tea|お茶|té
咖啡|ka fei||coffee|コーヒー|café
朋友|peng you||friend|友達|amigo
家|jia||home; family|家; 家族|casa; familia
今天|jin tian||today|今日|hoy
明天|ming tian||tomorrow|明日|mañana
早上|zao shang||morning|朝|mañana
晚上|wan shang||evening|夜|noche
时间|shi jian||time|時間|tiempo
天气|tian qi||weather|天気|tiempo meteorológico
开心|kai xin||happy|うれしい|feliz
可以|ke yi||can; may|できる|poder
没有|mei you||not have|ない|no tener
什么|shen me||what|何|qué
为什么|wei shen me||why|なぜ|por qué
怎么|zen me||how|どう|cómo
知道|zhi dao||to know|知っている|saber
看到|kan dao||to see|見える|ver
中国|zhong guo|khlg|China|中国|China
中文|zhong wen||Chinese language|中国語|chino
北京|bei jing||Beijing|北京|Pekín
西安|xi an||Xi'an|西安|Xi'an
先|xian||first|先に|primero''',
'学习': '''学习|xue xi|ipnu|to study; to learn|学ぶ|estudiar; aprender
学|xue|ipbf|to study|学ぶ|estudiar
习|xi|nud|to practice|習う|practicar
英语|ying yu||English|英語|inglés
日语|ri yu||Japanese|日本語|japonés
西班牙语|xi ban ya yu||Spanish|スペイン語|español
语言|yu yan||language|言語|idioma
词汇|ci hui||vocabulary|語彙|vocabulario
记忆|ji yi||memory; to memorize|記憶|memoria
阅读|yue du||reading|読書|lectura
练习|lian xi||practice|練習|práctica
老师|lao shi||teacher|先生|profesor
学生|xue sheng||student|学生|estudiante
问题|wen ti||question; problem|質問; 問題|pregunta; problema
答案|da an||answer|答え|respuesta
学校|xue xiao||school|学校|escuela
大学|da xue||university|大学|universidad
书|shu||book|本|libro
我喜欢学习英语|wo xi huan xue xi ying yu||I like learning English.|英語を学ぶのが好きです。|Me gusta aprender inglés.''',
'工作': '''工作|gong zuo||work|仕事|trabajo
开发|kai fa||development|開発|desarrollo
软件|ruan jian||software|ソフトウェア|software
输入法|shu ru fa||input method|入力メソッド|método de entrada
输入|shu ru||input|入力|entrada
设置|she zhi||settings|設定|ajustes
电脑|dian nao||computer|コンピューター|ordenador
网络|wang luo||network|ネットワーク|red
会议|hui yi||meeting|会議|reunión
项目|xiang mu||project|プロジェクト|proyecto
测试|ce shi||test|テスト|prueba
安全|an quan||safety; security|安全|seguridad
保存|bao cun||to save|保存する|guardar
文件|wen jian||file; document|ファイル|archivo
计划|ji hua||plan|計画|plan
完成|wan cheng||to complete|完了する|completar
开始|kai shi||to begin|始める|empezar
结束|jie shu||to end|終わる|terminar''',
'旅行': '''旅行|lv xing||travel|旅行|viaje
酒店|jiu dian||hotel|ホテル|hotel
车站|che zhan||station|駅|estación
机场|ji chang||airport|空港|aeropuerto
地图|di tu||map|地図|mapa
方向|fang xiang||direction|方向|dirección
左边|zuo bian||left side|左側|izquierda
右边|you bian||right side|右側|derecha
价格|jia ge||price|価格|precio
多少钱|duo shao qian||how much|いくら|cuánto cuesta
餐厅|can ting||restaurant|レストラン|restaurante
早餐|zao can||breakfast|朝食|desayuno
午餐|wu can||lunch|昼食|almuerzo
晚餐|wan can||dinner|夕食|cena
帮助|bang zhu||help|助け|ayuda
请|qing||please|どうぞ; 〜してください|por favor'''
}
for index, (name, content) in enumerate(packs.items()):
    rows = ['# LexiIME-Open 原创示例词库 v0.1 — 尚未进行专业语言审校', '# 汉字\t分音节拼音\t五笔86（可空）\t英语\t日语\t西班牙语\t频率\t领域']
    for line in content.splitlines():
        fields=line.split('|')
        assert len(fields)==6, fields
        rows.append('\t'.join(fields+['1000',name]))
    (root/'data'/f'{index+1:02}-{name}.tsv').write_text('\n'.join(rows)+'\n',encoding='utf-8')
# A deliberately small, documented layout demonstration, not branded as Xiaohe or another scheme.
(root/'data'/'layout.tsv').write_text('# 自定义双拼演示表，只覆盖以下音节；可导入自己的完整方案\nni\tni\nhao\thc\nwo\two\nxi\txi\nhuan\thr\nxue\txt\nying\tyk\nyu\tyu\nzhong\tvs\nguo\tgo\n',encoding='utf-8')
(root/'data'/'import-example.tsv').write_text('# 示例：导入后输入 ci ban\n词伴开源版\tci ban\t\tword companion\t語彙のパートナー\tcompañero de vocabulario\t2000\t自定义\n',encoding='utf-8')
print(sum(len(c.splitlines()) for c in packs.values()), 'original seed entries')
