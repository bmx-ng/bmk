
Strict

Import BRL.MaxUtil
Import BRL.TextStream

Import "bmk_util.bmx"

Const SOURCE_UNKNOWN:Int = 0
Const SOURCE_BMX:Int = $01
Const SOURCE_IFACE:Int = $02
Const SOURCE_C:Int = $04
Const SOURCE_HEADER:Int = $08
Const SOURCE_ASM:Int = $10
'Const SOURCE_PYTHON:Int = $20
'Const SOURCE_PERL:Int = $40
'Const SOURCE_RUBY:Int = $80
' etc ?

Type TSourceFile
	Field ext$		'one of: "bmx", "i", "c", "cpp", "m", "s", "h"
	Field path$
	Field modid$
	Field framewk$
	Field info:TList=New TList

	Field modimports:TList=New TList
	
	Field imports:TList=New TList
	Field includes:TList=New TList
	Field incbins:TList=New TList
	
	Field declids:TList=New TList
	
	Field pragmas:TList = New TList
End Type

Function ValidSourceExt( ext:Int )
	If ext & $FFFF Then
		Return True
	End If
	Return False
End Function

Function ParseSourceFile:TSourceFile( path$ )

	If FileType(path)<>FILETYPE_FILE Return

	Local ext$=ExtractExt( path ).ToLower()
	Local exti:Int = String(RunCommand("source_type", [ext])).ToInt()

	If Not ValidSourceExt( exti ) Return

	Local file:TSourceFile=New TSourceFile
	file.ext=ext
	file.path=path
	
	Local str$=LoadText( path )

	Local pos,in_rem,cc=True

	While pos<Len(str)

		Local eol=str.Find( "~n",pos )
		If eol=-1 eol=Len(str)

		Local line$=str[pos..eol].Trim()
		pos=eol+1

		Local pragmaLine:String
		Local n:Int = line.Find("@")
		If n <> -1 And line[n+1..n+4] = "bmk" Then
			pragmaLine = line[n+4..]
		End If
		
		Select exti
		Case SOURCE_BMX, SOURCE_IFACE

			n=line.Find( "'" )
			If n<>-1 line=line[..n]
			
			If Not line And Not pragmaLine Continue

			Local lline$=line.Tolower()

			If in_rem
				If lline[..6]="endrem" Or lline[..7]="end rem" 
					in_rem=False
				EndIf
				Continue
			Else If lline[..3]="rem"
				in_rem=True
				Continue
			EndIf

			If lline[..1]="?"
				Local t$=lline[1..].Trim()
				
				Local cNot
				If t.StartsWith( "not " )
					cNot=True
					t=t[4..].Trim()
				EndIf

				t = t.toLower()
				Select t
				Case ""
					cc=True
				Case "debug"
					cc=opt_debug
				Case "threaded"
					cc=opt_threaded
?x86
				Case "x86" cc=processor.CPU()="x86"
?ppc
				Case "ppc" cc=processor.CPU()="ppc"
?
				Case "win32" 
					cc=False
					If processor.Platform() = "win32"
						cc=True
					End If
				Case "win32x86"
					cc=False
					If processor.Platform() = "win32"
						cc=opt_arch="x86"
					End If
				Case "win32ppc"
					cc=False
					If processor.Platform() = "win32"
						cc=opt_arch="ppc"
					End If
				Case "linux"
					cc=False
					If processor.Platform() = "linux"
						 cc=True
					End If
				Case "linuxx86"
					cc=False
					If processor.Platform() = "linux"
						 cc=opt_arch="x86"
					End If
				Case "linuxppc"
					cc=False
					If processor.Platform() = "linux"
						 cc=opt_arch="ppc"
					End If
				Case "macos"
					cc=False
					If processor.Platform() = "macos"
						cc=True
					End If
				Case "macosx86"
					cc=False
					If processor.Platform() = "macos"
						 cc=processor.CPU()="x86"
					End If
				Case "macosppc"
					cc=False
					If processor.Platform() = "macos"
						 cc=processor.CPU()="ppc"
					End If
				Default
					cc=False
				End Select
				If cNot cc=Not cc
				Continue
			EndIf

			If Not cc Continue
			
			Local i:Int
			' new pragma stuff
			If pragmaLine Then
				Local lpragma:String = pragmaLine.ToLower()
				i = 0
				While i<lpragma.length And Not (CharIsAlpha(lpragma[i]) Or CharIsDigit(lpragma[i]))
					i:+1
				Wend
				file.pragmas.AddLast pragmaLine[i..]
			End If

			If Not CharIsAlpha( lline[0] ) Continue

			i=1
			While i<lline.length And (CharIsAlpha(lline[i]) Or CharIsDigit(lline[i]))
				i:+1
			Wend
			If i=lline.length Continue
			
			Local key$=lline[..i]
			
			Local val$=line[i..].Trim(),qval$,qext$
			If val.length>1 And val[0]=34 And val[val.length-1]=34
				qval=val[1..val.length-1]
			EndIf

			Select key
			Case "module"
				file.modid=val.ToLower()
			Case "framework"
				file.framewk=val.ToLower()
			Case "import"
				If qval
					file.imports.AddLast qval
				Else
					file.modimports.AddLast val.ToLower()
				EndIf
			Case "incbin"
				If qval
					file.incbins.AddLast qval
				EndIf
			Case "include"
				If qval
					file.includes.AddLast qval
				EndIf
			Case "moduleinfo"
				If qval
					file.info.AddLast qval
					If mod_opts mod_opts.addOption(qval) ' BaH
				EndIf
			End Select
		Case SOURCE_C, SOURCE_HEADER '"c","m","h","cpp","cxx","hpp","hxx"
			If line[..8]="#include"
				Local val$=line[8..].Trim(),qval$,qext$
				If val.length>1 And val[0]=34 And val[val.length-1]=34
					qval=val[1..val.length-1]
				EndIf
				If qval
					file.includes.AddLast qval
				EndIf
			EndIf
		End Select

	Wend
	
	Return file

End Function
