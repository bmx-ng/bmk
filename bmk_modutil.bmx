
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

Const STAGE_GENERATE:Int = 0
Const STAGE_FASM2AS:Int = 1
Const STAGE_OBJECT:Int = 2
Const STAGE_LINK:Int = 3
Const STAGE_MERGE:Int = 4

Type TSourceFile
	Field ext$		'one of: "bmx", "i", "c", "cpp", "m", "s", "h"
	Field exti:Int
	Field path$
	Field modid$
	Field framewk$
	Field info:TList=New TList

	Field modimports:TList=New TList
	
	Field imports:TList=New TList
	Field includes:TList=New TList
	Field incbins:TList=New TList
	
	Field pragmas:TList = New TList
	
	Field stage:Int
	Field deps:TMap = New TMap
	Field moddeps:TMap
	Field processed:Int
	Field arc_path:String
	Field iface_path:String
	Field obj_path:String
	Field time:Int
	Field obj_time:Int
	Field arc_time:Int
	Field asm_time:Int
	Field iface_time:Int
	Field gen_time:Int
	Field requiresBuild:Int
	Field dontBuild:Int
	Field depsList:TList
	Field ext_files:TList
	
	Field merge_path:String
	Field merge_time:Int
	
	Field cc_opts:String
	Field bcc_opts:String
	Field cpp_opts:String
	Field c_opts:String
	
	Field mod_opts:TModOpt
	Field includePaths:TOrderedMap = New TOrderedMap
	Field includePathString:String
	
	Field pct:Int
	
	Field linksCache:TList
	Field optsCache:TList
	Field lastCache:Int = -1
	Field doneLinks:Int
	'cache calculated MaxLinkTime()-value for faster lookups
	Field maxLinkTimeCache:Int = -1
	
	' add cc_opts or ld_opts
	Method AddModOpt(opt:String)
		If Not mod_opts Then
			mod_opts = New TModOpt
		End If
		mod_opts.AddOption(opt)
	End Method
	
	Method MaxObjTime:Int()
		Local t:Int = obj_time
		If depsList Then
			For Local s:TSourceFile = EachIn depsList
				Local st:Int = s.MaxObjTime()
				If st > t Then
					t = st
				End If
			Next
		End If
		Return t
	End Method
	
	Method GetObjs(list:TList)
		If list Then
			If Not stage Then
				If Not list.Contains(obj_path) Then
					list.AddLast(obj_path)
				End If
			End If

			If depsList Then
				For Local s:TSourceFile = EachIn depsList
					s.GetObjs(list)
				Next
			End If
		End If
	End Method

	Method SetRequiresBuild(enable:Int)
		If requiresBuild <> enable Then
			requiresBuild = enable
			'seems our information is outdated now
			If requiresBuild Then
				maxLinkTimeCache = -1
			End If
		End If
	End Method

	Method MaxLinkTime:Int(modsOnly:Int = False)
		If maxLinkTimeCache = -1 Then
			Local t:Int
			If modid Then
				t = arc_time
			Else
				t = obj_time
			End If
			If depsList Then
				For Local s:TSourceFile = EachIn depsList
					Local st:Int = s.MaxLinkTime(modsOnly)
					If st > t Then
						t = st
					End If
				Next
			End If
			If moddeps Then
				For Local s:TSourceFile = EachIn moddeps.Values()
					Local st:Int = s.MaxLinkTime(True)
					If st > t Then
						t = st
					End If
				Next
			End If

			maxLinkTimeCache = t
		End If

		Return maxLinkTimeCache
	End Method
	
	Method MakeFatter(list:TList, o_path:String)
		Local ext:String = ExtractExt(o_path)
		If ext = "o" Then
			Local file:String = StripExt(o_path)
			Local fp:String = StripExt(file)
			Select ExtractExt(file)
				Case "arm64"
					fp :+ ".armv7.o"
				Case "armv7"
					fp :+ ".arm64.o"
				Case "x86"
					fp :+ ".x64.o"
				Case "x64"
					fp :+ ".x86.o"
			End Select
			If Not list.Contains(fp) Then
				list.AddLast(fp)
				
				linksCache.AddLast(fp)
			End If
		End If
	End Method

	Method GetLinks(list:TList, opts:TList, modsOnly:Int = False, cList:TList = Null, cOpts:TList = Null)

		If linksCache Then
		
			If lastCache <> modsOnly Then
				linksCache = Null
				optsCache = Null
				doneLinks = False
			End If
		
		End If
		
		If doneLinks Then
			Return
		End If
		
		doneLinks = True

		If Not linksCache Then
			linksCache = New TList
			optsCache = New TList
			lastCache = modsOnly
		

			If list And stage = STAGE_LINK Then
				If Not modid Then
					If Not list.Contains(obj_path) Then
						list.AddLast(obj_path)
						
						linksCache.AddLast(obj_path)
					
						If opt_universal And processor.Platform() = "ios" Then
							MakeFatter(list, obj_path)
						End If
					End If
				End If
			End If
	
			If depsList And list Then
				For Local s:TSourceFile = EachIn depsList
					If Not modsOnly Or (modsOnly And s.modid) Then
						If Not stage Then
							If Not s.modid Then
								If s.obj_path And Not list.Contains(s.obj_path) Then
									list.AddLast(s.obj_path)
									
									linksCache.AddLast(s.obj_path)
									
									If opt_universal And processor.Platform() = "ios" Then
										MakeFatter(list, s.obj_path)
									End If
								End If
							End If
						End If
					End If

					If s.exti = SOURCE_BMX Or s.exti = SOURCE_IFACE Or s.modid Then
						s.GetLinks(list, opts, modsOnly, linksCache, optsCache)
					End If
	
				Next
			End If
	
			If moddeps Then
				For Local s:TSourceFile = EachIn moddeps.Values()
					s.GetLinks(list, opts, True, linksCache, optsCache)
				Next
			End If
	
			If mod_opts Then
				For Local f:String = EachIn mod_opts.ld_opts
					Local p:String = TModOpt.SetPath(f, ExtractDir(path))
					If Not list.Contains(p) Then
						list.AddLast(p)
						
						linksCache.AddLast(p)
					End If
				Next
			End If
		
			If ext_files Then
				For Local f:String = EachIn ext_files
					' remove previous link, add latest to the end...
					If opts.Contains(f) Then
						opts.Remove(f)
						
						optsCache.Remove(f)
					End If
					opts.AddLast(f)
					
					optsCache.AddLast(f)
				Next
			End If
			
			If cList Then
				For Local s:String = EachIn linksCache
					cList.AddLast(s)
				Next
				For Local f:String = EachIn optsCache
					If cOpts.Contains(f) Then
						cOpts.Remove(f)
					End If
					cOpts.AddLast(f)
				Next
			End If

		Else

			For Local s:String = EachIn linksCache
				list.AddLast(s)
			Next
		
			For Local f:String = EachIn optsCache
				If opts.Contains(f) Then
					opts.Remove(f)
				End If
				opts.AddLast(f)
			Next

			If cList Then
				For Local s:String = EachIn linksCache
					cList.AddLast(s)
				Next
				For Local f:String = EachIn optsCache
					If cOpts.Contains(f) Then
						cOpts.Remove(f)
					End If
					cOpts.AddLast(f)
				Next
			End If

		End If

	End Method

	Method MaxIfaceTime:Int()
		Local t:Int = iface_time
		If depsList Then
			For Local s:TSourceFile = EachIn depsList
				Local st:Int = s.MaxIFaceTime()
				If st > t Then
					t = st
				End If
			Next
		End If
		Return t
	End Method

	Method CopyInfo(source:TSourceFile)
		source.ext = ext
		source.exti = exti
		source.path = path
		source.modid = modid
		source.framewk = framewk
		source.info = info
		source.processed = processed
		source.arc_path = arc_path
		source.iface_path = iface_path
		source.obj_path = obj_path
		source.time = time
		source.obj_time = obj_time
		source.arc_time = arc_time
		source.iface_time = iface_time
		source.requiresBuild = requiresBuild
		source.dontBuild = dontBuild
		source.cc_opts = cc_opts
		source.bcc_opts = bcc_opts
		source.merge_path = merge_path
		source.merge_time = merge_time
		source.cpp_opts = cpp_opts
		source.c_opts = c_opts
		source.CopyIncludePaths(includePaths)
		source.maxLinkTimeCache = maxLinkTimeCache
	End Method
	
	Method GetSourcePath:String()
		Local p:String
		Select stage
			Case STAGE_GENERATE
				p = path
			Case STAGE_FASM2AS
				p = StripExt(obj_path) + ".s"
			Case STAGE_OBJECT
				p = StripExt(obj_path) + ".c"
			Case STAGE_LINK
				p = obj_path
			Case STAGE_MERGE
				p = arc_path
		End Select
		Return p
	End Method
	
	Method GetIncludePaths:String()
		If Not includePathString Then
			For Local path:String = EachIn includePaths.OrderedKeys()
				includePathString :+ path
			Next
		End If
		Return includePathString
	End Method
	
	Method AddIncludePath(path:String)
		includePaths.Insert(path, path)
		includePathString = ""
	End Method
	
	Method CopyIncludePaths(paths:TOrderedMap)
		For Local path:String = EachIn paths.OrderedKeys()
			includePaths.Insert(path, path)
		Next
		includePathString = ""
	End Method
	
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
	Local exti:Int = String(processor.RunCommand("source_type", [ext])).ToInt()
	
	' don't want headers?
	If exti = SOURCE_HEADER Return

	If Not ValidSourceExt( exti ) Return

	Local file:TSourceFile=New TSourceFile
	file.ext=ext
	file.exti=exti
	file.path=path
	file.time = FileTime(path)
	
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
'?x86
				Case "x86" cc=processor.CPU()="x86"
'?ppc
				Case "ppc" cc=processor.CPU()="ppc"
				Case "x64" cc=processor.CPU()="x64"
				Case "arm" cc=processor.CPU()="arm"
				Case "armeabi" cc=processor.CPU()="armeabi"
				Case "armeabiv7a" cc=processor.CPU()="armeabiv7a"
				Case "arm64v8a" cc=processor.CPU()="arm64v8a"
				Case "armv7" cc=processor.CPU()="armv7"
				Case "arm64" cc=processor.CPU()="arm64"
				Case "js" cc=processor.CPU()="js"

				Case "ptr32" cc=(processor.CPU()="x86" Or processor.CPU()="ppc" Or processor.CPU()="arm" Or processor.CPU()="armeabi" Or processor.CPU()="armeabiv7a" Or processor.CPU()="armv7" Or processor.CPU()="js")
				Case "ptr64" cc=(processor.CPU()="x64" Or processor.CPU()="arm64v8a" Or processor.CPU()="arm64")
''?
				Case "win32" 
					cc=False
					If processor.Platform() = "win32"
						cc=True
					End If
				Case "win32x86"
					cc=False
					If processor.Platform() = "win32"
						cc=processor.CPU()="x86"
					End If
				Case "win32ppc"
					cc=False
					If processor.Platform() = "win32"
						cc=processor.CPU()="ppc"
					End If
				Case "win32x64"
					cc=False
					If processor.Platform() = "win32"
						cc=processor.CPU()="x64"
					End If
				Case "linux"
					cc=False
					If processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi"
						 cc=True
					End If
				Case "linuxx86"
					cc=False
					If processor.Platform() = "linux" Or processor.Platform() = "android"
						 cc=processor.CPU()="x86"
					End If
				Case "linuxppc"
					cc=False
					If processor.Platform() = "linux"
						 cc=processor.CPU()="ppc"
					End If
				Case "linuxx64"
					cc=False
					If processor.Platform() = "linux" Or processor.Platform() = "android"
						 cc=processor.CPU()="x64"
					End If
				Case "linuxarm"
					cc=False
					If processor.Platform() = "linux" Or processor.Platform() = "android" Or processor.Platform() = "raspberrypi"
						 cc=processor.CPU()="arm"
					End If
				Case "macos"
					cc=False
					If processor.Platform() = "macos" Or processor.Platform() = "osx" Or processor.Platform() = "ios"
						cc=True
					End If
				Case "macosx86"
					cc=False
					If processor.Platform() = "macos"Or processor.Platform() = "osx" Or processor.Platform() = "ios"
						 cc=processor.CPU()="x86"
					End If
				Case "macosppc"
					cc=False
					If processor.Platform() = "macos" Or processor.Platform() = "osx"
						 cc=processor.CPU()="ppc"
					End If
				Case "macosx64"
					cc=False
					If processor.Platform() = "macos" Or processor.Platform() = "osx" Or processor.Platform() = "ios"
						 cc=processor.CPU()="x64"
					End If
				Case "osx"
					cc=False
					If processor.Platform() = "macos" Or processor.Platform() = "osx"
						cc=True
					End If
				Case "osxx86"
					cc=False
					If processor.Platform() = "macos"Or processor.Platform() = "osx"
						 cc=processor.CPU()="x86"
					End If
				Case "osxx64"
					cc=False
					If processor.Platform() = "macos" Or processor.Platform() = "osx"
						 cc=processor.CPU()="x64"
					End If
				Case "ios"
					cc=False
					If processor.Platform() = "ios"
						cc=True
					End If
				Case "iosx86"
					cc=False
					If processor.Platform() = "ios"
						 cc=processor.CPU()="x86"
					End If
				Case "iosx64"
					cc=False
					If processor.Platform() = "ios"
						 cc=processor.CPU()="x64"
					End If
				Case "iosarmv7"
					cc=False
					If processor.Platform() = "ios"
						 cc=processor.CPU()="armv7"
					End If
				Case "iosarm64"
					cc=False
					If processor.Platform() = "ios"
						 cc=processor.CPU()="arm64"
					End If
				Case "android"
					cc=False
					If processor.Platform() = "android"
						 cc=True
					End If
				Case "androidarm"
					cc=False
					If processor.Platform() = "android"
						 cc=processor.CPU()="arm"
					End If
				Case "androidarmeabi"
					cc=False
					If processor.Platform() = "android"
						 cc=processor.CPU()="armeabi"
					End If
				Case "androidarmeabiv7a"
					cc=False
					If processor.Platform() = "android"
						 cc=processor.CPU()="armeabiv7a"
					End If
				Case "androidarm64v8a"
					cc=False
					If processor.Platform() = "android"
						 cc=processor.CPU()="arm64v8a"
					End If
				Case "raspberrypi"
					cc=False
					If processor.Platform() = "raspberrypi"
						 cc=True
					End If
				Case "raspberrypiarm"
					cc=False
					If processor.Platform() = "raspberrypi"
						 cc=processor.CPU()="arm"
					End If
				Case "raspberrypiarm64"
					cc=False
					If processor.Platform() = "raspberrypi"
						 cc=processor.CPU()="arm64"
					End If
				Case "emscripten"
					cc=False
					If processor.Platform() = "emscripten"
						 cc=True
					End If
				Case "emscriptenjs"
					cc=False
					If processor.Platform() = "emscripten"
						 cc=processor.CPU()="js"
					End If
				Case "opengles"
					cc=False
					If processor.Platform() = "android" Or processor.Platform() = "raspberrypi" Or processor.Platform() = "emscripten" Or processor.Platform() = "ios" 
						 cc=True
					End If
				Case "bmxng"
					cc=False
					If processor.BCCVersion() <> "BlitzMax" Then
						cc=True
					End If
				Case "musl"
					cc=False
					If processor.Platform() = "linux" Or processor.Platform() ="raspberrypi"
						 cc=True
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
				While i<lpragma.length And Not (CharIsAlpha(lpragma[i]) Or CharIsDigit(lpragma[i]) Or lpragma[i] = Asc("@"))
					i:+1
				Wend
				file.pragmas.AddLast pragmaLine[i..]
			End If

			If lline.length And Not CharIsAlpha( lline[0] ) Continue

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
					file.imports.AddLast ReQuote(qval)
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
					file.AddModOpt(qval) ' bmk2
					'If mod_opts mod_opts.addOption(qval) ' BaH
				EndIf
			End Select
		Case SOURCE_C, SOURCE_HEADER '"c","m","h","cpp","cxx","hpp","hxx"
		'	If line[..8]="#include"
		''		Local val$=line[8..].Trim(),qval$,qext$
			'	If val.length>1 And val[0]=34 And val[val.length-1]=34
			'		qval=val[1..val.length-1]
			'	EndIf
			'	If qval
			'		file.includes.AddLast qval
			'	EndIf
			'EndIf
		End Select

	Wend
	
	Return file

End Function

Function ParseISourceFile:TSourceFile( path$ )

	If FileType(path)<>FILETYPE_FILE Return

	Local file:TSourceFile=New TSourceFile
	file.ext="i"
	file.exti=SOURCE_IFACE
	file.path=path
	file.time = FileTime(path)
	
	Local str$=LoadText( path )

	Local pos,in_rem,cc=True

	While pos<Len(str)

		Local eol=str.Find( "~n",pos )
		If eol=-1 eol=Len(str)

		Local line$=str[pos..eol].Trim()
		pos=eol+1

		Local lline$=line.Tolower()

		Local i:Int

		If lline.length And Not CharIsAlpha( lline[0] ) Continue

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
		Case "import"
			If qval
				Local q:String = ReQuote(qval)
				If q.StartsWith("-") Then
					file.imports.AddLast q
				End If
			Else
				file.modimports.AddLast val.ToLower()
			EndIf
		Case "moduleinfo"
			If qval
				file.info.AddLast qval
				file.AddModOpt(qval) ' bmk2
				'If mod_opts mod_opts.addOption(qval) ' BaH
			EndIf
		End Select

	Wend
	
	Return file

End Function

Function ValidatePlatformArchitecture()
	Local valid:Int = False
	
	Local platform:String = processor.Platform()
	Local arch:String = processor.CPU()

	Select platform
		Case "win32"
			If arch = "x86" Or arch = "x64" Then
				valid = True
			End If
		Case "linux"
			If arch = "x86" Or arch = "x64" Or arch = "arm" Or arch="arm64" Then
				valid = True
			End If
		Case "macos", "osx"
			If arch = "x86" Or arch = "x64" Or arch = "ppc" Then
				valid = True
			End If
		Case "ios"
			If arch = "x86" Or arch = "x64" Or arch = "armv7" Or arch = "arm64" Then
				valid = True
			End If
		Case "android"
			If arch = "x86" Or arch = "x64" Or arch = "arm" Or arch = "armeabi"  Or arch = "armeabiv7a"  Or arch = "arm64v8a" Then
				valid = True
			End If
		Case "raspberrypi"
			If arch = "arm" Or arch="arm64" Then
				valid = True
			End If
		Case "emscripten"
			If arch = "js" Then
				valid = True
			End If
	End Select
	
	If Not valid Then
		CmdError "Invalid Platform/Architecture configuration : " + platform + "/" + arch
	End If
End Function
