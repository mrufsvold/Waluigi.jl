# using Pkg
# Pkg.activate()
# using TestEnv
# Pkg.activate(".")
# TestEnv.activate("Waluigi")

using Scratch
function __init__()
    global test_files = get_scratch!(@__MODULE__, "test_files")
end
__init__()

using Test
using DataFrames
using Dagger
using Waluigi

# Putting all the structs for tester jobs in a module makes it easier to iterate
include("./custom_target.jl")
include("./test_jobs.jl")


# My hacky version of checking if struct results are the same
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
    for job in (TestJobs.NothingJob(), TestJobs.OopsAllOmited())
        @test get_dependencies(job) == []
        @test get_target(job) isa Waluigi.NoTarget
        @test run_process(job, [nothing], nothing) isa Nothing
        @test fields_equal(
            get_result(Waluigi.run_pipeline(job)),
            Waluigi.ScheduledJob(zero(UInt64), Waluigi.NoTarget(), nothing))
    end
end


@testset "Basic dependencies" begin
    @test begin
        result = Waluigi.run_pipeline(TestJobs.MainJob())
        Waluigi.get_result(result) == 7
    end
end

@testset "Malformed Jobs" begin
    @test_throws ArgumentError get_result(Waluigi.run_pipeline(TestJobs.BadDeps()))
    @test_throws Dagger.ThunkFailedException get_result(Waluigi.run_pipeline(TestJobs.BadTarget()))
    @test_throws ArgumentError @Job begin paramters = nothing; process = 5 end
    @test_throws InvalidStateException Waluigi.run_pipeline(TestJobs.CycleDepA())
end

@testset "Checkpointing" begin
    checkpoint_fp = joinpath(test_files, "checkpoint_tester.bin")

    # CheckPointTester just caches the value it's given and returns it.
    first_checkpoint_tester = TestJobs.CheckPointTester(1)
    first_checkpoint_res = get_result(Waluigi.run_pipeline(first_checkpoint_tester))

    @test isfile(checkpoint_fp)
    @test  first_checkpoint_res == 1

    # But since the path to the target is the same for all instances, this new version of CheckPointTester will
    # still return `1` since it's just going to grab the cached result regardless of the input
    second_checkpoint_res = TestJobs.CheckPointTester(2)
    @test 1 == second_checkpoint_res |> Waluigi.run_pipeline |> get_result

    rm(checkpoint_fp)

    # Checkpoint with custom target, same strategy as above
    test_parq_dir = joinpath(test_files, "test_parq_dir")
    parq_file = joinpath(test_parq_dir, "1.parq")
    rm(test_parq_dir; force=true, recursive=true)
    @test !isdir(test_parq_dir)
    df_1 = DataFrame(a=[1,2,3], b=["a","b","c"])
    use_custom_1 = TestJobs.UsingCustomTarget(df_1, test_parq_dir)
    @test df_1 == (Waluigi.run_pipeline(use_custom_1) |> get_result |> DataFrame)
    @test isfile(parq_file)

    df_2 = DataFrame(e=[1,1,1])
    use_custom_2 = TestJobs.UsingCustomTarget(df_2, test_parq_dir)
    @test df_1 == (Waluigi.run_pipeline(use_custom_2) |> get_result |> DataFrame)
    rm(test_parq_dir; force=true, recursive=true)
end

@testset "Typing Parameters" begin
    @test TestJobs.TypedParams(1,"a").a == 1
    @test_throws MethodError TestJobs.TypedParams(1,5)
end

@testset "Use a custom type in a function" begin
    @test begin
        i_use_tester_type = TestJobs.IUseTesterType(TestJobs.TesterType())
        Waluigi.run_pipeline(i_use_tester_type) |> get_result
    end
end
