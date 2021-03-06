#[
This file contains the procedures related to attributes.

The attribute types are defined in the datatypes.nim file.
]#

import typeinfo
import typetraits
import tables
import strutils, sequtils

import hdf5_wrapper
import H5nimtypes
import datatypes
import dataspaces
import h5util
import util

# forward declare procs, which we need to read the attributes from file
proc read_all_attributes*(h5attr: H5Attributes)
proc getNumAttrs(h5attr: H5Attributes): int

proc `$`*(h5attr: ref H5Attr): string =
  ## proc to define echo of ref H5Attr by echoing its contained object
  result = $(h5attr[])

proc newH5Attributes*(): H5Attributes =
  let attr = newTable[string, ref H5Attr]()
  result = H5Attributes(attr_tab: attr,
                        num_attrs: -1,
                        parent_name: "",
                        parent_id: -1.hid_t,
                        parent_type: "")

proc initH5Attributes*(p_id: hid_t, p_name: string = "", p_type: string = ""): H5Attributes =
  let attr = newTable[string, ref H5Attr]()
  doAssert p_id > 0, "parent id must exist!"
  var h5attr = H5Attributes(attr_tab: attr,
                            num_attrs: -1,
                            parent_name: p_name,
                            parent_id: p_id,
                            parent_type: p_type)
  h5attr.num_attrs = h5attr.getNumAttrs
  # read_all_attributes(h5attr)
  result = h5attr

proc openAttrByIdx(h5attr: H5Attributes, idx: int): hid_t =
  ## proc to open an attribute by its id in the H5 file and returns
  ## attribute id if succesful
  ## need to hand H5Aopen_by_idx the location relative to the location_id,
  ## if I understand correctly
  let loc = "."
  # we read by creation order, increasing from 0
  result = H5Aopen_by_idx(h5attr.parent_id,
                          loc,
                          H5_INDEX_CRT_ORDER,
                          H5_ITER_INC,
                          hsize_t(idx),
                          H5P_DEFAULT,
                          H5P_DEFAULT)

proc openAttribute(h5attr: H5Attributes, key: string): hid_t =
  ## proc to open an attribute by its name.
  ## NOTE: This assumes the caller already checked the attribute exists!
  # we read by creation order, increasing from 0
  result = H5Aopen(h5attr.parent_id, key.cstring, H5P_DEFAULT)

proc close*(attr: ref H5Attr): herr_t =
  ## closes the attribute and the corresponding dataspace
  if attr.opened:
    result = H5Aclose(attr.attr_id)
    withDebug:
      echo "Closed attribute with status ", result
    result = H5Sclose(attr.attr_dspace_id)
    attr.opened = false

proc getAttrName*(attr_id: hid_t, buf_space = 20): string =
  ## proc to get the attribute name of the attribute with the given id
  ## reserves space for the name to be written to
  withDebug:
    debugEcho "Call to getAttrName! with size $#" % $buf_space
  var name = newString(buf_space)
  # read the name
  let length = attr_id.H5Aget_name(len(name), name)
  # H5Aget_name returns the length of the name. In case the name
  # is longer than the given buffer, we call this function again with
  # a buffer with the correct length
  if length <= name.len:
    result = name.strip
    # now set the length of the resulting string to the size
    # it actually occupies
    result.setLen(length)
  else:
    result = getAttrName(attr_id, length)

proc getNumAttrs(h5attr: H5Attributes): int =
  ## proc to get the number of attributes of the parent
  ## uses H5Oget_info, which returns a struct containing the
  ## metadata of the object (incl type etc.). Might be useful
  ## at other places too?
  ## reserve space for the info object
  var h5info: H5O_info_t
  let err = H5Oget_info(h5attr.parent_id, addr(h5info))
  if err >= 0:
    # successful
    withDebug:
      debugEcho "getNumAttrs(): ", h5attr
    result = int(h5info.num_attrs)
  else:
    withDebug:
      debugEcho "getNumAttrs(): ", h5attr
    raise newException(HDF5LibraryError, "Call to HDF5 library failed in `getNumAttr` when reading $#" % $h5attr.parent_name)

proc setAttrAnyKind(attr: var H5Attr) =
  ## proc which sets the AnyKind fields of a H5Attr
  let npoints = H5Sget_simple_extent_npoints(attr.attr_dspace_id)
  if npoints > 1:
    attr.dtypeAnyKind = akSequence
    # set the base type based on what's contained in the sequence
    attr.dtypeBaseKind = h5ToNimType(attr.dtype_c)
  else:
    attr.dtypeAnyKind = h5ToNimType(attr.dtype_c)

proc attr_dspace_id(attr: H5Attr): hid_t =
  ## returns a valid dataspace for the given attribute
  result = H5Aget_space(attr.attr_id)

proc readAttributeInfo(h5attr: H5Attributes,
                       attr: ref H5Attr,
                       name: string) =
  withDebug:
    debugEcho "Found? ", attr.attr_id, " with name ", name
  # get dtypes and dataspace id
  attr.dtype_c = H5Aget_type(attr.attr_id)

  # TODO: remove debug
  withDebug:
    debugEcho "attr ", name, " is vlen string ", H5Tis_variable_str(attr.dtype_c)
  #attr.dtype_c = H5Tget_native_type(attr.dtype_c, H5T_DIR_ASCEND)
  #echo "Encoding is native ", H5Tget_cset(attr.dtype_c)
  attr.attr_dspace_id = H5Aget_space(attr.attr_id)
  # now set the attribute any kind fields (checks whether attr is a sequence)
  attr[].setAttrAnyKind
  # add to this attribute object
  h5attr.attr_tab[name] = attr

proc readAttributeInfo(h5attr: H5Attributes, key: string) =
  ## reads all information about the attribute `key` from the H5 file
  ## NOTE: this does ``not`` read the value of that attribute!
  var attr = new H5Attr
  attr.attr_id = openAttribute(h5attr, key)
  attr.opened = true
  readAttributeInfo(h5attr, attr, key)

proc read_all_attributes*(h5attr: H5Attributes) {.deprecated: "Read all " &
  "attributes is deprecated, because it is unsafe and not very useful.".} =
  ## proc to read all attributes of the parent from file and store the names
  ## and attribute ids in `h5attr`
  ## NOTE: when using this proc, make sure to close all attributes again!
  # first get how many objects there are
  h5attr.num_attrs = h5attr.getNumAttrs
  for i in 0..<h5attr.num_attrs:
    var attr = new H5Attr
    attr.attr_id = openAttrByIdx(h5attr, i)
    attr.opened = true
    let name = getAttrName(attr.attr_id)
    readAttributeInfo(h5attr, attr, name)

proc existsAttribute*(h5id: hid_t, name: string): bool =
  ## simply check if the given attribute name corresponds to an attribute
  ## of the given object
  ## throws:
  ##   HDF5LibraryError = in case a call to the H5 library fails
  let exists = H5Aexists(h5id, name)
  if exists > 0:
    result = true
  elif exists == 0:
    result = false
  else:
    raise newException(HDF5LibraryError, "HDF5 library called returned bad value in `existsAttribute` function")

template existsAttribute*[T: (H5FileObj | H5Group | H5DataSet)](h5o: T, name: string): bool =
  ## proc to check whether a given
  ## simply check if the given attribute name corresponds to an attribute
  ## of the given object
  existsAttribute(h5o.getH5Id, name)

proc deleteAttribute*(h5id: hid_t, name: string): bool =
  ## deletes the given attribute `name` on the object defined by
  ## the H5 id `h5id`
  ## throws:
  ##   HDF5LibraryError = may be raised by the call to `existsAttribute`
  ##     if a call to the H5 library fails
  withDebug:
    debugEcho "Deleting attribute $# on id $#" % [name, $h5id]
  if existsAttribute(h5id, name) == true:
    let success = H5Adelete(h5id, name)
    result = if success >= 0: true else: false
  else:
    result = true

proc deleteAttribute*[T: (H5FileObj | H5Group | H5DataSet)](h5o: var T, name: string): bool =
  result = deleteAttribute(getH5Id(h5o), name)
  # if successful also lower the number of attributes
  h5o.attrs.num_attrs = h5o.attrs.getNumAttrs

proc write_attribute*[T](h5attr: H5Attributes, name: string, val: T, skip_check = false) =
  ## writes the attribute `name` of value `val` to the object `h5o`
  ## NOTE: by defalt this function overwrites an attribute, if an attribute
  ## of the same name already exists!
  ## need to
  ## - create simple dataspace
  ## - create attribute
  ## - write attribute
  ## - add attribute to h5attr
  ## - later close attribute when closing parent of h5attr

  var attr_exists = false
  # the first check is done, since we may be calling this function KNOWING that
  # the attribute does not exist. This should normally not be done by a user,
  # but only in case we have previously succesfully deleted the attribute
  if skip_check == false:
    attr_exists = name in h5attr
    withDebug:
      debugEcho "Attribute $# exists $#" % [name, $attr_exists]
  if not attr_exists:
    # create a H5Attr, which we add to the table attr_tab of the given
    # h5attr object once we wrote it to file
    var attr = new H5Attr

    when T is SomeNumber or T is char:
      let
        dtype = nimToH5type(T)
        # create dataspace for single element attribute
        attr_dspace_id = simple_dataspace(1)
        # create the attribute
        attribute_id = H5Acreate2(h5attr.parent_id, name, dtype,
                                  attr_dspace_id, H5P_DEFAULT, H5P_DEFAULT)
        # mutable copy for address
      var mval = val
      # write the value
      let err = H5Awrite(attribute_id, dtype, addr(mval))
      if err < 0:
        raise newException(HDF5LibraryError, "Call to HDF5 library failed while " &
          "calling `H5Awrite` in `write_attribute` to write " & $name)
      # write information to H5Attr tuple
      attr.attr_id = attribute_id
      attr.opened = true
      attr.dtype_c = dtype
      attr.attr_dspace_id = attr_dspace_id
      # set any kind fields (check whether is sequence)
      attr[].setAttrAnyKind

    elif T is seq or T is string:
      # NOTE:
      # in principle we need to differentiate between simple sequences and nested
      # sequences. However, for now only support normal seqs.
      # extension to nested seqs should be easy (using shape, handed simple_dataspace),
      # however we still need to have a good function to get the basetype of a nested
      # sequence for that
      when T is seq:
        # take first element of sequence to get the datatype
        let dtype = nimToH5type(type(val[0]))
        # create dataspace for attribute
        # 1D so call simple_dataspace with integer, instead of seq
        let attr_dspace_id = simple_dataspace(len(val))
      else:
        let
          # get copy of string type
          dtype = nimToH5type(type(val))
          # and reserve dataspace for string
          attr_dspace_id = string_dataspace(val, dtype)
      # create the attribute
      let attribute_id = H5Acreate2(h5attr.parent_id, name, dtype, attr_dspace_id, H5P_DEFAULT, H5P_DEFAULT)
      # mutable copy for address
      var mval = val
      # write the value
      if mval.len > 0:
        # only write the value, if we have something to write
        discard H5Awrite(attribute_id, dtype, addr(mval[0]))

      # write information to H5Attr tuple
      attr.attr_id = attribute_id
      attr.opened = true
      attr.dtype_c = dtype
      attr.attr_dspace_id = attr_dspace_id
      # set any kind fields (check whether is sequence)
      attr[].setAttrAnyKind
    elif T is bool:
      # NOTE: in order to support booleans, we need to use HDF5 enums, since HDF5 does not support
      # a native boolean type. H5 enums not supported yet though...
      echo "Type `bool` currently not supported as attribute"
      discard
    else:
      echo "Type `$#` currently not supported as attribute" % $T
      discard

    # add H5Attr tuple to H5Attributes table
    h5attr.attr_tab[name] = attr

    if h5attr.attr_tab[name].close() < 0:
      raise newException(HDF5LibraryError, "Error closing attribute " & $name &
                         " after writing")
  else:
    # if it does exist, we delete the attribute and call this function again, with
    # exists = true, i.e. without checking again whether element exists. Saves us
    # a call to the hdf5 library
    let success = deleteAttribute(h5attr.parent_id, name)
    if success == true:
      write_attribute(h5attr, name, val, true)
    else:
      raise newException(HDF5LibraryError, "Call to HDF5 library failed on call in `deleteAttribute`")

  # independent of previous attribute, refresh the number of attributes
  h5attr.num_attrs = h5attr.getNumAttrs

template `[]=`*[T](h5attr: H5Attributes, name: string, val: T) =
  ## convenience access to write_attribue
  h5attr.write_attribute(name, val)

proc parseString(buffer: ptr UncheckedArray[char]): string =
  ## parses the given unchecked array until a null delimiter is reached
  ## and returns the string
  var i = 0
  while buffer[i] != '\0':
    result.add buffer[i]
    inc i

proc readStringAttribute(attr: ref H5Attr): string =
  ## proc to read a string attribute from a H5 file, for an existing
  ## `H5Attr`. This proc is only used in the `read_attribute` proc
  ## for users after checking of attribute is done.
  # TODO: complete documentation
  attr.attr_dspace_id = H5Aget_space(attr.attr_id)
  let isVlen = H5Tis_variable_str(attr.dtype_c)
  let nativeType = H5Tget_native_type(attr.dtype_c, H5T_DIR_ASCEND)
  withDebug:
    # TODO: remove debug
    debugEcho "isVlen ", isVlen
    debugEcho "Native type is ", nativeType
    debugEcho "Encoding is ", H5Tget_cset(attr.dtype_c)
  if isVlen == 1:
    # create a void pointer equivalent
    var bufPtrPtr = alloc(8 * sizeof(char))
    let err2 = H5Aread(attr.attr_id, nativeType, bufPtrPtr)
    # cast the void pointer to a ptr on a ptr of an unchecked array
    # and dereference it to get a ptr to an unchecked char array
    let bufData = cast[ptr ptr UncheckedArray[char]](bufPtrPtr)[]
    # parse the unchecked char array
    result = parseString(bufData)

    # TODO: remove debug
    withDebug:
      debugEcho "Freeing pointer ", bufPtrPtr.repr
    dealloc bufPtrPtr
  else:
    # in case of string, need to determine size. use:
    # in case of existence, read the data and return
    let string_len = H5Aget_storage_size(attr.attr_id)
    var buf_string = newString(string_len)
    let err = H5Aread(attr.attr_id, nativeType, addr buf_string[0])
    result = buf_string

proc read_attribute*[T](h5attr: H5Attributes, name: string, dtype: typedesc[T]): T =
  ## now implement reading of attributes
  ## finally still need a read_all attribute. This function only reads a single one, if
  ## it exists.
  ## check existence, since we read all attributes upon creation of H5Attributes object
  ## (attr as small, so the performance overhead should be minimal), we can just access
  ## the attribute table to check for existence
  ## inputs:
  ##   h5attr: H5Attributes = H5Attributes from which to read specific attribute
  ##   name: string = name of the attribute to be read
  ##   dtype: typedesc[T] = datatype of the attribute to be read. Needed to define return
  ##     value.
  ## throws:
  ##   KeyError: In case the key does not exist as an attribute

  # TODO: check err values!

  let attr_exists = name in h5attr
  var err: herr_t

  if attr_exists:
    # in case of existence, read the data and return
    h5attr.readAttributeInfo(name)
    let attr = h5attr.attr_tab[name]
    when T is SomeNumber or T is char:
      var at_val: T
      err = H5Aread(attr.attr_id, attr.dtype_c, addr(at_val))
      result = at_val
    elif T is seq:
      # determine number of elements in seq
      let npoints = H5Sget_simple_extent_npoints(attr.attr_dspace_id)
      # return correct type based on base kind
      var buf_seq: T = @[]
      buf_seq.setLen(npoints)

      # given number of elements in seq attribute, check what user desired
      # basetype is
      type TT = type(buf_seq[0])

      # in case it's a string, do things differently..
      when TT is string:
        # get string attribute as single string first
        let s = readStringAttribute attr
        # now split the attribute into a seq of correct length each
        let strLength = s.len div npoints
        for i in 0 ..< npoints:
          # iterate over each substring and append a string w/o additional
          # null-terminators (if substring shorter max length)
          let
            start = i * strLength
            stop = (i + 1) * strLength
          result.add s[start ..< stop].strip(chars = {'\0'})
      else:
        # read data
        err = H5Aread(attr.attr_id, attr.dtype_c, addr buf_seq[0])
        result = buf_seq
    elif T is string:
      # case of single string attribute
      result = readStringAttribute attr
    # close attribute again after reading
    if h5attr.attr_tab[name].close() < 0:
      raise newException(HDF5LibraryError, "Error closing attribute " & $name &
                         " after reading")
  else:
    raise newException(KeyError, "No attribute `$#` exists in object `$#`" % [name, h5attr.parent_name])

template `[]`*[T](h5attr: H5Attributes, name: string, dtype: typedesc[T]): T =
  # convenience access to read_attribute
  h5attr.read_attribute(name, dtype)

template `[]`*(h5attr: H5Attributes, name: string): AnyKind =
  # accessing H5Attributes by string simply returns the datatype of the stored
  # attribute as an AnyKind value
  h5attr.attr_tab[name].dtypeAnyKind

proc contains*(attr: H5Attributes, key: string): bool =
  ## proc to check whether a given attribute with name `key` exists in the attribute
  ## field of a group or dataset
  result = attr.parent_id.existsAttribute(key)

template withAttr*(h5attr: H5Attributes, name: string, actions: untyped) =
  ## convenience template to read and work with an attribute from the file and perform actions
  ## with that attribute, without having to manually check the data type of the attribute

  # TODO: NOTE this is a very ugly solution, when we could just use H5Ocopy in the calling
  # proc....
  case h5attr.attr_tab[name].dtypeAnyKind
  of akBool:
    let attr {.inject.} = h5attr[name, bool]
    actions
  of akChar:
    let attr {.inject.} = h5attr[name, char]
    actions
  of akString:
    let attr {.inject.} = h5attr[name, string]
    actions
  of akFloat32:
    let attr {.inject.} = h5attr[name, float32]
    actions
  of akFloat64:
    let attr {.inject.} = h5attr[name, float64]
    actions
  of akInt8:
    let attr {.inject.} = h5attr[name, int8]
    actions
  of akInt16:
    let attr {.inject.} = h5attr[name, int16]
    actions
  of akInt32:
    let attr {.inject.} = h5attr[name, int32]
    actions
  of akInt64:
    let attr {.inject.} = h5attr[name, int64]
    actions
  of akUint8:
    let attr {.inject.} = h5attr[name, uint8]
    actions
  of akUint16:
    let attr {.inject.} = h5attr[name, uint16]
    actions
  of akUint32:
    let attr {.inject.} = h5attr[name, uint32]
    actions
  of akUint64:
    let attr {.inject.} = h5attr[name, uint64]
    actions
  of akSequence:
    # need to perform same game again...
    case h5attr.attr_tab[name].dtypeBaseKind
    of akString:
      let attr {.inject.} = h5attr[name, seq[string]]
      actions
    of akFloat32:
      let attr {.inject.} = h5attr[name, seq[float32]]
      actions
    of akFloat64:
      let attr {.inject.} = h5attr[name, seq[float64]]
      actions
    of akInt8:
      let attr {.inject.} = h5attr[name, seq[int8]]
      actions
    of akInt16:
      let attr {.inject.} = h5attr[name, seq[int16]]
      actions
    of akInt32:
      let attr {.inject.} = h5attr[name, seq[int32]]
      actions
    of akInt64:
      let attr {.inject.} = h5attr[name, seq[int64]]
      actions
    of akUint8:
      let attr {.inject.} = h5attr[name, seq[uint8]]
      actions
    of akUint16:
      let attr {.inject.} = h5attr[name, seq[uint16]]
      actions
    of akUint32:
      let attr {.inject.} = h5attr[name, seq[uint32]]
      actions
    of akUint64:
      let attr {.inject.} = h5attr[name, seq[uint64]]
      actions
    else:
      echo "Seq type of ", h5attr.attr_tab[name].dtypeBaseKind, " not supported"
  else:
    echo "Attribute of dtype ", h5attr.attr_tab[name].dtypeAnyKind, " not supported"
    discard

proc copy_attributes*[T: H5Group | H5DataSet](h5o: var T, attrs: H5Attributes) =
  ## copies the attributes contained in `attrs` given to the function to the `h5o` attributes
  ## this can be used to copy attributes also between different files
  # simply walk over all key value pairs in the given attributes and
  # write them as new attributes to `h5o`
  for key, value in pairs(attrs.attr_tab):
    # TODO: fix it using H5Ocopy instead!
    # IMPORTANT!!!!
    # let ocpypl_id = H5Pcreate(H5P_OBJECT_COPY)
    # let lcpl_id = H5Pcreate(H5P_LINK_CREATE)
    # H5Ocopy(value.attr_id, key, h5o.attrs.parent_id, key, ocpypl_id, lcpl_id)
    attrs.withAttr(key):
      # use injected read attribute value to write it
      h5o.attrs[key] = attr
