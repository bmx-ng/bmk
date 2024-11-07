
Strict

Import "bmk_config.bmx"

Import Pub.ZLib
Import BRL.SocketStream

Function CompressBank:TBank( bank:TBank )

?bmxng
	Local size:ULongInt=bank.Size()
	Local out_size:ULongInt=size+size/10+32
	Local out:TBank=TBank.Create( Size_T(out_size) )
?Not bmxng
	Local size=bank.Size()
	Local out_size=size+size/10+32
	Local out:TBank=TBank.Create( out_size )
?
	compress out.Buf()+4,out_size,bank.Buf(),size

	out.PokeByte 0,Int(size)
	out.PokeByte 1,Int(size Shr 8)
	out.PokeByte 2,Int(size Shr 16)
	out.PokeByte 3,Int(size Shr 24)
?bmxng
	out.Resize Size_T(out_size+4)
?Not bmxng
	out.Resize out_size+4
?
	Return out

End Function

Function UncompressBank:TBank( bank:TBank )

?bmxng
	Local out_size:ULongInt
?Not bmxng
	Local out_size
?
	out_size:|bank.PeekByte(0)
	out_size:|bank.PeekByte(1) Shl 8
	out_size:|bank.PeekByte(2) Shl 16
	out_size:|bank.PeekByte(3) Shl 24
?bmxng
	Local out:TBank=TBank.Create( Size_T(out_size) )
	uncompress out.Buf(),out_size,bank.Buf()+4,ULongInt(bank.Size()-4)
?Not bmxng
	Local out:TBank=TBank.Create( out_size )
	uncompress out.Buf(),out_size,bank.Buf()+4,bank.Size()-4
?
	Return out
	
End Function

Function SplitUrl( url$,server$ Var,file$ Var )
	Local i=url.Find( "/",0 )
	If i<>-1
		server=url[..i]
		file=url[i..]
	Else
		server=url
		file="/"
	EndIf
End Function

