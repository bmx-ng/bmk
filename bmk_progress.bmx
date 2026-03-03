SuperStrict

Import BRL.StandardIO

Import "bmk_config.bmx"

?win32
Extern "win32"
	Function GetStdHandle:Byte Ptr(nStdHandle:Int)="HANDLE __stdcall GetStdHandle(DWORD)!"
	Function GetConsoleMode:Int(hConsoleHandle:Byte Ptr, lpMode:Int Ptr)="WINBOOL __stdcall GetConsoleMode(HANDLE, LPDWORD)!"
	Function GetFileType:Int(hFile:Byte Ptr)="DWORD __stdcall GetFileType(HANDLE)!"
End Extern
Const STD_OUTPUT_HANDLE:Int = -11
Const FILE_TYPE_DISK:Int = 1
Global _ProgressLineIsConsole:Int
?

?Not win32
Extern
	Function isatty:Int(fd:Int)
End Extern
?

Function IsInteractiveStdout:Int()
	If opt_no_progress Then
		Return False
	End If

	' Disable for certain environments
	Local term:String = GetEnv_("TERM")
	If term.ToLower() = "dumb" Then
		Return False
	End If
	If GetEnv_("CI") <> "" Then
		Return False
	End If

	?win32
		Local h:Byte Ptr = GetStdHandle(STD_OUTPUT_HANDLE)

		Local mode:Int
		If h And GetConsoleMode(h, Varptr mode) <> 0 Then
			_ProgressLineIsConsole = True
			Return True
		End If
		
		Local ft:Int = GetFileType(h)
		If ft = FILE_TYPE_DISK Then
			Return False
		End If

		' If TERM is set and stdout isn't disk, assume interactive.
		If term <> "" Then
			Return True
		End If
	?	
	?Not win32
		Return isatty(1)
	?
End Function

Global _UseProgressLine:Int = False

Const ESC:String = Chr(27)

Function InitProgressLine()
	_UseProgressLine = IsInteractiveStdout()
	
	EnableAnsiIfPossible()
End Function

Function UpdateProgressLine(pct:Int, path:String)
	If Not _UseProgressLine Then Return
	
	Local file:String = StripDir(path)
	Local line:String = BuildProgressBarLine(pct, file)

	' Clear + rewrite
	WriteStdout("~r" + ESC + "[2K" + line)
End Function

Function ClearProgressLine()
	If Not _UseProgressLine Then Return
	WriteStdout("~r" + ESC + "[2K")
End Function

Function BuildProgressBarLine:String(pct:Int, file:String)
	Local barW:Int = 30
	If pct < 0 Then
		pct = 0
	Else If pct > 100 Then
		pct = 100
	End If

	Local filled:Int = (pct * barW) / 100
	Local bar:String = "[" + "#".Replicate(filled) + "-".Replicate(barW - filled) + "]"

	' Example: "[########------] 72% file.c"
	Return bar + " " + pct + "%  " + file
End Function

?win32
Extern "win32"
	Function SetConsoleMode:Int(hConsoleHandle:Byte Ptr, dwMode:Int)="WINBOOL __stdcall SetConsoleMode(HANDLE, DWORD)!"
End Extern
Const ENABLE_VIRTUAL_TERMINAL_PROCESSING:Int = $0004

Function EnableAnsiIfPossible()
	If Not _UseProgressLine Then Return

	If _ProgressLineIsConsole Then
		Local h:Byte Ptr = GetStdHandle(STD_OUTPUT_HANDLE)
		Local mode:Int
		If GetConsoleMode(h, Varptr mode) = 0 Then Return
		' Try to add VT processing
		SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
	End If
End Function
?
?Not win32
Function EnableAnsiIfPossible()
	' nothing needed
End Function
?

Function LogLine(s:String)
	If _UseProgressLine Then
		' Return to start of bar line and clear it
		WriteStdout("~r" + ESC + "[2K")
	EndIf
	Print s
End Function
