# concurrency.jl -- concurrent-sweep speed-up (manuscript Table 1).
#
# Metric: median over ROUNDS of the per-round PAIRED RATIO t_serial / t_concurrent,
# where the serial arm is the hand-written `for transform in all_lattice_transformations`
# loop and the concurrent arm is `sweep_transformations` at admission limit c. Arms are
# interleaved and a full reclaim (`GC.gc(true)` + `CUDA.reclaim()` on device) runs before
# EVERY timed section -- without this the CUDA pool state inflates the serial baseline and
# fabricates a speed-up (see README.md, "Protocol notes").
#
# Ratio > 1 means the concurrent sweep is faster than the serial loop.
#
# MUST run with several Julia threads or the concurrent arm cannot overlap:
#     julia --project=$PKG -t auto concurrency.jl
#
# ENV: CASE=A|B|both  DEVICE=cpu|gpu  LEVELS=1,2,4,8  ROUNDS=Int  SEED=Int
#      MERGE=droplets|none  OUT=path(append)  BLAS_THREADS=Int(optional)
#      PKG=SpinGlassPEPS.jl checkout
#
# Cases match the manuscript:
#   A  Chimera 3x4x3 (36 spins), D=16, SVDTruncate/Dense, KingSingleNode, beta=2
#   B  Chimera 128power (128 spins), D=32, Zipper/Dense, SquareSingleNode, beta=3
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassEngine: no_merge
import CUDA
using Random, Printf, Statistics
using LinearAlgebra: BLAS

const DEVICE = get(ENV, "DEVICE", CUDA.functional() ? "gpu" : "cpu")
const onGPU  = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")
const CASE   = get(ENV, "CASE", "both")
const LEVELS = parse.(Int, split(get(ENV, "LEVELS", onGPU ? "1,2,4" : "1,2,4,8"), ","))
const ROUNDS = parse(Int, get(ENV, "ROUNDS", onGPU ? "7" : "5"))
const SEED   = parse(Int, get(ENV, "SEED", "1"))
const MERGE  = get(ENV, "MERGE", "droplets")
const OUT    = get(ENV, "OUT", "concurrency_raw.csv")
const PKG    = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))
haskey(ENV, "BLAS_THREADS") && BLAS.set_num_threads(parse(Int, ENV["BLAS_THREADS"]))
const BASE_BLAS = BLAS.get_num_threads()

reclaim!() = (GC.gc(true); onGPU && CUDA.reclaim(); nothing)

# wall time of f(), with device work flushed inside the timed region on GPU
function timed(f)
    onGPU && CUDA.synchronize()
    st = @timed begin
        v = f()
        onGPU && CUDA.synchronize()
        v
    end
    (st.time, st.value)
end

const SPARAMS = SearchParameters(; max_states = 2^8, cutoff_prob = 1e-4)
mergefn(ctr) = MERGE == "none" ? no_merge :
    merge_branches(ctr; merge_prob = :none,
        droplets_encoding = SingleLayerDroplets(; max_energy = 10, min_size = 5, metric = :hamming))

inst(p...) = joinpath(PKG, "test", "engine", "instances", p...)

# returns (name, build) where build: transformation -> MpsContractor
function case_setup(case)
    if case == "A"
        (m, n, t) = (3, 4, 3)
        ph = potts_hamiltonian(ising_graph(inst("pathological", "chim_3_4_3.txt"));
            spectrum = full_spectrum, cluster_assignment_rule = super_square_lattice((m, n, t)))
        params = MpsParameters{Float64}(; bond_dim = 16, num_sweeps = 1)
        build = tr -> MpsContractor(SVDTruncate,
            PEPSNetwork{KingSingleNode{GaugesEnergy},Dense,Float64}(m, n, ph, tr),
            params; onGPU = onGPU, beta = 2.0, graduate_truncation = true)
        ("chim_3_4_3_D16_svd", build)
    elseif case == "B"
        (m, n, t) = (4, 4, 8)
        ph = potts_hamiltonian(ising_graph(inst("chimera_droplets", "128power", "001.txt"));
            spectrum = full_spectrum, cluster_assignment_rule = super_square_lattice((m, n, t)))
        params = MpsParameters{Float64}(; bond_dim = 32, var_tol = 1e-8, num_sweeps = 4, tol_SVD = 1e-16)
        build = tr -> MpsContractor(Zipper,
            PEPSNetwork{SquareSingleNode{GaugesEnergy},Dense,Float64}(m, n, ph, tr),
            params; onGPU = onGPU, beta = 3.0, graduate_truncation = true)
        ("128power_D32_zipper", build)
    else
        error("CASE must be A, B or both; got $case")
    end
end

# serial reference: the 8-transformation loop, each transform seeded deterministically
function serial_arm(build)
    energies = Float64[]
    for (i, tr) in enumerate(all_lattice_transformations)
        s = SEED * 1000 + i
        Random.seed!(s); onGPU && CUDA.seed!(s)
        ctr = build(tr)
        sol, _ = low_energy_spectrum(ctr, SPARAMS, mergefn(ctr); show_progress = false)
        push!(energies, first(sol.energies))
        clear_memoize_cache()
    end
    minimum(energies)
end

concurrent_arm(build, c) = sweep_transformations(build, SPARAMS;
    merge_strategy = mergefn, concurrency = c, seed = SEED, show_progress = false)

if !isfile(OUT)
    open(OUT, "w") do io
        println(io, "case,device,concurrency,round,seed,t_serial_s,t_concurrent_s,ratio,e_serial,e_concurrent")
    end
end

Threads.nthreads() == 1 && @warn "Only 1 Julia thread: the concurrent arm cannot overlap. Launch with -t auto."

for case in (CASE == "both" ? ["A", "B"] : [CASE])
    (name, build) = case_setup(case)
    @printf("== case %s (%s)  device=%s  threads=%d  BLAS=%d  merge=%s ==\n",
        case, name, DEVICE, Threads.nthreads(), BASE_BLAS, MERGE)
    # warm up JIT for this case on both arms (not recorded)
    serial_arm(build); concurrent_arm(build, first(LEVELS))
    for c in LEVELS
        ratios = Float64[]
        for r in 1:ROUNDS
            BLAS.set_num_threads(BASE_BLAS)          # serial arm gets the full BLAS pool
            reclaim!(); (t_ser, e_ser) = timed(() -> serial_arm(build))
            reclaim!(); (t_con, sweep) = timed(() -> concurrent_arm(build, c))
            e_con = first(best_solution(sweep).energies)
            ratio = t_ser / t_con
            push!(ratios, ratio)
            open(OUT, "a") do io
                @printf(io, "%s,%s,%d,%d,%d,%.6f,%.6f,%.4f,%.8f,%.8f\n",
                    name, DEVICE, c, r, SEED, t_ser, t_con, ratio, e_ser, e_con)
            end
        end
        @printf("  c=%d: median ratio %.2f over %d rounds  (>1 = concurrent faster)\n",
            c, median(ratios), ROUNDS)
        flush(stdout)
    end
end
