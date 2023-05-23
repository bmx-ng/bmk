SuperStrict

Import BRL.Reflection
Import BRL.Map
Import BRL.LinkedList
'?win32
Import Pub.FreeProcess
'?

?threaded
Import BRL.Threads
Import "bmk_proc_man.bmx"
?
?Not win32
Import "waitpid.c"
?

Import "bmk_config.bmx"
Import "bmk_ng_utils.bmx"


Global processor:TBMK = New TBMK
Global globals:TBMKGlobals = New TBMKGlobals

' load in the base stuff
LoadBMK(AppDir + "/core.bmk", True)
LoadBMK(AppDir + "/make.bmk", True)
' optional
LoadBMK(AppDir + "/config.bmk")

' add some defaults
globals.SetVar("macos_version", String(macos_version))
globals.SetVar("cc_opts", New TOptionVariable)
globals.SetVar("ld_opts", New TOptionVariable)
globals.SetVar("c_opts", New TOptionVariable)
globals.SetVar("cpp_opts", New TOptionVariable)
'globals.SetVar("gcc_version", String(processor.GCCVersion()))

Function LoadBMK(path:String, required:Int = False)
	processor.LoadBMK(path, required)
End Function

' this is the core bmk processor.
Type TBMK

	Field commands:TMap = New TMap

	Field buildLog:TList
	Field sourceList:TList

	Field _minGWBinPath:String
	Field _minGWPath:String
	Field _minGWLinkPaths:String
	Field _minGWDLLCrtPath:String
	Field _minGWCrtPath:String
	Field _minGWExePrefix:String
	
	Field callback:TCallback
	Field _appSettings:TMap

	Method New()
		LuaRegisterObject Self,"bmk"
	End Method
	
	Method Reset()
		buildLog = Null
		sourceList = Null
		_minGWBinPath = Null
		_minGWPath = Null
		_minGWLinkPaths = Null
		_minGWDLLCrtPath = Null
		_minGWCrtPath = Null
		_minGWExePrefix = Null
	End Method

	' loads a .bmk, stores any functions, and runs any commands.
	Method LoadBMK(path:String, required:Int = False)
		Local str:String
		Try
			If FileType(path) = 1 Then
				str = LoadText( path )

				If Int(globals.Get("verbose")) Or opt_verbose
					Print "Loading " + path
				End If
			Else
				If FileType(AppDir + "/" + path) = 1 Then
					str = LoadText( AppDir + "/" + path )

					If Int(globals.Get("verbose")) Or opt_verbose
						Print "Loading " + AppDir + "/" + path
					End If
				Else
					If FileType(globals.Get("BUILDPATH") + "/" + path) = 1 Then
						str = LoadText(globals.Get("BUILDPATH") + "/" + path )

						If Int(globals.Get("verbose")) Or opt_verbose
							Print "Loading " + globals.Get("BUILDPATH") + "/" + path
						End If
					Else
						If required Then
							Throw "Could not load required config '" + path + "'"
						End If
						Return
					End If
				End If
			End If
		Catch e:Object
			Try
				If FileType(AppDir + "/" + path) = 1 Then
					str = LoadText( AppDir + "/" + path )

					If Int(globals.Get("verbose")) Or opt_verbose
						Print "Loading " + AppDir + "/" + path
					End If
				Else
					If FileType(globals.Get("BUILDPATH") + "/" + path) = 1 Then
						str = LoadText(globals.Get("BUILDPATH") + "/" + path )

						If Int(globals.Get("verbose")) Or opt_verbose
							Print "Loading " + globals.Get("BUILDPATH") + "/" + path
						End If
					Else
						If required Then
							Throw "Could not load required config '" + path + "'"
						End If
						Return
					End If
				End If
			Catch e:Object
				' we tried... twice
				' fail silently...
				' unless the file was required!
				If required Then
					Throw "Could not load required config '" + path + "'"
				End If
				Return
			End Try
		End Try

		Local pos:Int, inDefine:Int, Text:String, name:String
	
		While pos < str.length
	
			Local eol:Int = str.Find( "~n",pos )
			If eol = -1 Then
				eol = str.length
			End If
	
			Local line:String = str[pos..eol].Trim()
			pos = eol+1
			
			ProcessLine(line, inDefine, Text, name)

			' anything else?
		Wend
	End Method
	
	' processes a pragma
	Method ProcessPragma(line:String, inDefine:Int Var, Text:String Var, name:String Var)
		ProcessLine(line, inDefine, Text, name)
	End Method
	
	Method ProcessLine(line:String, inDefine:Int Var, Text:String Var, name:String Var)
	
		If line.StartsWith("#") Then
			Return
		End If
		
		Local lline:String = line.ToLower()
		
		If line.StartsWith("@") Then
			
			If lline[1..].StartsWith("define") Then
				
				inDefine = True
				name = line[8..].Trim()
	
				Local cmd:TBMKCommand = New TBMKCommand
				cmd.name = name
				commands.Insert(name.ToLower(), cmd)
				
				Return
			End If
			
			If lline[1..].StartsWith("end") Then
			
				If inDefine Then
					Local cmd:TBMKCommand = TBMKCommand(commands.ValueForKey(name.ToLower()))
					cmd.LoadCommand(Text)
	
					Text = ""
					inDefine = False
				End If
				
				Return
			End If
			
		End If
	
		If inDefine Then
			Text:+ line + "~n"
			Return
		End If
		
		If line.length = 0 Then
			Return
		End If
		
		' find command, and run
		Local i:Int=1
		While i < lline.length And (CharIsAlpha(lline[i]) Or CharIsDigit(lline[i]))
			i:+1
		Wend
		'If i = lline.length Then
		'	Continue
		'End If
		
		Local command:String = lline[..i]
		Local cmd:TBMKCommand = TBMKCommand(commands.ValueForKey(command))
		
		' this is a command!
		If cmd Then
			cmd.RunCommand(line[i+1..])
			Return
		End If
		
		' what's left?
		' setting a variable?
		i = line.Find("=")
		If i <> -1 Then
			' hmm. maybe a variable...
			Local variable:String = line[..i].Trim()
			Local value:String = Parse(line[i+1..].Trim())
			globals.SetVar(variable, value)
		End If
	
	End Method
	
	Method Parse:String(str:String)

		Local done:Int
		
		While Not done
		
			Local pos:Int, restart:Int, changed:Int
			While pos < str.length And Not restart
		
				Local eol:Int = str.Find( "~n",pos )
				If eol = -1 Then
					eol = str.length
				End If
		
				Local line:String = str[pos..eol].Trim()
				pos = eol+1
				
				Local i:Int
				While i < line.length
					i = line.find("%", i)
					If i = -1 Then
						i = line.length
						Continue
					End If
					Local start:Int = i
					i:+ 1
				
					While i < line.length And (CharIsAlpha(line[i]) Or CharIsDigit(line[i]))
						i:+1
					Wend
					
					If i > start Then
						If line[i..i+1] = "%" Then
							i:+ 1
							Local toReplace:String = line[start..i]
							' we want to replace this with something, so we
							' will look in the globals list and env for a match.
							' Otherwise, it will swap % with $, and leave it as is.
							Local with:String = FindValue(toReplace)
							If with Then
								str = str.Replace(toReplace, with)
								restart = True
							End If
						End If
					End If
					
				
				Wend
				
				
			Wend
			
			
			If Not restart Then
				done = True
			End If
			
		Wend

		Return str
	End Method
	
	Method FindValue:String(variable:String)
		Local plainVar:String = variable.Replace("%", "")
		Local value:String = globals.Get(plainVar)
		
		If value Then
			Return value
		End If
		
		' look for environment variable ?
		Local env:String = getenv_(plainVar)
		If env Then
			Return env
		End If
		
		' return the original
		Return variable.Replace("%", "$")
	End Method
	
	' quotes a string, if required (does it have spaces in it?)
	Method Quote:String(t:String)
		Return CQuote(t)
	End Method
	
	' returns the platform as a string
	Method Platform:String()
		If Not opt_target_platform Then
			' the native target platform
?raspberrypi
			Return "raspberrypi"
?android
			Return "android"
?macos
			Return "macos"
?linux
			Return "linux"
?win32
			Return "win32"
?emscripten
			Return "emscripten"
?haiku
			Return "haiku"
?
		Else
			' the custom target platform
			Return opt_target_platform
		End If
	End Method

	Method OSPlatform:String()
?raspberrypi
		Return "raspberrypi"
?android
		Return "android"
?macos
		Return "macos"
?linux
		Return "linux"
?win32
		Return "win32"
?emscripten
		Return "emscripten"
?haiku
		Return "haiku"
?
	End Method

	'returns the app type as a string ("gui", "console" ...)
	Method AppType:String()
		Return opt_apptype
	End Method

	
	' returns the cpu type, as a string
	Method CPU:String()
		Return opt_arch
'		Return cputypes[cputype]
	End Method
	
	Method ToggleCPU()
		If opt_universal Then
			Select Platform()
				Case "macos"
					Select CPU()
						Case "ppc"
							opt_arch = "x86"
						Case "x86"
							opt_arch = "ppc"
						Case "x64"
							opt_arch = "arm64"
						Case "arm64"
							opt_arch = "x64"
					End Select
				Case "ios"
					Select CPU()
						Case "x86"
							opt_arch = "x64"
						Case "x64"
							opt_arch = "x86"
						Case "armv7"
							opt_arch = "arm64"
						Case "arm64"
							opt_arch = "armv7"
					End Select
			End Select
		End If
	End Method
	
	Method BuildName:String(v:String)
		Local s:String = Platform() + "." + CPU() + "." + v
		Return s.ToLower()
	End Method
	
	Method Sys:Int(cmd:String)
		If Int(globals.Get("verbose")) Or opt_verbose
			Print cmd
		Else If Int(globals.Get("dumpbuild"))
			Local p$=cmd
			p = p.Replace( BlitzMaxPath()+"/","./" )
			WriteStdout p+"~n"
			Local t$="mkdir "
			If cmd.StartsWith( t ) And FileType( cmd[t.length..] ) Return False
		EndIf

		If opt_standalone And Not opt_nolog PushLog(cmd)

		If Not opt_standalone Or (opt_standalone And opt_nolog) Then
?win32
			Return system_( cmd )
?Not win32
			Local s:Byte Ptr = cmd.ToUtf8String()
			Local res:Int = bmx_system(s)
			MemFree(s)
			Return res
?
		End If
	End Method

	Method MultiSys:Int(cmd:String, src:String, obj:String, supp:String)
		If Int(globals.Get("verbose")) Or opt_verbose
			Print cmd
		Else If Int(globals.Get("dumpbuild"))
			Local p$=cmd
			p = p.Replace( BlitzMaxPath()+"/","./" )
			WriteStdout p+"~n"
			Local t$="mkdir "
			If cmd.StartsWith( t ) And FileType( cmd[t.length..] ) Return False
		EndIf

		If opt_standalone And Not opt_nolog PushLog(cmd)
		
		If Not opt_standalone Or (opt_standalone And opt_nolog) Then
			Local threaded:Int
?threaded
			threaded = True

			If threaded And Not opt_single Then
				processManager.DoSystem(cmd, src, obj, supp)
			Else
?
					If obj Then
						DeleteFile obj
					End If
					
					If supp Then
						DeleteFile supp
					End If
	
					Local res:Int = system_( cmd )
					If Not res Then
						If src.EndsWith(".bmx") Then
							processor.DoCallback(src)
						End If
					End If
					
					Return res
?threaded
			End If
?
		End If
	End Method

	Method ThrowNew(e:String)
		Throw e
	End Method
	
	Method Call(name:String, args:String[])
		RunCommand(name, args)
	End Method

	Method AddArg(option:String, extra:String)
		Local args:String[] = [option]
		If extra Then
			args:+ [extra]
		End If
		
		ParseConfigArgs args
	End Method

	Method Option:String(key:String, defaultValue:String)
		Local value:String = globals.Get(key)
		
		If Not value Then
			Return defaultValue
		Else
			Return value
		End If
	End Method
	
	Method GCCVersion:String(getVersionNum:Int = False, getRawVersion:Int = False)
'?win32
		Global compiler:String
		Global version:String
		Global rawVersion:String
		
		If compiler Then
			If getVersionNum Then
				If getRawVersion Then
					Return rawVersion
				Else
					Return version
				End If
			Else
				Return compiler + " " + version
			End If
		End If

		Local process:TProcess
		If Platform() = "win32" Then
			process = CreateProcess(Option("path_to_gcc", MinGWBinPath() + "/gcc.exe") + " --version", HIDECONSOLE)
		Else	
			process = CreateProcess("gcc --version")
		End If
		
		If Not process Then
			Throw "Cannot find a valid GCC compiler. Please check your paths and environment."
		End If
		
		While True
			Delay 10
			
			Local line:String = process.pipe.ReadLine()

			If Not process.Status() And Not line Then
				Exit
			End If

			Local parts:String[] = line.Split(" ")
			
			If line.startswith("gcc") or parts[0].EndsWith("gcc") Then
				compiler = "gcc"
			Else If line.startswith("Target:") Then
				_target = line[7..].Trim()
			Else
				Local pos:Int = line.Find("clang")
				If pos >= 0 Then
					compiler = "clang"
					_clang = True
				End If
			End If
			
		Wend
		If process Then
			process.Close()
		End If

		' get version
		If Platform() = "win32" Then
			process = CreateProcess(Option("path_to_gcc", MinGWBinPath() + "/gcc.exe") + " -dumpversion -dumpfullversion", HIDECONSOLE)
		Else	
			process = CreateProcess("gcc -dumpversion -dumpfullversion")
		End If
		Local s:String
		
		While True
			Delay 10
			
			Local line:String = process.pipe.ReadLine()

			If Not process.Status() And Not line Then
				Exit
			End If
			
			If Not rawVersion and line Then
				rawVersion = line.Trim()

				Local values:String[] = rawVersion.split(".")
				For Local v:String = EachIn values
					Local n:String = "0" + v
					s:+ n[n.length - 2..]
				Next
			End If
		
		Wend
	
		If process Then
			process.Close()
		End If

		version = s
		
		If getVersionNum Then
			If getRawVersion Then
				Return rawVersion
			Else
				Return version
			End If
		End If
		
		Return compiler + " " + version
'?
	End Method

	Method XCodeVersion:String()
?macos
		Global xcode:String
		Global version:String
		
		If xcode Then
			Return version
		End If

		Local process:TProcess
		process = CreateProcess(Option(BuildName("xcodebuild"), "xcodebuild") + " -version")

		Local s:String
		
		If Not process Then
			Throw "Cannot find xcodebuild. Please check your paths and environment."
		End If
		
		While True
			Delay 10
			
			Local line:String = process.pipe.ReadLine()

			If Not process.Status() And Not line Then
				Exit
			End If
			
			If line.startswith("Xcode") Then
				xcode = line
				Local parts:String[] = line.split(" ")
				
				version =parts[1].Trim()
			End If
			
		Wend
		If process Then
			process.Close()
		End If
		
		Return version
?Not macos
		Return Null
?
	End Method

	Global _target:String
	Global _clang:Int
	
	Method HasTarget:Int(find:String)
		
		If Not _target Then
			GCCVersion()	
		End If
		
		If _target Then
			If _target.Find(find) >= 0 Then
				Return True
			End If
		End If
		
		Return False
		
	End Method
	
	Method GCCVersionInt:Int()
	End Method

	Method HasClang:Int()
		Return _clang
	End Method

	Method BCCVersion:String()

		Global bcc:String
		
		If bcc Then
			Return bcc
		End If

		Local exe:String = "bcc"
		If OSPlatform() = "win32" Then
			exe :+ ".exe"
		End If

		Local process:TProcess = CreateProcess(CQuote(BlitzMaxPath() + "/bin/" + exe), HIDECONSOLE)
		Local s:String
		
		If Not process Then
			Throw "Cannot find a valid bcc. I am looking for it here : " + BlitzMaxPath() + "/bin/" + exe
		End If
		
		While True
			Delay 10
			
			Local line:String = process.pipe.ReadLine()
		
			If Not process.Status() And Not line Then
				Exit
			End If
			
			If line.startswith("BlitzMax") Then
				bcc = "BlitzMax"
			Else
				bcc = line[..line.Find(" ")]
			End If
			
		Wend
		If process Then
			process.Close()
		End If

		Return bcc
	End Method

	Method MinGWBinPath:String()
		If Not _minGWBinPath Then
			_minGWBinPath = MinGWPath() + "/bin"
?win32
			Local PATH:String = _wgetenv("PATH")
			PATH = _minGWBinPath + ";" + PATH
			_wputenv("PATH=" + PATH)
?
		End If
		
		Return _minGWBinPath
	End Method
	
	Method MinGWPath:String()
		If Not _minGWPath Then
			Local path:String
			' look for local MinGW32 dir
			' some distros (eg. MinGW-w64) only support a single target architecture - x86 or x64
			' to compile for both, requires two separate MinGW installations. Check against
			' CPU target based dir first, before working through the fallbacks.
			Local cpuMinGW:String = "/MinGW32x86"
			If processor.CPU()="x64" Then
				cpuMinGW = "/MinGW32x64"
			EndIf

			path = BlitzMaxPath() + cpuMinGW + "/bin"
			If FileType(path) = FILETYPE_DIR Then
				' bin dir exists, go with that
				_minGWPath = BlitzMaxPath() + cpuMinGW 
				Return _minGWPath
			End If

			path = BlitzMaxPath() + "/MinGW32/bin"
			If FileType(path) = FILETYPE_DIR Then
				' bin dir exists, go with that
				_minGWPath = BlitzMaxPath() + "/MinGW32"
				Return _minGWPath
			End If

			path = BlitzMaxPath() + "/MinGW32x86/bin"
			If FileType(path) = FILETYPE_DIR Then
				' bin dir exists, go with that
				_minGWPath = BlitzMaxPath() + "/MinGW32x86" 
				Return _minGWPath
			End If

			path = BlitzMaxPath() + "/MinGW32x64/bin"
			If FileType(path) = FILETYPE_DIR Then
				' bin dir exists, go with that
				_minGWPath = BlitzMaxPath() + "/MinGW32x64" 
				Return _minGWPath
			End If

			path = BlitzMaxPath() + "/llvm-mingw/bin"
			If FileType(path) = FILETYPE_DIR Then
				' bin dir exists, go with that
				_minGWPath = BlitzMaxPath() + "/llvm-mingw"
				Return _minGWPath
			End If

			' try MINGW environment variable
			path = getenv_("MINGW")
			If path And FileType(path) = FILETYPE_DIR Then
				' check for bin dir
				If FileType(path + "/bin") = FILETYPE_DIR Then
					' go with that
					_minGWPath = path
					Return _minGWPath
				End If
			End If

			' none of the above? fallback to BlitzMax dir (for bin and lib)
			_minGWPath = BlitzMaxPath()
		End If
		
		Return _minGWPath
	End Method
	
	Method MinGWLinkPaths:String()
		If Not _minGWLinkPaths Then
			Local links:String
			
			If HasClang() Then
				Select processor.CPU()
					Case "x86"
						links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/i686-w64-mingw32/lib"))
					Case "x64"
						links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/x86_64-w64-mingw32/lib"))
					Case "armv7"
						links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/armv7-w64-mingw32/lib"))
					Case "arm64"
						links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/aarch64-w64-mingw32/lib"))
				End Select
			Else If processor.HasTarget("x86_64") Then
				If processor.CPU()="x86" Then
					links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/lib/gcc/x86_64-w64-mingw32/" + GCCVersion(True, True) + "/32"))
					links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/x86_64-w64-mingw32/lib32"))
				Else
					links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/lib/gcc/x86_64-w64-mingw32/" + GCCVersion(True, True)))
					links :+ " -L" +  CQuote(RealPath(MinGWPath() + "/x86_64-w64-mingw32/lib"))
				End If
			Else
				links :+ " -L" + CQuote(RealPath(MinGWPath() + "/lib"))
				links :+ " -L" + CQuote(RealPath(MinGWPath() +"/lib/gcc/mingw32/" + GCCVersion(True, True)))
			End If
			
			_minGWLinkPaths = links
		End If
		
		Return _minGWLinkPaths
	End Method
	
	' the path where dllcrt2.o resides
	Method MinGWDLLCrtPath:String()
		If Not _minGWDLLCrtPath Then
			' mingw64 ?
			Local path:String = MinGWPath() + "/"
			If processor.HasTarget("x86_64") Then
				
				path :+ "x86_64-w64-mingw32/"
				
				If processor.CPU()="x86" Then
					path :+ "lib32"
				Else
					path :+ "lib"
				End If
				
				If FileType(path) = 0 Then
					Throw "Could not determine MinGWDLLCrtPath : Expecting '" + path + "'"
				End If
				
				_minGWDLLCrtPath = path
			Else
				path :+ "lib"

				If FileType(path) = 0 Then
					Throw "Could not determine MinGWDLLCrtPath : Expecting '" + path + "'"
				End If
				
				_minGWDLLCrtPath = path
			End If
		End If
		
		Return RealPath(_minGWDLLCrtPath)
	End Method
	
	' the path where crtbegin.o resides
	Method MinGWCrtPath:String()
		If Not _minGWCrtPath Then
			' mingw64 ?
			Local path:String = MinGWPath() + "/"
			If processor.HasTarget("x86_64") Then
				
				path :+ "x86_64-w64-mingw32/"
				
				If processor.CPU()="x86" Then
					path :+ "lib32"
				Else
					path :+ "lib"
				End If
				
				If FileType(path) = 0 Then
					Throw "Could not determine MinGWCrtPath: Expecting '" + path + "'"
				End If
				
				_minGWCrtPath = path
			Else
			
				Local p:String = path +  "lib/gcc/mingw32/" + GCCVersion(True, True)
				If FileType(p) = 0 Then
					path :+ "lib/gcc/i686-w64-mingw32/" + GCCVersion(True, True)
				Else
					path = p
				End If

				If FileType(path) = 0 Then
					Throw "Could not determine MinGWCrtPath: Expecting '" + p + "' or '" + path + "'"
				End If
				
				_minGWCrtPath = path
			End If
		End If
		
		Return RealPath(_minGWCrtPath)
	End Method

	Method MinGWExePrefix:String()
		If Not _minGWExePrefix Then
			GCCVersion()
			If processor.HasClang() Then
				Select processor.CPU()
					Case "x86"
						_minGWExePrefix = "i686-w64-mingw32uwp-"
					Case "x64"
						_minGWExePrefix = "x86_64-w64-mingw32uwp-"
					Case "armv7"
						_minGWExePrefix = "armv7-w64-mingw32-"
					Case "arm64"
						_minGWExePrefix = "aarch64-w64-mingw32-"
				End Select
			End If
		End If
		Return _minGWExePrefix
	End Method
	
	Method IsDebugBuild:Int()
		Return opt_debug
	End Method

	Method IsGdbDebugBuild:Int()
		Return opt_gdbdebug
	End Method

	Method IsReleaseBuild:Int()
		Return opt_release
	End Method

	Method IsThreadedBuild:Int()
		Return opt_threaded
	End Method

	Method IsQuickscanBuild:Int()
		Return opt_quickscan
	End Method

	Method IsUniversalBuild:Int()
		Return opt_universal
	End Method

	Method GetModFilter:String()
		Return opt_modfilter
	End Method

	Method GetConfigMung:String()
		Return opt_configmung
	End Method
	
	Method SupportsHiRes:Int()
		Return opt_hi
	End Method

	Method RunCommand:Object(command:String, args:String[])
		Local cmd:TBMKCommand = TBMKCommand(commands.ValueForKey(command.ToLower()))
		If cmd Then
			' we need to add the "arg0" string to the front of the array
			Local all:String
			For Local i:Int = 0 Until args.length
				Local arg:String = args[i]
				all:+ CQuote$(arg) + " "
			Next
			args = [ all.Trim() ] + args
			' now we can run the command
			Return cmd.RunCommandArgs(args)
		End If
	End Method

	Method PushLog(cmd:String)
		If Not buildLog Then
			buildLog = New TList
		End If

		Local p:String = FixPaths(cmd)

		buildLog.AddLast(p)
	End Method

	Method PushSource(src:String)
		If Not sourceList Then
			sourceList = New TList
		End If

		Local p:String = FixPaths(src)

		sourceList.AddLast(p)
	End Method

	Method PushEcho(cmd:String)
		PushLog("echo " + cmd)
	End Method
	
	Method FixPaths:String(Text:String)
		Local p:String = Text
		Local bmxRoot:String = "$BMX_ROOT"
		If Platform() = "win32" Then
			bmxRoot = "%BMX_ROOT%"
		End If
		Local appRoot:String = "$APP_ROOT"
		If Platform() = "win32" Then
			appRoot = "%APP_ROOT%"
		End If
		p = p.Replace(BlitzMaxPath()+"/", bmxRoot + "/")
		p = p.Replace(String(globals.GetRawVar("EXEPATH")), appRoot)
		Return p
	End Method
	
	Method AppDet:String()
		Return StripExt(StripDir(app_main)) + "." + opt_apptype + opt_configmung + processor.CPU()
	End Method
	
	Method DoCallback(src:String)
		If callback Then
			callback.DoCallback(src)
		End If
	End Method
	
	Method VerboseBuild:Int()
		Return opt_verbose
	End Method
	
	Method AppSetting:String(key:String)
		If Not _appSettings Then
			_appSettings = ParseApplicationIniFile()
		End If
		
		Return String(_appSettings.ValueForKey(key))
	End Method
	
End Type

?win32
Extern
	Function _wgetenv$w(varname$w)
	Function _wputenv:Int(varname$w)
End Extern
?

' stores variables, as well as a variable stack which can be pushed and popped.
Type TBMKGlobals

	' current value of variables
	Field vars:TMap = New TMap
	' variable stack
	Field stack:TMap = New TMap
	
	Method New()
		LuaRegisterObject Self,"globals"
	End Method

	' sets the variable with value
	Method SetVar(variable:String, value:Object)
'Print "SetVar : " + variable + " : " + String(value)
		vars.Insert(variable.ToUpper(), value)
	End Method
	
	' returns the current value for variable
	Method Get:String(variable:String)
		Local obj:Object = vars.ValueForKey(variable.ToUpper())
		If obj Then
			If String(obj) Then
				Return String(obj)
			End If
			Return obj.ToString()
		End If
	End Method
	
	Method GetRawVar:Object(variable:String)
		Local obj:Object = vars.ValueForKey(variable.ToUpper())
		If TOptionVariable(obj) Then
			' return a copy of the object - any changes to this won't affect the current value.
			Return TOptionVariable(obj).Clone()
		End If
		Return obj
	End Method

	Method GetOptionVar:String(variable:String, name:String)
		Local obj:TOptionVariable = TOptionVariable(vars.ValueForKey(variable.ToUpper()))
		If obj Then
			Return obj.GetVar(name)
		End If
	End Method

	' push the variable onto the stack (save the value)
	Method Push(variable:String)
		variable = variable.ToUpper()
		
		Local list:TList = TList(stack.ValueForKey(variable))
		If Not list Then
			list = New TList
			stack.Insert(variable, list)
		End If
		
		list.AddLast(GetRawVar(variable))
	End Method
	
	' pop the variable from the stack (load the value)
	Method Pop(variable:String)
		variable = variable.ToUpper()
	
		Local list:TList = TList(stack.ValueForKey(variable))
		If list And Not list.IsEmpty() Then
			SetVar(variable, list.RemoveLast())
		End If
	End Method
	
	' push all the variables
	Method PushAll(exclude:String[] = Null)
		For Local v:String = EachIn vars.Keys()
			If Not exclude
				Push(v)
			Else
				For Local s:String = EachIn exclude
					If s <> v Then
						Push(v)
						Exit
					End If
				Next
			End If
		Next
	End Method
	
	' pop all the variables
	Method PopAll()
		For Local v:String = EachIn vars.Keys()
			Pop(v)
		Next
	End Method
	
	' adds value to the end of variable
	Method Add(variable:String, value:String, once:Int = False)
		If Not AsConfigurable(variable.ToLower(), value) Then
			variable = variable.ToUpper()
	
			Local v:Object = vars.ValueForKey(variable)
			If Not TOptionVariable(v) Then
				If v And Not once Then
					SetVar(variable, String(v) + " " + value)
				Else
					SetVar(variable, value)
				End If
			End If
		End If
	End Method

	' adds comma separated value to the end of variable
	Method AddC(variable:String, value:String)
		If Not AsConfigurable(variable.ToLower(), value) Then
			variable = variable.ToUpper()
	
			Local v:Object = vars.ValueForKey(variable)
			If Not TOptionVariable(v) Then
				If v Then
					SetVar(variable, String(v) + "," + value)
				Else
					SetVar(variable, value)
				End If
			End If
		End If
	End Method

	Method AddOption(variable:String, key:String, value:String)
		variable = variable.ToUpper()

		Local v:Object = vars.ValueForKey(variable)
		If TOptionVariable(v) Then
			TOptionVariable(v).AddVar(key, value)
		Else
			Local opt:TOptionVariable = New TOptionVariable
			opt.addVar(key, value)
			setVar(variable, opt)
		End If

	End Method

	Method SetOption(variable:String, key:String, value:String)
		variable = variable.ToUpper()

		Local v:Object = vars.ValueForKey(variable)
		If TOptionVariable(v) Then
			TOptionVariable(v).SetVar(key, value)
		Else
			Local opt:TOptionVariable = New TOptionVariable
			opt.SetVar(key, value)
			setVar(variable, opt)
		End If

	End Method

	' only appropriate for TOptionVariables
	Method RemoveVar(variable:String, name:String)
		variable = variable.ToUpper()
		Local v:Object = vars.ValueForKey(variable)
		If TOptionVariable(v) Then
			TOptionVariable(v).RemoveVar(name)
		End If
	End Method
	
	Method Clear(variable:String)
		variable = variable.ToUpper()

		Local v:Object = vars.ValueForKey(variable)
		If TOptionVariable(v) Then
			vars.remove(variable)
		End If
	End Method
	
	Method Reset()
		stack.Clear()
	End Method
	
	Method Dump()
		For Local k:String = EachIn vars.Keys()
			Print k + " : " + Get(k)
		Next
	End Method
	
End Type

Type TOpt
	Field name:String
	Field value:String
End Type

' holds a list of options.
' useful for storing a list of cc_opts, for example.
' the list can be modified as required, and cloned during push/pop calls.
Type TOptionVariable

	Field options:TMap = New TMap
	Field orderedOptions:TList = New TList
	
	Method AddVar(name:String, value:String)', insertBefore:Int = False)
		Local opt:TOpt = New TOpt
	
		If Not name Then
			Global count:Int
			count:+1
			name = "VAR" + count
			opt.name = name
		Else
			opt.name = name
		End If
		opt.value = value
		
		options.Insert(name, opt)
		orderedOptions.AddLast(opt)
		
	End Method

	Method SetVar(name:String, value:String)', insertBefore:Int = False)
		Local opt:TOpt = New TOpt
	
		If Not name Then
			Global count:Int
			count:+1
			name = "VAR" + count
			opt.name = name
		Else
			opt.name = name
		End If
		opt.value = value

		' option already exists?
		Local o:TOpt = TOpt(options.ValueForKey(name))
		If o Then
			orderedOptions.Remove(o)
		End If
		
		options.Insert(name, opt)
		orderedOptions.AddLast(opt)
		
	End Method
	
	Method GetVar:String(name:String)
		Return String(options.ValueForKey(name))
	End Method
	
	' finds and removes a matching value
	Method RemoveVar(name:String)
		Local opt:TOpt = TOpt(options.ValueForKey(name))
		options.Remove(opt)
		orderedOptions.Remove(opt)
	End Method
	
	Method ToString:String()
		Local s:String = " "
		
		For Local opt:TOpt = EachIn orderedOptions
			s:+ opt.value + " "
		Next

		Return s
	End Method
	
	' create an exact copy of me
	Method Clone:TOptionVariable()
		Local me:TOptionVariable = New TOptionVariable
		For Local name:String = EachIn options.Keys()
			me.options.insert(name, options.ValueForKey(name))
		Next
		For Local opt:TOpt = EachIn orderedOptions
			me.orderedOptions.AddLast(opt)
		Next
		Return me
	End Method

End Type

' a bmk function/command
Type TBMKCommand

	Field name:String
	Field command:String

	Field argCount:Int = 0

	Field class:TLuaClass
	Field instance:TLuaObject
	
	Method LoadCommand(cmd:String)
		
		cmd = WrapVariables(ParseArgs(cmd))
		
	
		Local code:String = "function bmk_" + name + "(...)~n" + ..
			GetArgs() + ..
			"nvl = function(a1,a2) if a1 == nil then return a2 else return a1 end end~n" + ..
			cmd + ..
			"end"

		class = New TLuaClass.SetSourceCode( code )
		instance = New TLuaObject.Init( class, Null )

	End Method
	
	Method RunCommand:Object(args:String)
		Return RunCommandArgs([args] + ExtractArgs(args))
	End Method
	
	' This assumes we have arg0 + other args
	Method RunCommandArgs:Object(args:Object[])
		Return instance.invoke("bmk_" + name, args)
	End Method

	' handles quotes and arrays [].
	' [] inside quotes are ignored.	
	Method ExtractArgs:Object[](args:String)
		Local argArray:Object[]

		Local arg:String, arr:String[]
		Local i:Int, inString:Int, inArray:Int
		While i < args.length
			Local c:String = args[i..i+1]
			i:+ 1
			
			If c = "~q" Then
				If inString Then
					If arg Then
						If Not inArray Then
							argArray:+ [ arg ]
						Else
							arr:+ [ arg ]
						End If
					End If

					arg = ""
					inString = False
					Continue
				Else
					arg = ""
					inString = True
					Continue
				End If
			End If
			
			If c = " " And Not inString Then
				If arg Then
					If Not inArray Then
						argArray:+ [ arg ]
					Else
						arr:+ [ arg ]
					End If
					arg = ""
				End If
				Continue
			End If
			
			If c = "[" And Not inString Then
				If Not inArray Then
					inArray = True
					arr = Null
					arg = ""
					Continue
				End If
			End If
			
			If c = "]" And Not inString Then
				If inArray Then
					If arg Then
						arr:+ [ arg ]
					End If
					inArray = False
					argArray:+ [ arr ]
					arr = Null
					arg = ""
					Continue
				End If
			End If
			
			
			arg:+ c
			
		Wend
		
		If arg Then
			If arr Then
				arr:+ [arg]
				argArray:+ [arr]
			Else
				argArray:+ [arg]
			End If
		Else
			If arr Then
				argArray:+ [arr]
			End If
		End If
		
		Return argArray
	End Method
	
	Method ParseArgs:String(cmd:String)
		' This needs to process the command text to work out what args are used.
		' so, for example, arg0, arg1 and arg2.
		' That way, we generate the correct functionality when we build the function code.

		Local pos:Int
		While pos < cmd.length
	
			Local eol:Int = cmd.Find( "~n",pos )
			If eol = -1 Then
				eol = cmd.length
			End If
	
			Local line:String = cmd[pos..eol].Trim()
			pos = eol+1

			Local i:Int
			While i < line.length
				i = line.find("arg", i)
				If i = -1 Then
					i = line.length
					Continue
				End If
				
				i:+ 3
				Local start:Int = i
			
				While i < line.length And CharIsDigit(line[i])
					i:+1
				Wend

				Local num:Int = line[start..i].ToInt()
				If num Then
					argCount = Max(argCount, num)
				End If
				
			Wend
		Wend
		
		Return cmd
		
	End Method
	
	Method GetArgs:String()
		Local args:String = "local arg0"
		Local rep:String = "arg0 = bmk.Parse(arg0)~n"
		
		If argCount > 0 Then
			For Local i:Int = 1 To argCount
				args:+ ",arg" + i
				rep :+ "arg" + i + " = bmk.Parse(arg" + i + ")~n"
			Next
		End If
		
		args :+ " = unpack({...})~n"
		args :+ rep

		Return args
	End Method
	
	Method WrapVariables:String(str:String)

		Local done:Int
		
		While Not done
		
			Local pos:Int, restart:Int, changed:Int
			While pos < str.length And Not restart
		
				Local eol:Int = str.Find( "~n",pos )
				If eol = -1 Then
					eol = str.length
				End If
		
				Local line:String = str[pos..eol].Trim()
				pos = eol+1
				
				Local i:Int
				While i < line.length
					i = line.find("%", i)
					If i = -1 Then
						i = line.length
						Continue
					End If
					Local start:Int = i
					i:+ 1
				
					While i < line.length And (CharIsAlpha(line[i]) Or CharIsDigit(line[i]))
						i:+1
					Wend
					
					If i > start Then
						If line[i..i+1] = "%" Then
							i:+ 1
							Local toReplace:String = line[start..i]

							Local with:String = "globals.Get(~q" + toReplace.Replace("%", "") + "~q)"
							str = str.Replace(toReplace, with)
							restart = True
						End If
					End If
					
				Wend
				
			Wend
			
			If Not restart Then
				done = True
			End If
			
		Wend

		Return str
	End Method

End Type

?Not win32
Extern
	Function bmx_system:Int(cmd:Byte Ptr)
End Extern
?

Type TProcessTaskFactoryImpl Extends TProcessTaskFactory
	Method Create:TProcessTask( cmd:String, src:String, obj:String, supp:String )
		Return new TProcessTaskImpl.Create(cmd, src, obj, supp)
	End Method
End Type

new TProcessTaskFactoryImpl

Type TProcessTaskImpl Extends TProcessTask

	Field command:String
	Field source:String
	
	Field obj:String
	Field supp:String
	
	Method Create:TProcessTask(cmd:String, src:String, obj:String, supp:String)
		command = cmd
		source = src
		Self.obj = obj
		Self.supp = supp
		Return Self
	End Method
	
	Method DoTasks:Object()
		Local res:Int
		
		If obj Then
			DeleteFile(obj)
		End If
		
		If supp Then
			DeleteFile(supp)
		End If
		
?Not win32
		Local s:Byte Ptr = command.ToUtf8String()
		res = bmx_system(s)
		MemFree(s)
?win32
		res = system_(command)
?
		If res Then
			Local s:String = "Build Error: failed to compile (" + res + ") " + source
			Throw s
		End If
		
		If source.EndsWith(".bmx") Then
			processor.DoCallback(source)
		End If
	End Method

End Type

Type TCallback

	Method DoCallback(src:String) Abstract
	
End Type

?threaded
Global processManager:TProcessManager = New TProcessManager
?