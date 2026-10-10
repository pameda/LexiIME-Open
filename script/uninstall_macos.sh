#!/bin/bash
set -euo pipefail
echo '先切换到系统自带输入法，再从键盘设置中移除词伴开源版。'
echo '退出词伴开源版设置和输入法后，将以下两个项目移到废纸篓：'
echo '  /Applications/LexiIME-Open.app'
echo '  /Library/Input Methods/LexiIME-Open Input.app'
echo '本次用户级测试安装的位置为：'
echo '  ~/Applications/LexiIME-Open.app'
echo '  ~/Library/Input Methods/LexiIME-Open Input.app'
echo '用户词库、学习记录保留在 ~/Library/Application Support/LexiIME-Open。'
echo 'API 密钥可在词伴开源版设置中删除。此脚本只显示路径，不删除数据。'
