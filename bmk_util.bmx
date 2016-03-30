
Strict

Import "bmk_config.bmx"
Import "bmk_ng.bmx"

'OS X Nasm doesn't work? Used to produce incorrect reloc offsets - haven't checked for a while 
Const USE_NASM=False

Const CC_WARNINGS=False'True

Type TModOpt ' BaH
	Field cc_opts:String = ""
	Field ld_opts:TList = New TList
	Field cpp_opts:String = ""
	Field c_opts:String = ""
	
	Method addOption(qval:String)
		If qval.startswith("CC_OPTS") Then
			cc_opts:+ " " + ReQuote(qval[qval.find(":") + 1..].Trim())
		ElseIf qval.startswith("CPP_OPTS") Then
			cpp_opts:+ " " + ReQuote(qval[qval.find(":") + 1..].Trim())
		ElseIf qval.startswith("C_OPTS") Then
			c_opts:+ " " + ReQuote(qval[qval.find(":") + 1..].Trim())
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

	Method hasCPPopt:Int(value:String)
		Return cpp_opts.find(value) >= 0
	End Method

	Method hasCopt:Int(value:String)
		Return c_opts.find(value) >= 0
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

Function CreateMergeArc( path$ , arc_path:String )
	Local cmd$

	If processor.Platform() = "ios" Then
		Local proc:String = processor.CPU()
		Local opp:String
		Select proc
			Case "x86"
				proc = "i386"
				opp = "x86_64"
			Case "x64"
				proc = "x86_64"
				opp = "i386"
			Case "armv7"
				opp = "arm64"
			Case "arm64"
				opp = "armv7"
		End Select
		
		cmd = "lipo "

		If Not FileType(path) Then
			cmd :+ "-create -arch_blank " + opp + " -arch "
		Else
			cmd :+ CQuote(path)
			cmd :+ " -replace "
		End If
	
		cmd :+ proc + " " + CQuote(arc_path)
	
		cmd :+ " -output " + CQuote(path)
	End If

	If cmd And processor.MultiSys( cmd, path )
		DeleteFile path
		Throw "Build Error: Failed to merge archive " + path
	EndIf

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
	
	If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
		cmd="libtool -o "+CQuote(path)
		For Local t$=EachIn oobjs
			cmd:+" "+CQuote(t)
		Next
	End If

	If processor.Platform() = "ios" Then
		Local proc:String = processor.CPU()
		Select proc
			Case "x86"
				proc = "i386"
			Case "x64"
				proc = "x86_64"
		End Select
	
		cmd="libtool -static -arch_only " + proc + " -o "+CQuote(path)
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

	If processor.Platform() = "ios" Then

		PackageIOSApp(path, lnk_files, opts)

		Return
	End If

	DeleteFile path

	Local cmd$
	Local files$
	Local tmpfile$=BlitzMaxPath()+"/tmp/ld.tmp"
	
	If opt_standalone tmpfile = String(globals.GetRawVar("EXEPATH")) + "/ld." + processor.AppDet() + ".txt.tmp"
	
	If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
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
			cmd=CQuote(processor.Option("path_to_ld", processor.MinGWBinPath()+ "/ld.exe"))+" -stack 4194304"
			cmd :+ processor.option("strip.debug", " -s ")
			If opt_apptype="gui" cmd:+" -subsystem windows"
		Else
			cmd=CQuote(processor.Option("path_to_gpp", processor.MinGWBinPath() + "/g++.exe"))+" --stack=4194304"
			cmd :+ processor.option("strip.debug", " -s ")
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
				If processor.HasTarget("x86_64") Then
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
				files:+" "+CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/dllcrt2.o" ) )
			End If
		Else
			If usingLD
				files:+" "+CQuote( RealPath(processor.Option("path_to_mingw_lib2", processor.MinGWCrtPath()) + "/crtbegin.o" ) )
				files:+" "+CQuote( RealPath(processor.Option("path_to_mingw_lib", processor.MinGWDLLCrtPath()) + "/crt2.o" ) )
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
					files:+" "+t
				EndIf
			EndIf
		Next
		If xpmanifest files:+" "+xpmanifest
		
		cmd:+" "+CQuote( tmpfile )
	
		files:+" -lgdi32 -lwsock32 -lwinmm -ladvapi32"

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
			If version >= 40800 Or processor.HasTarget("x86_64") Then
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
		If processor.CPU() = "x86" Or processor.CPU() = "arm" Then
			cmd:+" -m32"
		End If
		If processor.CPU() = "x64" Or processor.CPU() = "arm64" Then
			cmd:+" -m64"
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
		
		' for stlport shared lib
		cmd :+ " -L" + AndroidSTLPortDir()
		
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
		' libstlport
		cmd :+ " -lstlport_shared"
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
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		appId :+ ".debug"
	End If

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
	
	If opt_all Then
		' remove assets if we are doing a full build
		DeleteDir(assetsDir, True)
	End If
	
	If FileType(assetsDir) <> FILETYPE_DIR Then
		CreateDir(assetsDir)

		If FileType(assetsDir) <> FILETYPE_DIR Then
			Throw "Error creating assests dir '" + assetsDir + "'"
		End If
	End If

	' create libs/abi dir if missing
	Local abiDir:String = projectDir + "/libs"

	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs dir '" + abiDir + "'"
		End If
	End If
	
	abiDir :+ "/" + GetAndroidArch()

	If FileType(abiDir) <> FILETYPE_DIR Then
		CreateDir(abiDir)

		If FileType(abiDir) <> FILETYPE_DIR Then
			Throw "Error creating libs abi dir '" + abiDir + "'"
		End If
	End If
	
	' copy stlport
	Local stlportDest:String = abiDir + "/libstlport_shared.so"
	
	If opt_all Or Not FileType(stlportDest) Then
		Local stlportSrc:String = AndroidSTLPortDir() + "/libstlport_shared.so"
		
		CopyFile(stlportSrc, stlportDest)
		
		If Not FileType(stlportDest) Then
			Throw "Error copying libstlport_shared.so from '" + stlportSrc + "'"
		End If
	End If
	
	Local projectSettings:TMap = ParseAndroidIniFile()
	
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
	
	Local javaApp:String = LoadString( gameClassFile )
	' set the package
	javaApp = ReplaceBlock( javaApp, "app.package","package " + appPackage + ";" )
	' lib imports
	javaApp = ReplaceBlock( javaApp, "lib.imports", GetAndroidLibImports() )
	SaveString(javaApp, gameClassFile)

	'     update strings.xml
	MergeFile(projectDir + "/res/values", "strings.xml", projectSettings)

	'     update build.xml
	MergeFile(projectDir, "build.xml", projectSettings)

	' set the sdk target
	Local projectPropertiesFile:String = projectDir + "/project.properties"
	Local projectProperties:String = LoadString( projectPropertiesFile )
	projectProperties = ReplaceBlock( projectProperties, "sdk.target","target=android-" + processor.option("android.sdk.target", ""), "~n#")
	SaveString(projectProperties, projectPropertiesFile)

	' copy resources to assets
	CopyAndroidResources(buildDir, assetsDir)
End Function

Function GetAndroidLibImports:String()
	Local imports:String
	
	imports = "System.loadLibrary( ~qstlport_shared~q);~n"
	
	' TODO : others imported via project...
	
	Return imports
End Function

Function GetAndroidArch:String()
	Local arch:String
	Select processor.CPU()
		Case "x86"
			arch = "x86"
		Case "x64"
			arch = "x86_64"
		Case "arm"
			arch = "armeabi-v7a"
		Case "armeabi"
			arch = "armeabi"
		Case "armeabiv7a"
			arch = "armeabi-v7a"
		Case "arm64v8a"
			arch = "arm64-v8a"
		Default
			Throw "Not a valid architecture '" + processor.CPU() + "'"
	End Select
	Return arch
End Function

Function AndroidSTLPortDir:String()
	Return processor.Option("android.ndk", "") + "/sources/cxx-stl/stlport/libs/" + GetAndroidArch()
End Function

Function CopyAndroidResources(buildDir:String, assetsDir:String)

	Local paths:String[] = SplitPaths(String(globals.GetRawVar("resource_path")))
	
	If paths Then
		For Local dir:String = EachIn paths
			Local resourceDir:String = buildDir + "/" + dir
			
			If Not FileType(resourceDir) Then
				Print "Warning : Defined resource_path '" + dir + "' not found"
			End If
			
			If FileType(resourceDir) = FILETYPE_DIR Then
				
				CopyDir assetsDir + "/" + dir, resourceDir
				
			End If
				
		Next
	End If

End Function

Function ParseAndroidIniFile:TMap()
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

	Local id:String = StripDir(StripExt(opt_outfile))
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		id :+ ".debug"
	End If
	settings.Insert("app.id", id)
	
	Return settings
End Function

Function DefaultAndroidSettings:TMap()
	Local settings:TMap = New TMap
	settings.Insert("app.package", "com.blitzmax.android")
	settings.Insert("app.version.code", "1")
	settings.Insert("app.version.name", "1.0")
	settings.Insert("app.name", "BlitzMax Application")
	settings.Insert("app.orientation", "landscape")

	Local appId:String = StripDir(StripExt(opt_outfile))
	If opt_debug And opt_outfile.EndsWith(".debug") Then
		appId :+ ".debug"
	End If
	settings.Insert("app.id", appId)
	Return settings
End Function

Function GetAndroidSDKTarget:String()
	Local sdkPath:String = processor.Option("android.sdk", "") + "/platforms"
	Local target:String = processor.Option("android.sdk.target", "")
	
	Local targetPath:String
	
	If target Then
		targetPath = sdkPath + "/android-" + target
		
		If FileType(targetPath) = FILETYPE_DIR Then
			Return target
		End If
		
	End If
	
	' find highest numbered target platform dir
	Local dirs:String[] = LoadDir(sdkPath, True)
	Local high:Int
	
	For Local dir:String = EachIn dirs
	
		Local index:Int = dir.Find("android-")
		
		If index >= 0 Then
			Local value:Int = dir[index + 8..].ToInt()
			high = Max(value, high)
		End If
	
	Next
	
	If high > 0 Then
		Return high
	End If
	
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

Function ReplaceBlock:String( Text:String,tag:String,repText:String,mark:String="~n//" )

	'find begin tag
	Local beginTag:String = mark+"${start."+tag+"}"
	Local i:Int = Text.Find( beginTag )
	If i=-1 Throw "Error updating target project - can't find block begin tag '"+tag+"'."
	i :+ beginTag.Length
	While i < Text.Length And Text[i-1]<>10
		i :+ 1
	Wend
	
	'find end tag
	Local endTag:String = mark+"${end."+tag+"}"
	Local i2:Int = Text.Find( endTag,i-1 )
	If i2=-1 Throw "Error updating target project - can't find block end tag '"+tag+"'."
	If Not repText Or repText[repText.Length-1]=10 Then
		i2 :+ 1
	End If
	
	Return Text[..i]+repText+Text[i2..]
End Function

Function SplitPaths:String[](paths:String)
	Local split:String[] = New String[0]
	
	Local inQuote:Int
	Local token:String
	For Local i:Int = 0 Until paths.length
		Local char:Int = paths[i]
		If char = Asc("~q") Then
			inQuote = Not inQuote
		Else If char = Asc(" ") And Not inQuote Then
			token = token.Trim()
			If token Then
				split :+ [token]
			End If
			token = Null
		Else
			token :+ Chr(char)
		End If
	Next
	
	token = token.Trim()
	If token Then
		split :+ [token]
	End If
	
	Return split
End Function

Function PackageIOSApp( path$, lnk_files:TList, opts$ )

	Local templatePath:String = BlitzMaxPath() + "/resources/ios/template"
	
	If Not FileType(templatePath) Then
		Throw "iOS template dir is missing. Expecting it at '" + templatePath + "'"
	End If
	
	Local appId:String = StripDir(StripExt(opt_outfile))
	Local appPath:String = ExtractDir(opt_outfile)
	
	Local appProjectDir:String = appPath + "/" + appId + ".xcodeproj"

	If opt_all Then
		DeleteDir appProjectDir, True
	End If

	If Not FileType(appProjectDir) Then
		CopyDir templatePath + "/project.xcodeproj", appProjectDir
	End If
	
	
	Local projectPath:String = appProjectDir + "/project.pbxproj"
	
	Local uuid:String = "5CABB1EFACE"

	Local fileMap:TFileMap = New TFileMap
	
	For Local f:String = EachIn lnk_files
		Local kind:Int
		Select ExtractExt(f)
			Case "a"
				kind = TFileID.TYPE_ARC
			Case "o"
				kind = TFileID.TYPE_OBJ
			Case "dylib"
				kind = TFileID.TYPE_DYL
		Default
			If f.StartsWith("-l") Then
				kind = TFileID.TYPE_DYL
			End If
			If f.StartsWith("-framework") Then
				kind = TFileID.TYPE_FRM
			End If
		End Select
		fileMap.FileId(f, uuid, TFileMap.BUILD, kind)
	Next
	
	' add project-specific resource paths?
	Local paths:String[] = SplitPaths(String(globals.GetRawVar("resource_path")))
	If paths Then
		For Local f:String = EachIn paths
			fileMap.FileId(f, uuid, TFileMap.BUILD, TFileID.TYPE_DIR)
		Next
	End If

	Local project:String = LoadString(projectPath)

	' clean project
	project = iOSProjectClean(project, uuid)
	
	project = iOSProjectAppendFiles(project, uuid, fileMap)

	project = project.Replace("${PROJECT}", appId)
	project = project.Replace("${PROJECT_STRIPPED}", iOSFixAppId(appId))
	project = project.Replace("${COMPANY_IDENTIFIER}", processor.option("company_identifier", "com.mycompany"))
	
	SaveString(project, projectPath)
	
	iOSCopyDefaultFiles(templatePath, appPath)
	
End Function

Function iOSFixAppId:String(id:String)
	id = id.Replace(" ", "") ' no spaces
	id = id.Replace("_", "") ' no underscores
	Return id
End Function

Function iOSCopyDefaultFiles(templatePath:String, appPath:String)

	Local iconSrc:String = templatePath + "/Icon.png"
	Local iconDest:String = appPath + "/Icon.png"
	
	Local defaultSrc:String = templatePath + "/Default.png"
	Local defaultDest:String = appPath + "/Default.png"

	Local default2Src:String = templatePath + "/Default-568h@2x.png"
	Local default2Dest:String = appPath + "/Default-568h@2x.png"

	Local plistSrc:String = templatePath + "/Info.plist"
	Local plistDest:String = appPath + "/Info.plist"
	
	If opt_all Or Not FileType(iconDest) Then
		CopyFile iconSrc, iconDest
	End If

	If opt_all Or Not FileType(defaultDest) Then
		CopyFile defaultSrc, defaultDest
	End If

	If opt_all Or Not FileType(default2Dest) Then
		CopyFile default2Src, default2Dest
	End If

	If opt_all Or Not FileType(plistDest) Then
		CopyFile plistSrc, plistDest
	End If

End Function

Function iOSProjectClean:String(Text:String, uuid:String)
	
	Local stack:TStringStack = New TStringStack
	
	For Local line:String = EachIn Text.Split("~n")
	
		If Not line.Trim().StartsWith(uuid) Then
			stack.AddLast(line)
		End If
	
	Next

	Return stack.Join("~n")
End Function

Function iOSProjectAppendFiles:String(Text:String, uuid:String, fileMap:TFileMap)
	
	Local offset:Int = -1
	
	offset = FindEol(Text, "/* Begin PBXBuildFile section */")
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectBuildFiles(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXFileReference section */")
	If offset  = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFileRefs(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXFrameworksBuildPhase section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Frameworks */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"files = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFrameworksBuildPhase(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXResourcesBuildPhase section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Resources */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"files = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectResourcesBuildPhase(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Resources */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectResourcesGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Frameworks */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectFrameworksGroup(uuid, fileMap) + Text[offset..]
	
	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* libs */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibsGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin PBXGroup section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Objects */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"children = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectObjectsGroup(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin XCBuildConfiguration section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Debug */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"LIBRARY_SEARCH_PATHS = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibSearchPaths(uuid, fileMap) + Text[offset..]

	offset = FindEol(Text,"/* Begin XCBuildConfiguration section */")
	If offset <> -1 Then
		offset = FindEol(Text,"/* Release */ = {",offset)
	End If
	If offset <> -1 Then
		offset = FindEol(Text,"LIBRARY_SEARCH_PATHS = (",offset)
	End If
	If offset = -1 Then
		Return ""
	End If
	Text = Text[..offset] + iOSProjectLibSearchPaths(uuid, fileMap) + Text[offset..]

	Return Text
End Function

Function iOSProjectBuildFiles:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		Local fileRef:String = fileMap.FileId(path, uuid, TFileMap.REF, f.kind)
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select f.kind
			Case TFileId.TYPE_ARC, TFileId.TYPE_OBJ, TFileId.TYPE_DYL
				stack.AddLast "~t~t" + id + " /* " + name + " */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
			Case TFileId.TYPE_DIR
				stack.AddLast "~t~t" + id + " /* " + name + " in Resources */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
			Case TFileId.TYPE_LIB, TFileId.TYPE_FRM
				stack.AddLast "~t~t" + id + " /* " + name + " in Frameworks */ = {isa = PBXBuildFile; fileRef = " + fileRef + "; };"
		End Select
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join("~n")
End Function

Function iOSProjectFileRefs:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Local fid:TFileId = fileMap.GetBuildFileIdForPath(path)
		
		Select fid.kind
			Case TFileId.TYPE_ARC
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = archive.ar; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_OBJ
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = ~qcompiled.mach-o.objfile~q; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_DYL
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = ~qcompiled.mach-o.dylib~q; name = " + name + "; path = ~q" + path + "~q; sourceTree = ~q<absolute>~q; };"
			Case TFileId.TYPE_DIR
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = folder; path = ~q" + path + "~q; sourceTree = SOURCE_ROOT; };"

			Case TFileId.TYPE_LIB
				name = "lib" + path[2..] + ".a"
				Local found:Int = False
				' path should be provided as a -L...
				For Local p:String = EachIn fileMap.refFiles.Keys()
					If p.StartsWith("-L") Then
						Local libPath:String = p[2..].Replace("~q", "") + "/" + name
						If FileType(libPath) Then
							found = True
							stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = archive.ar; name = " + name + "; path = ~q" + libPath + "~q; sourceTree = ~q<absolute>~q; };"
							Exit
						End If
					End If
				Next
				If Not found Then
					Print "WARNING : could not find file for library import '" + path + "'. Maybe LD_OPTS: -L...  was not defined?"
				End If

			Case TFileId.TYPE_FRM
				name = path[11..]
				stack.AddLast "~t~t" + id + " = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = " + name + ".framework; path = System/Library/Frameworks/" + name + ".framework; sourceTree = SDKROOT; };"
		End Select

	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join("~n")
End Function

Function iOSProjectFrameworksBuildPhase:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "a", "o"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select
		
		If path.StartsWith("-l") Then
			name = "lib" + path[2..] + ".a"
			stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End If

		If path.StartsWith("-framework") Then
			name = path[11..]
			stack.AddLast "~t~t~t~t" + id + " /* " + name + ".framework in Frameworks */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectResourcesBuildPhase:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local id:String = f.id
		
		If f.kind = TFileId.TYPE_DIR Then
			stack.AddLast "~t~t~t~t" + id + " /* " + path + " in Resources */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectResourcesGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		
		Local fid:TFileId = fileMap.GetBuildFileIdForPath(path)
		
		If fid.kind = TFileId.TYPE_DIR Then
			stack.AddLast "~t~t~t~t" + id + " /* " + path + " */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectFrameworksGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		
		If path.StartsWith("-framework") Then
			Local name:String = path[11..]
			stack.AddLast "~t~t~t~t" + id + " /* " + name + ".framework in Frameworks */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectLibsGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "a"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select

		If path.StartsWith("-l") Then
			name = "lib" + path[2..] + ".a"
			stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End If
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectObjectsGroup:String(uuid:String, fileMap:TFileMap)
	Local stack:TStringStack = New TStringStack

	For Local path:String = EachIn fileMap.refFiles.Keys()
		Local id:String = String(fileMap.refFiles.ValueForKey(path))
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)
		
		Select ExtractExt(name)
			Case "o"
				stack.AddLast "~t~t~t~t" + id + " /* " + name + " */"
		End Select
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function iOSProjectLibSearchPaths:String(uuid:String, fileMap:TFileMap)

	Local stack:TStringStack = New TStringStack

	For Local f:TFileId = EachIn fileMap.buildFiles
		Local path:String = f.path
		Local dir:String = ExtractDir(path)
		Local name:String = StripDir(path)

		Select ExtractExt(name)
			Case "a"
				stack.AddLast "~t~t~t~t~q" + EscapeSpaces(dir) + "~q"
		End Select
		
		If path.StartsWith("-L") Then
			stack.AddLast("~t~t~t~t~q" + EscapeSpaces(path[2..]) + "~q")
		End If
		
	Next
	
	If stack.Count() Then
		stack.AddLast ""
	End If
	
	Return stack.Join(",~n")
End Function

Function FindEOL:Int(Text:String, substr:String, start:Int = 0)
	Local i:Int = Text.Find(substr, start)
	If i = -1 Then
		Return -1
	End If
	i :+ substr.Length
	Local eol:Int = Text.Find("~n", i) + 1
	If eol = 0 Then
		Return Text.Length
	End If
	Return eol
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

Type TFileId

	Const TYPE_OBJ:Int = 1
	Const TYPE_ARC:Int = 2
	Const TYPE_DYL:Int = 3
	Const TYPE_LIB:Int = 4
	Const TYPE_FRM:Int = 5
	Const TYPE_DIR:Int = 6

	Field path:String
	Field id:String
	
	Field kind:Int
End Type

Type TFileMap

	Const BUILD:Int = 0
	Const REF:Int = 1

	Field lastId:Int = 0

	Field refFiles:TMap = New TMap
	Field buildFiles:TList = New TList
	
	Method FileId:String(path:String, uuid:String, kind:Int = BUILD, fileKind:Int = 0)
	
		Local id:String
		If kind = BUILD Then
			Local f:TFileId = GetBuildFileIdForPath(path)
			If f Then
				id = f.id
			End If
		Else
			id = String(refFiles.ValueForKey(path))
		End If
		
		If id Then 
			Return id
		End If
		
		Local file:String = "0000000000000" + lastId
		
		id = uuid + file[file.length - 13..]
		
		If kind = BUILD Then
			Local f:TFileId = New TFileId
			f.path = path
			f.id = id
			f.kind = fileKind
			buildFiles.AddLast(f)
		Else
			refFiles.Insert(path, id)
		End If
		
		lastId :+ 1
		
		Return id
	End Method
	
	Method GetBuildFileIdForPath:TFileId(path:String)
		For Local f:TFileId = EachIn buildFiles
			If f.path = path Then
				Return f
			End If
		Next
	End Method

End Type

Type TOrderedMap Extends TMap

	Field _keys:TList = New TList

	Method Insert( key:Object,value:Object )
		If Not Contains(key) Then
			_keys.AddLast(key)
		End If
		Super.Insert(key, value)
	End Method
	
	Method Remove( key:Object )
		_keys.Remove(key)
		Return Super.Remove(key)
	End Method

	Method OrderedKeys:TList()
		Return _keys
	End Method

End Type

