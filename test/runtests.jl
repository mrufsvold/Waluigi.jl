using Waluigi
using Test

fieldequal(v1, v2) = (v1==v2) isa Bool ? v1==v2 : false
fieldequal(::Nothing, ::Nothing) = true
fieldequal(::Missing, ::Missing) = true
fieldequal(a1::AbstractArray, a2::AbstractArray) = length(a1) == length(a2) && fieldequal.(a1,a2) |> all
function fieldsequal(o1, o2)
    for name in fieldnames(typeof(o1))
        prop1 = getproperty(o1, name)
        prop2 = getproperty(o2, name)
        if !fieldequal(prop1, prop2)
            println("Didn't match on $name. Got $prop1 and $prop2")
            return false
        end
    end
    return true
end


@testset "Jobs" begin
    Waluigi.@Job begin
        name = NothingJob
        parameters = nothing
        dependencies = nothing
        target = nothing
        process = nothing
    end

    @show methods(Waluigi.parameters)
    nothing_job = NothingJob()
    
    @test Waluigi.parameters(nothing_job) == ()
    @test Waluigi.dependencies(nothing_job) == [nothing]
    @test Waluigi.target(nothing_job) isa Nothing
    @test Waluigi.process(nothing_job, [nothing], nothing) isa Nothing
    
    @show nothing_job()
end
