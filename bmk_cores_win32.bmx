SuperStrict

Import "bmk_cores_win32.c"

Extern
	Function bmx_GetSystemInfo_dwNumberOfProcessors:Int()
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
		count = bmx_GetSystemInfo_dwNumberOfProcessors()
	End If

	Return count
End Function

