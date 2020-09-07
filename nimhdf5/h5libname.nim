# file which defines the shared library names for the different OS
when not declared(libname):
  when defined(Windows):
    const
      libname* = "C:/Program Files/HDF_Group/HDF5/1.10.5/bin/hdf5.dll"
  elif defined(MacOSX):
    const
      libname* = "libhdf5.dylib"
  else:
    const
      libname* = "(libhdf5|libhdf5_serial).so"
