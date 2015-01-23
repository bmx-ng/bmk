SuperStrict

Import BRL.Reflection
Import BRL.Map
Import BRL.LinkedList
'?win32
Import Pub.FreeProcess
'?

?threaded
Import BRL.Threads
?
?Not win32
Import "waitpid.c"
?

Import "bmk_config.bmx"
Import "bmk_ng_utils.bmx"


Global commands:TMap = New TMap
Global processor:TBMK = New TBMK
Global globals:TBMKGlobals = New TBMKGlobals

' load in the base stuff
LoadBMK(AppDir + "/core.bmk")
LoadBMK(AppDir + "/make.bmk")
' optional
LoadBMK(AppDir + "/config.bmk")

' add some defaults
If processor.Platform() = "macos"
	globals.SetVar("macos_version", String(macos_version))
End If
globals.SetVar("cc_opts", New TOptionVariable)
globals.SetVar("ld_opts", New TOptionVariable)
'globals.SetVar("gcc_version", String(processor.GCCVersion()))

Function LoadBMK(path:String)
	processor.LoadBMK(path)
End Function

' this is the core bmk processor.
Type TBMK

	Method New()
		LuaRegisterObject Self,"bmk"
	End Method

	' loads a .bmk, stores any functions, and runs any commands.
	Method LoadBMK(path:String)
		Local str:String
		Try
			If FileType(path) = 1 Then
				str = LoadText( path )
			Else
				If FileType(AppDir + "/" + path) = 1 Then
					str = LoadText( AppDir + "/" + path )
				Else
					If FileType(globals.Get("BUILDPATH") + "/" + path) = 1 Then
						str = LoadText(globals.Get("BUILDPATH") + "/" + path )
					Else
						Return
					End If
				End If
			End If
		Catch e:Object
			Try
				If FileType(AppDir + "/" + path) = 1 Then
					str = LoadText( AppDir + "/" + path )
				Else
					If FileType(globals.Get("BUILDPATH") + "/" + path) = 1 Then
						str = LoadText(globals.Get("BUILDPATH") + "/" + path )
					Else
						Return
					End If
				End If
			Catch e:Object
				' we tried... twice
				' fail silently...
				Return
			End Try
		End Try

		Local pos:Int, inDefine:Int, text:String, name:String
	
		While pos < str.length
	
			Local eol:Int = str.Find( "~n",pos )
			If eol = -1 Then
				eol = str.length
			End If
	
			Local line:String = str[pos..eol].Trim()
			pos = eol+1
			
			ProcessLine(line, inDefine, text, name)

			' anything else?
		Wend
	End Method
	
	' processes a pragma
	Method ProcessPragma(line:String, inDefine:Int Var, text:String Var, name:String Var)
		ProcessLine(line, inDefine, text, name)
	End Method
	
	Method ProcessLine(line:String, inDefine:Int Var, text:String Var, name:String Var)
	
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
					cmd.LoadCommand(text)
	
					text = ""
					inDefine = False
				End If
				
				Return
			End If
			
		End If
	
		If inDefine Then
			text:+ line + "~n"
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
?macos
			Return "macos"
?linux
			Return "linux"
?win32
			Return "win32"
?android
			Return "android"
?raspberrypi
			Return "raspberrypi"
?emscripten
			Return "emscripten"
?
		Else
			' the custom target platform
			Return opt_target_platform
		End If
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
			If opt_arch = "ppc" Then
				opt_arch = "x86"
			Else
				opt_arch = "ppc"
			End If
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
		Return system_( cmd )
	End Method

	Method MultiSys:Int(cmd:String, src:String)
		If Int(globals.Get("verbose")) Or opt_verbose
			Print cmd
		Else If Int(globals.Get("dumpbuild"))
			Local p$=cmd
			p = p.Replace( BlitzMaxPath()+"/","./" )
			WriteStdout p+"~n"
			Local t$="mkdir "
			If cmd.StartsWith( t ) And FileType( cmd[t.length..] ) Return False
		EndIf
		
?threaded
		processManager.DoSystem(cmd, src)
?Not threaded
		Return system_( cmd )
?
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
			If processor.BCCVersion() = "BlitzMax" Then
				process = CreateProcess("gcc -v")
			Else
				process = CreateProcess(MinGWBinPath() + "/gcc.exe -v")
			End If
		Else	
			process = CreateProcess("gcc -v")
		End If
		Local s:String
		
		If Not process Then
			Throw "Cannot find a valid GCC compiler. Please check your paths and environment."
		End If
		
		While True
			Delay 10
			
			Local line:String = process.err.ReadLine()

			If Not process.Status() And Not line Then
				Exit
			End If
			
			If line.startswith("gcc") Then
				compiler = "gcc"
				Local parts:String[] = line.split(" ")
				
				rawVersion = parts[2].Trim()
				Local values:String[] = parts[2].split(".")
				For Local v:String = EachIn values
					Local n:String = "0" + v
					s:+ n[n.length - 2..]
				Next
			Else If line.startswith("Target:") Then
				_target = line[7..].Trim()
			Else
				Local pos:Int = line.Find("clang")
				If pos >= 0 Then
					compiler = "clang"
					s = line[pos + 6..line.find(")", pos)]
				End If
			End If
			
		Wend
		
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
	
	Global _target:String
	
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

	Method BCCVersion:String()

		Global bcc:String
		
		If bcc Then
			Return bcc
		End If

		Local exe:String = "bcc"
		If Platform() = "win32" Then
			exe :+ ".exe"
		End If

		Local process:TProcess = CreateProcess(BlitzMaxPath() + "/bin/" + exe)
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

		Return bcc
	End Method

	Method MinGWBinPath:String()
		Global _path:String

		If Not _path Then
			If processor.BCCVersion() = "BlitzMax" Then
				_path = BlitzMaxPath() + "/bin"
			Else
				_path = MinGWPath() + "/bin"
?win32
				Local PATH:String = _wgetenv("PATH")
				PATH = _path + ";" + PATH
				_wputenv("PATH=" + PATH)
?
			End If
		End If
		
		Return _path
	End Method
	
	Method MinGWPath:String()
		Global _path:String

		If Not _path Then
			If processor.BCCVersion() = "BlitzMax" Then
				_path = getenv_("MINGW")
			Else
				Local path:String
				' look for local MinGW32 dir
				path = BlitzMaxPath() + "/MinGW32/bin"
				If FileType(path) = FILETYPE_DIR Then
					' bin dir exists, go with that
					_path = BlitzMaxPath() + "/MinGW32"
					Return _path
				End If

				' try MINGW environment variable
				path = getenv_("MINGW")
				If path And FileType(path) = FILETYPE_DIR Then
					' check for bin dir
					If FileType(path + "/bin") = FILETYPE_DIR Then
						' go with that
						_path = path
						Return _path
					End If
				End If

				' none of the above? fallback to BlitzMax dir (for bin and lib)
				_path = BlitzMaxPath()
			End If
		End If
		
		Return _path
	End Method
	
	Method MinGWLinkPaths:String()
		Global _links:String
		
		If Not _links Then
			If processor.BCCVersion() = "BlitzMax" Then
				_links = "-L" + CQuote(BlitzMaxPath() + "/lib")
			Else
				Local links:String
				
				If processor.HasTarget("x86_64") Then
					If processor.CPU()="x86" Then
						links :+ " -L" +  CQuote( MinGWPath() + "/lib/gcc/x86_64-w64-mingw32/" + GCCVersion(True, True) + "/32")
						links :+ " -L" +  CQuote( MinGWPath() + "/x86_64-w64-mingw32/lib32")
					Else
						links :+ " -L" +  CQuote( MinGWPath() + "/lib/gcc/x86_64-w64-mingw32/" + GCCVersion(True, True))
						links :+ " -L" +  CQuote( MinGWPath() + "/x86_64-w64-mingw32/lib")
					End If
				Else
					links :+ " -L" + CQuote(MinGWPath() + "/lib")
					links :+ " -L" + CQuote(MinGWPath() +"/lib/gcc/mingw32/" + GCCVersion(True, True))
				End If
				
				_links = links
			End If
		End If
		
		Return _links
	End Method
	
	' the path where dllcrt2.o resides
	Method MinGWDLLCrtPath:String()
		Global _path:String
		
		If Not _path Then
			If processor.BCCVersion() = "BlitzMax" Then
				_path = BlitzMaxPath() + "/lib"
			Else
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
					
					_path = path
				Else
					path :+ "lib"

					If FileType(path) = 0 Then
						Throw "Could not determine MinGWDLLCrtPath : Expecting '" + path + "'"
					End If
					
					_path = path
				End If
			End If
		End If
		
		Return _path
	End Method
	
	' the path where crtbegin.o resides
	Method MinGWCrtPath:String()
		Global _path:String
		
		If Not _path Then
			If processor.BCCVersion() = "BlitzMax" Then
				_path = BlitzMaxPath() + "/lib"
			Else
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
					
					_path = path
				Else
					path :+ "lib/gcc/mingw32/" + GCCVersion(True, True)

					If FileType(path) = 0 Then
						Throw "Could not determine MinGWCrtPath: Expecting '" + path + "'"
					End If
					
					_path = path
				End If
			End If
		End If
		
		Return _path
	End Method
	
	Method IsDebugBuild:Int()
		Return opt_debug
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
	Method Add(variable:String, value:String)
		variable = variable.ToUpper()

		Local v:Object = vars.ValueForKey(variable)
		If Not TOptionVariable(v) Then
			SetVar(variable, String(v) + " " + value)
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

Function RunCommand:Object(command:String, args:String[])
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
End Function

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
					If Not inArray Then
						argArray:+ [ arg ]
					Else
						arr:+ [ arg ]
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
		
		args :+ " = unpack(arg)~n"
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

?threaded
Type TProcessManager
	
	Field cpuCount:Int
	
	Field threads:TList = New TList

	Method New()
		cpuCount = GetCoreCount()
		' single cpu boost...
		If cpuCount = 1 Then
			cpuCount = 2
		End If
	End Method

	Method CheckThreads()
		While threads.Count() = cpuCount
			For Local thread:TThread = EachIn threads
				If Not thread.Running() Then
					threads.Remove(thread)
				End If
			Next
			Delay 5
		Wend
	End Method
	
	Method WaitForThreads()
		While threads.Count()
			For Local thread:TThread = EachIn threads
				If Not thread.Running() Then
					threads.Remove(thread)
				End If
			Next
			Delay 5
		Wend
	End Method
	
	Method DoSystem(cmd:String, src:String)
		threads.AddLast(CreateThread(TProcessTask._DoTasks, New TProcessTask.Create(cmd, src)))

		CheckThreads()
	End Method

End Type

?Not win32
Extern
	Function fork:Int()
	Function bmx_waitpid:Int(pid:Int)
	Function bmx_system(cmd:Byte Ptr)
End Extern
?

Type TProcessTask

	Field command:String
	Field source:String
	
	Method Create:TProcessTask(cmd:String, src:String)
		command = cmd
		source = src
		Return Self
	End Method

	Function _DoTasks:Object(data:Object)
		Return TProcessTask(data).DoTasks()
	End Function
	
	Method DoTasks:Object()
		Local res:Int
		
?Not win32
		Local pid:Int = fork()
		If Not pid Then
			bmx_system(command)
		Else
			res = bmx_waitpid(pid)
		End If
?win32
		res = system_(command)
?

		If res Then
			Local s:String = "Build Error: failed to compile (" + res + ") " + source
			Print s + "~n"
			Throw s
		End If
	End Method

End Type

?threaded
Global processManager:TProcessManager = New TProcessManager
?
