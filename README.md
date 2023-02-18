# Waluigi.jl

Waluigi is a pure-Julia implementation of Luigi. It aims to provide a simple interface for defining 
`Job`s in a data pipeline and linking dependencies together. In the background, it schedules 
jobs with Dagger.jl and ensures that dependencies are satisfied in the correct order.

Any step in the pipeline can be saved to a `Target`. A target can be a file on disk, a SQL
table, or anything else that can store and return data. Just like 'Job's, targets can be 
defined by a user by implementing a small set of interface functions.

# Getting Started
'''julia
using Waluigi

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
        greeting = get_result(dependencies[:Greeting])
        addressee = get_result(dependencies[:Addressee])
        println("$greeting, $(addressee)!")
    end
end

SayHelloWorld() |> Waluigi.execute |> get_result
```
