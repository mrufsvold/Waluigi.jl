# Waluigi.jl

Waluigi is a pure-Julia implementation of Luigi. It aims to provide a simple interface for defining 
`Job`s in a data pipeline and linking dependencies together.

# Getting Started
You can get started with this quick example:

```julia
using Waluigi

module JobDefinitions
@Job begin
    name = GetGreeting
    process = begin
        return "Hello"
    end
end

@Job begin
    name = GetAddressee
    parameters = (name::String,)
    process = name
end

@Job begin
    name = SayHelloWorld
    dependencies = Dict(
        :Greeting => GetGreeting(),
        :Addressee => GetAddressee("World")
    )
    process = begin
        addressee = get_result(dependencies[:Addressee])
        greeting = get_result(dependencies[:Greeting])
        println("$greeting, $(addressee)!")
    end
end

end # end module

JobDefinitions.SayHelloWorld() |> Waluigi.run_pipeline |> get_result
```

We'll look at this piece by piece.

The module `JobDefinitions` is not necessary for creating jobs, but it is convenient for debugging
and iterating because it allows you to redefine the Job structs without restarting your Julia
session.

`GetGreeting` and `GetAddressee` are both depencies of `SayHelloWorld`. Looking at `GetAddressee`
we can see that it has a parameter of type `String` which it returns without change in the 
`process` function. Also, notice that `name` is immediately available to all fields
below it.

`SayHelloWorld` is the "end of the pipeline". It tells `Waluigi` to run its dependencies. 
Each dependency returns a 'ScheduledJob' which provides information about the run of the job.
Here, all we need is the result, so we call `get_result`.

Of course, Hello world is the cannonical trivial example, but with these building blocks, you
can define complex dependencies and parameterize abstracted processes to reduce code reuse.

# Storing Results in a Target

Any step in the pipeline can be saved to a `Target`. A target can be a file on disk, a SQL
table, or anything else that can store and return data. Just like 'Job's, targets can be 
defined by a user by implementing a small set of interface functions.

The required interface for an AbstractTarget is:

```julia

# Use T if you want to parameterize your target's return type. Otherwise, replace
# T with a specific type. This helps with type inference between Jobs, so you should use a 
# type whenever possible
struct MyTarget{T} <: Waluigi.AbstracTarget{T}
    # add fields here
end

# is_completed returns a boolean indicating whether the process should be skipped because the 
# target is completed.
function Waluigi.is_complete(t::MyTarget)
    true
end

# store accepts the target of a job and the data returend by `process` and stores it in the target
function Waluigi.store(t::MyTarget, data)
    # logic
end

# Given a completed target, returns the retrieved data
function Waluigi.retrieve(t::MyTarget)
    # get data
    return data
end

```

The current implementation of the pipeline always stores the results of the job and the runs
retrieve and only passes on the retrieved data. This prevents a situation where the store and
retrieve functions are not perfect inverses of each other. This does result in cases where unnecessary
computation is required. In the future, there may be a new AbstractTarget type that will tell the
pipeline to only store and then return the actual result of process if the user is taking responsibility
for ensuring that the retrieved data is consistent with the the result data. 
