
Strict

Import "bmk_config.bmx"
Import "bmk_ng.bmx"

'OS X Nasm doesn't work? Used to produce incorrect reloc offsets - haven't checked for a while 
Const USE_NASM=False

Const CC_WARNINGS=False'True

Type TModOpt ' BaH
	Field cc_opts:String = ""
	Field ld_opts:TList = New TList
	
	Method addOption(qval:String)
		If qval.startswith("CC_OPTS") Then
			cc_opts:+ " " + ReQuote(qval[qval.find(":") + 1..].Trim())
		ElseIf qval.startswith("LD_OPTS") Then
			Local opt:String = ReQuote(qval[qval.find(":") + 1..].Trim())
			
			If opt.startsWith("-L") Then
				opt = "-L" + CQuote(opt[2..])
			End If
			ld_opts.addLast opt
		End If
	End Method
	
	Method hasCCopt:Int(value:String)
		Return cc_opts.find(value) >= 0
	End Method

	Method hasLDopt:Int(value:String)
		For Local opt:String = EachIn ld_opts
			If opt.find(value) >= 0 Then
				Return True
			End If
		Next
		Return False
	End Method

	Function setPath:String(value:String, path:String)
		Return value.Replace("%PWD%", path)
	End Function
	
End Type

Global mod_opts:TModOpt ' BaH

Function Match( ext$,pat$ )
	Return (";"+pat+";").Find( ";"+ext+";" )<>-1
End Function

Function HTTPEsc$( t$ )
	t=t.Replace( " ","%20" )
	Return t
End Function

Function Sys( cmd$ )
	If opt_verbose
		Print cmd
	Else If opt_dumpbuild
		Local p$=cmd
		p=p.Replace( BlitzMaxPath()+"/","./" )
		WriteStdout p+"~n"
		Local t$="mkdir "
		If cmd.StartsWith( t ) And FileType( cmd[t.length..] ) Return
	EndIf
	Return system_( cmd )
End Function

Function Ranlib( dir$ )
	'
?MacOS
	If macos_version>=$1040 Return
?
	'
	For Local f$=EachIn LoadDir( dir )
		Local p$=dir+"/"+f
		Select FileType( p )
		Case FILETYPE_DIR
			Ranlib p
		Case FILETYPE_FILE
			If ExtractExt(f).ToLower()="a" Sys "ranlib "+p
		End Select
	Next
End Function

Function Assemble( src$,obj$ )
	processor.RunCommand("assemble", [src, obj])
End Function

Function Fasm2As( src$,obj$ )
	processor.RunCommand("fasm2as", [src, obj])
End Function

Function CompileC( src$,obj$,opts$ )
	processor.RunCommand("CompileC", [src, obj, opts])
End Function

Function CompileBMX( src$,obj$,opts$ )
	DeleteFile obj

	Local azm$=StripExt(obj)
	
	If processor.BCCVersion() = "BlitzMax" Then
		' remove any "NG" generated source.
		DeleteFile azm + ".c"
		
		azm :+ ".s"
	Else
		' remove any "legacy" generated source.
		DeleteFile azm + ".s"
	
		opts :+ " -p " + processor.Platform()
	End If
	
	If opt_standalone opt_nolog = True
	
	processor.RunCommand("CompileBMX", [src, azm, opts])

	If opt_standalone opt_nolog = False

End Function

Function CreateArc( path$ , oobjs:TList )
	DeleteFile path
	Local cmd$,t$
	
	If processor.Platform() = "win32"
		For t$=EachIn oobjs
			If Len(cmd)+Len(t)>1000
				If processor.Sys( cmd )
					DeleteFile path
					Throw "Build Error: Failed to create archive "+path
				EndIf
				cmd=""
			EndIf
			If Not cmd cmd= processor.Option("path_to_ar", processor.MinGWBinPath() + "/ar.exe") + " -r "+CQuote(path)
			cmd:+" "+CQuote(t)
		Next
	End If
	
	If processor.Platform() = "macos"
		cmd="libtool -o "+CQuote(path)
		For Local t$=EachIn oobjs
			cmd:+" "+CQuote(t)
		Next
	End If
	
	If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Or processor.Platform() = "android" Or processor.Platform() = "emscripten"
		For Local t$=EachIn oobjs
			If Len(cmd)+Len(t)>1000
				If processor.Sys( cmd )
					DeleteFile path
					Throw "Build Error: Failed to create archive "+path
				EndIf
				cmd=""
			EndIf
			If processor.Platform() = "emscripten" Then
				If Not cmd cmd=processor.Option(processor.BuildName("ar"), "emar") + " r "+CQuote(path)
			Else
				If Not cmd cmd=processor.Option(processor.BuildName("ar"), "ar") + " -r "+CQuote(path)
			End If
			cmd:+" "+CQuote(t)
		Next
	End If

	If cmd And processor.MultiSys( cmd, path )
		DeleteFile path
		Throw "Build Error: Failed to create archive "+path
	EndIf
End Function

Function LinkApp( path$,lnk_files:TList,makelib,opts$ )
	DeleteFile path

	Local cmd$
	Local files$
	Local tmpfile$=BlitzMaxPath()+"/tmp/ld.tmp"
	
	If opt_standalone tmpfile = string(globals.GetRawVar("EXEPATH")) + "/ld." + processor.AppDet() + ".txt.tmp"
	
	If processor.Platform() = "macos"
		cmd="g++"

		If processor.CPU()="ppc" 
			cmd:+" -arch ppc" 
		Else If processor.CPU()="x86"
			cmd:+" -arch i386 -read_only_relocs suppress"
		Else
			cmd:+" -arch x86_64"
		EndIf
	
		cmd:+" -o "+CQuote( path )
	
		cmd:+" "+CQuote( "-L"+CQuote( BlitzMaxPath()+"/lib" ) )
	
		If Not opt_dumpbuild cmd:+" -filelist "+CQuote( tmpfile )
		
		For Local t$=EachIn lnk_files
			If opt_dumpbuild Or (t[..1]="-")
				cmd:+" "+t 
			Else
				files:+t+Chr(10)
			EndIf
		Next
		cmd:+" -lSystem -framework CoreServices -framework CoreFoundation"

		If opts Then
			cmd :+ " " + opts
		End If
		
		If processor.CPU() = "ppc"
			cmd:+ " -lc -lgcc_eh"
		End If
		
	End If
	
	If processor.Platform() = "win32"
		Local version:Int = Int(processor.GCCVersion(True))
		Local usingLD:Int = False
		
		' always use g++ instead of LD...
		' uncomment if we want to change to only use LD for GCC's < 4.x
		'If version < 40000 Then
		'	usingLD = True
		'End If
		' or we can override in the config...
		If globals.Get("link_with_ld") Or version >= 40600 Then
			usingLD = True
		End If
		
		Local blitzMaxLibDir:String = "/lib"
		If processor.CPU()="x64" Then
			blitzMaxLibDir = "/lib64"
		End If

		If usingLD Then
			cmd=CQuote(processor.Option("path_to_ld", processor.MinGWBinPath()+ "/ld.exe"))+" -s -stack 4194304"
			If opt_apptype="gui" cmd:+" -subsystem windows"
		Else
			cmd=CQuote(processor.Option("path_to_gpp", processor.MinGWBinPath() + "/g++.exe"))+" -s --stack=4194304"
			If opt_apptype="gui"
				cmd:+" --subsystem,windows -mwindows"
			Else
				If Not makelib
					cmd:+" -mconsole"
				End If
			End If
			
			If opt_threaded Then
				cmd:+" -mthread"
			End If
		End If
		If makelib cmd:+" -shared"
		
		cmd:+" -o "+CQuote( path )
		If usingLD Then
			If processor.CPU()="x86"
				cmd:+" "+ processor.MinGWLinkPaths() ' the BlitzMax lib folder
				
				' linking for x86 when using mingw64 binaries
				If processor.HasTarget("x86_64") And processor.BCCVersion() <> "BlitzMax" Then
					cmd:+" -mi386pe"
				End If
			Else
				cmd:+" "+ processor.MinGWLinkPaths() ' the BlitzMax lib folder 
			End If

			If globals.Get("path_to_mingw_lib") Then
				cmd:+" "+CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib", BlitzMaxPath()+"/lib") ) ) )
			End If
			If globals.Get("path_to_mingw_lib2") Then
				cmd:+" "+CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib2", BlitzMaxPath()+"/lib") ) ) )
			End If
			If globals.Get("path_to_mingw_lib3") Then
				cmd:+" "+CQuote( "-L"+CQuote( RealPath(processor.Option("path_to_mingw_lib3", BlitzMaxPath()+"/lib") ) ) )
			End If
		End If
	
		If makelib
			Local imp$=StripExt(path)+".a"
			Local def$=StripExt(path)+".def"
			If FileType( def )<>FILETYPE_FILE Throw "Cannot locate .def file"
			cmd:+" "+def
			cmd:+" --out-implib "+imp
			If usingLD Then
				files:+"~n"+CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/dllcrt2.o" ) )
			End If
		Else
			If usingLD
				files:+"~n"+CQuote( RealPath(processor.Option("path_to_mingw_lib2", processor.MinGWCrtPath()) + "/crtbegin.o" ) )
				files:+"~n"+CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/crt2.o" ) )
			End If
		EndIf
	
		Local xpmanifest$
		For Local f$=EachIn lnk_files
			Local t$=CQuote( f )
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				cmd:+" "+t
			Else
				If f.EndsWith( "/win32maxguiex.mod/xpmanifest.o" )
					xpmanifest=t
				Else
					files:+"~n"+t
				EndIf
			EndIf
		Next
		If xpmanifest files:+"~n"+xpmanifest
		
		cmd:+" "+CQuote( tmpfile )
	
		files:+"~n-lgdi32 -lwsock32 -lwinmm -ladvapi32"

		' add any user-defined linker options
		files:+ " " + opts

		If usingLD
			If opts.Find("stdc++") = -1 Then
				files:+" -lstdc++"
			End If

			files:+" -lmingwex"
			
		
		' for a native Win32 runtiime of mingw 3.4.5, this needs to appear early.
		'If Not processor.Option("path_to_mingw", "") Then
			files:+" -lmingw32"
		'End If

			If opts.Find("gcc") = -1 Then
				files:+" -lgcc"
			End If

			' if using 4.8+ or mingw64, we need to link to pthreads
			If version >= 40800 Or (processor.HasTarget("x86_64") And processor.BCCVersion() <> "BlitzMax") Then
				files :+ " -lwinpthread "
			End If
			
			files :+ " -lmoldname -lmsvcrt "
		End If

		files :+ " -luser32 -lkernel32 "

		'If processor.Option("path_to_mingw", "") Then
			' for a non-native Win32 runtime, this needs to appear last.
			' (Actually, also for native gcc 4.x, but I dunno how we'll handle that yet!)
		If usingLD
			files:+" -lmingw32 "
		End If

		' add any user-defined linker options, again - just to cover whether we missed dependencies before.
		files:+ " " + opts

		'End If
		
		If Not makelib
			If usingLD
				files:+" "+CQuote( processor.Option("path_to_mingw_lib2", processor.MinGWCrtPath()) + "/crtend.o" )
			End If
		EndIf
		
		files="INPUT("+files+")"
	End If
	
	If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi"
		cmd$ = processor.Option(processor.BuildName("gpp"), "g++")
		'cmd:+" -m32 -s -Os -pthread"
		If processor.CPU() = "x86" Then
			cmd:+" -m32"
		End If
		cmd:+" -pthread"
		cmd:+" -o "+CQuote( path )
		cmd:+" "+CQuote( tmpfile )
		If processor.CPU() = "x86" Then
			cmd:+ " -L" + processor.Option(processor.BuildName("lib32"), "/usr/lib32")
		End If
		cmd:+" -L" + processor.Option(processor.BuildName("x11lib"), "/usr/X11R6/lib")
		cmd:+" -L" + processor.Option(processor.BuildName("lib"), "/usr/lib")
		cmd:+" -L"+CQuote( BlitzMaxPath()+"/lib" )
	
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				cmd:+" "+t
			Else
				files:+" "+t
			EndIf
		Next
	
		files="INPUT("+files+")"
	End If
	
	If processor.Platform() = "android" Then
		cmd$ = processor.Option(processor.BuildName("gpp"), "g++")
		
		Local libso:String = StripDir(path)
		cmd :+ " -fPIC -shared "
		
		cmd :+ " -Wl,-soname,lib" + libso + ".so "
		cmd :+ " -Wl,--export-dynamic -rdynamic "
		cmd:+" -o "+CQuote( ExtractDir(path) + "/lib" + libso + ".so" )
		cmd:+" "+CQuote( tmpfile )
		cmd:+" " + processor.Option("android.platform.sysroot", "")
		
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				cmd:+" "+t
			Else
				files:+" "+t
			EndIf
		Next
	
		cmd :+ " -Wl,-Bdynamic -lGLESv2 -lGLESv1_CM "
		cmd :+ " -llog -ldl -landroid "
	
		files="INPUT("+files+")"
	End If

	If processor.Platform() = "emscripten"
		cmd$ = processor.Option(processor.BuildName("gpp"), "em++")

		' cmd:+" -pthread" ' No threading support yet...
		cmd:+" -o "+CQuote( path )
		'cmd:+" -filelist "+CQuote( tmpfile )
		
		cmd:+ " " + opts
		
		For Local t$=EachIn lnk_files
			t=CQuote(t)
			'If opt_dumpbuild Or (t[..1]="-" And t[..2]<>"-l")
				cmd:+" "+t
			'Else
			'	files:+" "+t
			'EndIf
		Next
	
		files="INPUT("+files+")"
	End If
	

	Local t$=getenv_( "BMK_LD_OPTS" )
	If t 
		cmd:+" "+t
	EndIf

	If Not opt_standalone Then
		Local stream:TStream=WriteStream( tmpfile )
		stream.WriteBytes files.ToCString(),files.length
		stream.Close
	End If

	If processor.Sys( cmd ) Throw "Build Error: Failed to link "+path

	If opt_standalone
		Local stream:TStream=WriteStream( StripExt(tmpfile) )
		Local f:String = processor.FixPaths(files)
		stream.WriteBytes f.ToCString(),f.length
		stream.Close
	End If
End Function

Function MergeApp(fromFile:String, toFile:String)

	If Not opt_quiet Print "Merging:"+StripDir(fromFile) + " + " + StripDir(toFile)

	Local cmd:String = "lipo -create ~q" + fromFile + "~q ~q" + toFile + "~q -output ~q" + toFile + "~q"
	
	If processor.Sys( cmd ) Throw "Merge Error: Failed to merge " + toFile
	
	DeleteFile fromFile

End Function

Function DeployAndroidProject()
	Local appId:String = StripDir(StripExt(opt_outfile))
	Local buildDir:String = ExtractDir(opt_outfile)

	' eg. android-project-test_01
	Local projectDir:String = buildDir + "/android-project-" + appId '+ "-" + processor.CPU()

	' check for dir
	If Not FileType(projectDir) Then
		' doesn't exist. create it

		Local resourceProject:String = BlitzMaxPath() + "/resources/android/android-project"
		If Not FileType(resourceProject) Then
			Throw "Missing resources folder for Android build : " + resourceProject
		End If
		
		CopyDir(resourceProject, projectDir)
	End If
	
	' check for valid dir
	If FileType(projectDir) <> FILETYPE_DIR Then
		Throw "Error creating project dir '" + projectDir + "'"
	End If
	
	' create assets dir if missing
	Local assetsDir:String = projectDir + "/assets"
	
	If FileType(assetsDir) <> FILETYPE_DIR Then
		CreateDir(assetsDir)

		If FileType(assetsDir) <> FILETYPE_DIR Then
			Throw "Error creating assests dir '" + assetsDir + "'"
		End If
	End If

	' create libs/abi dir if missing
	Local abiDir:String = projectDir + "/libs/"

	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs dir '" + abiDir + "'"
		End If
	End If

	Select processor.CPU()
		Case "x86"
			abiDir :+ "x86"
		Case "x64"
			abiDir :+ "x86_64"
		Case "arm"
			abiDir :+ "armeabi-v7a"
		Case "armeabi"
			abiDir :+ "armeabi"
		Case "armeabiv7a"
			abiDir :+ "armeabi-v7a"
		Case "arm64v8a"
			abiDir :+ "arm64-v8a"
		Default
			Throw "Not a valid architecture '" + processor.CPU() + "'"
	End Select
	
	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs abi dir '" + abiDir + "'"
		End If
	End If
	
	Local projectSettings:TMap = ParseIniFile()
	
	Local appPackage:String = String(projectSettings.ValueForKey("app.package"))
	
	Local packagePath:String = projectDir + "/src/" + PathFromPackage(appPackage)
	
	' create the package
	If Not FileType(packagePath) Then
		CreateDir(packagePath, True)
	
		If FileType(packagePath) <> FILETYPE_DIR Then
			Throw "Error creating package '" + packagePath + "'"
		End If
	End If
	
	' copy/create java
	Local gameClassFile:String = packagePath+ "/BlitzMaxApp.java"
	
	If Not FileType(gameClassFile) Then
		CopyFile(projectDir + "/BlitzMaxApp.java", gameClassFile)
		
		If Not FileType(gameClassFile) Then
			Throw "Error creating class file '" + gameClassFile + "'"
		End If
	End If
	
	' merge project data
	'     update AndroidManifest.xml
	MergeFile(projectDir, "AndroidManifest.xml", projectSettings)
	
	'     update BlitzMaxApp.java
	MergeFile(packagePath, "BlitzMaxApp.java", projectSettings)
	
	' set the package
	Local javaApp:String = LoadString( gameClassFile )
	javaApp = ReplaceBlock( javaApp, "app.package","package " + appPackage + ";" )
	SaveString(javaApp, gameClassFile)

	'     update strings.xml
	MergeFile(projectDir + "/res/values", "strings.xml", projectSettings)

	'     update build.xml
	MergeFile(projectDir, "build.xml", projectSettings)

End Function

Function ParseIniFile:TMap()
	Local appId:String = StripDir(StripExt(opt_outfile))
	Local buildDir:String = ExtractDir(opt_outfile)

	Local path:String = ExtractDir(opt_outfile) + "/" + appId + ".android"

	Local settings:TMap = New TMap
	
	If Not FileType(path) Then
		Print "Not Found : application settings file '" + appId + ".android'. Using defaults..."
		Return DefaultAndroidSettings()
	End If

	Local file:TStream = ReadFile(path)
	If Not file
		Return Null
	EndIf

	Local line:String
	Local pos:Int
	While Not Eof(file)
		line = ReadLine(file).Trim()

		If line.Find("#") = 0 Then
			Continue
		End If

		pos = line.Find("=")

		If pos = -1 Then
			Continue
		End If

		settings.Insert(line[..pos], line[pos+1..])
	Wend

	file.Close()
	
	settings.Insert("app.id", StripDir(StripExt(opt_outfile)))
	
	Return settings
End Function

Function DefaultAndroidSettings:TMap()
	Local settings:TMap = New TMap
	settings.Insert("app.package", "com.blitzmax.android")
	settings.Insert("app.version.code", "1")
	settings.Insert("app.version.name", "1.0")
	settings.Insert("app.name", "BlitzMax Application")
	settings.Insert("app.orientation", "landscape")
	settings.Insert("app.id", StripDir(StripExt(opt_outfile)))
	Return settings
End Function

Function PathFromPackage:String(package:String)
	Return package.Replace(".", "/")
End Function

Function MergeFile(dir:String, file:String, settings:TMap)
	Local s:String = LoadString(dir + "/" + file)
	s = ReplaceEnv(s, settings)
	SaveString(s, dir + "/" + file)
End Function

Function ReplaceEnv:String( str:String, settings:TMap )
	Local bits:TStringStack = New TStringStack

	Repeat
		Local i:Int = str.Find( "${" )
		If i=-1 Exit

		Local e:Int = str.Find( "}",i+2 ) 
		If e=-1 Exit
		
		If i>=2 And str[i-2..i] = "//" Then
			bits.AddLast str[..e+1]
			str = str[e+1..]
			Continue
		EndIf
		
		Local t:String = str[i+2..e]

		Local v:String = String(settings.ValueForKey(t))

		If Not v Then
			v = "${" + t + "}"
		End If

		bits.AddLast str[..i]
		bits.AddLast v
		
		str = str[e+1..]
	Forever
	If bits.IsEmpty() Then
		Return str
	End If
	
	bits.AddLast str
	Return bits.Join( "" )
End Function

Function ReplaceBlock:String( text:String,tag:String,repText:String,mark:String="~n//" )

	'find begin tag
	Local beginTag:String = mark+"${start."+tag+"}"
	Local i:Int = text.Find( beginTag )
	If i=-1 Throw "Error updating target project - can't find block begin tag '"+tag+"'."
	i :+ beginTag.Length
	While i < text.Length And text[i-1]<>10
		i :+ 1
	Wend
	
	'find end tag
	Local endTag:String = mark+"${end."+tag+"}"
	Local i2:Int = text.Find( endTag,i-1 )
	If i2=-1 Throw "Error updating target project - can't find block end tag '"+tag+"'."
	If Not repText Or repText[repText.Length-1]=10 Then
		i2 :+ 1
	End If
	
	Return text[..i]+repText+text[i2..]
End Function

Type TStringStack Extends TList

	Method Join:String(s:String)
		Local arr:String[] = New String[count()]
		Local index:Int
		For Local t:String = EachIn Self
			arr[index] = t
			index :+ 1
		Next
		
		Return s.Join(arr)
	End Method

End Type
