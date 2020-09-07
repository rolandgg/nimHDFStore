##  * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
##  Copyright by The HDF Group.                                               *
##  Copyright by the Board of Trustees of the University of Illinois.         *
##  All rights reserved.                                                      *
##                                                                            *
##  This file is part of HDF5.  The full HDF5 copyright notice, including     *
##  terms governing use, modification, and redistribution, is contained in    *
##  the COPYING file, which can be found at the root of the source code       *
##  distribution tree, or in https://support.hdfgroup.org/ftp/HDF5/releases.  *
##  If you do not have access to either file, you may request a copy from     *
##  help@hdfgroup.org.                                                        *
##  * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
## 
##  This is the main public HDF5 include file.  Put further information in
##  a particular header file and include that here, don't fill this file with
##  lots of gunk...
##


#[ NOTE: in a few files (H5Tpublic, H5Epublic and H5Ppublic) we need to define 
   several variables (regarding type ids), which can only be set after the HDF5
   library has been 'opened' (= initialized). Thus we include H5initialize 
   in these libraries, which (at the moment) simply calls the H5open() function
   which does exactly that. Then we can use the variables, like e.g.
   H5T_NATIVE_INTEGER 
   in the Nim progams as function arguments without getting any weird errors.
]#

include
  wrapper/H5public, wrapper/H5Apublic,        ##  Attributes
  wrapper/H5ACpublic,                 ##  Metadata cache
  wrapper/H5Dpublic,                  ##  Datasets
  wrapper/H5Epublic,                  ##  Errors
  wrapper/H5Fpublic,                  ##  Files
  wrapper/H5FDpublic,                 ##  File drivers
  wrapper/H5Gpublic,                  ##  Groups
  wrapper/H5Ipublic,                  ##  ID management
  wrapper/H5Lpublic,                  ##  Links
  wrapper/H5MMpublic,                 ##  Memory management
  wrapper/H5Opublic,                  ##  Object headers
  wrapper/H5Ppublic,                  ##  Property lists
  wrapper/H5PLpublic,                 ##  Plugins
  wrapper/H5Rpublic,                  ##  References
  wrapper/H5Spublic,                  ##  Dataspaces
  wrapper/H5Tpublic,                  ##  Datatypes
  wrapper/H5Zpublic


##  Data filters
##  Predefined file drivers

include
  wrapper/H5FDcore,                   ##  Files stored entirely in memory
  wrapper/H5FDdirect,                 ##  Linux direct I/O
  wrapper/H5FDfamily,                 ##  File families
  wrapper/H5FDlog,                    ##  sec2 driver with I/O logging (for debugging)
  wrapper/H5FDmpi,                    ##  MPI-based file drivers
  wrapper/H5FDmulti,                  ##  Usage-partitioned file family
  wrapper/H5FDsec2,                   ##  POSIX unbuffered file I/O
  wrapper/H5FDstdio

include
  hl/H5TBpublic

when defined(H5_HAVE_WINDOWS): ##  Standard C buffered I/O
  import
    H5FDwindows

  ##  Windows buffered I/O
