
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
	RunCommand("assemble", [src, obj])
End Function

Function CompileC( src$,obj$,opts$ )
	RunCommand("CompileC", [src, obj, opts])
End Function

Function CompileBMX( src$,obj$,opts$ )
	DeleteFile obj

	Local azm$=StripExt(obj)
	
	If processor.BCCVersion() = "BlitzMax" Then
		azm :+ ".s"
	End If
	
?threaded
		processManager.WaitForThreads()
?			
	RunCommand("CompileBMX", [src, azm, opts])

	If processor.BCCVersion() = "BlitzMax" Then
		' it would be nice to be able to call this from the script... but we need more refactoring first :-p
		Assemble azm,obj
	End If
End Function

Function CreateArc( path$ , oobjs:TList )
	DeleteFile path
	Local cmd$,t$
	
	If processor.Platform() = "win32"
		For t$=EachIn oobjs
			If Len(cmd)+Len(t)>1000
				If Sys( cmd )
					DeleteFile path
					Throw "Build Error: Failed to create archive "+path
				EndIf
				cmd=""
			EndIf
			If Not cmd cmd= processor.Option("path_to_ar", "ar") + " -r "+CQuote(path)
			cmd:+" "+CQuote(t)
		Next
	End If
	
	If processor.Platform() = "macos"
		cmd="libtool -o "+CQuote(path)
		For Local t$=EachIn oobjs
			cmd:+" "+CQuote(t)
		Next
	End If
	
	If processor.Platform() = "linux"
		For Local t$=EachIn oobjs
			If Len(cmd)+Len(t)>1000
				If Sys( cmd )
					DeleteFile path
					Throw "Build Error: Failed to create archive "+path
				EndIf
				cmd=""
			EndIf
			If Not cmd cmd=processor.Option(processor.BuildName("ar"), "ar") + " -r "+CQuote(path)
			cmd:+" "+CQuote(t)
		Next
	End If

	If cmd And Sys( cmd )
		DeleteFile path
		Throw "Build Error: Failed to create archive "+path
	EndIf
End Function

Function LinkApp( path$,lnk_files:TList,makelib,opts$ )
	DeleteFile path

	Local cmd$
	Local files$
	Local tmpfile$=BlitzMaxPath()+"/tmp/ld.tmp"
	
	If processor.Platform() = "macos"
		cmd="g++"

		If processor.CPU()="ppc" 
			cmd:+" -arch ppc" 
		Else If processor.CPU()="x86"
			cmd:+" -arch i386 -read_only_relocs suppress"
		Else
			cmd:+" -arch x86_64"
		EndIf
		If macos_version>=$1070				'Lion?
			cmd:+" -mmacosx-version-min=10.4"	'...can build for Tiger++
		Else If macos_version>=$1040			'Tiger?
			cmd:+" -mmacosx-version-min=10.3"	'...can build for Panther++
		EndIf
	
		cmd:+" -o "+CQuote( path )
	'	cmd:+" -bind_at_load"
	
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
		
		If usingLD Then
			cmd=CQuote(processor.Option("path_to_ld", BlitzMaxPath()+"/bin/ld.exe"))+" -s -stack 4194304"
			If opt_apptype="gui" cmd:+" -subsystem windows"
		Else
			cmd=CQuote(processor.Option("path_to_gpp", "g++"))+" -s --stack=4194304"
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
			cmd:+" "+CQuote( "-L"+CQuote( BlitzMaxPath()+"/lib") ) ' the BlitzMax lib folder 

			If globals.Get("path_to_mingw_lib") Then
				cmd:+" "+CQuote( "-L"+CQuote( processor.Option("path_to_mingw_lib", BlitzMaxPath()+"/lib") ) )
			End If
			If globals.Get("path_to_mingw_lib2") Then
				cmd:+" "+CQuote( "-L"+CQuote( processor.Option("path_to_mingw_lib2", BlitzMaxPath()+"/lib") ) )
			End If
			If globals.Get("path_to_mingw_lib3") Then
				cmd:+" "+CQuote( "-L"+CQuote( processor.Option("path_to_mingw_lib3", BlitzMaxPath()+"/lib") ) )
			End If
		End If
	
		If makelib
			Local imp$=StripExt(path)+".a"
			Local def$=StripExt(path)+".def"
			If FileType( def )<>FILETYPE_FILE Throw "Cannot locate .def file"
			cmd:+" "+def
			cmd:+" --out-implib "+imp
			If usingLD Then
				files:+"~n"+CQuote( processor.Option("path_to_mingw_lib", BlitzMaxPath()+"/lib") + "/dllcrt2.o" )
			End If
		Else
			If usingLD
				files:+"~n"+CQuote( processor.Option("path_to_mingw_lib2", BlitzMaxPath()+"/lib") + "/crtbegin.o" )
				files:+"~n"+CQuote( processor.Option("path_to_mingw_lib", BlitzMaxPath()+"/lib") + "/crt2.o" )
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
				files:+" "+CQuote( processor.Option("path_to_mingw_lib2", BlitzMaxPath()+"/lib") + "/crtend.o" )
			End If
		EndIf
		
		files="INPUT("+files+")"
	End If
	
	If processor.Platform() = "linux"
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
	
	Local t$=getenv_( "BMK_LD_OPTS" )
	If t 
		cmd:+" "+t
	EndIf

	Local stream:TStream=WriteStream( tmpfile )
	stream.WriteBytes files.ToCString(),files.length
	stream.Close

	If Sys( cmd ) Throw "Build Error: Failed to link "+path

End Function

Function MergeApp(fromFile:String, toFile:String)

	If Not opt_quiet Print "Merging:"+StripDir(fromFile) + " + " + StripDir(toFile)

	Local cmd:String = "lipo -create ~q" + fromFile + "~q ~q" + toFile + "~q -output ~q" + toFile + "~q"
	
	If Sys( cmd ) Throw "Merge Error: Failed to merge " + toFile
	
	DeleteFile fromFile

End Function
