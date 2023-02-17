# using TestEnv
# TestEnv.activate("Waluigi")

using Scratch
function __init__()
    global test_files = get_scratch!(@__MODULE__, "test_files")
end
__init__()

using Dagger
using Test
using DataFrames

using Waluigi

# Putting all the structs for tester jobs in a module makes it easier to iterate
include("./custom_target.jl")
include("./test_jobs.jl")


# My hacky version of checking if struct results are the same
field_equal(v1, v2) = (v1==v2) isa Bool ? v1==v2 : false
field_equal(::Nothing, ::Nothing) = true
field_equal(::Missing, ::Missing) = true
field_equal(a1::AbstractArray, a2::AbstractArray) = length(a1) == length(a2) && field_equal.(a1,a2) |> all
field_equal(p1::Dagger.EagerThunk, p2::Dagger.EagerThunk) = field_equal(fetch(p1), fetch(p2))
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
    nothing_job = TestJobs.NothingJob()
    @test get_dependencies(nothing_job) == []
    @test get_target(nothing_job) isa Waluigi.NoTarget
    @test run_process(nothing_job, [nothing], nothing) isa Nothing
    @test fields_equal(
        Waluigi.execute(nothing_job), Waluigi.ScheduledJob(Waluigi.ScheduledJob[], Waluigi.NoTarget(), 
        Dagger.spawn(() -> nothing))
        )
end


@testset "Basic dependencies" begin
    @test begin
        result = Waluigi.execute(TestJobs.MainJob())
        Waluigi.get_result(result) == 7
    end
end


@testset "Malformed Jobs" begin
    @test_throws ArgumentError Waluigi.execute(TestJobs.BadDeps())
end

@testset "Checkpointing" begin
    checkpoint_fp = joinpath(test_files, "checkpoint_tester.bin")

    # CheckPointTester just caches the value it's given and returns it.
    first_checkpoint_tester = TestJobs.CheckPointTester(1)
    first_checkpoint_res = Waluigi.execute(first_checkpoint_tester)

    @test isfile(checkpoint_fp)
    @test get_result(first_checkpoint_res) == 1

    # But since the path to the target is the same for all instances, this new version of CheckPointTester will
    # still return `1` since it's just going to grab the cached result regardless of the input
    second_checkpoint_res = TestJobs.CheckPointTester(2)
    @test 1 == second_checkpoint_res |> Waluigi.execute |> get_result
    rm(checkpoint_fp)

    # Checkpoint with custom target
    test_parq_dir = joinpath(test_files, "test_parq_dir")
    parq_file = joinpath(test_parq_dir, "1.parq")
    mkdir(test_parq_dir)

    df_1 = DataFrame(a=[1,2,3], b=["a","b","c"])
    use_custom_1 = TestJobs.UsingCustomTarget(df_1, test_parq_dir)
    res = Waluigi.execute(use_custom_1) |> get_result 
    @test df_1 == res |> DataFrame
    isfile(parq_file)
    df_2 = DataFrame(e=[1,1,1])
    use_custom_2 = TestJobs.UsingCustomTarget(df_2, test_parq_dir)
    @test df_1 == Waluigi.execute(use_custom_1) |> get_result |> DataFrame
    rm(test_parq_dir; force=true, recursive=true)
end

