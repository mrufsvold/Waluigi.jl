# Vision
Waliugi should provide a seemless interface for constructing data pipelines. Users just need 
to define an job that has three parts:
* a list of jobs on which the current job depends 
* a target which holds the resulting data. Can be a local file, a database table, etc
* process function that providest the steps for creating the data

The workflow should be

Defining a list of jobs, calling `run()` on the final job, and then Waliuigi will
spawn all the dependent jobs required. If a job is already done, then it will read the target
and return that data. `run()` will return a Result object which contains references to the 
results of the depenencies, the target, and the data created by the job.

We will lean on Dagger.jl for the backend infrastructure which schedules jobs, mantains the
graph of dependencies, and provides visualizations of the processes. 

Some brainstroming code:




## Target Vision
A target needs three things to work.
* A place to store the result
* A way to write to that place
* a way to read from that place

The simplest way to do this is a local bin file that serializes the result to and from
Julia
```julia
struct LocalSerialFile 
    fp
end
write(t::LocalSerialFile, data) = write(t.fp, data)
read(t::LocalSerialFile) = read(t.fp)


target = LocalSerialFile("path/to/serialized.bin")

x = 5 # result of job

write(target, x)
y = read(target)
```

It would be great to have targets for Tables
```julia
using CSV
using DataFrames
struct CsvTableTarget{T}
    fp
    sink::T
end

write(t::CsvTableTarget{T}, df::T) where T = CSV.write(t.fp, df)
read(t::CsvTableTarget) = CSV.read(t.fp, t.sink)

target = CsvTableTarget("path/to/file.csv", DataFrame)
df = DataFrame(a=[1,2], b=[3,4])
write(target, df)
df2 = read(target)
```

Custom Target
```julia
struct Target
    location
    config
    write_function
    read_function
end
write(t::Target, data) = t.write_function(data)
read(t::Target) = t.read_function()

function LocalSerialFile(fp)
    Target(
        fp,
        nothing,
        (data) -> write(fp, data),
        () -> read(fp)
    )
end

function CsvTableTarget(fp, sink)
    Target(
        fp,
        nothing,
        (data) -> CSV.write(fp, data),
        () -> CSV.read(fp, sink)
    )
end



```
## Improving the macro
Right now the Job type contains no data. It's just contained in the dispatched getter functions
What we should really do is have a workflow like

```julia
@Job begin
    name = MyJob
    #details
end

# the fall back constructor for AbstractJob should take any number of params and then
# filter for the ones this type needs?

# saves these configurations
job_instance = MyJob(param1, param2)


result = run(job_instance)

```

This solves the problem with Dagger.delay because we can delay the run() and users can define
a generator of instantiated Jobs that aren't run yet

get_parameters(types) is no longer necessary because we can use field_names on a job type

we should be able to do some kind of think to unroll the parameters like
function get_dependencies(job_instance::JobInstanceType)
    let param1 = job_instance.param1 ...
        userfunc block
    end
end




get_dependencies(typeof(job_instance); (n=>getproperty(job_instance, n) for n in fieldnames(typeof(job_instance)))...) )

and then define the user submitted functions with signatures like

get_dependencies(::Type{MyJob}; user_param1, user_param2) = begin userfunction... end




## Planning Targets

A target needs to take data from the end of a process, write it to some location, and then
provide a read function that returns the data

Targets are unique on type of source and type of location. But the problem is that the target
needs to know the source type so that it can call the correct read function later on

The problem is then that you need to define the Target with a type into which it will read
the data. But you may or may not know the type emitted by the process

But maybe it just is what it is. 

we could try to decouple read/write from de/serialize 

For example, 

run_process could emit a TypedTable or a DataFrame. We could write those objects
to a parquet file or a database table
OR
run_process could emit a string or an int, and we could write either of those to BSON or .txt
