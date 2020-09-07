import macros

macro numFields*(T: typedesc): untyped =
  let tDesc = getType(getType(T)[1])
  var i: int = 0
  for field in tDesc[2].children:
    if field.getType.typeKind != ntyObject:
      inc i
    else:
      for frec in getType(field)[2].children:
        inc i
  result = nnkStmtList.newTree()
  result.add(newIntLitNode(i))

macro offsets*(T: typedesc): untyped =
  let tDesc = getType(getType(T)[1])
  result = nnkStmtList.newTree()
  result.add(newNimNode(nnkBracket))
  for field in tDesc[2].children:
    if field.getType.typeKind != ntyObject:
      result[0].add(newIntLitNode(getOffset(field)))
    else:
      let align = getOffset(field)
      for frec in getType(field)[2].children:
        result[0].add(newIntLitNode(getOffset(frec)+align))


proc mapHDFtype(t: NimTypeKind): NimNode =
  case t
  of ntyInt, ntyInt64, ntyRange:
    return ident("H5T_NATIVE_INT64")
  of ntyFloat, ntyFloat64:
    return ident("H5T_NATIVE_DOUBLE")
  of ntyFloat32:
    return ident("H5T_NATIVE_FLOAT")
  of ntyInt32:
    return ident("H5T_NATIVE_INT32")
  of ntyUInt32:
    return ident("H5T_NATIVE_UINT32")
  else:
    discard

macro hdftypes*(T: typedesc): untyped =
  let tDesc = getType(getType(T)[1])
  result = nnkStmtList.newTree()
  result.add(newNimNode(nnkBracket))
  for field in tDesc[2].children:
    if field.getType.typeKind != ntyObject:
      result[0].add(mapHDFtype(field.getType.typeKind))
    else:
      for frec in getType(field)[2].children:
        result[0].add(mapHDFtype(frec.getType.typeKind))

macro fieldnames*(T: typedesc): untyped = 
  let tDesc = getType(getType(T)[1])
  result = nnkStmtList.newTree()
  result.add(newNimNode(nnkBracket))
  for field in tDesc[2].children:
    if field.getType.typeKind != ntyObject:
      result[0].add(newCall("cstring", newStrLitNode($field)))
    else:
      for frec in getType(field)[2].children:
        result[0].add(newCall("cstring", newStrLitNode($field & "-" & $frec)))