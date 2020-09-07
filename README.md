# nimHDFStore
pandas-like HDFStore for Nim based on Vindaar's wrapper: https://github.com/Vindaar/nimhdf5

The table schema is defined by a Nim object-type at compile time. The corresponding calls into the HDF5 dll are generated using Nim's macro system.

For usage examples see the test suit.
