SuperStrict

Import BRL.MaxUtil
Import BRL.FileSystem
?Not linux
Import BRL.System
?
Import BRL.MaxLua
Import BRL.TextStream

?linux
Import "bmk_cores_linux.bmx"
?macos
Import "bmk_cores_macos.bmx"
?win32
Import "bmk_cores_win32.bmx"
?

Global utils:TMaxUtils = New TMaxUtils
Global fsys:TSystem = New TSystem
Global futils:TFileUtils = New TFileUtils

' Access to BRL.MaxUtil
Type TMaxUtils

	Method New()
		LuaRegisterObject Self,"utils"
	End Method

	Method BlitzMaxPath:String()
		Return BRL.MaxUtil.BlitzMaxPath()
	End Method
	
	Method ModulePath:String( modid$ )
		Return BRL.MaxUtil.ModulePath(modid)
	End Method

	Method ModuleIdent:String( modid$ )
		Return BRL.MaxUtil.ModuleIdent(modid)
	End Method

	Method ModuleSource:String( modid$ )
		Return BRL.MaxUtil.ModuleSource(modid)
	End Method

	Method ModuleArchive:String( modid$,mung$="" )
		Return BRL.MaxUtil.ModuleArchive(modid, mung)
	End Method

	Method ModuleInterface:String( modid$,mung$="" )
		Return BRL.MaxUtil.ModuleInterface(modid, mung)
	End Method

End Type

' Access to BRL.FileSystem and BRL.System
Type TSystem

	Method New()
		LuaRegisterObject Self,"sys"
	End Method

	Method FixPath:String(path:String, dirPath:Int = False)
		Local p:String = path
		BRL.FileSystem.FixPath(p, dirPath)
		Return p
	End Method
	
	Method StripDir$( path$ )
		Return BRL.FileSystem.StripDir(path)
	End Method

	Method StripExt$( path$ )
		Return BRL.FileSystem.StripExt(path)
	End Method

	Method StripAll$( path$ )
		Return BRL.FileSystem.StripAll(path)
	End Method

	Method StripSlash$( path$ )
		Return BRL.FileSystem.StripSlash(path)
	End Method

	Method ExtractDir$( path$ )
		Return BRL.FileSystem.ExtractDir(path)
	End Method

	Method ExtractExt$( path$ )
		Return BRL.FileSystem.ExtractExt(path)
	End Method

	Method CurrentDir$()
		Return BRL.FileSystem.CurrentDir()
	End Method

	Method RealPath$( path$ )
		Return BRL.FileSystem.RealPath(path)
	End Method

	Method FileType:Int( path$ )
		Return BRL.FileSystem.FileType(path)
	End Method

	Method CreateFile:Int( path$ )
		Return BRL.FileSystem.CreateFile(path)
	End Method

	Method CreateDir:Int( path$,recurse:Int=False )
		Return BRL.FileSystem.CreateDir(path, recurse)
	End Method

	Method DeleteFile:Int( path$ )
		Return BRL.FileSystem.DeleteFile(path)
	End Method

	Method RenameFile:Int( oldpath$,newpath$ )
		Return BRL.FileSystem.RenameFile(oldpath, newpath)
	End Method

	Method CopyFile:Int( src$,dst$ )
		Return BRL.FileSystem.CopyFile(src, dst)
	End Method

	Method CopyDir:Int( src$,dst$ )
		Return BRL.FileSystem.CopyDir(src, dst)
	End Method

	Method DeleteDir:Int( path$,recurse:Int=False )
		Return BRL.FileSystem.DeleteDir(path, recurse)
	End Method

	Method ChangeDir:Int( path$ )
		Return BRL.FileSystem.ChangeDir(path)
	End Method
	
?Not linux	
	' System
	Method CurrentDate:String()
		Return BRL.System.CurrentDate()
	End Method
	
	Method CurrentTime:String()
		Return BRL.System.CurrentTime()
	End Method

	Method Notify(text:String, serious:Int = False)
		BRL.System.Notify(text, serious)
	End Method
	
	Method OpenURL(url:String)
		BRL.System.OpenURL(url)
	End Method
?linux
	Method CurrentDate:String(_format$="%d %b %Y")
		Local time:Byte[256],buff:Byte[256]
		time_(time)
		strftime_(buff,256,_format,localtime_( time ))
		Return String.FromCString(buff)
	End Method
	
	Method CurrentTime:String()
		Local time:Byte[256],buff:Byte[256]
		time_(time)
		strftime_( buff,256,"%H:%M:%S",localtime_( time ) );
		Return String.FromCString(buff)
	End Method

	Method Notify(text:String, serious:Int = False)
		WriteStdout text+"~r~n"
	End Method
?
End Type

' Access to BRL.MaxUtil
Type TFileUtils

	Method New()
		LuaRegisterObject Self,"futils"
	End Method

	Method SaveText:Int(filename:String, text:String)
		Try
			Return BRL.TextStream.SaveText(text, filename)
		Catch e:TStreamWriteException
			Return False
		End Try
	End Method
	
End Type
