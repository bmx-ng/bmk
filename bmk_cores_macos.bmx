SuperStrict

Extern
	Function sysctlbyname:Int(name:Byte Ptr, count:Int Ptr, size:Int Ptr, a:Byte Ptr, b:Int)
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
		Local l:Int = 4
		sysctlbyname("hw.ncpu", Varptr count, Varptr l,Null,0)
	End If

	Return count
End Function

