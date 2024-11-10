SuperStrict

Import "bmk_cores_linux.c"

Extern
	Function bmx_get_core_count:Int()
End Extern

Function GetCoreCount:Int()
	Global count:Int

	If Not count Then
		count = bmx_get_core_count()
	End If

	Return count
End Function
