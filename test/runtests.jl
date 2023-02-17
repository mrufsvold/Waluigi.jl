using TestEnv
TestEnv.activate()
using Test

field_equal(v1, v2) = (v1==v2) isa Bool ? v1==v2 : false
field_equal(::Nothing, ::Nothing) = true
field_equal(::Missing, ::Missing) = true
field_equal(a1::AbstractArray, a2::AbstractArray) = length(a1) == length(a2) && field_equal.(a1,a2) |> all
function fields_equal(o1, o2)
    for name in fieldnames(typeof(o1))
        prop1 = getproperty(o1, name)
        prop2 = getproperty(o2, name)
        if !field_equal(prop1, prop2)
            println("Didn't match on $name. Got $prop1 and $prop2")
            return false
        end
    end
    return true
end


@testset "All nothing jobs description" begin
    Waluigi.@Job begin
        name = NothingJob
        parameters = nothing
        dependencies = nothing
        target = nothing
        process = nothing
    end
    nothing_job = NothingJob()
    @test get_dependencies(nothing_job) == []
    @test get_target(nothing_job) isa Nothing
    @test run_process(nothing_job, [nothing], nothing) isa Nothing
    @test fields_equal(Waluigi.execute(nothing_job), Waluigi.Result(Any[], nothing, nothing))
end
