import typeinfo
import strutils
import tables
import strformat

import hdf5_wrapper
import H5nimtypes
import util


type
  # these distinct types provide the ability to distinguish the `[]` function
  # acting on H5FileObj between a dataset and a group, s.t. we can access groups
  # as well as datasets from the object using `[]`. Typecast the name (as a string)
  # of the object to either of the two types (you have to know the type of the
  # dset / group you want to access of course!)
  grp_str*  = distinct string
  dset_str* = distinct string

  #special_vlen = hid_t
  #special_str  = hid_t

  # an enum, which is used for the `[]=` functions of H5DataSets. By handing
  # RW_ALL as the argument to said function, we declare to write all data contained
  # in the object on the RHS of the `=`
  DsetReadWrite* = enum
    RW_ALL

  # object which stores information about the attributes of a H5 object
  # each dataset, group etc. has a field .attr, which contains a H5Attributes
  # object
  H5Attributes* = ref object
    # attr_tab is a table containing names and corresponding
    # H5 info
    attr_tab*: ref Table[string, ref H5Attr]
    num_attrs*: int
    parent_name*: string
    parent_id*: hid_t
    parent_type*: string

  # a tuple which stores information about a single attribute
  H5Attr* = tuple[
    opened: bool, # flag which indicates whether attribute is opened
    attr_id: hid_t,
    dtype_c: hid_t,
    dtypeAnyKind: AnyKind,
    # BaseKind contains the type within a (nested) seq iff
    # dtypeAnyKind is akSequence
    dtypeBaseKind: AnyKind,
    attr_dspace_id: hid_t]


  # not used atm
  H5Object = object of RootObj
    name*: string
    parent*: string
    parent_id*: hid_t

  # an object to store information about a hdf5 dataset. It is a combination of
  # an HDF5 dataspace and dataset id (contains both of them)
  H5DataSet* = object #of H5Object
    name*: string
    # we store the shape information internally as a seq, so that we do
    # not have to know about it at compile time
    shape*: seq[int]
    # maxshape stores the maximum size of each dimension the dataset can have,
    # if empty sequence or one dimension set to `int.high`, unlimited size
    maxshape*: seq[int]
    # if chunking is used, stores the size of a chunk, same shape as `shape`, e.g.
    # if shape is @[1000, 1000], chunksize may be @[100, 100]
    chunksize*: seq[int]
    # descriptor of datatype as string of the Nim type
    dtype*: string
    dtypeAnyKind*: AnyKind
    # BaseKind contains the type within a (nested) seq iff
    # dtypeAnyKind is akSequence (i.e. of variable length type)
    dtypeBaseKind*: AnyKind
    # actual HDF5 datatype used as a hid_t, this can be handed to functions needing
    # its datatype
    dtype_c*: hid_t
    # H5 datatype class, useful to check what kind of data we're dealing with (VLEN etc.)
    dtype_class*: H5T_class_t
    # parent string, which contains the name of the group in which the
    # dataset is located
    parent*: string
    # the id of the parent (location id in HDF5 lang). Either file id or group ID
    parent_id*: hid_t
    # filename string, in which the dataset is located
    file*: string
    # reference to the file object, in which dataset resides. Important to perform checks
    # in procs, which should not depend explicitly on H5FileObj, but necessarily depend
    # implicitly on it, e.g. create_dataset (called from group) etc.
    # TODO: is this needed for dataset?
    # file_ref*: ref H5FileObj
    # the id of the dataset
    dataset_id*: hid_t
    # `all` index, to indicate that we wish to set the whole dataset to the
    # value on the RHS (has to be exactly the same shape!)
    all*: DsetReadWrite
    # attr stores information about attributes
    attrs*: H5Attributes
    # property list identifiers, which stores information like "is chunked storage" etc.
    # here we store H5P_DATASET_ACCESS property list
    dapl_id*: hid_t
    # here we store H5P_DATASET_CREATE property list
    dcpl_id*: hid_t

  # an object to store information about a HDF5 group
  H5Group* = object #of H5Object
    name*: string
    # # parent string, which contains the name of the group in which the
    # # dataset is located
    parent*: string
    # # the id of the parent (location id in HDF5 lang). Either file id or group ID
    parent_id*: hid_t
    # filename string, in which the dataset is located
    file*: string
    # file id of the file in which group is stored
    file_id*: hid_t
    # reference to the file object, in which group resides. Important to perform checks
    # in procs, which should not depend explicitly on H5FileObj, but necessarily depend
    # implicitly on it, e.g. create_group, iterator items etc.
    file_ref*: ref H5FileObj
    # the id of the HDF5 group (its location id)
    group_id*: hid_t
    # TODO: think, should H5Group contain a table about its dataspaces? Or should
    # all of this be in H5FileObj? Probably better here for accessing it later via
    # [] I guess
    # However: then H5FileObj needs to still know (!) about its dataspaces and where
    # they are located. Easily done by keeping a table of string of each dataset, which
    # contains their location simply by the path and have a table of H5Group objects
    datasets*: ref Table[string, ref H5DataSet]
    # each group may have subgroups itself, keep table of these
    groups*: ref Table[string, ref H5Group]
    # attr stores information about attributes
    attrs*: H5Attributes
    # property list identifier, which stores information like "is chunked storage" etc.
    # here we store H5P_GROUP_ACCESS property list
    gapl_id*: hid_t
    # here we store H5P_GROUP_CREATE property list
    gcpl_id*: hid_t



  H5FileObj* = object #of H5Object
    name*: string
    # the file_id is the unique identifier of the opened file. Each
    # low level C call uses this file_id to idenfity the file to work
    # on. Should only be used if you need to access functions for which
    # no high level equivalent exists.
    file_id*: hid_t
    # var which stores access type. For internal use. Might be needed
    # for access to low level C calls, which have no high level equiv.
    rw_type*: cuint
    # var to store error codes of called C functions
    err*: herr_t
    # var to store status of C calls
    status*: hid_t
    # groups is a table, which stores the names of groups stored in the file
    groups*: ref Table[string, ref H5Group]
    # datasets is a table, which stores the names of datasets by string
    # while keeping the hid_t dataset_id as the value
    datasets*: ref Table[string, ref H5DataSet]
    dataspaces*: Table[string, hid_t]
    # attr stores information about attributes
    attrs*: H5Attributes
    # flag to be aware if we visited the whole file yet (discovered groups and dsets)
    visited*: bool
    # property list identifier, which stores information like "is chunked storage" etc.
    # here we store H5P_FILE_ACCESS property list
    fapl_id*: hid_t
    # here we store H5P_FILE_CREATE property list
    fcpl_id*: hid_t



  # this exception is used in cases where all conditional cases are already thought
  # to be covered to annotate (hopefully!) unreachable branches
  UnkownError* = object of Exception
  # raised if a call to a HDF5 library function returned with an error
  # (typically result < 0 means error)
  HDF5LibraryError* = object of Exception
  # raised if the user tries to change the size of an immutable dataset, i.e. non-chunked storage
  ImmutableDatasetError* = object of Exception
  # raised if the user tries to change to write to a file opened with read only access
  ReadOnlyError* = object of Exception
  # raised if some part of code that is not yet implemented (but planned) is being called
  NotImplementedError* = object of Exception

  # enum which determines how the given H5 object should be flushed
  # corresponds to the H5F_SCOPE flags
  FlushKind* = enum
    fkLocal, fkGlobal

const
    H5_NOFILE* = hid_t(-1)
    H5_OPENFILE* = hid_t(1)

# add an invalid rw code to handle wrong inputs in parseH5rw_type
const H5F_INVALID_RW*    = cuint(0x00FF)

proc getTypeNoSize(x: AnyKind): AnyKind =
  ## returns the datatype without size information
  case x
  of akNone .. akCString:
    result = x
  of akInt .. akInt64:
    result = akInt
  of akFloat .. akFloat128:
    result = akFloat
  of akUint .. akUint64:
    result = akUint
  else:
    # for other cases (which ones?!) return akNone
    result = akNone

proc typeMatches*(dtype: typedesc, dstr: string): bool =
  ## returns true, if the given ``typedesc`` matches the descriptor in
  ## string
  ## ``dstr`` should always contain the number in bytes of the type!
  ## (if it is of int | float | uint that is)
  ## This is the case for datatypes stored as strings in the datasets within
  ## a H5 file
  ## We construct an `Any` object, get its kind and compare that to the
  ## ``AnyKind`` we parse from the string
  ## This is reasonable, because we create the `dstr` from ``AnyKind`` by stripping
  ## the "ak" prefix in the first place!
  var tmp: dtype
  # create an ``AnyKind`` from given dtype and remove potential size information
  let dAnyKind = toAny(tmp).kind.getTypeNoSize
  # get the string datatypes `AnyKind` without size information
  let dstrAnyKind = parseEnum[AnyKind]("ak" & dstr, akNone).getTypeNoSize
  # and the size in bytes of it
  case dstrAnyKind
  of akInt .. akUint64:
    let expectedSize = dstr.strip(chars = Letters).parseInt div 8
    result = if expectedSize == sizeof(dtype) and
                dAnyKind == dstrAnyKind:
               true
             else:
               false
  else:
    # no size check necessary
    result = if dAnyKind == dstrAnyKind: true else: false


proc h5ToNimType*(dtype_id: hid_t): AnyKind =
  ## proc to return a type descriptor (via typeinfo.AnyKind) describing the given
  ## H5 type. From the return value, we can set the data type in the H5DataSet obj
  ## inputs:
  ##     dtype_id: hid_t = datatype id returned by the H5 library about the datasets' type
  ## outputs:
  ##     AnyKind = typeinfo.AnyKind enum value corresponding to a Nim datatype. We use the
  ##            string representation of it to set the H5DataSet.dtype: string to its
  ##            correct value
  ## throws:
  ##    KeyError: if the given H5 data type is currently not mapped to a Nim type
  ##              (see src/nimhdf5/H5Tpublic.nim for a list of *all* H5 types...)

  # TODO: we may can seperate the dtypes by class using H5Tget_class, which returns a value
  # of the H5T_class_t enum (e.g. H5T_FLOAT)
  withDebug:
    echo "dtype is ", dtype_id
    echo "native is ", H5Tget_native_type(dtype_id, H5T_DIR_ASCEND)
  # TODO: make sure the types are correctly identified!
  # MAKING PROBLEMS ALREADY! int64 is read back as a NATIVE_LONG, which thus needs to be
  # converted to int64

  if H5Tequal(H5T_NATIVE_DOUBLE, dtype_id) == 1:
    result = akFloat64
  elif H5Tequal(H5T_NATIVE_FLOAT, dtype_id) == 1:
    result = akFloat32
  elif H5Tequal(H5T_NATIVE_SHORT, dtype_id) == 1:
    result = akInt32
  elif H5Tequal(H5T_NATIVE_LONG, dtype_id) == 1 or H5Tequal(H5T_NATIVE_INT, dtype_id) == 1 or H5Tequal(H5T_NATIVE_LLONG, dtype_id) == 1:
    result = akInt64
  elif H5Tequal(H5T_NATIVE_UINT, dtype_id) == 1 or H5Tequal(H5T_NATIVE_ULONG, dtype_id) == 1:
    result = akUint32
  elif H5Tequal(H5T_NATIVE_ULLONG, dtype_id) == 1:
    result = akUint64
  elif H5Tequal(H5T_NATIVE_SHORT, dtype_id) == 1:
    result = akInt16
  elif H5Tequal(H5T_NATIVE_USHORT, dtype_id) == 1:
    result = akUint16
  elif H5Tequal(H5T_NATIVE_CHAR, dtype_id) == 1:
    result = akChar
  elif H5Tequal(H5T_NATIVE_UCHAR, dtype_id) == 1:
    result = akUint8
  elif H5Tget_class(dtype_id) == H5T_STRING:
    result = akString
  elif H5Tget_class(dtype_id) == H5T_VLEN:
    # represent vlen types as sequence for any kind
    result = akSequence
  else:
    raise newException(KeyError, "Warning: the following H5 type could not be converted: $# of class $#" % [$dtype_id, $H5Tget_class(dtype_id)])

proc nimToH5type*(dtype: typedesc): hid_t =
  ## given a typedesc, we return a corresponding
  ## H5 data type. This is a template, since we
  ## the compiler won't be able to determine
  ## the generic return type by the given typedesc
  ## inputs:
  ##    dtype: typedesc = a typedescription of the data type for the dataset
  ##          which we want to store
  ## outputs:
  ##    hid_t = the identifier int value of the HDF5 library for the data types

  # TODO: this still seems to be very much wrong and it's only valid for my machine
  # (64 bit) anyways.

  result = hid_t(-1)
  when dtype is int8:
    # for 8 bit int we take the STD LE one, since there is no
    # native type available (besides char)
    # TODO: are we doing this the correct way round? maybe only relevant, if
    # we read data, as the data is STORED in some byte order...!
    when cpuEndian == littleEndian:
      result = H5T_STD_I8LE
    else:
      result = H5T_STD_I8BE
  elif dtype is int16:
    result = H5T_NATIVE_SHORT
  elif dtype is int32:
    result = H5T_NATIVE_INT # H5T_STD_I32LE
  when sizeOf(int) == 8:
    if dtype is int:
      result = H5T_NATIVE_LONG
  else:
    if dtype is int:
      result = H5T_NATIVE_INT
  if dtype is int64:
    result = H5T_NATIVE_LONG
  elif dtype is uint8:
    # for 8 bit int we take the STD LE one, since there is no
    # native type available (besides char)
    when cpuEndian == littleEndian:
      result = H5T_STD_U8LE
    else:
      result = H5T_STD_U8BE
  elif dtype is uint16:
    result = H5T_NATIVE_USHORT
  elif dtype is uint32:
    result = H5T_NATIVE_UINT # H5T_STD_I32LE
  elif dtype is uint or dtype is uint64:
    result = H5T_NATIVE_ULLONG # H5T_STD_I64LE
  elif dtype is float32:
    result = H5T_NATIVE_FLOAT # H5T_STD_
  elif dtype is float or dtype is float64:
    result = H5T_NATIVE_DOUBLE # H5T_STD_
  elif dtype is char:
    # Nim's char is an unsigned char!
    result = H5T_NATIVE_UCHAR
  elif dtype is string:
    # NOTE: in case a string is desired, we still have to prepare it later, because
    # a normal string will end up as a sequence of characters otherwise. Instead
    # to get a continous string, need to set the size of the individual string
    # datatype (the result of this), to the size of the string and instead set
    # the size of the dataspace we reserve back to 1!
    # Also we need to copy the datatype, in order to be able to change its size
    # later
    result = H5Tcopy(H5T_C_S1)
    # -> call string_dataspace(str: string, dtype: hid_t) with
    # `result` as the second argument and the string you wish to
    # write as 1st after the call to this fn

template anyTypeToString*(dtype: AnyKind): string =
  ## return a datatype string from an AnyKind object
  strip($dtype, chars = {'a', 'k'}).toLowerAscii

proc getDtypeString*(dset_id: hid_t): string =
  ## using a dataset id `dset_id`, return the name of the datatype by a call
  ## to the H5 library to get the datatype of that dataset
  let t = H5Dget_type(dset_id)
  result = anyTypeToString(h5ToNimType(t))

template special_type*(dtype: typedesc): untyped =
  ## calls the H5Tvlen_create() to create a special datatype
  ## for variable length data
  when dtype isnot string:
    H5Tvlen_create(nimToH5type(dtype))
  else:
    echo "Currently not implemented to create variable string datatype"


proc parseH5rw_type*(rw_type: string, exists: bool): cuint =
  ## this proc simply acts as a parser for the read/write
  ## type string handed to the H5file() proc.
  ## inputs:
  ##    rw_type: string = the identifier string, which sets the
  ##            read / write options for a HDF5 file
  ##    exits: bool = a bool to tell whether the file for which
  ##          we need to parse r/w already exists. Changes
  ##          potential return values
  ## outputs:
  ##    cuint = returns a C uint, since that is the datatype of
  ##            the constans defined in H5Fpublic.nim. These can be
  ##            handed directly to the low level C functions
  ## throws:
  ##
  if rw_type == "w" or
     rw_type == "rw" or
     rw_type == "write":
    if exists == true:
      result = H5F_ACC_RDWR
    else:
      result = H5F_ACC_EXCL
  elif rw_type == "r" or
       rw_type == "read":
    result = H5F_ACC_RDONLY
  else:
    result = H5F_INVALID_RW

template getH5rw_invalid_error*(): string =
  """
  The given r/w type is invalid. Make sure to use one of the following:
  - {'r', 'read'} = read access
  - {'w', 'write', 'rw'} =  read/write access
  """

proc getH5read_non_exist_file*(filename: string): string =
  result = &"Cannot open a non-existing file {filename} with read only access. Write " &
    "access will create the file for you."

template toH5vlen*[T](data: var seq[T]): untyped =
  when T is seq:
    mapIt(toSeq(0..data.high)) do:
      if data[it].len > 0:
        hvl_t(`len`: csize(data[it].len), p: addr(data[it][0]))
      else:
        hvl_t(`len`: csize(0), p: nil)
  else:
    # this doesn't make sense ?!...
    static:
      warning("T is " & T.name)
      warning("Cannot be converted to VLEN data!")
    #mapIt(toSeq(0 .. data.high), hvl_t(`len`: csize(data[it]), p: addr(data[it][0])))

proc vlenToSeq*[T](data: seq[hvl_t]): seq[seq[T]] =
  # converting the raw data from the C library to a Nim sequence is sort of ugly, but
  # here it goes...
  # number of elements we read
  result = newSeq[seq[T]](data.len)
  # iterate over every element of the pointer we have with data
  for i in 0 ..< data.len:
    let elem_len = data[i].len
    # create corresponding sequence for the size of this element
    result[i] = newSeq[T](elem_len)
    # now we need to cast the data, which is a pointer, to a ptr of an unchecked
    # array of our datatype
    let data_seq = cast[ptr UncheckedArray[T]](data[i].p)
    # now assign each element of the unckecked array to our sequence
    for j in 0 ..< elem_len:
      result[i][j] = data_seq[j]
