-- 「Tungsten Edge 开会话」启动器：认领 tungsten-cc:// 链接。进度看板每条工作线的「▶ 开会话」按钮发这个链接，
-- 它弹一个选模型的框，点「开会话」后开一个 Ghostty 窗口、进对应仓库、跑 co / cf / cv，并把开场白灌进 Claude Code 的输入框（不发送）。
-- 由同目录的 install.sh 编译安装；__HELPER__ 在安装时换成装进 app 包里的 open-session.py 的绝对路径。
-- 链接内容任何网页都能发：模型与目录只认白名单、开场白只认看板的格式，而且一定先弹框、你点了才开。

on run
	display dialog "这个小程序只认进度看板发来的 tungsten-cc:// 链接，直接打开没有用。" buttons {"好"} default button 1
end run

on open location theURL
	set helper to "__HELPER__"
	try
		set parsed to do shell script "/usr/bin/python3 " & quoted form of helper & " parse " & quoted form of theURL
	on error errMsg
		activate
		display dialog "链接不合法，没开会话：" & return & errMsg buttons {"好"} default button 1 with icon caution
		return
	end try
	set fields to paragraphs of parsed
	set lineName to item 1 of fields
	set defaultAlias to item 2 of fields
	set dirLabel to item 3 of fields
	set choices to {"Fable 5.1 —— cf", "Opus 5 —— co", "Opus 5 + ChatCut —— cv"}
	set def to item 1 of choices
	if defaultAlias is "co" then set def to item 2 of choices
	if defaultAlias is "cv" then set def to item 3 of choices
	activate
	set picked to choose from list choices with title ("开会话：" & lineName) with prompt ("会在「" & dirLabel & "」目录开一个新终端窗口，开场白先放进输入框、不自动发送。用哪个模型？") default items {def} OK button name "开会话" cancel button name "取消"
	if picked is false then return
	set aliasName to last word of (item 1 of picked)
	try
		do shell script "/usr/bin/python3 " & quoted form of helper & " launch " & quoted form of aliasName
	on error errMsg
		activate
		display dialog "没开成：" & return & errMsg buttons {"好"} default button 1 with icon caution
	end try
end open location
