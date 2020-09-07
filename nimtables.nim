#include hdfwrapper
include nimhdf5/hdf5_wrapper
#import nimhdf5
import nimhdf5/H5nimtypes
import typeinspect
import times
import macros
import os
import tables

{.experimental.}
type
    HDFStore = object
        fileId: hid_t
        chunkSize: hsize_t
        compression: cint
        filename: string
        dsets: seq[string]
    HDFStoreRef* = ref HDFStore
    HDFTable*[T] = ref object
        fileHandle: HDFStoreRef
        table: cstring
        n_fields: hsize_t
        nrecords: hsize_t
        field_names: seq[string]
        field_sizes: seq[csize]
        field_offsets: seq[csize]
        type_size: csize
    HDFMode* = enum
        hdRead, hdOverwrite, hdReadWrite, hdInfer

proc `=destroy`(x: var HDFStore) =
    var code = H5Fclose(x.fileId)
    assert(code == 0)

proc close*(self: HDFStoreRef) =
    var code = H5Fclose(self.fileId)
    assert(code == 0, "Closing HDF file failed.")

proc op_func(loc_id: hid_t, name: cstring, info: ptr H5O_info_t, operator_data: pointer): herr_t =
    var store = cast[var HDFStoreRef](operator_data)
    if name == ".":
        # in case the location is `.`, we are simply at our starting point (currently
        # means root group), we don't want to do anything here, so continue
        result = 0
    else:
        if info.`type` == H5O_TYPE_DATASET:
            # misuse `[]` proc for now.
            # TODO: write proc which opens and reads dataset from file by id...
            # see, I'm going to where the HDF5 library is in the first place...
            store.dsets.add($name)
        result = 0

proc items*(self:var HDFStoreRef) =
    var code = H5Ovisit(self.fileId, H5_INDEX_NAME, H5_ITER_NATIVE,
                    cast[H5O_iterate_t](op_func),
                    cast[pointer](addr(self)))
    assert(code == 0, "Reading dataset keys failed.")

proc openHDFStore*(filename: string, mode: HDFMode = hdInfer, chunkSize: int = 5000, compression: bool = false): HDFStoreRef =
    new(result)
    result.filename = filename
    case mode
    of hdOverwrite:
        result.fileId = H5Fcreate(cstring(filename), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT)
        result.chunkSize = hsize_t(chunkSize)
        result.compression = cint(compression)
        result.dsets = @[]
    of hdRead:
        result.fileId = H5Fopen(cstring(filename), H5F_ACC_RDONLY, H5P_DEFAULT)
        result.chunkSize = hsize_t(chunkSize)
        result.compression = cint(compression)
        result.items()
    of hdReadWrite:
        result.fileId = H5Fopen(cstring(filename),  H5F_ACC_RDWR, H5P_DEFAULT)
        result.chunkSize = hsize_t(chunkSize)
        result.compression = cint(compression)
        result.items()
    of hdInfer:
        if fileExists(filename):
            result.fileId = H5Fopen(cstring(filename),  H5F_ACC_RDWR, H5P_DEFAULT)
            result.chunkSize = hsize_t(chunkSize)
            result.compression = cint(compression)
            result.items()
        else:
            result.fileId = H5Fcreate(cstring(filename), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT)
            result.chunkSize = hsize_t(chunkSize)
            result.compression = cint(compression)
            result.dsets = @[]

proc keys*(self: HDFStoreRef): seq[string]=
    result = self.dsets

proc `[]=`*[T](self: HDFStoreRef, table: string, content: var seq[T]) = 
    var field_names = fieldnames(T)
    var field_type = hdftypes(T)
    var dst_size: csize = sizeof(T)
    var dst_offset = offsets(T)
    var fill_data: ptr cint = nil
    var code = H5TBmake_table( cstring(table), self.file_id, cstring(table),numFields(T),hsize_t(content.len),
                    dst_size, field_names[0].addr, dst_offset[0].addr, field_type[0].addr,
                    self.chunk_size, fill_data, self.compression, content[0].addr);
    self.dsets.add(table)
    assert(code == 0, "Creating HDF table failed.")

proc delete*(self: HDFStoreRef, table: string) =
    if table in self.dsets:
        let code = H5Ldelete(self.fileId, cstring(table), H5P_DEFAULT)
        assert( code == 0, "Table deletion failed")
    
proc `[]`*[T](self: HDFStoreRef, table: string, t: typedesc[T]): HDFTable[T] =
    new(result)
    var n_fields: hsize_t
    var nrecords: hsize_t
    var code = H5TBget_table_info(self.fileid, cstring(table), n_fields.addr, nrecords.addr)
    var field_names: cstringArray = allocCStringArray(newSeq[string](n_fields))
    var field_sizes = newSeq[csize](n_fields)
    var field_offsets = newSeq[csize](n_fields)
    var type_size: csize = 0
    var code2 = H5TBget_field_info(self.fileId, cstring(table), field_names,
                        field_sizes[0].addr, field_offsets[0].addr, type_size.addr)
    if code == 0 and code2 == 0:
        result.fileHandle = self
        result.table = cstring(table)
        result.n_fields = n_fields
        result.field_names = cstringArraytoSeq(field_names, n_fields)
        deallocCStringArray(field_names)
        result.nrecords = nrecords
        result.field_sizes = field_sizes
        result.field_offsets = field_offsets
        result.type_size = type_size

proc checkCompatiblity[T](table: HDFTable[T])=
    assert(table.n_fields == numFields(T))
    assert(table.type_size == sizeof(T))
    let dst_offsets = offsets(T)
    for i,offset in pairs(dst_offsets):
        assert(offset == table.field_offsets[i])
 
proc toSeq*[T](src: HDFTable[T]): seq[T] =
    src.checkCompatiblity()
    result = newSeq[T](src.nrecords)
    var dst_size: csize = sizeof(T)
    var dst_offset = offsets(T)
    var code = H5TBread_table(src.fileHandle.fileId, src.table, dst_size, dst_offset[0].addr,
     src.field_sizes[0].addr, result[0].addr)
    assert(code == 0)

proc `[]`*[T; I:Ordinal](s: HDFTable[T], i: I): T =
    var n = hsize_t(i)
    var code = H5TBread_records(s.fileHandle.fileId, s.table, n, hsize_t(1), s.type_size, s.field_offsets[0].addr,
        s.field_sizes[0].addr, result.addr)

proc `[]`*[T](s: HDFTable[T], i: BackwardsIndex): T =
    var n:hsize_t = s.nrecords - hsize_t(i)
    var code = H5TBread_records(s.fileHandle.fileId, s.table, n, hsize_t(1), s.type_size, s.field_offsets[0].addr,
        s.field_sizes[0].addr, result.addr)

proc `[]`*[T, U, V](s: HDFTable[T], idx: HSlice[U,V]): seq[T] =
    var n,m: hsize_t
    when U is BackwardsIndex:
        n = s.nrecords-hsize_t(idx.a)
    else:
        n = hsize_t(idx.a)
    when V is BackwardsIndex:
        m = s.nrecords-hsize_t(idx.b)
    else:
        m = hsize_t(idx.b)
    newSeq(result, m-n+1)
    discard H5TBread_records(s.fileHandle.fileId, s.table, hsize_t(n), hsize_t(m-n+1), s.type_size, s.field_offsets[0].addr,
        s.field_sizes[0].addr, result[0].addr)

proc append*[T](s: HDFTable[T], data: var seq[T]) =
    s.nrecords += hsize_t(data.len)
    discard H5TBappend_records(s.fileHandle.fileId, s.table, hsize_t(data.len), s.type_size, s.field_offsets[0].addr, s.field_sizes[0].addr, data[0].addr)

proc `[]=`*[T; I:Ordinal](s: HDFTable[T], i: I, data: var T) =
    let n = hsize_t(i)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    discard H5TBwrite_records(s.fileHandle.fileId, s.table, n, hsize_t(1), s.type_size, s.field_offsets[0].addr, s.field_sizes[0].addr, data.addr)

proc `[]=`*[T](s: HDFTable[T], i: BackwardsIndex, data: var T) =
    let n = s.nrecords - hsize_t(i)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    discard H5TBwrite_records(s.fileHandle.fileId, s.table, n, hsize_t(1), s.type_size, s.field_offsets[0].addr, s.field_sizes[0].addr, data.addr)

proc `[]=`*[T, U, V](s: HDFTable[T], idx: HSlice[U,V], data: var seq[T]) =
    var n,m: hsize_t
    when U is BackwardsIndex:
        n = s.nrecords-hsize_t(idx.a)
    else:
        n = hsize_t(idx.a)
    when V is BackwardsIndex:
        m = s.nrecords-hsize_t(idx.b)
    else:
        m = hsize_t(idx.b)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    assert((m > hsize_t(0) and m < s.nrecords), "Index out of bounds!")
    assert((m > n), "Range error!")
    discard H5TBwrite_records(s.fileHandle.fileId, s.table, n, hsize_t(m-n+1), s.type_size, s.field_offsets[0].addr, s.field_sizes[0].addr, data[0].addr)

proc delete*[T](s: HDFTable[T], i: int) =
    let n = hsize_t(i)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    discard H5TBdelete_record(s.fileHandle.fileId, s.table, n, hsize_t(1))
    s.nrecords -= 1

proc delete*[T](s: HDFTable[T], i: BackwardsIndex) =
    let n = s.nrecords - hsize_t(i)
    s.delete(int(n))

proc delete*[T, U, V](s: HDFTable[T], idx: HSlice[U,V]) =
    var n,m: hsize_t
    when U is BackwardsIndex:
        n = s.nrecords-hsize_t(idx.a)
    else:
        n = hsize_t(idx.a)
    when V is BackwardsIndex:
        m = s.nrecords-hsize_t(idx.b)
    else:
        m = hsize_t(idx.b)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    assert((m > hsize_t(0) and m < s.nrecords), "Index out of bounds!")
    assert((m > n), "Range error!")
    let l = m-n+1
    discard H5TBdelete_record(s.fileHandle.fileId, s.table, n, l)
    s.nrecords -= l

proc insert*[T; I:Ordinal](s: HDFTable[T], i: I, data: var seq[T]) =
    let n = hsize_t(i)
    assert((n > hsize_t(0) and n < s.nrecords), "Index out of bounds!")
    discard H5TBinsert_record(s.fileHandle.fileId, s.table, n, hsize_t(data.len), s.type_size, s.field_offsets[0].addr, s.field_sizes[0].addr,
        data[0].addr)    

proc nrows*[T](s: HDFTable[T]): int =
    result = int(s.nrecords)