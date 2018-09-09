SuperStrict

Import brl.map
Import "stringbuffer_core.bmx"

Global compilerOptions:TValues

Function EvalOption:Int(line:String)
	If Not line Then
		Return True
	End If
	Local tok:TOptTokenizer = New TOptTokenizer.Create(line.ToLower())
	Local parser:TOptParser = New TOptParser.Create(tok, compilerOptions)
	Return parser.Eval()
End Function

Type TOptParser

	Field tokenizer:TOptTokenizer
	Field token:TOptToken
	
	Field values:TValues
	
	Method Create:TOptParser(tokenizer:TOptTokenizer, values:TValues)
		Self.tokenizer = tokenizer
		Self.values = values
		Return Self
	End Method

	Method Eval:Int()
		NextToke
		Local expr:TExpr = Parse()
		Return expr.Eval()
	End Method

	Method NextToke()
		token = tokenizer.NextToken()
	End Method

	Method Parse:TExpr()
		Return ParseOrExpr()
	End Method
	
	Method ParseOrExpr:TExpr()
		Local expr:TExpr = ParseAndExpr()
		Repeat
			If token.tokType = TOK_OR Then
				NextToke
				Local rhs:TExpr = ParseAndExpr()
				expr = New TBinaryExpr.Create(TOK_OR, expr, rhs)
			Else
				Return expr
			End If
		Forever
		Return expr
	End Method
	
	Method ParseAndExpr:TExpr()
		Local expr:TExpr = ParseNotExpr()
		Repeat
			If token.tokType = TOK_AND Then
				NextToke
				Local rhs:TExpr = ParseNotExpr()
				expr = New TBinaryExpr.Create(TOK_AND, expr, rhs)
			Else
				Return expr
			End If
		Forever
	End Method
	
	Method ParseNotExpr:TExpr()
		If token.tokType = TOK_NOT Then
			NextToke
			Local expr:TExpr = ParseNotExpr()
			Return New TNotExpr.Create(expr)
		End If
		
		Return ParsePrimaryExpr()
	End Method
	
	Method ParsePrimaryExpr:TExpr()
		Local expr:TExpr
		
		Select token.tokType
			Case TOK_LPAREN
				NextToke
				expr = Parse()
				If token.tokType <> TOK_RPAREN Then
					Throw "Expected ')'"
				End If
			Case TOK_IDENT
				Local value:Int = values.Value(token.value)
				expr = New TIdentExpr.Create(token.value, value)
				NextToke
			Case TOK_RPAREN
				Throw "Unexpected ')'"
		End Select
		
		Return expr
	End Method
	
End Type

Type TOptToken

	Field tokType:Int
	Field value:String
	
	Method Create:TOptToken(tokType:Int, value:String)
		Self.tokType = tokType
		Self.value = value
		Return Self
	End Method
	
End Type

Type TOptTokenizer
	
	Field line:String
	Field pos:Int

	Method Create:TOptTokenizer(line:String)
		Self.line = line
		Return Self
	End Method

	Method NextToken:TOptToken()
		While True
			If pos = line.length
				Return New TOptToken.Create(TOK_EOL, Null)
			End If
			
			Local char:Int = line[pos]
			
			pos :+ 1
			
			If char = Asc("(") Then
				Return New TOptToken.Create(TOK_LPAREN, "(")
			Else If char = Asc(")") Then
				Return New TOptToken.Create(TOK_RPAREN, ")")
			Else If IsAlphaNumeric(char) Then
				Return NextIdentToken(char)
			Else If Not IsWhitespace(char) Then
				Throw "Unexpected character : " + Chr(char)
			End If			
		Wend
	End Method
	
	Method NextIdentToken:TOptToken(char:Int)
		Local sb:TStringBuffer = TStringBuffer.Create(Chr(char))
		
		While True
			char = Peek()
			If Not IsAlphaNumeric(char) Then
				Exit
			End If
			
			pos :+ 1
			sb.Append(Chr(char))
		Wend
		
		Local token:String = sb.ToString().ToLower()
		
		Select token
			Case "not"
				Return New TOptToken.Create(TOK_NOT, token)
			Case "and"
				Return New TOptToken.Create(TOK_AND, token)
			Case "or"
				Return New TOptToken.Create(TOK_OR, token)
			Default
				Return New TOptToken.Create(TOK_IDENT, token)
		End Select
	End Method
	
	Method IsAlphaNumeric:Int(char:Int)
		Return (char >= Asc("A") And char <= Asc("Z")) Or (char >= Asc("a") And char <= Asc("z")) Or (char >= Asc("0") And char <= Asc("9")) Or char = Asc("_")
	End Method
	
	Method IsWhitespace:Int(char:Int)
		Return char = Asc(" ") Or char = Asc("~t")
	End Method
	
	Method Peek:Int()
		If pos < line.length Then
			Return line[pos]
		End If
		
		Return 0
	End Method
	
End Type

Type TExpr
	Method Eval:Int() Abstract
End Type

Type TNotExpr Extends TExpr
	Field expr:TExpr
	
	Method Create:TNotExpr(expr:TExpr)
		Self.expr = expr
		Return Self
	End Method
	
	Method Eval:Int()
		Return Not expr.Eval()
	End Method
	
End Type

Type TBinaryExpr Extends TExpr
	Field op:Int
	Field lhs:TExpr
	Field rhs:TExpr

	Method Create:TBinaryExpr(op:Int, lhs:TExpr, rhs:TExpr)
		Self.op = op
		Self.rhs = rhs
		Self.lhs = lhs
		Return Self
	End Method
	
	Method Eval:Int()
		Select op
			Case TOK_OR
				Return lhs.Eval() Or rhs.Eval()
			Case TOK_AND
				Return lhs.Eval() And rhs.Eval()
		End Select
	End Method
	
End Type

Type TIdentExpr Extends TExpr
	Field ident:String
	Field value:Int

	Method Create:TIdentExpr(ident:String, value:Int)
		Self.ident = ident
		Self.value = value
		Return Self
	End Method
	
	Method Eval:Int()
		Return value
	End Method
	
End Type

Type TInt
	Field value:Int
	Method Create:TInt(value:Int)
		Self.value = value
		Return Self
	End Method
End Type

Type TValues
	Field values:TMap = New TMap
	
	Method Add(key:String, value:Int)
		values.Insert(key, New TInt.Create(value))
	End Method
	
	Method Value:Int(key:String)
		Local obj:Object = values.ValueForKey(key)
		If obj Then
			Return TInt(obj).value
		End If
		Return 0
	End Method
	
End Type

Const TOK_IDENT:Int = 0
Const TOK_NOT:Int = 1
Const TOK_AND:Int = 2
Const TOK_OR:Int = 3
Const TOK_LPAREN:Int = 4
Const TOK_RPAREN:Int = 5
Const TOK_EOL:Int = 6

