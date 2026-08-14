# crossover.jl -- one CPU-or-GPU crossover cell, seeded, over REPS repetitions.
#
# Protocol (matches the manuscript): SquareSingleNode{GaugesEnergy}, Zipper,
# beta = 3, max_states = 128, full cluster spectrum. One raw row per repetition is
# appended to OUT, so a run can be resumed or inspected mid-flight; the summary
# (min-of-reps -> cpu_s/gpu_s) is produced by summarize_crossover.py.
#
# Instances (chimera): chim_3_4_3 (36 spins), 128power (128, 4x4x8),
# 2048power (2048, 16x16x8) -- all shipped in the SpinGlassPEPS.jl repo.
#
# ENV: SPINS=36|128|2048  SPARSITY=dense|sparse  BOND=Int  DEVICE=cpu|gpu
#      REPS=Int  SEED=Int  OUT=path(append)  PKG=SpinGlassPEPS.jl checkout
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassEngine: no_merge
import CUDA
using Random, Printf

const SPINS    = parse(Int, ENV["SPINS"])
const SPARSITY = get(ENV, "SPARSITY", "dense")
const BOND     = parse(Int, ENV["BOND"])
const DEVICE   = get(ENV, "DEVICE", "cpu")
const REPS     = parse(Int, get(ENV, "REPS", "5"))
const SEED     = parse(Int, get(ENV, "SEED", "1"))
const OUT      = get(ENV, "OUT", "crossover_raw.csv")
const PKG      = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))

const onGPU = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")

const INSTS = Dict(
    36   => (joinpath(PKG, "test", "engine", "instances", "pathological", "chim_3_4_3.txt"), (3, 4, 3)),
    128  => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "128power", "001.txt"), (4, 4, 8)),
    2048 => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "2048power", "001.txt"), (16, 16, 8)),
)
const inst, (m, n, t) = INSTS[SPINS]
const Sp = SPARSITY == "sparse" ? Sparse : Dense

const ph = potts_hamiltonian(ising_graph(inst); spectrum = full_spectrum,
    cluster_assignment_rule = super_square_lattice((m, n, t)))

function one_solve()
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Sp,Float64}(m, n, ph, rotation(0))
    ctr = MpsContractor(Zipper, net,
        MpsParameters{Float64}(; bond_dim = BOND, var_tol = 1e-8, num_sweeps = 4, tol_SVD = 1e-16);
        onGPU = onGPU, beta = 3.0, graduate_truncation = true)
    onGPU && CUDA.synchronize()
    tsolve = @elapsed res = low_energy_spectrum(ctr,
        SearchParameters(; max_states = 128, cutoff_prob = 0.0), no_merge; show_progress = false)
    onGPU && CUDA.synchronize()
    e = first(first(res).energies)
    clear_memoize_cache()
    tsolve, e
end

one_solve()  # warm up JIT; not recorded

if !isfile(OUT)
    open(OUT, "w") do io
        println(io, "spins,sparsity,bond,device,rep,seed,t_solve,energy")
    end
end
for rep in 1:REPS
    s = SEED + rep
    Random.seed!(s)
    onGPU && CUDA.seed!(s)
    tsolve, e = one_solve()
    open(OUT, "a") do io
        @printf(io, "%d,%s,%d,%s,%d,%d,%.6f,%.8f\n", SPINS, SPARSITY, BOND, DEVICE, rep, s, tsolve, e)
    end
    @printf("  [%s] %d spins %s D=%d  rep %d/%d  t=%.3fs  E=%.6f\n",
        DEVICE, SPINS, SPARSITY, BOND, rep, REPS, tsolve, e)
    flush(stdout)
end
