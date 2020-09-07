import unittest
import nimtables

type
    Particle = object
        lati: int
        longi: int
        pressure: float
        temperature: float

const data: seq[Particle] = @[
    Particle(lati: 1, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 2, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 3, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 4, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 5, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 6, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 7, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 8, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 9, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 10, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 11, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 12, longi: 1, pressure: 100.0, temperature: 20.0),
    Particle(lati: 13, longi: 1, pressure: 100.0, temperature: 20.0),
]

suite "HDF Store":
    test "Create HDF Store":
        var store = openHDFStore("test.h5", mode=hdOverwrite)
        store.close
    test "Open HDF Store":
        var store = openHDFStore("test.h5", mode=hdReadWrite)
        store.close
    test "Open HDF Store Read Only":
        var store = openHDFStore("test.h5", mode=hdRead)
        store.close
    test "Create HDF Store custom chunk size":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize=10)
        store.close
    test "Create HDF Store Compressed":
        var store = openHDFStore("test.h5", mode=hdOverwrite, compression = true)
        store.close

suite "HDF Table":
    test "Create Table uncompressed":
        var store = openHDFStore("test.h5", mode=hdOverwrite)
        var particles = data
        store["particles"] = particles
        store["particles2"] = particles
        check(store.keys() == @["particles", "particles2"])
        store.delete("particle2")
        store.close
    test "Create Table compressed":
        var store = openHDFStore("test.h5", mode=hdOverwrite, compression = true)
        var particles = data
        store["particles"] = particles
        store.close
    test "Create Table compressed, custom chunk size":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10, compression = true)
        var particles = data
        store["particles"] = particles
        store.close
    test "Read table":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10)
        var particles = data
        store["particles"] = particles
        var table = store["particles",Particle]
        check(data == table.toSeq)
        store.close
    test "Read rows":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10)
        var particles = data
        store["particles"] = particles
        var table = store["particles",Particle]
        check(data[0] == table[0])
        check(data[^1] == table[^1])
        check(data[3..10] == table[3..10])
        store.close
    test "Append rows":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10)
        var particles = data
        store["particles"] = particles
        var table = store["particles",Particle]
        var newParticles: seq[Particle] = @[
            Particle(lati: 14, longi: 1, pressure: 100.0, temperature: 20.0),
            Particle(lati: 15, longi: 1, pressure: 100.0, temperature: 20.0)
        ]
        table.append(newParticles)
        check(newParticles == table[^2..^1])
        check(table.nrows == 15)
        store.close
    test "Delete rows":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10)
        var particles = data
        store["particles"] = particles
        var table = store["particles",Particle]
        table.delete(^1)
        check(data[^2] == table[^1])
        check(table.nrows == 12)
        store.close
    test "Insert rows":
        var store = openHDFStore("test.h5", mode=hdOverwrite, chunkSize = 10)
        var particles = data
        store["particles"] = particles
        var table = store["particles",Particle]
        var newParticles: seq[Particle] = @[
            Particle(lati: 14, longi: 1, pressure: 100.0, temperature: 20.0),
            Particle(lati: 15, longi: 1, pressure: 100.0, temperature: 20.0)
        ]
        table.insert(3, newParticles)
        check(table[3..4] == newParticles)
        store.close

